#!/usr/bin/env node
'use strict';
// RAG rerank prototype runner (docs/research/system-one/README.md §5). Offline: needs three local
// llama.cpp servers — embeddings, a reranker, and one chat model — and nothing else. Uses
// production's chunker (rag.chunkText), production's prompt shape (rag.filesContext's manifest,
// coverage note and "[from file]" excerpts) and the decision layer's backends, so the only thing
// that differs between modes is how the excerpts were chosen.
//
//   EMBED_URL=http://127.0.0.1:18081 RERANK_URL=http://127.0.0.1:18082 CHAT_URL=http://127.0.0.1:18083 \
//   CHAT_MODEL=<label> node experiments/system-one/rag/run.cjs [--modes baseline,rerank6,rerank3] [--repeat 1]
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const web = path.resolve(__dirname, '../../../apps/web/server');
const { chunkText } = require(path.join(web, 'rag.cjs'));
const { createDecisions } = require(path.join(web, 'decision/index.cjs'));
const { embedBackend, llamaRerankBackend } = require(path.join(web, 'decision/backends.cjs'));
const { build } = require('./corpus.cjs');

const env = (k, d) => process.env[k] || d;
const EMBED = env('EMBED_URL', 'http://127.0.0.1:18081'), RERANK = env('RERANK_URL', 'http://127.0.0.1:18082'), CHAT = env('CHAT_URL', 'http://127.0.0.1:18083');
const CHAT_MODEL = env('CHAT_MODEL', 'chat');
const arg = (name, d) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : d; };
const MODES = arg('modes', 'baseline,rerank6,rerank3,rerank6p12').split(',');
// A deadline far above the measured cost, so this run measures reranking quality; latency is
// recorded per row and judged separately. Production would use a much tighter one (doc 4 §4.2).
const RERANK_DEADLINE_MS = Number(arg('rerank-deadline', '60000'));
const REPEAT = Number(arg('repeat', '1'));
const ONLY = arg('family', null); // run one task family only, e.g. --family multihop
// Production constants (rag.cjs): TOP_K 6, MIN_SCORE 0.3. The candidate pool for reranking is 24.
const TOP_K = 6, MIN_SCORE = 0.3, POOL = 24;

async function post(base, route, body) {
  const t = Date.now();
  const r = await fetch(base.replace(/\/+$/, '') + route, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  if (!r.ok) throw Error(`${route} ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return { body: await r.json(), ms: Date.now() - t };
}
async function embed(texts) {
  const out = [];
  for (let i = 0; i < texts.length; i += 16) {
    const { body } = await post(EMBED, '/v1/embeddings', { input: texts.slice(i, i + 16) });
    out.push(...body.data.sort((a, b) => a.index - b.index).map((d) => d.embedding));
  }
  return out;
}
const cosine = (a, b) => { let d = 0, na = 0, nb = 0; for (let i = 0; i < a.length; i++) { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; } return d / Math.sqrt(na * nb); };

function prompt(files, excerpts) {
  // Same shape as rag.filesContext, with the chunks the mode chose.
  const manifest = `Sources attached to this project (${files.length}): ${files.map((f) => `"${f.name}"`).join(', ')}. Excerpts of the relevant ones follow; ask to read a file in full if you need more of it.`;
  const coverage = 'Source completeness: Legacy text sources have no page completeness metadata.\nContext may contain excerpts only. Use read_project_file with PDF startPage/endPage and offset for pages beyond the summary. Do not treat missing excerpts or failed/partial sources as evidence of absence.';
  const block = [manifest, coverage, ...excerpts.map((c) => `[from ${c.file}] ${c.body}`)].join('\n\n');
  return [
    'You are working inside the user\'s project "Household and lab".',
    `Relevant knowledge-file excerpts for this message:\n${block}`,
    'Answer from the excerpts. If they do not contain the answer, say you could not find it rather than guessing.',
  ].join('\n\n');
}

const norm = (s) => String(s).toLowerCase().replace(/[,*_`]/g, '').replace(/\s+/g, ' ');
const REFUSAL = /\b(could not|couldn't|cannot|can't|unable to|not able to) (find|locate|see|determine)|\bno (information|record|mention|data|entry|details)\b|\b(not|isn't|is not|aren't|are not|doesn't|does not) (included|listed|mentioned|present|appear|contain|available|in the)/i;

function grade(task, answer) {
  if (task.family === 'unanswerable') return REFUSAL.test(answer);
  const a = norm(answer);
  return task.gold.every((g) => a.includes(norm(g)));
}

async function main() {
  const { files, tasks: all } = build();
  const tasks = ONLY ? all.filter((t) => t.family === ONLY) : all;
  const chunks = files.flatMap((f) => chunkText(f.content).map((body, i) => ({ id: `${f.name}#${i}`, file: f.name, body })));
  const t0 = Date.now();
  const vectors = await embed(chunks.map((c) => c.body));
  chunks.forEach((c, i) => { c.vec = vectors[i]; });
  console.error(`indexed ${chunks.length} chunks from ${files.length} files in ${Date.now() - t0} ms`);

  const decisions = createDecisions({
    backends: { 'llama-rerank': llamaRerankBackend({ baseUrl: RERANK }), embed: embedBackend() },
    chains: { 'rag.rerank': ['llama-rerank'] },
    log: (e) => { if (e.failed || e.fellBack) console.error('[decision]', JSON.stringify(e)); },
  });

  const outDir = path.join(__dirname, 'results');
  fs.mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const rowsFile = path.join(outDir, `${stamp}-${CHAT_MODEL.replace(/[^a-z0-9.-]+/gi, '_')}.jsonl`);
  const rows = [];

  for (let rep = 0; rep < REPEAT; rep++) for (const task of tasks) {
    const [qvec] = await embed([task.question]);
    const ranked = chunks.map((c) => ({ c, score: cosine(qvec, c.vec) })).sort((a, b) => b.score - a.score);
    for (const mode of MODES) {
      let selected, rerankMs = 0, fellBack = null;
      if (mode === 'baseline') {
        selected = ranked.filter((r) => r.score >= MIN_SCORE).slice(0, TOP_K).map((r) => r.c);
      } else {
        const n = mode === 'rerank3' ? 3 : 6;
        const pool = ranked.slice(0, mode === 'rerank6p12' ? 12 : POOL);
        const items = pool.map((r) => ({ id: r.c.id, label: r.c.body, score: r.score }));
        const fallbackOrder = items.map((i) => i.id);
        const t = Date.now();
        const d = await decisions.rank({ purpose: 'rag.rerank', question: task.question, items,
          fallback: { selected: fallbackOrder, scores: Object.fromEntries(items.map((i) => [i.id, i.score])), confidence: null },
          constraints: { deadlineMs: RERANK_DEADLINE_MS } });
        rerankMs = Date.now() - t; fellBack = d.metadata?.fellBack || null;
        const byId = new Map(pool.map((r) => [r.c.id, r.c]));
        selected = d.selected.slice(0, n).map((id) => byId.get(id));
      }
      const text = selected.map((c) => c.body).join('\n');
      const recall = task.evidence.length ? task.evidence.every((e) => text.includes(e)) : null;
      const goldRank = task.evidence.length ? (() => { const i = ranked.findIndex((r) => r.c.body.includes(task.evidence[0])); return i < 0 ? null : i + 1; })() : null;
      const { body, ms } = await post(CHAT, '/v1/chat/completions', {
        messages: [{ role: 'system', content: prompt(files, selected) }, { role: 'user', content: task.question }],
        temperature: 0, max_tokens: 300, chat_template_kwargs: { enable_thinking: false },
      });
      const answer = body.choices?.[0]?.message?.content || '';
      const row = { rep, task: task.id, family: task.family, mode, model: CHAT_MODEL, correct: grade(task, answer), recall, goldCosineRank: goldRank,
        promptTokens: body.usage?.prompt_tokens ?? null, genMs: ms, rerankMs, fellBack, chunks: selected.length, answer: answer.slice(0, 400) };
      rows.push(row); fs.appendFileSync(rowsFile, JSON.stringify(row) + '\n');
      console.error(`${task.id.padEnd(8)} ${mode.padEnd(8)} ${row.correct ? 'OK ' : 'MISS'} recall=${recall} rank=${goldRank} tok=${row.promptTokens} gen=${ms}ms rr=${rerankMs}ms`);
    }
  }
  summarise(rows, rowsFile);
}

function summarise(rows, rowsFile) {
  const median = (xs) => { const s = xs.filter((x) => x != null).sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : null; };
  const pct = (xs) => xs.length ? `${Math.round(100 * xs.filter(Boolean).length / xs.length)}% (${xs.filter(Boolean).length}/${xs.length})` : '—';
  const families = [...new Set(rows.map((r) => r.family))];
  const lines = [`# RAG rerank run — ${path.basename(rowsFile)}`, '', `Host: ${os.cpus()[0]?.model} · ${Math.round(os.totalmem() / 2 ** 30)} GB · chat model ${rows[0]?.model}`, '',
    `| Mode | Correct | Evidence recall | ${families.map((f) => `${f} correct`).join(' | ')} | Median prompt tokens | Median rerank ms | Median gen ms |`,
    `|---|---|---|${families.map(() => '---').join('|')}|---|---|---|`];
  for (const mode of [...new Set(rows.map((r) => r.mode))]) {
    const m = rows.filter((r) => r.mode === mode);
    lines.push(`| ${mode} | ${pct(m.map((r) => r.correct))} | ${pct(m.filter((r) => r.recall !== null).map((r) => r.recall))} | ${families.map((f) => pct(m.filter((r) => r.family === f).map((r) => r.correct))).join(' | ')} | ${median(m.map((r) => r.promptTokens))} | ${median(m.map((r) => r.rerankMs))} | ${median(m.map((r) => r.genMs))} |`);
  }
  const md = lines.join('\n') + '\n';
  fs.writeFileSync(rowsFile.replace(/\.jsonl$/, '.md'), md);
  console.log(md);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
