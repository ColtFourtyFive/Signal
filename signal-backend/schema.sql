-- ============================================================
-- Signal — Supabase Schema
-- Run this entire file in the Supabase SQL Editor
-- ============================================================

-- Enable pgvector (required for embeddings)
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- FEEDS — RSS sources (seed + auto-discovered)
-- ============================================================
CREATE TABLE IF NOT EXISTS feeds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  url TEXT UNIQUE NOT NULL,
  category TEXT,                      -- 'lab'|'research'|'industry'|'open_source'
  is_active BOOLEAN DEFAULT true,
  is_auto_discovered BOOLEAN DEFAULT false,
  last_fetched_at TIMESTAMPTZ,
  article_count INTEGER DEFAULT 0,
  avg_score FLOAT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ARTICLES — Scored articles (only score >= 7 persisted)
-- ============================================================
CREATE TABLE IF NOT EXISTS articles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_id UUID REFERENCES feeds(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  url TEXT UNIQUE NOT NULL,
  content TEXT,
  published_at TIMESTAMPTZ,
  fetched_at TIMESTAMPTZ DEFAULT NOW(),
  score FLOAT,                        -- NULL = scoring pending; never stored if < 7
  score_reason TEXT,                  -- max 12 words from Claude
  category TEXT,                      -- see scoring service enum
  is_primary_source BOOLEAN DEFAULT false,
  key_entities TEXT[],
  embedding VECTOR(1536),             -- populated on positive user interaction
  interaction_count INTEGER DEFAULT 0,
  is_read BOOLEAN DEFAULT false,
  is_saved BOOLEAN DEFAULT false,
  dismissed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INTERACTIONS — Every user reading signal
-- ============================================================
CREATE TABLE IF NOT EXISTS interactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id UUID REFERENCES articles(id) ON DELETE CASCADE,
  type TEXT NOT NULL,   -- 'read_30s'|'read_60s'|'saved'|'shared'|'closed_fast'|'dismissed'
  weight FLOAT NOT NULL,
  occurred_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TASTE_VECTORS — Embeddings for positive-signal articles
-- ============================================================
CREATE TABLE IF NOT EXISTS taste_vectors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id UUID REFERENCES articles(id) ON DELETE CASCADE,
  embedding VECTOR(1536) NOT NULL,
  weight FLOAT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TASTE_CENTROID — Single-row weighted average centroid
-- ============================================================
CREATE TABLE IF NOT EXISTS taste_centroid (
  id INTEGER PRIMARY KEY DEFAULT 1,   -- always 1; single-row table
  embedding VECTOR(1536),
  based_on_count INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DISCOVERED_SOURCES — Auto-discovery results
-- ============================================================
CREATE TABLE IF NOT EXISTS discovered_sources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  url TEXT,
  rss_url TEXT,
  avg_score FLOAT,
  discovery_reason TEXT,
  status TEXT DEFAULT 'pending',      -- 'pending'|'added'|'rejected'
  discovered_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- Primary feed query: high-score recent articles
CREATE INDEX IF NOT EXISTS idx_articles_score_published
  ON articles(score DESC, published_at DESC)
  WHERE score IS NOT NULL;

-- Unread + non-dismissed filter
CREATE INDEX IF NOT EXISTS idx_articles_unread
  ON articles(is_read, dismissed);

-- Feed membership
CREATE INDEX IF NOT EXISTS idx_articles_feed
  ON articles(feed_id);

-- Interaction lookup
CREATE INDEX IF NOT EXISTS idx_interactions_article
  ON interactions(article_id);

-- Taste vector recency (for centroid computation)
CREATE INDEX IF NOT EXISTS idx_taste_vectors_created
  ON taste_vectors(created_at DESC);

-- pgvector cosine similarity indexes
-- Note: IVFFlat indexes need data to be useful (lists * 39 rows minimum).
-- They are created empty and become active as data grows.
CREATE INDEX IF NOT EXISTS idx_taste_vectors_embedding
  ON taste_vectors USING ivfflat (embedding vector_cosine_ops) WITH (lists = 10);

CREATE INDEX IF NOT EXISTS idx_articles_embedding
  ON articles USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================================
-- SEED FEEDS — Insert initial sources
-- ============================================================
INSERT INTO feeds (name, url, category) VALUES
  ('OpenAI News',            'https://openai.com/news/rss.xml',                                                                              'lab'),
  ('Anthropic Engineering',  'https://raw.githubusercontent.com/conoro/anthropic-engineering-rss-feed/main/anthropic_engineering_rss.xml',   'lab'),
  ('Anthropic News',         'https://raw.githubusercontent.com/Olshansk/rss-feeds/main/feed_anthropic_news.xml',                            'lab'),
  ('DeepMind',               'https://deepmind.google/blog/rss/',                                                                            'lab'),
  ('HuggingFace Blog',       'https://huggingface.co/blog/feed.xml',                                                                         'open_source'),
  ('BAIR Blog',              'https://bair.berkeley.edu/blog/feed.xml',                                                                      'research'),
  ('Google Research Blog',   'https://research.google/blog/rss',                                                                             'lab'),
  ('Mistral AI',             'https://mistral.ai/news/rss',                                                                                  'lab'),
  ('arXiv CS.AI',            'https://rss.arxiv.org/rss/cs.AI',                                                                              'research'),
  ('arXiv CS.LG',            'https://rss.arxiv.org/rss/cs.LG',                                                                              'research'),
  ('arXiv CS.CL',            'https://rss.arxiv.org/rss/cs.CL',                                                                              'research'),
  ('GitHub Blog',            'https://github.blog/feed/',                                                                                    'open_source'),
  ('Hacker News',            'https://news.ycombinator.com/rss',                                                                             'industry'),
  ('TechCrunch AI',          'https://techcrunch.com/category/artificial-intelligence/feed/',                                                'industry'),
  ('VentureBeat AI',         'https://venturebeat.com/category/ai/feed/',                                                                    'industry'),
  ('Ars Technica',           'https://feeds.arstechnica.com/arstechnica/index',                                                              'industry')
ON CONFLICT (url) DO NOTHING;
