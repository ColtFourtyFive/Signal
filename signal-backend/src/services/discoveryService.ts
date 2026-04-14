import Anthropic from '@anthropic-ai/sdk';
import { supabaseAdmin } from '../db/supabase';
import { discoverRssUrl, validateAndSampleFeed } from './rssService';
import { scoreArticlesForValidation } from './scoringService';
import { getCurrentTasteProfile, scoreArticleAgainstProfile } from './tasteProfileService';
import { sendPushNotification } from './pushService';

let _client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY! });
  return _client;
}

interface DiscoverySuggestion {
  domain: string;
  likely_rss: string;
  reason: string;
  why_relevant?: string;
  confidence: 'high' | 'medium' | 'low';
}

// Extract all https:// domain names from article content
function extractDomains(content: string): string[] {
  const urlPattern = /https?:\/\/([a-zA-Z0-9.-]+)/g;
  const domains = new Set<string>();
  let match;
  while ((match = urlPattern.exec(content)) !== null) {
    const domain = match[1];
    // Filter out common noise
    if (
      !domain.includes('google.com') &&
      !domain.includes('twitter.com') &&
      !domain.includes('x.com') &&
      !domain.includes('youtube.com') &&
      !domain.includes('github.com/cdn') &&
      !domain.includes('linkedin.com') &&
      !domain.includes('facebook.com') &&
      domain.split('.').length >= 2
    ) {
      domains.add(domain);
    }
  }
  return Array.from(domains);
}

export async function runDiscovery(): Promise<{
  added: number;
  pending: number;
  rejected: number;
}> {
  console.log('[discoveryService] Starting discovery run...');

  // Step 0: Check taste profile — need confidence >= 0.3 to proceed
  const profile = await getCurrentTasteProfile();
  if (!profile || profile.confidence_score < 0.3) {
    console.log(`[discoveryService] Profile not ready (confidence: ${profile?.confidence_score ?? 0}). Skipping.`);
    return { added: 0, pending: 0, rejected: 0 };
  }

  // Step 1: Get top engaged articles from last 7 days
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const { data: engagedArticleIds } = await supabaseAdmin
    .from('interactions')
    .select('article_id')
    .in('type', ['saved', 'read_60s'])
    .gte('occurred_at', sevenDaysAgo);

  if (!engagedArticleIds?.length) {
    console.log('[discoveryService] No engaged articles found, skipping');
    return { added: 0, pending: 0, rejected: 0 };
  }

  const articleIds = [...new Set(engagedArticleIds.map(r => r.article_id))].slice(0, 15);

  const { data: topArticles } = await supabaseAdmin
    .from('articles')
    .select('id, title, content, key_entities, feeds(name)')
    .in('id', articleIds)
    .not('content', 'is', null);

  if (!topArticles?.length) {
    console.log('[discoveryService] No article content found');
    return { added: 0, pending: 0, rejected: 0 };
  }

  // Step 2: Extract candidate domains from article content
  const allDomains = new Set<string>();
  for (const article of topArticles) {
    if (article.content) {
      extractDomains(article.content).forEach(d => allDomains.add(d));
    }
  }

  // Get already-subscribed domains + previously rejected domains to exclude
  const [{ data: existingFeeds }, { data: rejectedSources }] = await Promise.all([
    supabaseAdmin.from('feeds').select('url, name'),
    supabaseAdmin.from('discovered_sources').select('url').eq('status', 'rejected'),
  ]);

  const knownDomains = new Set([
    ...(existingFeeds ?? []).map(f => {
      try { return new URL(f.url).hostname; } catch { return ''; }
    }),
    ...(rejectedSources ?? []).map(s => {
      try { return new URL(s.url).hostname; } catch { return ''; }
    }),
  ]);

  const existingFeedNames = (existingFeeds ?? []).map(f => f.name).join(', ');

  const candidateDomains = Array.from(allDomains)
    .filter(d => !knownDomains.has(d))
    .slice(0, 30);

  if (!candidateDomains.length) {
    console.log('[discoveryService] No new candidate domains found');
    return { added: 0, pending: 0, rejected: 0 };
  }

  // Step 3: Ask Claude for profile-aware source suggestions
  const articleSummary = topArticles.map(a => {
    const feedsData = a.feeds as { name: string } | { name: string }[] | null;
    const feedName = Array.isArray(feedsData) ? feedsData[0]?.name ?? 'unknown' : feedsData?.name ?? 'unknown';
    const entities = (a.key_entities as string[] | null)?.join(', ') ?? '';
    return `- "${a.title}" (from ${feedName}) [${entities}]`;
  }).join('\n');

  const topInterests = Object.entries(profile.primary_interests as Record<string, number>)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, score]) => `${name} (${Math.round(score * 100)}%)`)
    .join(', ');

  const keyEntities = profile.key_entities as { models?: string[]; benchmarks?: string[]; techniques?: string[]; organizations?: string[] } | null;
  const entitiesSummary = [
    keyEntities?.models?.slice(0, 4).join(', '),
    keyEntities?.organizations?.slice(0, 4).join(', '),
  ].filter(Boolean).join(' | ');

  const prompt = `You are discovering RSS sources for a specific reader. Match their EXACT interests, not general AI news.

READER'S INTEREST PROFILE:
${profile.profile_text}

Top interests: ${topInterests}
Key entities they follow: ${entitiesSummary}
What they avoid: ${profile.anti_interests?.join(', ') ?? 'none specified'}

Currently following: ${existingFeedNames}

Their most engaged articles recently:
${articleSummary}

Candidate domains from their reading (not currently followed):
${candidateDomains.join(', ')}

Identify up to 10 specific RSS sources this person would find extremely valuable based on their SPECIFIC interests above. Each suggestion must reference which of their actual interests it serves. Focus on:
- Individual researchers or engineers who work on the specific techniques/models they follow
- Smaller labs or teams working on the specific problems they care about
- GitHub release feeds for specific tools/frameworks they engage with
- Technical blogs that go deep on their specific interest areas

Return ONLY valid JSON, nothing else:
[{
  "domain": "example.com",
  "likely_rss": "https://example.com/feed",
  "reason": "one sentence: which specific interest this serves and why",
  "why_relevant": "references specific interest from their profile e.g. 'covers LLM inference optimization at the level of detail they engage with'",
  "confidence": "high"
}]`;

  let suggestions: DiscoverySuggestion[] = [];
  try {
    const response = await getClient().messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 1000,
      messages: [{ role: 'user', content: prompt }],
    });

    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const cleaned = text
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();

    const parsed = JSON.parse(cleaned);
    if (Array.isArray(parsed)) {
      suggestions = parsed.filter(s =>
        s.confidence === 'high' || s.confidence === 'medium'
      );
    }
  } catch (err) {
    console.warn('[discoveryService] Claude suggestion failed:', err);
    return { added: 0, pending: 0, rejected: 0 };
  }

  console.log(`[discoveryService] Claude suggested ${suggestions.length} sources`);

  // Step 4: Validate each suggestion and score sample articles
  let added = 0;
  let pending = 0;
  let rejected = 0;

  for (const suggestion of suggestions) {
    // Validate RSS URL
    let validRssUrl = await discoverRssUrl(suggestion.likely_rss);
    if (!validRssUrl && suggestion.domain) {
      validRssUrl = await discoverRssUrl(`https://${suggestion.domain}`);
    }

    if (!validRssUrl) {
      console.log(`[discoveryService] No valid RSS for ${suggestion.domain}`);
      rejected++;
      await supabaseAdmin.from('discovered_sources').insert({
        name: suggestion.domain,
        url: `https://${suggestion.domain}`,
        rss_url: suggestion.likely_rss,
        avg_score: 0,
        discovery_reason: suggestion.reason,
        status: 'rejected',
      });
      continue;
    }

    // Check if already in feeds
    const { data: existing } = await supabaseAdmin
      .from('feeds')
      .select('id')
      .eq('url', validRssUrl)
      .single();

    if (existing) continue;

    // Score sample articles
    const samples = await validateAndSampleFeed(validRssUrl);
    if (!samples?.length) {
      rejected++;
      continue;
    }

    const scores = await scoreArticlesForValidation(samples);
    const avgScore = scores.length
      ? scores.reduce((a, b) => a + b, 0) / scores.length
      : 0;

    // Score samples against taste profile
    let avgPersonalization = 0;
    if (profile && profile.confidence_score >= 0.3 && samples.length > 0) {
      const personalizationResults = await Promise.all(
        samples.slice(0, 3).map(async (s) => {
          const result = await scoreArticleAgainstProfile(
            { id: 'discovery', title: s.title, content: s.content ?? null, category: null, key_entities: null, score: null },
            profile,
            s.feedName
          );
          return result?.score ?? 0.5;
        })
      );
      avgPersonalization = personalizationResults.reduce((a, b) => a + b, 0) / personalizationResults.length;
    }

    const feedName = suggestion.domain;
    let status: 'added' | 'pending' | 'rejected';

    // Auto-add requires both high general score AND profile relevance
    if (avgScore >= 7.0 && avgPersonalization >= 0.6) {
      status = 'added';
      added++;
      await supabaseAdmin.from('feeds').insert({
        name: feedName,
        url: validRssUrl,
        is_auto_discovered: true,
        avg_score: avgScore,
      });
    } else if (avgScore >= 5.0 || (avgScore >= 4.0 && avgPersonalization >= 0.7)) {
      status = 'pending';
      pending++;
    } else {
      status = 'rejected';
      rejected++;
    }

    const discoveryReason = suggestion.why_relevant
      ? `${suggestion.reason} | ${suggestion.why_relevant}`
      : suggestion.reason;

    await supabaseAdmin.from('discovered_sources').insert({
      name: feedName,
      url: `https://${suggestion.domain}`,
      rss_url: validRssUrl,
      avg_score: avgScore,
      discovery_reason: discoveryReason,
      status,
    });

    console.log(`[discoveryService] ${suggestion.domain}: avg_score=${avgScore.toFixed(1)}, personalization=${avgPersonalization.toFixed(2)} → ${status}`);
  }

  console.log(`[discoveryService] Done — added: ${added}, pending: ${pending}, rejected: ${rejected}`);

  // Push notification when 2+ sources are auto-added
  if (added >= 2) {
    sendPushNotification({
      title: 'New Sources Discovered',
      body: `Signal found ${added} new sources matching your interests`,
      data: { type: 'discovery', added },
    }).catch(() => {});
  }

  return { added, pending, rejected };
}
