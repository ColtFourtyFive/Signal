import { Router, type Request, type Response } from 'express';
import { supabaseAdmin } from '../db/supabase';
import { discoverRssUrl, validateAndSampleFeed } from '../services/rssService';
import { scoreArticlesForValidation } from '../services/scoringService';

const router = Router();

// -------------------------------------------------------
// GET /api/feeds
// All active feeds with metadata
// -------------------------------------------------------
router.get('/', async (_req: Request, res: Response) => {
  try {
    const { data, error } = await supabaseAdmin
      .from('feeds')
      .select('*')
      .order('avg_score', { ascending: false });

    if (error) throw error;
    res.json({ feeds: data ?? [] });
  } catch (err) {
    console.error('[feeds] GET / error:', err);
    res.status(500).json({ error: 'Failed to fetch feeds' });
  }
});

// -------------------------------------------------------
// POST /api/feeds/add
// Validate RSS URL, score sample articles, add if avg >= 6
// -------------------------------------------------------
router.post('/add', async (req: Request, res: Response) => {
  const { url, name } = req.body as { url?: string; name?: string };

  if (!url?.trim()) {
    res.status(400).json({ error: 'url is required' });
    return;
  }

  try {
    // Check if already subscribed
    const { data: existing } = await supabaseAdmin
      .from('feeds')
      .select('id')
      .eq('url', url.trim())
      .single();

    if (existing) {
      res.status(409).json({ error: 'Feed already exists' });
      return;
    }

    // Try to find a valid RSS URL
    const rssUrl = await discoverRssUrl(url.trim());
    if (!rssUrl) {
      res.status(422).json({ error: 'Could not find a valid RSS feed at this URL' });
      return;
    }

    // Sample and score recent articles
    const sampleArticles = await validateAndSampleFeed(rssUrl);
    if (!sampleArticles?.length) {
      res.status(422).json({ error: 'Feed is empty or unreadable' });
      return;
    }

    const scores = await scoreArticlesForValidation(sampleArticles);
    const avgScore = scores.length
      ? scores.reduce((a, b) => a + b, 0) / scores.length
      : 0;

    if (avgScore < 6) {
      res.status(422).json({
        error: `Feed average score is ${avgScore.toFixed(1)} (minimum 6.0 required)`,
        avg_score: avgScore,
      });
      return;
    }

    // Add to feeds table
    const feedName = name?.trim() || sampleArticles[0]?.feedName || new URL(rssUrl).hostname;
    const { data: feed, error: insertError } = await supabaseAdmin
      .from('feeds')
      .insert({ name: feedName, url: rssUrl, avg_score: avgScore })
      .select()
      .single();

    if (insertError) throw insertError;

    res.status(201).json({ feed, avg_score: avgScore });
  } catch (err) {
    console.error('[feeds] POST /add error:', err);
    res.status(500).json({ error: 'Failed to add feed' });
  }
});

// -------------------------------------------------------
// DELETE /api/feeds/:id
// Soft-delete: set is_active = false
// -------------------------------------------------------
router.delete('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const { error } = await supabaseAdmin
      .from('feeds')
      .update({ is_active: false })
      .eq('id', id);

    if (error) throw error;
    res.json({ success: true });
  } catch (err) {
    console.error('[feeds] DELETE /:id error:', err);
    res.status(500).json({ error: 'Failed to delete feed' });
  }
});

// -------------------------------------------------------
// GET /api/feeds/discovered
// Auto-discovered sources (pending manual review)
// -------------------------------------------------------
router.get('/discovered', async (_req: Request, res: Response) => {
  try {
    const { data, error } = await supabaseAdmin
      .from('discovered_sources')
      .select('*')
      .order('discovered_at', { ascending: false });

    if (error) throw error;
    res.json({ sources: data ?? [] });
  } catch (err) {
    console.error('[feeds] GET /discovered error:', err);
    res.status(500).json({ error: 'Failed to fetch discovered sources' });
  }
});

// -------------------------------------------------------
// PATCH /api/feeds/discovered/:id
// Approve or reject a pending discovered source
// -------------------------------------------------------
router.patch('/discovered/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { status } = req.body as { status: 'added' | 'rejected' };

  if (status !== 'added' && status !== 'rejected') {
    res.status(400).json({ error: 'status must be "added" or "rejected"' });
    return;
  }

  try {
    const { data: source, error: fetchError } = await supabaseAdmin
      .from('discovered_sources')
      .select('*')
      .eq('id', id)
      .single();

    if (fetchError || !source) {
      res.status(404).json({ error: 'Discovered source not found' });
      return;
    }

    await supabaseAdmin
      .from('discovered_sources')
      .update({ status })
      .eq('id', id);

    // If approving, add to active feeds
    if (status === 'added' && source.rss_url) {
      const { data: existingFeed } = await supabaseAdmin
        .from('feeds')
        .select('id')
        .eq('url', source.rss_url)
        .single();

      if (!existingFeed) {
        await supabaseAdmin.from('feeds').insert({
          name: source.name ?? source.url ?? 'Discovered Feed',
          url: source.rss_url,
          is_auto_discovered: true,
          avg_score: source.avg_score ?? 0,
        });
      }
    }

    res.json({ success: true, status });
  } catch (err) {
    console.error('[feeds] PATCH /discovered/:id error:', err);
    res.status(500).json({ error: 'Failed to update discovered source' });
  }
});

export default router;
