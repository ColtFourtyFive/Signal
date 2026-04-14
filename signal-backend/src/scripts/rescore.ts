/**
 * rescore.ts — Re-score the 500 most recent articles with the updated prompt.
 * Logs old score → new score for each article so you can verify distribution.
 *
 * Usage: npm run rescore
 */

import dotenv from 'dotenv';
dotenv.config({ override: true });

import Anthropic from '@anthropic-ai/sdk';
import { supabaseAdmin } from '../db/supabase';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY! });

// -------------------------------------------------------
// Stricter prompt (identical to scoringService.ts)
// -------------------------------------------------------
const SYSTEM_PROMPT = `You are an elite signal filter for an AI infrastructure startup founder. You score articles on a 1-10 scale. You are STRICT. A score of 9-10 should be genuinely rare — roughly 5% of articles or fewer. If you are uncertain between a 7 and an 8, score it 7. If you are uncertain between an 8 and a 9, score it 8. Reserve 9-10 only for news that a serious AI researcher or founder would immediately share with their team.

SCORE 9-10 — CRITICAL (rare, maybe 1-3 per day maximum):
- A brand new frontier model actually released with weights or API access (GPT-5, Claude 4, Gemini 3, Llama 4 actual release — NOT speculation, previews, or system cards for existing models)
- A benchmark record broken on a major eval that changes the state of the art (MMLU, GPQA Diamond, SWE-bench, HumanEval) with verifiable results, not just claimed improvements
- A primary lab engineering post revealing new architecture, training method, or infrastructure technique that practitioners would immediately use or study
- An arXiv paper with genuinely novel findings that advance the field — not incremental improvements or surveys
- A major open source model release that is immediately usable and represents a meaningful capability jump
- Funding above $500M for a frontier AI lab

WHAT IS NOT A 9-10 (be strict about this):
- System cards, safety cards, or addendums for already-announced models
- Blog posts about how existing models are being used
- Product launches that use AI but are not about AI itself
- Incremental model updates, fine-tunes, or minor version bumps
- Funding rounds below $200M
- Conference announcements, calls for papers
- Opinion pieces, even from prominent researchers
- Any article that is primarily about business strategy rather than technical capability
- Retrospectives or case studies about past work
- Tool releases that wrap existing models without new capability

SCORE 7-8 — HIGH SIGNAL (notable, worth reading today):
- New model capability or significant API change with technical depth
- Solid academic paper with interesting but not groundbreaking results
- Notable open source project that practitioners would actually use
- Significant technical blog post from a frontier lab engineer
- Real industry move with strategic implications (partnership, pivot)
- New benchmark or evaluation framework worth knowing about
- Funding $50M-$500M for an AI infrastructure company

SCORE 4-6 — BACKGROUND NOISE (exists, not urgent):
- Opinion without new data
- Secondary reporting on something already scored above 7
- Incremental product updates
- Minor version releases
- Business strategy discussions without technical depth

SCORE 1-3 — FILTER OUT (never show):
- Changelogs and patch notes
- Job postings
- Event announcements
- Marketing content
- Anything unrelated to AI/ML/research/infrastructure

Return ONLY valid JSON, no other text:
{
  "score": <number 1-10>,
  "reason": "<max 12 words, say WHY it earned this specific score>",
  "category": "<one of: model_release | benchmark | research_paper | open_source | engineering_post | funding | industry | noise>",
  "is_primary_source": <true or false>,
  "key_entities": ["<up to 5 model names, benchmark names, lab names, tool names>"]
}`;

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function rescoreArticle(article: {
  id: string;
  title: string;
  content: string | null;
  score: number | null;
  feeds: { name: string } | null;
}): Promise<{ newScore: number; reason: string; category: string; isPrimary: boolean; entities: string[] } | null> {
  const feedName = (article.feeds as { name?: string } | null)?.name ?? 'Unknown';
  const userMessage = `Source: ${feedName}
Title: ${article.title}
Summary: ${(article.content ?? '').slice(0, 500)}`;

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 300,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userMessage }],
    });

    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const cleaned = text
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();

    const parsed = JSON.parse(cleaned) as {
      score: number;
      reason: string;
      category: string;
      is_primary_source: boolean;
      key_entities: string[];
    };

    return {
      newScore: Math.max(1, Math.min(10, Number(parsed.score))),
      reason: String(parsed.reason).slice(0, 200),
      category: parsed.category,
      isPrimary: Boolean(parsed.is_primary_source),
      entities: (parsed.key_entities ?? []).slice(0, 5),
    };
  } catch {
    return null;
  }
}

async function main() {
  console.log('[rescore] Fetching 500 most recent articles...');

  const { data: articles, error } = await supabaseAdmin
    .from('articles')
    .select('id, title, content, score, feeds(name)')
    .not('score', 'is', null)
    .order('published_at', { ascending: false })
    .limit(500);

  if (error || !articles?.length) {
    console.error('[rescore] Failed to fetch articles:', error?.message);
    process.exit(1);
  }

  console.log(`[rescore] Re-scoring ${articles.length} articles with updated prompt...`);
  console.log('[rescore] Batches of 35 with 65s delays (~50 RPM safe)\n');

  const BATCH_SIZE = 35;
  const DELAY_MS = 65_000;

  // Track score distribution
  const oldDist: Record<number, number> = {};
  const newDist: Record<number, number> = {};
  let updated = 0;
  let failed = 0;

  for (let i = 0; i < articles.length; i += BATCH_SIZE) {
    const batch = articles.slice(i, i + BATCH_SIZE);
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;
    const totalBatches = Math.ceil(articles.length / BATCH_SIZE);

    console.log(`\n[rescore] Batch ${batchNum}/${totalBatches} (articles ${i + 1}–${Math.min(i + BATCH_SIZE, articles.length)})`);

    const results = await Promise.all(batch.map(a => rescoreArticle(a as unknown as {
      id: string;
      title: string;
      content: string | null;
      score: number | null;
      feeds: { name: string } | null;
    })));

    for (let j = 0; j < batch.length; j++) {
      const article = batch[j];
      const result = results[j];
      const oldScore = article.score ?? 0;

      oldDist[oldScore] = (oldDist[oldScore] ?? 0) + 1;

      if (!result) {
        failed++;
        console.log(`  ✗ [${oldScore}→?] "${article.title.slice(0, 60)}"`);
        continue;
      }

      newDist[result.newScore] = (newDist[result.newScore] ?? 0) + 1;

      const arrow = result.newScore < oldScore ? '↓' : result.newScore > oldScore ? '↑' : '=';
      console.log(`  ${arrow} [${oldScore}→${result.newScore}] "${article.title.slice(0, 55)}" — ${result.reason}`);

      await supabaseAdmin
        .from('articles')
        .update({
          score: result.newScore,
          score_reason: result.reason,
          category: result.category,
          is_primary_source: result.isPrimary,
          key_entities: result.entities,
        })
        .eq('id', article.id);

      updated++;
    }

    if (i + BATCH_SIZE < articles.length) {
      console.log(`\n[rescore] Waiting ${DELAY_MS / 1000}s before next batch...`);
      await sleep(DELAY_MS);
    }
  }

  // Print distribution summary
  console.log('\n\n════════════════════════════════════════');
  console.log('SCORE DISTRIBUTION COMPARISON');
  console.log('════════════════════════════════════════');
  console.log('Score  | Before | After');
  console.log('-------|--------|------');
  for (let s = 10; s >= 1; s--) {
    const before = oldDist[s] ?? 0;
    const after = newDist[s] ?? 0;
    if (before > 0 || after > 0) {
      console.log(`   ${s}   |  ${String(before).padStart(4)}  | ${String(after).padStart(4)}`);
    }
  }
  console.log('────────────────────────────────────────');
  console.log(`Updated: ${updated} | Failed: ${failed}`);

  const total = updated;
  const nineOrTen = (newDist[9] ?? 0) + (newDist[10] ?? 0);
  const pct = total > 0 ? ((nineOrTen / total) * 100).toFixed(1) : '0';
  console.log(`\n9-10 articles: ${nineOrTen}/${total} (${pct}%)`);

  if (nineOrTen / total > 0.25) {
    console.log('\n⚠️  WARNING: 9-10 > 25% of articles. Prompt may need further tightening.');
  } else {
    console.log('\n✓ Distribution looks healthy.');
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[rescore] Fatal error:', err);
  process.exit(1);
});
