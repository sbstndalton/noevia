'use strict';
// #340 — rag.ragAvailable() only ever meant "native index deps are installed"; it said nothing
// about whether the configured embedding endpoint actually answers. /api/health and the Settings/
// Capabilities UI reported "Project retrieval: Available" even while cowork-embed-1 was restarting.
// rag.retrievalStatus() is the bounded, cached, tri-state probe that fixes that. These pin its
// three outcomes, its timeout bound, and its cache — independent of rag.test.cjs's embedding-path
// coverage, so a change to one cannot silently break the other's fixtures.
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const Module = require('node:module');

delete process.env.RAG_DIR;
delete process.env.EMBEDDING_BASE_URL;
delete process.env.EMBEDDING_MODEL;
delete process.env.EMBED_MODEL;

function freshRag() {
  delete require.cache[require.resolve('./rag.cjs')];
  return require('./rag.cjs');
}

const realFetch = global.fetch;
test.afterEach(() => {
  global.fetch = realFetch;
  delete process.env.RETRIEVAL_PROBE_TIMEOUT_MS;
  delete process.env.RETRIEVAL_PROBE_TTL_MS;
});

function initFresh(overrides = {}) {
  const rag = freshRag();
  rag.init({ dataDir: os.tmpdir(), embedModel: 'probe-model', inferenceUrl: 'http://embedder.invalid', ...overrides });
  return rag;
}

test('a healthy synthetic embedding response reads available, and never carries real content', async () => {
  const seen = [];
  global.fetch = async (url, opts) => {
    seen.push({ url, body: JSON.parse(opts.body) });
    return { ok: true, json: async () => ({ data: [{ embedding: [0.1, 0.2, 0.3] }] }) };
  };
  const rag = initFresh();
  assert.equal(await rag.retrievalStatus(), 'available');
  assert.equal(seen.length, 1);
  assert.match(seen[0].url, /\/v1\/embeddings$/);
  assert.deepEqual(seen[0].body.input, ['noevia health probe'], 'the probe is a fixed synthetic string, never user/project content');
  assert.equal(seen[0].body.model, 'probe-model');
});

test('an unreachable embedder reads degraded, not unavailable — the index itself is still installed', async () => {
  global.fetch = async () => { throw new Error('synthetic embedding endpoint unavailable'); };
  const rag = initFresh();
  assert.equal(await rag.retrievalStatus(), 'degraded');
  assert.equal(rag.ragAvailable(), true, 'native deps are present; only the embedder is down');
});

test('a non-2xx or malformed embedding response also reads degraded', async () => {
  global.fetch = async () => ({ ok: false, status: 503, text: async () => 'restarting' });
  const rag = initFresh();
  assert.equal(await rag.retrievalStatus(), 'degraded');

  global.fetch = async () => ({ ok: true, json: async () => ({ data: [] }) });
  const rag2 = initFresh();
  assert.equal(await rag2.retrievalStatus(), 'degraded', 'an empty data array is not a real vector');
});

test('missing native SQLite modules read unavailable and never probe the embedder', async () => {
  const orig = Module._load;
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return { ok: true, json: async () => ({ data: [{ embedding: [1] }] }) }; };
  Module._load = function (request, ...rest) {
    if (request === 'better-sqlite3' || request === 'sqlite-vec') {
      throw Object.assign(new Error(`Cannot find module '${request}'`), { code: 'MODULE_NOT_FOUND' });
    }
    return orig.apply(this, [request, ...rest]);
  };
  try {
    const rag = initFresh();
    assert.equal(await rag.retrievalStatus(), 'unavailable');
    assert.equal(rag.ragAvailable(), false);
    assert.equal(fetchCalled, false, 'no embedding request is made when the index cannot run at all');
  } finally {
    Module._load = orig;
  }
});

test('a slow probe is bounded by its own timeout and does not hang the caller', async () => {
  process.env.RETRIEVAL_PROBE_TIMEOUT_MS = '80';
  let aborted = false;
  global.fetch = (url, opts) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve({ ok: true, json: async () => ({ data: [{ embedding: [1] }] }) }), 5000);
    opts.signal?.addEventListener('abort', () => {
      aborted = true;
      clearTimeout(timer);
      reject(Object.assign(new Error('aborted'), { name: 'AbortError' }));
    });
  });
  const rag = initFresh();
  const started = Date.now();
  const status = await rag.retrievalStatus();
  const elapsed = Date.now() - started;
  assert.equal(status, 'degraded', 'a probe that never answers in time is treated as embeddings down');
  assert.ok(aborted, 'the bounded probe actually aborted the slow request');
  assert.ok(elapsed < 1000, `expected the probe to give up near its own timeout, took ${elapsed}ms`);
});

test('the result is cached for the TTL: concurrent and rapid repeat calls share one probe', async () => {
  process.env.RETRIEVAL_PROBE_TTL_MS = '10000';
  let calls = 0;
  global.fetch = async () => { calls++; return { ok: true, json: async () => ({ data: [{ embedding: [1] }] }) }; };
  const rag = initFresh();
  const [a, b] = await Promise.all([rag.retrievalStatus(), rag.retrievalStatus()]);
  assert.equal(a, 'available'); assert.equal(b, 'available');
  assert.equal(calls, 1, 'concurrent callers share one in-flight probe');
  assert.equal(await rag.retrievalStatus(), 'available');
  assert.equal(calls, 1, 'a repeat call inside the TTL does not re-probe');
});

test('the cache expires after its TTL and re-probes', async () => {
  process.env.RETRIEVAL_PROBE_TTL_MS = '100'; // clamped to the module's own floor if lower
  let calls = 0;
  global.fetch = async () => { calls++; return { ok: true, json: async () => ({ data: [{ embedding: [1] }] }) }; };
  const rag = initFresh();
  assert.equal(await rag.retrievalStatus(), 'available');
  assert.equal(calls, 1);
  await new Promise((r) => setTimeout(r, 250));
  assert.equal(await rag.retrievalStatus(), 'available');
  assert.equal(calls, 2, 'the stale cache entry was not reused past its TTL');
});

test('re-init() (an endpoint/model change) invalidates whatever the last probe found', async () => {
  let calls = 0;
  global.fetch = async () => { calls++; return { ok: true, json: async () => ({ data: [{ embedding: [1] }] }) }; };
  const rag = initFresh();
  assert.equal(await rag.retrievalStatus(), 'available');
  assert.equal(calls, 1);
  rag.init({ dataDir: os.tmpdir(), embedModel: 'probe-model-2', inferenceUrl: 'http://embedder2.invalid' });
  await rag.retrievalStatus();
  assert.equal(calls, 2, 'a fresh init() must not serve a cached verdict from before the reconfiguration');
});
