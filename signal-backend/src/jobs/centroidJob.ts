import cron from 'node-cron';
import { recomputeCentroid } from '../services/personalizationService';
import { supabaseAdmin } from '../db/supabase';

async function flagUnhealthyFeeds(): Promise<void> {
  const fortyEightHoursAgo = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();

  // Flag feeds not updated in 48+ hours as broken
  const { error: brokenError } = await supabaseAdmin
    .from('feeds')
    .update({ is_broken: true })
    .eq('is_active', true)
    .lt('last_fetched_at', fortyEightHoursAgo);

  if (brokenError) {
    console.warn('[centroidJob] Failed to flag broken feeds:', brokenError.message);
  }

  // Clear broken flag for feeds that have been fetched recently
  await supabaseAdmin
    .from('feeds')
    .update({ is_broken: false })
    .eq('is_active', true)
    .gte('last_fetched_at', fortyEightHoursAgo);

  // Flag consistently low-quality feeds (avg_score < 4.5 with at least 10 articles)
  const { error: lowQualityError } = await supabaseAdmin
    .from('feeds')
    .update({ is_low_quality: true })
    .lt('avg_score', 4.5)
    .gt('article_count', 10);

  if (lowQualityError) {
    console.warn('[centroidJob] Failed to flag low-quality feeds:', lowQualityError.message);
  }

  console.log('[centroidJob] Feed health flagging complete');
}

// Schedule: every day at 3am
export function startCentroidJob(): void {
  cron.schedule('0 3 * * *', async () => {
    try {
      await recomputeCentroid();
      await flagUnhealthyFeeds();
    } catch (err) {
      console.error('[centroidJob] Scheduled run failed:', err);
    }
  });

  console.log('[centroidJob] Scheduled (daily at 3am)');
}
