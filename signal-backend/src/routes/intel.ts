import { Router, type Request, type Response } from 'express';
import { supabaseAdmin } from '../db/supabase';

const router = Router();

// -------------------------------------------------------
// GET /api/stats
// Dashboard statistics
// -------------------------------------------------------
router.get('/stats', async (_req: Request, res: Response) => {
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  try {
    // Articles today (score >= 7)
    const { count: articlesCount } = await supabaseAdmin
      .from('articles')
      .select('*', { count: 'exact', head: true })
      .gte('score', 7)
      .gte('created_at', oneDayAgo);

    // Breaking today (score >= 9)
    const { count: breakingCount } = await supabaseAdmin
      .from('articles')
      .select('*', { count: 'exact', head: true })
      .gte('score', 9)
      .gte('created_at', oneDayAgo);

    // Articles by category (today)
    const { data: categoryData } = await supabaseAdmin
      .from('articles')
      .select('category')
      .gte('score', 7)
      .gte('created_at', oneDayAgo)
      .not('category', 'is', null);

    const byCategory: Record<string, number> = {};
    for (const row of categoryData ?? []) {
      if (row.category) {
        byCategory[row.category] = (byCategory[row.category] ?? 0) + 1;
      }
    }

    // Total interactions (taste strength)
    const { count: interactionCount } = await supabaseAdmin
      .from('interactions')
      .select('*', { count: 'exact', head: true })
      .in('type', ['read_30s', 'read_60s', 'saved', 'shared']);

    const tasteStrength = Math.min(100, Math.floor(((interactionCount ?? 0) / 30) * 100));

    // Active feeds count
    const { count: sourcesActive } = await supabaseAdmin
      .from('feeds')
      .select('*', { count: 'exact', head: true })
      .eq('is_active', true);

    // Sources discovered this week
    const { count: sourcesDiscoveredThisWeek } = await supabaseAdmin
      .from('discovered_sources')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'added')
      .gte('discovered_at', oneWeekAgo);

    // Last refresh time
    const { data: lastRefreshData } = await supabaseAdmin
      .from('feeds')
      .select('last_fetched_at')
      .not('last_fetched_at', 'is', null)
      .order('last_fetched_at', { ascending: false })
      .limit(1)
      .single();

    // Top sources today
    const { data: topSourcesData } = await supabaseAdmin
      .from('articles')
      .select('feed_id, feeds(name)')
      .gte('score', 7)
      .gte('created_at', oneDayAgo)
      .not('feed_id', 'is', null);

    const sourceCounts: Record<string, { name: string; count: number }> = {};
    for (const row of topSourcesData ?? []) {
      const feedId = row.feed_id as string;
      const feedsData = row.feeds as { name: string } | { name: string }[] | null;
      const feedName = Array.isArray(feedsData) ? feedsData[0]?.name ?? feedId : feedsData?.name ?? feedId;
      if (!sourceCounts[feedId]) sourceCounts[feedId] = { name: feedName, count: 0 };
      sourceCounts[feedId].count++;
    }

    const topSources = Object.values(sourceCounts)
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);

    // New sources added flag (for notification check)
    const { count: newSourcesAdded } = await supabaseAdmin
      .from('feeds')
      .select('*', { count: 'exact', head: true })
      .eq('is_auto_discovered', true)
      .gte('created_at', oneWeekAgo);

    res.json({
      articles_today: articlesCount ?? 0,
      breaking_today: breakingCount ?? 0,
      by_category: byCategory,
      taste_strength: tasteStrength,
      interaction_count: interactionCount ?? 0,
      sources_active: sourcesActive ?? 0,
      sources_discovered_this_week: sourcesDiscoveredThisWeek ?? 0,
      last_refresh: lastRefreshData?.last_fetched_at ?? null,
      top_sources_today: topSources,
      new_sources_added: newSourcesAdded ?? 0,
    });
  } catch (err) {
    console.error('[intel] GET /stats error:', err);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// -------------------------------------------------------
// GET /api/profile
// Returns the current LLM taste profile
// -------------------------------------------------------
router.get('/profile', async (_req: Request, res: Response) => {
  try {
    const { getCurrentTasteProfile, getTotalInteractionCount } = await import('../services/tasteProfileService');
    const [profile, interactionCount] = await Promise.all([
      getCurrentTasteProfile(),
      getTotalInteractionCount(),
    ]);

    if (!profile || interactionCount < 5) {
      res.status(404).json({
        message: 'Profile not ready yet',
        interactions_needed: 5,
        current_interactions: interactionCount,
      });
      return;
    }

    res.json({ ...profile, interaction_count: interactionCount });
  } catch (err) {
    console.error('[intel] GET /profile error:', err);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

// -------------------------------------------------------
// POST /api/push/register
// Register an APNs device token
// -------------------------------------------------------
router.post('/push/register', async (req: Request, res: Response) => {
  const { token } = req.body as { token?: string };
  if (!token || typeof token !== 'string' || token.trim().length === 0) {
    res.status(400).json({ error: 'Missing or invalid token' });
    return;
  }

  try {
    const { error } = await supabaseAdmin
      .from('push_tokens')
      .upsert({ token: token.trim() }, { onConflict: 'token' });

    if (error) throw error;
    res.json({ success: true });
  } catch (err) {
    console.error('[intel] POST /push/register error:', err);
    res.status(500).json({ error: 'Failed to register push token' });
  }
});

// -------------------------------------------------------
// POST /api/refresh
// Manual trigger for full feed refresh + scoring pipeline
// -------------------------------------------------------
router.post('/refresh', async (_req: Request, res: Response) => {
  res.json({ message: 'Feed refresh triggered', started_at: new Date().toISOString() });

  // Run asynchronously after responding (fire-and-forget)
  setImmediate(async () => {
    try {
      const { runFeedRefresh } = await import('../jobs/feedRefreshJob');
      await runFeedRefresh();
    } catch (err) {
      console.error('[intel] Manual refresh failed:', err);
    }
  });
});

// -------------------------------------------------------
// POST /api/refresh/discover
// Manual trigger for discovery agent
// -------------------------------------------------------
router.post('/refresh/discover', async (_req: Request, res: Response) => {
  res.json({ message: 'Discovery agent triggered', started_at: new Date().toISOString() });

  setImmediate(async () => {
    try {
      const { runDiscovery } = await import('../jobs/discoveryJob');
      await runDiscovery();
    } catch (err) {
      console.error('[intel] Manual discovery failed:', err);
    }
  });
});

export default router;
