import Anthropic from '@anthropic-ai/sdk';
import pLimit from 'p-limit';
import { supabaseAdmin, type TasteProfile } from '../db/supabase';

// Lazy-init client (dotenv must have run before first use)
let _client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY! });
  return _client;
}

// Separate rate-limit queue for personalization (max 2 concurrent, ~10/min)
const personalizeLimit = pLimit(2);

// -------------------------------------------------------
// Retry wrapper — exponential backoff on 429
// -------------------------------------------------------
async function callClaudeWithRetry(
  system: string,
  user: string,
  maxTokens = 800,
  maxRetries = 3
): Promise<string> {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await getClient().messages.create({
        model: 'claude-sonnet-4-5',
        max_tokens: maxTokens,
        system,
        messages: [{ role: 'user', content: user }],
      });
      const content = response.content[0];
      if (content.type !== 'text') throw new Error('Unexpected response type');
      return content.text;
    } catch (err: unknown) {
      const status = (err as { status?: number }).status;
      if (status === 429 && attempt < maxRetries - 1) {
        const waitMs = Math.pow(2, attempt) * 10_000;
        console.log(`[tasteProfile] Rate limited. Waiting ${waitMs / 1000}s...`);
        await sleep(waitMs);
      } else {
        throw err;
      }
    }
  }
  throw new Error('[tasteProfile] Max retries exceeded');
}

// -------------------------------------------------------
// 1. generateTasteProfile — builds LLM taste profile from interactions
// -------------------------------------------------------
export async function generateTasteProfile(): Promise<void> {
  // Fetch positive interactions (weight > 0) with article data — top 50 by weight
  const { data: positiveRows } = await supabaseAdmin
    .from('interactions')
    .select('weight, type, article_id, articles(title, content, category, key_entities, feeds(name))')
    .gt('weight', 0)
    .order('weight', { ascending: false })
    .limit(50);

  // Fetch negative interactions — last 30
  const { data: negativeRows } = await supabaseAdmin
    .from('interactions')
    .select('weight, type, article_id, articles(title, category, feeds(name))')
    .lt('weight', 0)
    .order('occurred_at', { ascending: false })
    .limit(30);

  if (!positiveRows?.length) {
    console.log('[tasteProfile] Not enough positive interactions to build profile');
    return;
  }

  const positiveArticles = positiveRows.map((r) => {
    const a = r.articles as unknown as { title: string; content: string | null; category: string | null; key_entities: string[] | null; feeds: { name: string } | { name: string }[] | null } | null;
    const feed = Array.isArray(a?.feeds) ? a?.feeds[0] : a?.feeds;
    return {
      title: a?.title ?? '',
      category: a?.category ?? '',
      key_entities: a?.key_entities ?? [],
      source: feed?.name ?? '',
      interaction: r.type,
      weight: r.weight,
      summary: (a?.content ?? '').slice(0, 200),
    };
  });

  const negativeArticles = (negativeRows ?? []).map((r) => {
    const a = r.articles as unknown as { title: string; category: string | null; feeds: { name: string } | { name: string }[] | null } | null;
    const feed = Array.isArray(a?.feeds) ? a?.feeds[0] : a?.feeds;
    return {
      title: a?.title ?? '',
      category: a?.category ?? '',
      source: feed?.name ?? '',
      interaction: r.type,
    };
  });

  const systemPrompt = `You are building a precise interest profile from reading behavior. Be specific, not generic. Name exact topics, models, benchmarks, techniques. Capture what this person cares about deeply vs. what they ignore.`;

  const userPrompt = `Analyze this person's reading behavior and create a detailed interest profile.

DEEPLY ENGAGED (saved, read thoroughly, shared):
${JSON.stringify(positiveArticles, null, 2)}

IGNORED OR DISMISSED:
${JSON.stringify(negativeArticles, null, 2)}

Return ONLY valid JSON, no other text:
{
  "profile_text": "2-3 paragraph natural language description of exactly what this person cares about. Name specific models, benchmarks, techniques, researchers they engage with. Note what they avoid. This text will be injected into future Claude prompts to personalize scoring and discovery.",
  "primary_interests": {
    "LLM inference optimization": 0.9
  },
  "top_sources": [
    {"name": "Anthropic Engineering", "engagement": 0.95}
  ],
  "key_entities": {
    "models": ["Claude", "Llama"],
    "benchmarks": ["GPQA", "SWE-bench"],
    "techniques": ["RLHF", "inference optimization"],
    "organizations": ["Anthropic", "DeepMind"]
  },
  "anti_interests": ["AI art", "consumer apps"],
  "confidence_score": 0.0
}`;

  let raw: string;
  try {
    raw = await callClaudeWithRetry(systemPrompt, userPrompt, 1200);
  } catch (err) {
    console.error('[tasteProfile] Failed to generate profile:', err);
    return;
  }

  // Strip markdown fences
  const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();

  let parsed: {
    profile_text: string;
    primary_interests: Record<string, number>;
    top_sources: Array<{ name: string; engagement: number }>;
    key_entities: { models: string[]; benchmarks: string[]; techniques: string[]; organizations: string[] };
    anti_interests: string[];
    confidence_score: number;
  };

  try {
    parsed = JSON.parse(cleaned);
  } catch {
    console.error('[tasteProfile] Failed to parse profile JSON:', cleaned.slice(0, 200));
    return;
  }

  // Get total interaction count for based_on_interactions
  const { count } = await supabaseAdmin
    .from('interactions')
    .select('id', { count: 'exact', head: true });

  const { data: existing } = await supabaseAdmin
    .from('user_taste_profile')
    .select('id')
    .limit(1)
    .single();

  if (existing?.id) {
    await supabaseAdmin.from('user_taste_profile').update({
      profile_text: parsed.profile_text,
      primary_interests: parsed.primary_interests,
      top_sources: parsed.top_sources,
      key_entities: parsed.key_entities,
      anti_interests: parsed.anti_interests,
      confidence_score: Math.min(1.0, (count ?? 0) / 50),
      based_on_interactions: count ?? 0,
      last_updated: new Date().toISOString(),
    }).eq('id', existing.id);
  } else {
    await supabaseAdmin.from('user_taste_profile').insert({
      profile_text: parsed.profile_text,
      primary_interests: parsed.primary_interests,
      top_sources: parsed.top_sources,
      key_entities: parsed.key_entities,
      anti_interests: parsed.anti_interests,
      confidence_score: Math.min(1.0, (count ?? 0) / 50),
      based_on_interactions: count ?? 0,
    });
  }

  const topInterests = Object.entries(parsed.primary_interests)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([k]) => k)
    .join(', ');

  const confidence = Math.round(Math.min(100, ((count ?? 0) / 50) * 100));
  console.log(`[tasteProfile] Profile updated. Confidence: ${confidence}%. Top: ${topInterests}`);
}

// -------------------------------------------------------
// 2. scoreArticleAgainstProfile — personalization score 0-1
// -------------------------------------------------------
export async function scoreArticleAgainstProfile(
  article: { id: string; title: string; content: string | null; category: string | null; key_entities: string[] | null; score: number | null },
  profile: TasteProfile,
  sourceName: string = ''
): Promise<{ score: number; reason: string } | null> {
  if (profile.confidence_score < 0.3) return null;

  return personalizeLimit(async () => {
    const systemPrompt = `Score this article's relevance to one specific person. Not whether it is good AI news generally — whether THIS person cares. You have their detailed interest profile. Use it.`;

    const userPrompt = `Person's interest profile:
${profile.profile_text}

Their interests: ${JSON.stringify(profile.primary_interests)}
Entities they follow: ${JSON.stringify(profile.key_entities)}
What they avoid: ${profile.anti_interests.join(', ')}

Article to score:
Title: ${article.title}
Source: ${sourceName}
Category: ${article.category ?? 'unknown'}
Key entities: ${article.key_entities?.join(', ') ?? 'none'}
Summary: ${(article.content ?? '').slice(0, 300)}

Return ONLY valid JSON:
{"score": 0.0, "reason": "max 10 words why it matches or doesn't"}`;

    let raw: string;
    try {
      raw = await callClaudeWithRetry(systemPrompt, userPrompt, 100);
    } catch {
      return null;
    }

    const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();

    try {
      const parsed = JSON.parse(cleaned) as { score: number; reason: string };
      const score = Math.max(0, Math.min(1, Number(parsed.score)));

      // Persist to DB (non-blocking, best-effort)
      supabaseAdmin.from('articles').update({
        personalization_score: score,
        profile_match_reason: String(parsed.reason).slice(0, 100),
      }).eq('id', article.id).then(() => {});

      return { score, reason: parsed.reason };
    } catch {
      return null;
    }
  });
}

// -------------------------------------------------------
// 3. rescoreRecentArticlesAgainstProfile — re-rank last 100 articles
// -------------------------------------------------------
export async function rescoreRecentArticlesAgainstProfile(): Promise<void> {
  const profile = await getCurrentTasteProfile();
  if (!profile || profile.confidence_score < 0.3) return;

  const { data: articles } = await supabaseAdmin
    .from('articles')
    .select('id, title, content, category, key_entities, score, feeds(name)')
    .not('score', 'is', null)
    .gte('score', 7)
    .order('published_at', { ascending: false })
    .limit(100);

  if (!articles?.length) return;

  console.log(`[tasteProfile] Re-scoring ${articles.length} recent articles against profile...`);

  const batchSize = 10;
  for (let i = 0; i < articles.length; i += batchSize) {
    const batch = articles.slice(i, i + batchSize);
    await Promise.all(batch.map((a) => {
      const feed = Array.isArray(a.feeds) ? a.feeds[0] : a.feeds;
      return scoreArticleAgainstProfile(
        { id: a.id, title: a.title, content: a.content, category: a.category, key_entities: a.key_entities, score: a.score },
        profile,
        (feed as { name?: string } | null)?.name ?? ''
      );
    }));
    if (i + batchSize < articles.length) await sleep(3000);
  }

  console.log('[tasteProfile] Re-scoring complete');
}

// -------------------------------------------------------
// 4. getCurrentTasteProfile
// -------------------------------------------------------
export async function getCurrentTasteProfile(): Promise<TasteProfile | null> {
  const { data } = await supabaseAdmin
    .from('user_taste_profile')
    .select('*')
    .order('last_updated', { ascending: false })
    .limit(1)
    .single();

  return (data as TasteProfile | null) ?? null;
}

// -------------------------------------------------------
// 5. getPersonalizedFeed — three-factor ranking
// final_rank = (claude_score * 0.5) + (personalization_score * 0.35 * 10) + recency_bonus
// -------------------------------------------------------
export async function getPersonalizedFeed(
  limit: number,
  offset: number,
  category?: string,
  unreadOnly?: boolean
): Promise<unknown[]> {
  let query = supabaseAdmin
    .from('articles')
    .select('*, feeds(name, category)')
    .not('score', 'is', null)
    .gte('score', 7)
    .eq('dismissed', false);

  if (category && category !== 'all') {
    query = query.eq('category', category);
  }

  if (unreadOnly) {
    query = query.eq('is_read', false);
  }

  // Fetch more than needed so we can re-rank in JS
  const candidateLimit = offset + limit + 100;

  const { data: articles, error } = await query
    .order('score', { ascending: false })
    .order('published_at', { ascending: false })
    .limit(candidateLimit);

  if (error || !articles) return [];

  const now = Date.now();

  const ranked = articles.map((article) => {
    const recency = (() => {
      if (!article.published_at) return 0.4;
      const ageMs = now - new Date(article.published_at).getTime();
      const ageHours = ageMs / (1000 * 60 * 60);
      if (ageHours < 6) return 1.5;
      if (ageHours < 24) return 1.0;
      if (ageHours < 72) return 0.7;
      return 0.4;
    })();

    const personScore = article.personalization_score ?? 0.5;
    const finalRank =
      (article.score * 0.5) + (personScore * 0.35 * 10) + recency;

    return { ...article, _final_rank: finalRank };
  });

  ranked.sort((a, b) => b._final_rank - a._final_rank);

  return ranked.slice(offset, offset + limit);
}

// -------------------------------------------------------
// Helpers
// -------------------------------------------------------
export async function getTotalInteractionCount(): Promise<number> {
  const { count } = await supabaseAdmin
    .from('interactions')
    .select('id', { count: 'exact', head: true });
  return count ?? 0;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
