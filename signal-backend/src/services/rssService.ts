import Parser from 'rss-parser';
import { supabaseAdmin, type Feed } from '../db/supabase';

const parser = new Parser({
  timeout: 10000,
  headers: {
    'User-Agent': 'Signal/1.0 (AI Intelligence Feed)',
    'Accept': 'application/rss+xml, application/xml, text/xml, */*',
  },
});

export interface RawArticle {
  feedId: string;
  feedName: string;
  title: string;
  url: string;
  content: string | null;
  publishedAt: string | null;
}

// Fetch all active feeds from DB and ingest new articles
export async function fetchAllFeeds(): Promise<{ feedName: string; newCount: number; error?: string }[]> {
  const { data: feeds, error } = await supabaseAdmin
    .from('feeds')
    .select('*')
    .eq('is_active', true);

  if (error || !feeds) {
    console.error('[rssService] Failed to fetch feeds from DB:', error);
    return [];
  }

  const results = await Promise.allSettled(
    feeds.map((feed: Feed) => fetchSingleFeed(feed))
  );

  return results.map((result, i) => {
    if (result.status === 'fulfilled') {
      return result.value;
    }
    return {
      feedName: feeds[i].name,
      newCount: 0,
      error: result.reason instanceof Error ? result.reason.message : String(result.reason),
    };
  });
}

// Fetch a single feed and return new (not-yet-seen) articles
export async function fetchSingleFeed(feed: Feed): Promise<{ feedName: string; newCount: number }> {
  let parsed;
  try {
    parsed = await parser.parseURL(feed.url);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(`[rssService] Failed to parse feed "${feed.name}" (${feed.url}): ${msg}`);
    return { feedName: feed.name, newCount: 0 };
  }

  if (!parsed.items || parsed.items.length === 0) {
    return { feedName: feed.name, newCount: 0 };
  }

  // Extract candidate URLs from this batch
  const candidateUrls = parsed.items
    .map(item => item.link)
    .filter((url): url is string => Boolean(url));

  if (candidateUrls.length === 0) {
    return { feedName: feed.name, newCount: 0 };
  }

  // Find which URLs already exist in DB (avoid re-scoring)
  const { data: existing } = await supabaseAdmin
    .from('articles')
    .select('url')
    .in('url', candidateUrls);

  const existingUrls = new Set((existing ?? []).map((r: { url: string }) => r.url));

  const newArticles: RawArticle[] = parsed.items
    .filter(item => item.link && !existingUrls.has(item.link))
    .map(item => ({
      feedId: feed.id,
      feedName: feed.name,
      title: item.title?.trim() || '(no title)',
      url: item.link!,
      content: extractContent(item),
      publishedAt: item.isoDate ?? item.pubDate ?? null,
    }));

  // Update last_fetched_at on the feed
  await supabaseAdmin
    .from('feeds')
    .update({ last_fetched_at: new Date().toISOString() })
    .eq('id', feed.id);

  return { feedName: feed.name, newCount: newArticles.length, ...{ _articles: newArticles } } as any;
}

// Retrieve new articles from all feeds (for scoring pipeline)
export async function getNewArticlesFromFeeds(feeds: Feed[]): Promise<RawArticle[]> {
  const allArticles: RawArticle[] = [];

  for (const feed of feeds) {
    try {
      const parsed = await parser.parseURL(feed.url);
      if (!parsed.items?.length) continue;

      const candidateUrls = parsed.items
        .map(item => item.link)
        .filter((url): url is string => Boolean(url));

      const { data: existing } = await supabaseAdmin
        .from('articles')
        .select('url')
        .in('url', candidateUrls);

      const existingUrls = new Set((existing ?? []).map((r: { url: string }) => r.url));

      const newItems = parsed.items
        .filter(item => item.link && !existingUrls.has(item.link))
        .map(item => ({
          feedId: feed.id,
          feedName: feed.name,
          title: item.title?.trim() || '(no title)',
          url: item.link!,
          content: extractContent(item),
          publishedAt: item.isoDate ?? item.pubDate ?? null,
        }));

      allArticles.push(...newItems);

      // Update last_fetched_at
      await supabaseAdmin
        .from('feeds')
        .update({ last_fetched_at: new Date().toISOString() })
        .eq('id', feed.id);

      console.log(`[rssService] "${feed.name}": ${newItems.length} new articles`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[rssService] Error fetching "${feed.name}": ${msg}`);
    }
  }

  return allArticles;
}

// Validate whether a URL is a parseable RSS feed
// Returns up to 5 most recent articles for scoring, or null if invalid
export async function validateAndSampleFeed(
  url: string
): Promise<RawArticle[] | null> {
  try {
    const parsed = await parser.parseURL(url);
    if (!parsed.items?.length) return null;

    return parsed.items.slice(0, 5).map(item => ({
      feedId: 'validation',
      feedName: parsed.title ?? url,
      title: item.title?.trim() || '(no title)',
      url: item.link ?? url,
      content: extractContent(item),
      publishedAt: item.isoDate ?? item.pubDate ?? null,
    }));
  } catch {
    return null;
  }
}

// Try common RSS URL patterns if the primary URL fails
export async function discoverRssUrl(baseUrl: string): Promise<string | null> {
  const candidates = [
    baseUrl,
    `${baseUrl}/feed`,
    `${baseUrl}/rss`,
    `${baseUrl}/atom.xml`,
    `${baseUrl}/feed.xml`,
    `${baseUrl}/rss.xml`,
    `${baseUrl}/blog/feed`,
    `${baseUrl}/blog/rss`,
  ];

  for (const candidate of candidates) {
    const result = await validateAndSampleFeed(candidate);
    if (result !== null) return candidate;
  }
  return null;
}

// Extract the best available text content from an RSS item
function extractContent(item: Parser.Item): string | null {
  const raw =
    (item as any)['content:encoded'] ||
    item.content ||
    item.contentSnippet ||
    item.summary ||
    '';

  if (!raw) return null;

  // Strip HTML tags, collapse whitespace, truncate to 2000 chars
  const stripped = raw
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  return stripped.slice(0, 2000) || null;
}
