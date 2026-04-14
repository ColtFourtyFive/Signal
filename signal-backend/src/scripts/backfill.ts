/**
 * Backfill script — score all articles that have score = null
 * Run with: npm run backfill
 *
 * Uses batches of 35 with 65-second delays to stay under 50 RPM limit.
 * Estimated runtime: ~1 minute per 35 articles.
 */
import dotenv from 'dotenv';
dotenv.config({ override: true, path: '../../.env' });

// Fallback for when run from project root
if (!process.env.ANTHROPIC_API_KEY) {
  dotenv.config({ override: true });
}

import { supabaseAdmin } from '../db/supabase';
import { scoreAndPersistArticles } from '../services/scoringService';
import type { RawArticle } from '../services/rssService';

const BATCH_SIZE = 35;
const DELAY_MS = 65_000; // 65 seconds between batches (under 50 RPM)

async function backfill(): Promise<void> {
  console.log('[backfill] Fetching articles with null score...');

  const { data: articles, error } = await supabaseAdmin
    .from('articles')
    .select('id, feed_id, title, url, content, published_at')
    .is('score', null)
    .order('published_at', { ascending: false });

  if (error) {
    console.error('[backfill] Failed to fetch articles:', error);
    process.exit(1);
  }

  if (!articles?.length) {
    console.log('[backfill] No articles with null score. Nothing to do.');
    process.exit(0);
  }

  console.log(`[backfill] Backfilling ${articles.length} articles in batches of ${BATCH_SIZE}...`);
  console.log(`[backfill] Estimated time: ~${Math.ceil(articles.length / BATCH_SIZE)} minutes\n`);

  let totalScored = 0;
  let totalPersisted = 0;
  let totalFailed = 0;

  for (let i = 0; i < articles.length; i += BATCH_SIZE) {
    const batch = articles.slice(i, i + BATCH_SIZE);
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;
    const totalBatches = Math.ceil(articles.length / BATCH_SIZE);

    console.log(`[backfill] Batch ${batchNum}/${totalBatches} — scoring ${batch.length} articles...`);

    const rawArticles: RawArticle[] = batch.map((a) => ({
      feedId: a.feed_id ?? 'backfill',
      feedName: 'backfill',
      title: a.title,
      url: a.url,
      content: a.content,
      publishedAt: a.published_at,
    }));

    // Delete null-score rows first so upsert works cleanly
    const urls = batch.map((a) => a.url);
    await supabaseAdmin.from('articles').delete().in('url', urls).is('score', null);

    const result = await scoreAndPersistArticles(rawArticles);
    totalScored += result.scored;
    totalPersisted += result.persisted;
    totalFailed += result.failed;

    const progress = Math.min(i + BATCH_SIZE, articles.length);
    console.log(
      `[backfill] Progress: ${progress}/${articles.length} ` +
      `(scored: ${result.scored}, persisted: ${result.persisted}, failed: ${result.failed})`
    );

    if (i + BATCH_SIZE < articles.length) {
      console.log(`[backfill] Waiting ${DELAY_MS / 1000}s before next batch...`);
      await sleep(DELAY_MS);
    }
  }

  console.log('\n[backfill] ✓ Complete!');
  console.log(`  Total scored:    ${totalScored}`);
  console.log(`  Total persisted: ${totalPersisted} (score >= 7)`);
  console.log(`  Total failed:    ${totalFailed}`);
  process.exit(0);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

backfill().catch((err) => {
  console.error('[backfill] Fatal error:', err);
  process.exit(1);
});
