import { Router, type Request, type Response } from 'express';
import { supabaseAdmin } from '../db/supabase';

const router = Router();

// -------------------------------------------------------
// GET /api/onboarding/articles
// Returns 10 diverse articles for calibration swipe flow.
// Covers a mix of categories so the user calibrates across
// the full content spectrum.
// -------------------------------------------------------
router.get('/articles', async (_req: Request, res: Response) => {
  try {
    // Fetch a pool of recent high-quality articles per category
    const categoryQuotas: Array<{ category: string; limit: number }> = [
      { category: 'model_release',   limit: 4 },
      { category: 'research_paper',  limit: 4 },
      { category: 'benchmark',       limit: 4 },
      { category: 'engineering_post',limit: 4 },
      { category: 'open_source',     limit: 3 },
      { category: 'industry',        limit: 3 },
    ];

    const pools = await Promise.all(
      categoryQuotas.map(({ category, limit }) =>
        supabaseAdmin
          .from('articles')
          .select('id, title, content, score, score_reason, category, is_primary_source, key_entities, published_at, feed_id, feeds(name, category)')
          .eq('category', category)
          .gte('score', 7)
          .eq('dismissed', false)
          .order('published_at', { ascending: false })
          .limit(limit)
      )
    );

    // Pick articles from each pool, then shuffle and take 10
    const quotaTarget: Record<string, number> = {
      model_release:    2,
      research_paper:   2,
      benchmark:        2,
      engineering_post: 2,
      open_source:      1,
      industry:         1,
    };

    const selected: unknown[] = [];

    for (let i = 0; i < categoryQuotas.length; i++) {
      const { category } = categoryQuotas[i];
      const pool = pools[i].data ?? [];
      const quota = quotaTarget[category] ?? 1;

      // Shuffle pool and take up to quota
      const shuffled = [...pool].sort(() => Math.random() - 0.5);
      selected.push(...shuffled.slice(0, quota));
    }

    // Final shuffle of the 10 selected
    const final = selected.sort(() => Math.random() - 0.5).slice(0, 10);

    res.json({ articles: final });
  } catch (err) {
    console.error('[onboarding] GET /articles error:', err);
    res.status(500).json({ error: 'Failed to fetch calibration articles' });
  }
});

// -------------------------------------------------------
// POST /api/onboarding/calibrate
// Body: [{ articleId: string, liked: boolean }]
// Creates interaction records, then triggers taste profile
// generation immediately (bypasses the 10-interaction threshold).
// -------------------------------------------------------
router.post('/calibrate', async (req: Request, res: Response) => {
  // Accept both top-level array and { swipes: [...] } envelope
  const raw = req.body as Array<{ articleId: string; liked: boolean }> | { swipes: Array<{ articleId: string; liked: boolean }> };
  const swipes = Array.isArray(raw) ? raw : raw.swipes;

  if (!Array.isArray(swipes) || swipes.length === 0) {
    res.status(400).json({ error: 'Body must be a non-empty array of swipe results' });
    return;
  }

  try {
    // Create interaction records for each swipe
    const interactions = swipes.map(({ articleId, liked }) => ({
      article_id: articleId,
      type: liked ? 'saved' : 'dismissed',
      weight: liked ? 2.0 : -1.0,
    }));

    const { error: insertError } = await supabaseAdmin
      .from('interactions')
      .insert(interactions);

    if (insertError) {
      console.error('[onboarding] Failed to insert interactions:', insertError.message);
      res.status(500).json({ error: 'Failed to save calibration data' });
      return;
    }

    // Respond immediately — profile generation runs in background
    res.json({ success: true, profile_generated: true, swipes_recorded: swipes.length });

    // Trigger profile generation asynchronously (non-blocking)
    setImmediate(async () => {
      try {
        const { generateTasteProfile } = await import('../services/tasteProfileService');
        await generateTasteProfile();
        console.log('[onboarding] Initial taste profile generated from calibration');
      } catch (err) {
        console.error('[onboarding] Profile generation failed:', err);
      }
    });
  } catch (err) {
    console.error('[onboarding] POST /calibrate error:', err);
    res.status(500).json({ error: 'Failed to process calibration' });
  }
});

export default router;
