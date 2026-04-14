import Anthropic from '@anthropic-ai/sdk';
import pLimit from 'p-limit';
import { supabaseAdmin, type ArticleCategory } from '../db/supabase';
import type { RawArticle } from './rssService';

// Lazy init so dotenv has time to load before the client is created
let _client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY! });
  return _client;
}

// Rate limit: max 3 concurrent scoring requests (50 RPM limit)
const limit = pLimit(3);

const VALID_CATEGORIES: ArticleCategory[] = [
  'model_release',
  'benchmark',
  'research_paper',
  'open_source',
  'engineering_post',
  'funding',
  'industry',
  'noise',
];

// -------------------------------------------------------
// The scoring prompt — DO NOT simplify this
// -------------------------------------------------------
const SYSTEM_PROMPT = `You are the signal filter for an AI infrastructure startup founder who needs frontier AI intelligence. You deeply understand the difference between:
- PRIMARY SOURCE CONTENT: lab engineering posts, actual papers, model weights/releases, benchmark results from the source
- SECONDARY REPORTING: journalism about those things

Primary sources always score higher. Apply rigorous standards.

Score each article 1-10:

SCORE 9-10 — CRITICAL:
- New frontier model release or open weights dropped
- Benchmark record broken / new SOTA on major eval (MMLU, HumanEval, GPQA, SWE-bench, MATH, etc.)
- Primary lab engineering post with technical depth (Anthropic/OpenAI/DeepMind/Meta blog — their actual post)
- Major academic paper with novel finding (arXiv primary)
- Significant open source model, tool or framework launch
- AI infrastructure architecture breakthrough
- Funding round $100M+ or major acquisition in frontier AI
- Indie dev ships something genuinely novel (agents, infra, tools)

SCORE 7-8 — HIGH SIGNAL:
- New model capability or significant API change
- Interesting academic paper / empirical study
- Notable new open source project, repo or tool
- Technical deep-dive from a practitioner at a frontier lab
- AI company product announcement with real technical content
- Industry move with strategic implications
- New benchmark or evaluation framework

SCORE 4-6 — LOW SIGNAL (store but de-emphasize):
- Opinion without new data or primary research
- Incremental updates, minor releases
- Secondary reporting on something already scored above 7
- Analysis without novel insights
- Conference announcements without content

SCORE 1-3 — NOISE (do not show):
- Changelogs, patch notes, bug fixes
- Job postings, hiring announcements
- Event announcements without substance
- Marketing or PR content
- Exact duplicate coverage of same story
- Anything not related to AI/ML/research/infrastructure

Return ONLY valid JSON, nothing else:
{
  "score": <number 1-10>,
  "reason": "<max 12 words, be specific — name the actual model/paper/tool/benchmark>",
  "category": "<one of: model_release | benchmark | research_paper | open_source | engineering_post | funding | industry | noise>",
  "is_primary_source": <true or false>,
  "key_entities": ["<up to 5 model names, benchmark names, lab names, tool names>"]
}`;

export interface ScoredArticle {
  raw: RawArticle;
  score: number;
  reason: string;
  category: ArticleCategory;
  is_primary_source: boolean;
  key_entities: string[];
}

interface ClaudeScoreResponse {
  score: number;
  reason: string;
  category: ArticleCategory;
  is_primary_source: boolean;
  key_entities: string[];
}

// Score a single article — returns null if Claude call or parse fails
async function scoreArticle(article: RawArticle): Promise<ClaudeScoreResponse | null> {
  const userMessage = `Source: ${article.feedName}
Title: ${article.title}
Summary: ${(article.content ?? '').slice(0, 500)}`;

  try {
    const response = await getClient().messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 300,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userMessage }],
    });

    const text = response.content[0].type === 'text' ? response.content[0].text : '';

    // Strip markdown code fences if Claude wraps the JSON
    const cleaned = text
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();

    const parsed = JSON.parse(cleaned) as ClaudeScoreResponse;

    // Validate shape
    if (
      typeof parsed.score !== 'number' ||
      parsed.score < 1 ||
      parsed.score > 10 ||
      !VALID_CATEGORIES.includes(parsed.category) ||
      typeof parsed.is_primary_source !== 'boolean'
    ) {
      console.warn(`[scoringService] Invalid score shape for "${article.title}":`, parsed);
      return null;
    }

    // Clamp key_entities to max 5
    parsed.key_entities = (parsed.key_entities ?? []).slice(0, 5);

    return parsed;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(`[scoringService] Failed to score "${article.title}": ${msg}`);
    return null;
  }
}

// Score a batch of articles and persist results to Supabase
// Only articles with score >= 7 are persisted (score=null failures are stored for retry)
export async function scoreAndPersistArticles(articles: RawArticle[]): Promise<{
  scored: number;
  persisted: number;
  failed: number;
}> {
  if (articles.length === 0) return { scored: 0, persisted: 0, failed: 0 };

  let scored = 0;
  let persisted = 0;
  let failed = 0;

  // 50 RPM limit → batch of 3 with 4-second delay ≈ 45 RPM
  const batchSize = 3;
  // Cap per-run to avoid exhausting the rate limit on first load (retry handles the rest)
  const toScore = articles.slice(0, 120);
  if (articles.length > 120) {
    console.log(`[scoringService] Capping this run to 120 articles (${articles.length - 120} queued for next cycle)`);
  }
  for (let i = 0; i < toScore.length; i += batchSize) {
    const batch = toScore.slice(i, i + batchSize);

    const results = await Promise.all(
      batch.map(article => limit(() => scoreArticle(article)))
    );

    // Persist results
    for (let j = 0; j < batch.length; j++) {
      const article = batch[j];
      const result = results[j];

      if (result === null) {
        // Scoring failed — store with score=null for retry in next cron cycle
        failed++;
        await supabaseAdmin.from('articles').upsert(
          {
            feed_id: article.feedId === 'validation' ? null : article.feedId,
            title: article.title,
            url: article.url,
            content: article.content,
            published_at: article.publishedAt,
            score: null,
          },
          { onConflict: 'url', ignoreDuplicates: true }
        );
        continue;
      }

      scored++;

      // Discard articles with score < 7 — they are noise
      if (result.score < 7) {
        continue;
      }

      // Persist high-signal articles — use ignoreDuplicates: false so that
      // articles previously stored with score=null get their score updated
      const { error } = await supabaseAdmin.from('articles').upsert(
        {
          feed_id: article.feedId === 'validation' ? null : article.feedId,
          title: article.title,
          url: article.url,
          content: article.content,
          published_at: article.publishedAt,
          score: result.score,
          score_reason: result.reason,
          category: result.category,
          is_primary_source: result.is_primary_source,
          key_entities: result.key_entities,
        },
        { onConflict: 'url', ignoreDuplicates: false }
      );

      if (error) {
        console.error(`[scoringService] Failed to persist "${article.title}":`, error);
      } else {
        persisted++;
        // Update feed stats asynchronously
        if (article.feedId !== 'validation') {
          updateFeedStats(article.feedId, result.score).catch(() => {});
        }
        // Non-blocking personalization scoring (separate rate-limit queue)
        triggerPersonalizationScore(article, result.score).catch(() => {});
      }
    }

    // 4s delay between batches → ~45 RPM (safely under 50 RPM limit)
    if (i + batchSize < toScore.length) {
      await sleep(4000);
    }
  }

  // Retry articles that previously failed scoring (score IS NULL)
  retryFailedScoring().catch(() => {});

  return { scored, persisted, failed };
}

// Score articles for feed validation (used by discovery + manual add)
// Returns array of scores without persisting
export async function scoreArticlesForValidation(articles: RawArticle[]): Promise<number[]> {
  const results = await Promise.all(
    articles.slice(0, 5).map(article => limit(() => scoreArticle(article)))
  );
  return results
    .filter((r): r is ClaudeScoreResponse => r !== null)
    .map(r => r.score);
}

// Retry articles with score=null from previous failed scoring attempts
async function retryFailedScoring(): Promise<void> {
  const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();

  const { data: failed } = await supabaseAdmin
    .from('articles')
    .select('id, feed_id, title, url, content, published_at')
    .is('score', null)
    .lt('fetched_at', fiveMinutesAgo)
    .limit(120);

  if (!failed?.length) return;

  console.log(`[scoringService] Retrying ${failed.length} failed articles...`);

  for (const article of failed) {
    const raw: RawArticle = {
      feedId: article.feed_id ?? 'unknown',
      feedName: 'retry',
      title: article.title,
      url: article.url,
      content: article.content,
      publishedAt: article.published_at,
    };

    const result = await scoreArticle(raw);
    if (!result) continue;

    if (result.score < 7) {
      // Delete — below threshold
      await supabaseAdmin.from('articles').delete().eq('id', article.id);
    } else {
      await supabaseAdmin
        .from('articles')
        .update({
          score: result.score,
          score_reason: result.reason,
          category: result.category,
          is_primary_source: result.is_primary_source,
          key_entities: result.key_entities,
        })
        .eq('id', article.id);
    }
  }
}

// Update feed avg_score and article_count
async function updateFeedStats(feedId: string, newScore: number): Promise<void> {
  const { data: feed } = await supabaseAdmin
    .from('feeds')
    .select('avg_score, article_count')
    .eq('id', feedId)
    .single();

  if (!feed) return;

  const count = (feed.article_count ?? 0) + 1;
  const avg = ((feed.avg_score ?? 0) * (count - 1) + newScore) / count;

  await supabaseAdmin
    .from('feeds')
    .update({ avg_score: avg, article_count: count })
    .eq('id', feedId);
}

// Separate rate-limit queue for personalization (max 2 concurrent, ~10/min)
const personalizeLimit = pLimit(2);

async function triggerPersonalizationScore(article: RawArticle, mainScore: number): Promise<void> {
  if (mainScore < 7) return;
  const { getCurrentTasteProfile, scoreArticleAgainstProfile } = await import('./tasteProfileService');
  const profile = await getCurrentTasteProfile();
  if (!profile || profile.confidence_score < 0.4) return;

  // Look up the persisted article by URL to get its DB id and metadata
  const { data: dbArticle } = await supabaseAdmin
    .from('articles')
    .select('id, title, content, category, key_entities, score, feeds(name)')
    .eq('url', article.url)
    .single();

  if (!dbArticle) return;

  const feed = Array.isArray(dbArticle.feeds) ? dbArticle.feeds[0] : dbArticle.feeds;
  await personalizeLimit(() =>
    scoreArticleAgainstProfile(
      { id: dbArticle.id, title: dbArticle.title, content: dbArticle.content, category: dbArticle.category, key_entities: dbArticle.key_entities, score: dbArticle.score },
      profile,
      (feed as { name?: string } | null)?.name ?? article.feedName
    )
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
