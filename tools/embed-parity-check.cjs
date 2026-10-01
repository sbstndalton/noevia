#!/usr/bin/env node
'use strict';
// #697/#720: before Diary's embeddings move from the inference engine to the `embed` sidecar, check
// that both servers produce the same vectors, so the Diary index built on the engine stays valid.
// Embeds a varied synthetic sample (40 documents + 10 queries, no user data) through each endpoint and
// checks two things:
//   1. per-string cosine similarity: the minimum must be >= min (default 0.997). On DaServer (2026-10-01,
//      same nomic GGUF, engine on Vulkan vs sidecar on CPU) this sample measured min 0.99863, median
//      0.99909: float noise, not a different model;
//   2. retrieval agreement: for each query, the top-k documents (k=5) ranked by each embedder; the mean
//      overlap@k must be >= minOverlap (default 0.9; measured 0.96: two of ten queries differed by one document).
//
//   node tools/embed-parity-check.cjs <engine-base> <engine-model> <sidecar-base> <sidecar-model> [min] [minOverlap]
//
// On DaServer the endpoints are internal; run it inside the web container, which reaches both:
//   docker exec -i cowork-web-1 node - http://llama:8080 nomic-embed-text-v1 \
//     http://embed:8080 nomic-embed-text-v1 < tools/embed-parity-check.cjs
//
// The engine request loads its embedding model. Under --models-max 1 that evicts the chat model, so
// check the router's /models first (nothing loaded or chat idle), and unload the embedding model
// afterwards (POST /models/unload). Exit 0: parity holds; 1: it does not; 2: usage or HTTP error.

const DOCS = [
  'Went for a long walk by the river this morning; the fog lifted around nine.',
  'Note to self: call the plumber about the dripping kitchen tap before Friday.',
  'Grocery list: oats, 2 litres of milk, lemons, coffee beans, and dish soap.',
  'Finished reading a novel about a lighthouse keeper. The ending felt rushed.',
  'Team meeting moved to 14:30 on Tuesday; bring the quarterly numbers (Q3: +4.2%).',
  'Felt tired all day. Probably the late night; aim for bed before 23:00 tonight.',
  'Planted tomatoes, basil and two rows of carrots in the raised bed.',
  'The train was 25 minutes late again, so I missed the first half of the lecture.',
  'Ideas for the weekend: bake sourdough, repair the bike chain, visit the market.',
  'Booked flights for the conference in Lisbon, 12-15 March, seat 23A.',
  'Heute war ein ruhiger Tag. Ich habe Brot gebacken und am Abend gelesen.',
  'Morgen früh Zahnarzttermin um 8:15 Uhr, nicht vergessen!',
  'Wir sind mit dem Fahrrad zum See gefahren; das Wasser war noch kalt.',
  "Aujourd'hui j'ai visité le musée avec ma sœur ; les tableaux impressionnistes étaient magnifiques.",
  'Penser à renouveler le passeport avant le mois de juin.',
  'Le marché du samedi avait des fraises excellentes, 4 € la barquette.',
  'function add(a, b) { return a + b; } // TODO: handle overflow',
  'SELECT id, title FROM entries WHERE created_at > NOW() - INTERVAL 7 DAY ORDER BY id DESC;',
  'def fib(n):\n    return n if n < 2 else fib(n - 1) + fib(n - 2)',
  'git rebase -i HEAD~3 && git push --force-with-lease',
  'ok',
  '42',
  '!!! ??? ... ;;; ---',
  'Temperature 18.5 °C, humidity 62 %, wind 11 km/h NW, pressure 1013 hPa.',
  'Invoice #2026-0457: 3 × 19.99 = 59.97, VAT 19 % included.',
  'Phone battery died at 3pm; the charger is still at the office.',
  'Started learning the guitar. Chords C, G and Am are fine; F is still impossible.',
  'Dinner with old friends. We laughed about the camping trip when the tent collapsed in the rain.',
  'Mood: anxious about the presentation, but the rehearsal went better than expected.',
  'The cat knocked a glass off the table at 4 a.m. and then looked very pleased with itself.',
  'Ran 5 km in 27:40, a new personal best. Knee felt fine afterwards.',
  'Rewatched an old science-fiction film; the special effects aged badly but the story holds up.',
  'Budget for October: rent 950, food 320, transport 85, savings 300.',
  'Reminder: the library books are due on the 14th; two of them are overdue already.',
  'Spent the afternoon cleaning the attic and found letters from my grandmother written in 1962.',
  'It snowed overnight; the whole street was silent and white when I opened the curtains.',
  'Long reflection: lately I keep postponing the things that matter, filling the days with small urgent tasks instead. ' +
    'Next week I want to block two mornings for the writing project, switch off notifications, and see whether the ' +
    'feeling of being busy but not productive goes away. If it works, keep it as a weekly habit.',
  'Recipe: fry onions in olive oil, add garlic, crushed tomatoes and a pinch of sugar, simmer 20 minutes, season.',
  'Emoji test 😀🎉 — mixed scripts: Ελληνικά, русский, 日本語, العربية.',
  'URL https://example.invalid/path?q=synthetic&n=1 and email someone@example.invalid',
];

const QUERIES = [
  'when is the dentist appointment',
  'what did I plant in the garden',
  'running and exercise progress',
  'travel plans and flights',
  'cooking and recipes',
  'feeling stressed or anxious',
  'Python code snippet',
  'monthly money and expenses',
  'visite au musée',
  'Wetter und Schnee',
];

function cosine(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || !a.length) return NaN;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

async function embed(base, model, texts, fetchImpl = fetch, batch = 8) {
  const url = `${String(base).replace(/\/+$/, '').replace(/\/v1$/, '')}/v1/embeddings`;
  const out = [];
  for (let i = 0; i < texts.length; i += batch) {
    const input = texts.slice(i, i + batch);
    const r = await fetchImpl(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model, input }), signal: AbortSignal.timeout(120000) });
    if (!r.ok) throw Error(`${url} answered HTTP ${r.status}`);
    const items = (await r.json())?.data;
    if (!Array.isArray(items) || items.length !== input.length) throw Error(`${url} returned ${items?.length ?? 0} embeddings for ${input.length} inputs`);
    for (const item of [...items].sort((x, y) => (x.index ?? 0) - (y.index ?? 0))) {
      if (!Array.isArray(item?.embedding) || !item.embedding.length) throw Error(`${url} returned no embedding`);
      out.push(item.embedding);
    }
  }
  return out;
}

function topK(query, docs, k) {
  return docs.map((d, i) => [cosine(query, d), i]).sort((x, y) => y[0] - x[0]).slice(0, k).map(([, i]) => i);
}

function stats(values) {
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return { min: s[0], median: s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2, mean: s.reduce((a, b) => a + b, 0) / s.length, max: s[s.length - 1] };
}

async function check({ engine, engineModel, sidecar, sidecarModel, min = 0.997, minOverlap = 0.9, k = 5, docs = DOCS, queries = QUERIES, fetchImpl = fetch }) {
  const texts = [...docs, ...queries];
  // Sequential: the engine request may load a model; keep the two servers' load apart.
  const a = await embed(engine, engineModel, texts, fetchImpl);
  const b = await embed(sidecar, sidecarModel, texts, fetchImpl);
  const sims = texts.map((_, i) => cosine(a[i], b[i]));
  const cos = stats(sims);
  const kk = Math.min(k, docs.length);
  const overlaps = queries.map((_, q) => {
    const ta = topK(a[docs.length + q], a.slice(0, docs.length), kk);
    const tb = new Set(topK(b[docs.length + q], b.slice(0, docs.length), kk));
    return ta.filter((i) => tb.has(i)).length / kk;
  });
  const overlap = queries.length ? overlaps.reduce((x, y) => x + y, 0) / overlaps.length : 1;
  const ok = sims.every(Number.isFinite) && cos.min >= min && overlap >= minOverlap;
  return { ok, similarity: cos.min, cosine: cos, overlapAtK: overlap, k: kk, overlaps, strings: texts.length, dimensions: [a[0].length, b[0].length], min, minOverlap };
}

module.exports = { cosine, check, embed, topK, DOCS, QUERIES };

if (require.main === module || !module.parent) {
  const [engine, engineModel, sidecar, sidecarModel, min, minOverlap] = process.argv.slice(2);
  if (!engine || !engineModel || !sidecar || !sidecarModel) {
    console.error('usage: embed-parity-check.cjs <engine-base> <engine-model> <sidecar-base> <sidecar-model> [min=0.997] [minOverlap=0.9]');
    process.exit(2);
  }
  check({ engine, engineModel, sidecar, sidecarModel, min: min ? Number(min) : 0.997, minOverlap: minOverlap ? Number(minOverlap) : 0.9 })
    .then((r) => { console.log(JSON.stringify(r)); process.exit(r.ok ? 0 : 1); })
    .catch((e) => { console.error(String(e?.message || e)); process.exit(2); });
}
