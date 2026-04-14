import { Router, type Request, type Response } from 'express';
import { supabaseAdmin } from '../db/supabase';

const router = Router();

// -------------------------------------------------------
// GET /api/taste-tuner/articles
// Returns 15 diverse articles for 3-tier calibration.
// Uses score >= 6 for wider calibration range.
// -------------------------------------------------------
router.get('/articles', async (_req: Request, res: Response) => {
  try {
    const categoryQuotas: Array<{ category: string; limit: number }> = [
      { category: 'model_release',    limit: 5 },
      { category: 'research_paper',   limit: 5 },
      { category: 'benchmark',        limit: 4 },
      { category: 'engineering_post', limit: 5 },
      { category: 'open_source',      limit: 4 },
      { category: 'industry',         limit: 4 },
    ];

    const pools = await Promise.all(
      categoryQuotas.map(({ category, limit }) =>
        supabaseAdmin
          .from('articles')
          .select('id, title, url, content, score, score_reason, category, is_primary_source, key_entities, published_at, feed_id, interaction_count, is_read, is_saved, dismissed, created_at, feeds(name, category)')
          .eq('category', category)
          .gte('score', 6)
          .eq('dismissed', false)
          .order('published_at', { ascending: false })
          .limit(limit)
      )
    );

    const quotaTarget: Record<string, number> = {
      model_release:    3,
      research_paper:   3,
      benchmark:        2,
      engineering_post: 3,
      open_source:      2,
      industry:         2,
    };

    const selected: unknown[] = [];

    for (let i = 0; i < categoryQuotas.length; i++) {
      const { category } = categoryQuotas[i];
      const pool = pools[i].data ?? [];
      const quota = quotaTarget[category] ?? 1;
      const shuffled = [...pool].sort(() => Math.random() - 0.5);
      selected.push(...shuffled.slice(0, quota));
    }

    // Final shuffle, take 15
    const final = selected.sort(() => Math.random() - 0.5).slice(0, 15);

    res.json({ articles: final });
  } catch (err) {
    console.error('[taste-tuner] GET /articles error:', err);
    res.status(500).json({ error: 'Failed to fetch calibration articles' });
  }
});

// -------------------------------------------------------
// POST /api/taste-tuner/submit
// Body: { ratings: [{ articleId: string, tier: "must_read" | "interesting" | "skip" }] }
// Inserts interactions, computes personal_thresholds, triggers profile generation.
// -------------------------------------------------------
router.post('/submit', async (req: Request, res: Response) => {
  const { ratings } = req.body as {
    ratings: Array<{ articleId: string; tier: 'must_read' | 'interesting' | 'skip' }>;
  };

  if (!Array.isArray(ratings) || ratings.length === 0) {
    res.status(400).json({ error: 'Body must include a non-empty ratings array' });
    return;
  }

  const tierMap: Record<string, { type: string; weight: number }> = {
    must_read:   { type: 'saved',     weight: 3.0 },
    interesting: { type: 'read_60s',  weight: 1.0 },
    skip:        { type: 'dismissed', weight: -1.5 },
  };

  try {
    // Build interaction records
    const interactions = ratings.map(({ articleId, tier }) => {
      const { type, weight } = tierMap[tier] ?? { type: 'dismissed', weight: -1.0 };
      return { article_id: articleId, type, weight };
    });

    const { error: insertError } = await supabaseAdmin
      .from('interactions')
      .insert(interactions);

    if (insertError) {
      console.error('[taste-tuner] Failed to insert interactions:', insertError.message);
      res.status(500).json({ error: 'Failed to save calibration data' });
      return;
    }

    // Compute personal_thresholds from must_read article scores
    const mustReadIds = ratings
      .filter(r => r.tier === 'must_read')
      .map(r => r.articleId);

    let thresholds: { must_read_min: number; interesting_min: number } = {
      must_read_min: 8.0,
      interesting_min: 6.0,
    };

    if (mustReadIds.length > 0) {
      const { data: mustReadArticles } = await supabaseAdmin
        .from('articles')
        .select('score')
        .in('id', mustReadIds);

      if (mustReadArticles && mustReadArticles.length > 0) {
        const scores = mustReadArticles
          .map(a => a.score as number)
          .filter(s => s != null);

        if (scores.length > 0) {
          const avgScore = scores.reduce((a, b) => a + b, 0) / scores.length;
          const mustReadMin = Math.min(9.5, Math.max(7.0, avgScore - 0.5));
          const interestingMin = Math.min(8.0, Math.max(5.0, mustReadMin - 2.0));
          thresholds = { must_read_min: mustReadMin, interesting_min: interestingMin };
        }
      }
    }

    // Upsert personal_thresholds into user_taste_profile (single-row table)
    const { error: upsertError } = await supabaseAdmin
      .from('user_taste_profile')
      .upsert(
        { id: '00000000-0000-0000-0000-000000000001', personal_thresholds: thresholds },
        { onConflict: 'id' }
      );

    if (upsertError) {
      // Non-fatal — thresholds are nice-to-have, not required
      console.warn('[taste-tuner] Could not upsert personal_thresholds:', upsertError.message);
    }

    // Respond immediately
    res.json({
      success: true,
      thresholds,
      ratings_recorded: ratings.length,
    });

    // Trigger taste profile generation non-blocking
    setImmediate(async () => {
      try {
        const { generateTasteProfile } = await import('../services/tasteProfileService');
        await generateTasteProfile();
        console.log('[taste-tuner] Taste profile generated from 3-tier calibration');
      } catch (err) {
        console.error('[taste-tuner] Profile generation failed:', err);
      }
    });
  } catch (err) {
    console.error('[taste-tuner] POST /submit error:', err);
    res.status(500).json({ error: 'Failed to process calibration' });
  }
});

export default router;
