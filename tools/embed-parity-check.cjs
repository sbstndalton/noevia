#!/usr/bin/env node
'use strict';
// #697: before Diary's embeddings move from the inference engine to the `embed` sidecar, check that
// both servers produce the same vectors, so the Diary index built on the engine stays valid.
// Embeds one synthetic string through each endpoint and requires cosine similarity >= 0.999.
//
//   node tools/embed-parity-check.cjs <engine-base> <engine-model> <sidecar-base> <sidecar-model> [min]
//
// On DaServer the endpoints are internal; run it inside the web container, which reaches both:
//   docker exec -i cowork-web-1 node - http://llama:8080 nomic-embed-text-v1 \
//     http://embed:8080 nomic-embed-text-v1 < tools/embed-parity-check.cjs
//
// The engine request loads its embedding model. Under --models-max 1 that evicts the chat model,
// so run it while chat is idle, before the engine is switched to one slot. Exit 0: parity holds.

const TEXT = 'noevia embedding parity check: synthetic text, no user data.';

function cosine(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || !a.length) return NaN;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

async function embed(base, model, fetchImpl = fetch) {
  const url = `${String(base).replace(/\/+$/, '').replace(/\/v1$/, '')}/v1/embeddings`;
  const r = await fetchImpl(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model, input: [TEXT] }), signal: AbortSignal.timeout(120000) });
  if (!r.ok) throw Error(`${url} answered HTTP ${r.status}`);
  const vector = (await r.json())?.data?.[0]?.embedding;
  if (!Array.isArray(vector) || !vector.length) throw Error(`${url} returned no embedding`);
  return vector;
}

async function check({ engine, engineModel, sidecar, sidecarModel, min = 0.999, fetchImpl = fetch }) {
  const [a, b] = await Promise.all([embed(engine, engineModel, fetchImpl), embed(sidecar, sidecarModel, fetchImpl)]);
  const similarity = cosine(a, b);
  return { ok: Number.isFinite(similarity) && similarity >= min, similarity, dimensions: [a.length, b.length], min };
}

module.exports = { cosine, check, TEXT };

if (require.main === module || !module.parent) {
  const [engine, engineModel, sidecar, sidecarModel, min] = process.argv.slice(2);
  if (!engine || !engineModel || !sidecar || !sidecarModel) {
    console.error('usage: embed-parity-check.cjs <engine-base> <engine-model> <sidecar-base> <sidecar-model> [min=0.999]');
    process.exit(2);
  }
  check({ engine, engineModel, sidecar, sidecarModel, min: min ? Number(min) : 0.999 })
    .then((r) => { console.log(JSON.stringify(r)); process.exit(r.ok ? 0 : 1); })
    .catch((e) => { console.error(String(e?.message || e)); process.exit(2); });
}
