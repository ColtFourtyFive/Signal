import OpenAI from 'openai';
import { supabaseAdmin } from '../db/supabase';
import { recordPositiveInteraction } from './personalizationService';

let _openai: OpenAI | null = null;
function getOpenAI(): OpenAI {
  if (!_openai) _openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY! });
  return _openai;
}

// HARD GUARD: only generate embeddings for positive interactions (weight > 0)
// Dismissed and closed_fast interactions MUST NOT reach this function
export async function generateAndStoreTasteVector(
  articleId: string,
  article: { title: string; content: string | null },
  weight: number
): Promise<void> {
  // Hard guard — negative signals never update taste vectors
  if (weight <= 0) {
    console.warn('[embeddingService] Blocked negative-weight embedding (this should not happen)');
    return;
  }

  const inputText = `${article.title}. ${(article.content ?? '').slice(0, 500)}`.trim();

  let embedding: number[];
  try {
    const response = await getOpenAI().embeddings.create({
      model: 'text-embedding-3-small',
      input: inputText,
      dimensions: 1536,
    });
    embedding = response.data[0].embedding;
  } catch (err) {
    console.warn('[embeddingService] OpenAI embedding failed:', err);
    return;
  }

  // Store in taste_vectors
  const { error: vectorError } = await supabaseAdmin.from('taste_vectors').insert({
    article_id: articleId,
    embedding,
    weight,
  });

  if (vectorError) {
    console.error('[embeddingService] Failed to insert taste vector:', vectorError);
    return;
  }

  // Also update the article's embedding (used for cosine similarity in feed ranking)
  await supabaseAdmin
    .from('articles')
    .update({ embedding })
    .eq('id', articleId);

  // Notify personalization service to consider recomputing centroid
  recordPositiveInteraction();

  console.log(`[embeddingService] Stored taste vector for article ${articleId} (weight: ${weight})`);
}

// Generate embedding for a text string (used by discovery service)
export async function generateEmbedding(text: string): Promise<number[] | null> {
  try {
    const response = await getOpenAI().embeddings.create({
      model: 'text-embedding-3-small',
      input: text.slice(0, 2000),
      dimensions: 1536,
    });
    return response.data[0].embedding;
  } catch (err) {
    console.warn('[embeddingService] Failed to generate embedding:', err);
    return null;
  }
}
