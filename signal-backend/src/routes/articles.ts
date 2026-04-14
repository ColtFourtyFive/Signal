import { Router, type Request, type Response } from 'express';
import { supabaseAdmin, type InteractionType } from '../db/supabase';

const router = Router();

const INTERACTION_WEIGHTS: Record<InteractionType, number> = {
  read_30s:    1.0,
  read_60s:    1.5,
  saved:       2.0,
  shared:      2.5,
  closed_fast: -0.3,
  dismissed:   -1.0,
};

const VALID_INTERACTION_TYPES = Object.keys(INTERACTION_WEIGHTS) as InteractionType[];

// -------------------------------------------------------
// NOTE: specific routes MUST come before /:id
// GET /feed, /feed/breaking, /saved/list, /search/query
// are all defined before /:id to avoid being swallowed
// -------------------------------------------------------

// GET /api/articles/feed
router.get('/feed', async (req: Request, res: Response) => {
  const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10));
  const limit = Math.min(50, Math.max(1, parseInt(String(req.query.limit ?? '20'), 10)));
  const offset = (page - 1) * limit;
  const category = req.query.category as string | undefined;
  const unreadOnly = req.query.unread_only === 'true';

  try {
    const { getPersonalizedFeed } = await import('../services/tasteProfileService');
    const articles = await getPersonalizedFeed(limit, offset, category, unreadOnly);
    res.json({ articles, page, limit });
  } catch (err) {
    console.error('[articles] GET /feed error:', err);
    res.status(500).json({ error: 'Failed to fetch feed' });
  }
});

// GET /api/articles/feed/breaking — score >= 9, last 8 hours
router.get('/feed/breaking', async (_req: Request, res: Response) => {
  const eightHoursAgo = new Date(Date.now() - 8 * 60 * 60 * 1000).toISOString();
  try {
    const { data, error } = await supabaseAdmin
      .from('articles')
      .select('*, feeds(name, category)')
      .gte('score', 9)
      .gte('published_at', eightHoursAgo)
      .eq('dismissed', false)
      .order('score', { ascending: false })
      .order('published_at', { ascending: false })
      .limit(10);

    if (error) throw error;
    res.json({ articles: data ?? [] });
  } catch (err) {
    console.error('[articles] GET /feed/breaking error:', err);
    res.status(500).json({ error: 'Failed to fetch breaking articles' });
  }
});

// GET /api/articles/saved/list
router.get('/saved/list', async (_req: Request, res: Response) => {
  try {
    const { data, error } = await supabaseAdmin
      .from('articles')
      .select('*, feeds(name, category)')
      .eq('is_saved', true)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json({ articles: data ?? [] });
  } catch (err) {
    console.error('[articles] GET /saved/list error:', err);
    res.status(500).json({ error: 'Failed to fetch saved articles' });
  }
});

// GET /api/articles/search/query?q=
router.get('/search/query', async (req: Request, res: Response) => {
  const q = String(req.query.q ?? '').trim();
  const limit = Math.min(50, parseInt(String(req.query.limit ?? '20'), 10));

  if (!q) {
    res.status(400).json({ error: 'Missing search query' });
    return;
  }

  try {
    const { data, error } = await supabaseAdmin
      .from('articles')
      .select('*, feeds(name, category)')
      .or(`title.ilike.%${q}%,content.ilike.%${q}%`)
      .gte('score', 7)
      .order('score', { ascending: false })
      .limit(limit);

    if (error) throw error;
    res.json({ articles: data ?? [], query: q });
  } catch (err) {
    console.error('[articles] GET /search/query error:', err);
    res.status(500).json({ error: 'Search failed' });
  }
});

// GET /api/articles/:id  — must be after all static routes
router.get('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  try {
    const { data, error } = await supabaseAdmin
      .from('articles')
      .select('*, feeds(name, category)')
      .eq('id', id)
      .single();

    if (error || !data) {
      res.status(404).json({ error: 'Article not found' });
      return;
    }
    res.json({ article: data });
  } catch (err) {
    console.error('[articles] GET /:id error:', err);
    res.status(500).json({ error: 'Failed to fetch article' });
  }
});

// PATCH /api/articles/:id/interact
router.patch('/:id/interact', async (req: Request, res: Response) => {
  const id = String(req.params.id);
  const { type } = req.body as { type: InteractionType };

  if (!VALID_INTERACTION_TYPES.includes(type)) {
    res.status(400).json({
      error: `Invalid type. Must be one of: ${VALID_INTERACTION_TYPES.join(', ')}`,
    });
    return;
  }

  const weight = INTERACTION_WEIGHTS[type];

  try {
    const { data: article, error: fetchError } = await supabaseAdmin
      .from('articles')
      .select('id, title, url, content, interaction_count')
      .eq('id', id)
      .single();

    if (fetchError || !article) {
      res.status(404).json({ error: 'Article not found' });
      return;
    }

    await supabaseAdmin.from('interactions').insert({ article_id: id, type, weight });

    const updates: Record<string, unknown> = {
      interaction_count: ((article.interaction_count as number) ?? 0) + 1,
    };
    if (type === 'saved') updates.is_saved = true;
    if (type === 'dismissed') updates.dismissed = true;
    if (type === 'read_30s' || type === 'read_60s') updates.is_read = true;

    await supabaseAdmin.from('articles').update(updates).eq('id', id);

    // Async embedding — non-blocking, positive signals only
    if (weight > 0) {
      import('../services/embeddingService')
        .then(({ generateAndStoreTasteVector }) =>
          generateAndStoreTasteVector(id, article as { title: string; content: string | null }, weight)
        )
        .catch(err => console.warn('[articles] Embedding failed:', err));
    }

    // Trigger LLM profile refresh every 10 interactions — fire-and-forget
    const totalCount = ((article.interaction_count as number) ?? 0) + 1;
    if (totalCount % 10 === 0) {
      import('../jobs/profileRefreshJob')
        .then(({ maybeRefreshProfile }) => maybeRefreshProfile())
        .catch(err => console.warn('[articles] Profile refresh failed:', err));
    }

    res.json({ success: true, weight });
  } catch (err) {
    console.error('[articles] PATCH /:id/interact error:', err);
    res.status(500).json({ error: 'Failed to record interaction' });
  }
});

export default router;
