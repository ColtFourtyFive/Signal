import cron from 'node-cron';
import {
  generateTasteProfile,
  rescoreRecentArticlesAgainstProfile,
  getCurrentTasteProfile,
  getTotalInteractionCount,
} from '../services/tasteProfileService';

function isOlderThanHours(dateStr: string | undefined, hours: number): boolean {
  if (!dateStr) return true;
  const ageMs = Date.now() - new Date(dateStr).getTime();
  return ageMs > hours * 60 * 60 * 1000;
}

// Core refresh logic — checks whether a refresh is warranted before calling Claude
export async function maybeRefreshProfile(): Promise<void> {
  const [totalInteractions, profile] = await Promise.all([
    getTotalInteractionCount(),
    getCurrentTasteProfile(),
  ]);

  const newInteractionsSinceUpdate =
    totalInteractions - (profile?.based_on_interactions ?? 0);

  const needsRefresh =
    !profile ||
    newInteractionsSinceUpdate >= 10 ||
    isOlderThanHours(profile.last_updated, 12);

  if (!needsRefresh) return;

  console.log(
    `[profileRefreshJob] Refreshing profile (${newInteractionsSinceUpdate} new interactions, ` +
    `confidence: ${((profile?.confidence_score ?? 0) * 100).toFixed(0)}%)...`
  );

  await generateTasteProfile();
  await rescoreRecentArticlesAgainstProfile();

  console.log('[profileRefreshJob] Profile refresh complete');
}

// Fallback cron — every 12 hours in case interaction-triggered refresh misses
export function startProfileRefreshJob(): void {
  cron.schedule('0 */12 * * *', () => {
    maybeRefreshProfile().catch((err) =>
      console.error('[profileRefreshJob] Scheduled refresh failed:', err)
    );
  });

  console.log('[profileRefreshJob] Scheduled (every 12 hours + on-demand)');
}
