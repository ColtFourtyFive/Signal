import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error(
    'Missing Supabase environment variables. Set SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY.'
  );
}

// Public client — for read operations that respect RLS
export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Admin client — for all backend write operations (bypasses RLS)
// NEVER expose this key to iOS or any client-side code
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

// -------------------------------------------------------
// Database types
// -------------------------------------------------------

export interface Feed {
  id: string;
  name: string;
  url: string;
  category: string | null;
  is_active: boolean;
  is_auto_discovered: boolean;
  last_fetched_at: string | null;
  article_count: number;
  avg_score: number;
  is_broken: boolean;
  is_low_quality: boolean;
  created_at: string;
}

export interface Article {
  id: string;
  feed_id: string | null;
  title: string;
  url: string;
  content: string | null;
  published_at: string | null;
  fetched_at: string;
  score: number | null;
  score_reason: string | null;
  category: string | null;
  is_primary_source: boolean;
  key_entities: string[] | null;
  embedding: number[] | null;
  interaction_count: number;
  is_read: boolean;
  is_saved: boolean;
  dismissed: boolean;
  personalization_score: number | null;
  profile_match_reason: string | null;
  created_at: string;
}

export interface Interaction {
  id: string;
  article_id: string;
  type: InteractionType;
  weight: number;
  occurred_at: string;
}

export type InteractionType =
  | 'read_30s'
  | 'read_60s'
  | 'saved'
  | 'shared'
  | 'closed_fast'
  | 'dismissed';

export interface TasteVector {
  id: string;
  article_id: string;
  embedding: number[];
  weight: number;
  created_at: string;
}

export interface TasteCentroid {
  id: number;
  embedding: number[] | null;
  based_on_count: number;
  updated_at: string;
}

export interface DiscoveredSource {
  id: string;
  name: string | null;
  url: string | null;
  rss_url: string | null;
  avg_score: number | null;
  discovery_reason: string | null;
  status: 'pending' | 'added' | 'rejected';
  discovered_at: string;
}

export interface TasteProfile {
  id: string;
  profile_text: string;
  primary_interests: Record<string, number>;
  top_sources: Array<{ name: string; engagement: number }>;
  key_entities: {
    models: string[];
    benchmarks: string[];
    techniques: string[];
    organizations: string[];
  };
  anti_interests: string[];
  based_on_interactions: number;
  confidence_score: number;
  last_updated: string;
  created_at: string;
}

export interface PushToken {
  id: string;
  token: string;
  registered_at: string;
}

export type ArticleCategory =
  | 'model_release'
  | 'benchmark'
  | 'research_paper'
  | 'open_source'
  | 'engineering_post'
  | 'funding'
  | 'industry'
  | 'noise';
