import cron from 'node-cron';
import { supabaseAdmin, type Feed } from '../db/supabase';
import { getNewArticlesFromFeeds } from '../services/rssService';
import { scoreAndPersistArticles } from '../services/scoringService';

// Run a full feed refresh: fetch all active feeds → score → persist score >= 7
export async function runFeedRefresh(): Promise<void> {
  const startedAt = new Date();
  console.log(`[feedRefreshJob] Starting feed refresh at ${startedAt.toISOString()}`);

  try {
    const { data: feeds, error } = await supabaseAdmin
      .from('feeds')
      .select('*')
      .eq('is_active', true);

    if (error || !feeds?.length) {
      console.warn('[feedRefreshJob] No active feeds found');
      return;
    }

    console.log(`[feedRefreshJob] Fetching ${feeds.length} feeds...`);
    const newArticles = await getNewArticlesFromFeeds(feeds as Feed[]);

    if (!newArticles.length) {
      console.log('[feedRefreshJob] No new articles found');
      return;
    }

    console.log(`[feedRefreshJob] Scoring ${newArticles.length} new articles...`);
    const { scored, persisted, failed } = await scoreAndPersistArticles(newArticles);

    const duration = ((Date.now() - startedAt.getTime()) / 1000).toFixed(1);
    console.log(
      `[feedRefreshJob] Done in ${duration}s — scored: ${scored}, persisted: ${persisted} (score >= 7), failed: ${failed}`
    );
  } catch (err) {
    console.error('[feedRefreshJob] Unexpected error during refresh:', err);
  }
}

// Schedule: run every 2 hours + immediately on start
export function startFeedRefreshJob(): void {
  // Immediate run on server start
  runFeedRefresh().catch(err =>
    console.error('[feedRefreshJob] Initial run failed:', err)
  );

  // Every 2 hours
  cron.schedule('0 */2 * * *', () => {
    runFeedRefresh().catch(err =>
      console.error('[feedRefreshJob] Scheduled run failed:', err)
    );
  });

  console.log('[feedRefreshJob] Scheduled (every 2 hours + immediate)');
}
