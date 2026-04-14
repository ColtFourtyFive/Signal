import { supabaseAdmin } from '../db/supabase';

export interface FeedOptions {
  limit: number;
  offset: number;
  category?: string;
  unreadOnly?: boolean;
}

// Cosine similarity between two equal-length vectors
function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  let magA = 0;
  let magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  return denom === 0 ? 0 : dot / denom;
}

// Parse embedding from Supabase (may arrive as JSON string)
function parseEmbedding(raw: unknown): number[] | null {
  if (!raw) return null;
  if (Array.isArray(raw)) return raw as number[];
  if (typeof raw === 'string') {
    try { return JSON.parse(raw); } catch { return null; }
  }
  return null;
}

// Returns the current taste centroid, or null if not yet computed
async function getTasteCentroid(): Promise<number[] | null> {
  const { data } = await supabaseAdmin
    .from('taste_centroid')
    .select('embedding')
    .eq('id', 1)
    .single();

  if (!data) return null;
  return parseEmbedding(data.embedding);
}

// Main feed ranking:
// Phase 1: ORDER BY score DESC, published_at DESC (no centroid)
// Phase 2+: final_score = (claude_score * 0.6) + (cosine_similarity * 0.4 * 10)
export async function getRankedFeed(options: FeedOptions): Promise<unknown[]> {
  const { limit, offset, category, unreadOnly } = options;

  // Fetch candidate articles (more than needed, then re-rank)
  const candidateLimit = offset + limit + 50;

  let query = supabaseAdmin
    .from('articles')
    .select('*, feeds(name, category)')
    .not('score', 'is', null)
    .gte('score', 7)
    .eq('dismissed', false);

  if (category && category !== 'all') {
    query = query.eq('category', category);
  }
  if (unreadOnly) {
    query = query.eq('is_read', false);
  }

  const { data: articles, error } = await query
    .order('score', { ascending: false })
    .order('published_at', { ascending: false })
    .limit(candidateLimit);

  if (error || !articles) return [];

  // Try to get centroid for personalized re-ranking
  const centroid = await getTasteCentroid();

  if (!centroid) {
    // No taste data yet — pure score ranking
    return articles.slice(offset, offset + limit);
  }

  // Re-rank using: final_score = (claude_score * 0.6) + (cosine_sim * 0.4 * 10)
  const ranked = articles.map(article => {
    const embedding = parseEmbedding(article.embedding);
    const cosSim = embedding ? cosineSimilarity(embedding, centroid) : 0;
    const finalScore = (article.score * 0.6) + (cosSim * 0.4 * 10);
    return { ...article, _final_score: finalScore };
  });

  ranked.sort((a, b) => b._final_score - a._final_score);

  return ranked.slice(offset, offset + limit);
}

// Recompute taste centroid from last 50 positive taste vectors
export async function recomputeCentroid(): Promise<boolean> {
  const { data: vectors, error } = await supabaseAdmin
    .from('taste_vectors')
    .select('embedding, weight')
    .order('created_at', { ascending: false })
    .limit(50);

  if (error || !vectors?.length) {
    console.log('[personalization] No taste vectors found, skipping centroid update');
    return false;
  }

  // Parse embeddings
  const parsed = vectors
    .map(v => ({
      embedding: parseEmbedding(v.embedding),
      weight: v.weight,
    }))
    .filter((v): v is { embedding: number[]; weight: number } => v.embedding !== null);

  if (!parsed.length) return false;

  const dim = parsed[0].embedding.length;
  const centroid = new Array<number>(dim).fill(0);
  let totalWeight = 0;

  for (const { embedding, weight } of parsed) {
    for (let i = 0; i < dim; i++) {
      centroid[i] += embedding[i] * weight;
    }
    totalWeight += weight;
  }

  // Weighted average
  for (let i = 0; i < dim; i++) {
    centroid[i] /= totalWeight;
  }

  // Normalize to unit length
  const mag = Math.sqrt(centroid.reduce((s, v) => s + v * v, 0));
  if (mag > 0) {
    for (let i = 0; i < dim; i++) centroid[i] /= mag;
  }

  const { error: upsertError } = await supabaseAdmin
    .from('taste_centroid')
    .upsert({
      id: 1,
      embedding: centroid,
      based_on_count: parsed.length,
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    console.error('[personalization] Failed to upsert centroid:', upsertError);
    return false;
  }

  console.log(`[personalization] Centroid updated from ${parsed.length} vectors`);
  return true;
}

// Count positive interactions since last centroid update
let positiveInteractionsSinceLastCentroid = 0;

export function recordPositiveInteraction(): void {
  positiveInteractionsSinceLastCentroid++;
  if (positiveInteractionsSinceLastCentroid >= 5) {
    positiveInteractionsSinceLastCentroid = 0;
    recomputeCentroid().catch(err =>
      console.warn('[personalization] Centroid recomputation failed:', err)
    );
  }
}
