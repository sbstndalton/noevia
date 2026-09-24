'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {
  sanitizeText, repoFromCheckpoint, cardUrl, hostAllowed, normalizeCard,
  artifactIdentityHash, fetchModelCardEvidence, importModelEvidence, deriveExternal,
} = require('./model-evidence-import.cjs');

const now = 2_000_000_000_000;
const cardBody = (over = {}) => ({
  id: 'acme/model-7b',
  sha: 'a'.repeat(40),
  license: 'apache-2.0',
  pipeline_tag: 'text-generation',
  library_name: 'gguf',
  tags: ['gguf', 'chat', 'x'.repeat(90)],
  cardData: {
    license: 'apache-2.0',
    model_summary: 'A general-purpose chat model.',
    'model-index': [{ results: [{ task: { type: 'text-generation' }, dataset: { name: 'MMLU' }, metrics: [{ type: 'accuracy', value: 71.2 }] }] }],
  },
  ...over,
});

test('sanitizeText strips markup/control characters and caps length', () => {
  assert.equal(sanitizeText('<b>hi</b>\u0007 there'), 'hi there');
  assert.equal(sanitizeText(null), null);
  assert.equal(sanitizeText('x'.repeat(3000)).length, 2001); // 2000 chars + ellipsis
});

test('repoFromCheckpoint validates and strips a quant tag', () => {
  assert.equal(repoFromCheckpoint('acme/model-7b'), 'acme/model-7b');
  assert.equal(repoFromCheckpoint('acme/model-7b:Q4_K_M'), 'acme/model-7b');
  assert.equal(repoFromCheckpoint('../etc/passwd'), null);
  assert.equal(repoFromCheckpoint('not-a-repo'), null);
  assert.equal(repoFromCheckpoint(''), null);
});

test('cardUrl targets the fixed allow-listed host and hostAllowed rejects other hosts', () => {
  const url = cardUrl('acme/model-7b');
  assert.equal(url, 'https://huggingface.co/api/models/acme/model-7b');
  assert.ok(hostAllowed(url));
  assert.ok(!hostAllowed('https://evil.example.com/api/models/acme/model-7b'));
  assert.ok(!hostAllowed('http://huggingface.co/api/models/acme/model-7b')); // not https
  assert.ok(!hostAllowed('not a url'));
});

test('normalizeCard extracts and caps license/eval claims, drops unrecognized shape', () => {
  const v = normalizeCard('acme/model-7b', cardBody());
  assert.equal(v.repo, 'acme/model-7b');
  assert.equal(v.revision, 'a'.repeat(40));
  assert.equal(v.license, 'apache-2.0');
  assert.equal(v.pipelineTag, 'text-generation');
  assert.equal(v.tags.length, 3);
  assert.equal(v.tags[2].length, 61); // 60 + ellipsis
  assert.deepEqual(v.evaluationClaims[0], { task: 'text-generation', dataset: 'MMLU', metric: 'accuracy', value: '71.2' });
  assert.equal(normalizeCard('acme/model-7b', null), null);
  assert.equal(normalizeCard('acme/model-7b', 'oops'), null);
});

test('artifactIdentityHash is stable for the same artifact and differs for another', () => {
  assert.equal(artifactIdentityHash('123:456:abc'), artifactIdentityHash('123:456:abc'));
  assert.notEqual(artifactIdentityHash('123:456:abc'), artifactIdentityHash('123:456:def'));
});

test('fetchModelCardEvidence rejects a bad checkpoint or missing artifact without fetching', async () => {
  let called = false;
  const fetchJson = async () => { called = true; return { ok: true, body: cardBody() }; };
  assert.equal((await fetchModelCardEvidence({ checkpoint: 'bad', artifact: 'x', fetchJson, now: () => now })).ok, false);
  assert.equal((await fetchModelCardEvidence({ checkpoint: 'acme/model-7b', artifact: null, fetchJson, now: () => now })).ok, false);
  assert.equal(called, false);
});

test('fetchModelCardEvidence never follows redirects and only queries the allow-listed host', async () => {
  let seenUrl = null, seenOpts = null;
  const fetchJson = async (url, opts) => { seenUrl = url; seenOpts = opts; return { ok: true, body: cardBody() }; };
  const result = await fetchModelCardEvidence({ checkpoint: 'acme/model-7b:Q4_K_M', artifact: 'artifact-hash', fetchJson, now: () => now });
  assert.equal(result.ok, true);
  assert.equal(seenUrl, 'https://huggingface.co/api/models/acme/model-7b');
  assert.equal(seenOpts.redirect, 'error');
  assert.equal(result.record.category, 'external_model_card');
  assert.equal(result.record.result, 'reported');
  assert.equal(result.record.identityHash, artifactIdentityHash('artifact-hash'));
  assert.equal(result.record.provenance.sourceUrl, 'https://huggingface.co/api/models/acme/model-7b');
  assert.equal(result.record.provenance.retrievedAt, now);
  assert.match(result.record.limitations[0], /unverified, from source/);
});

test('fetchModelCardEvidence handles offline/failed/oversized lookups without throwing', async () => {
  const throwing = async () => { throw Object.assign(new Error('response too large'), { status: 502 }); };
  assert.equal((await fetchModelCardEvidence({ checkpoint: 'acme/model-7b', artifact: 'a', fetchJson: throwing, now: () => now })).ok, false);
  const notFound = async () => ({ ok: false, status: 404, body: { error: 'not found' } });
  assert.equal((await fetchModelCardEvidence({ checkpoint: 'acme/model-7b', artifact: 'a', fetchJson: notFound, now: () => now })).ok, false);
  const priv = async () => ({ ok: true, body: { private: true } });
  assert.equal((await fetchModelCardEvidence({ checkpoint: 'acme/model-7b', artifact: 'a', fetchJson: priv, now: () => now })).ok, false);
});

function memoryStore() {
  const records = [];
  return {
    list: () => records,
    appendIfChanged(record) {
      const newest = records.filter((r) => r.model === record.model && r.category === record.category && r.identityHash === record.identityHash).at(-1);
      if (newest && JSON.stringify(newest.value) === JSON.stringify(record.value)) return newest;
      const entry = { id: `ev_${records.length}`, at: Date.now(), ...record };
      records.push(entry);
      return entry;
    },
  };
}

test('importModelEvidence dedupes repeated imports of the same artifact and card', async () => {
  const store = memoryStore();
  const fetchJson = async () => ({ ok: true, body: cardBody() });
  const first = await importModelEvidence({ model: 'laya', checkpoint: 'acme/model-7b', artifact: 'artifact-1', fetchJson, store, now: () => now });
  const second = await importModelEvidence({ model: 'laya', checkpoint: 'acme/model-7b', artifact: 'artifact-1', fetchJson, store, now: () => now + 1000 });
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  assert.equal(store.list().length, 1, 'unchanged card for the same artifact appends nothing');
  assert.equal(first.record.id, second.record.id);
});

test('importModelEvidence records a new entry when the card changes or the artifact changes', async () => {
  const store = memoryStore();
  let license = 'apache-2.0';
  const fetchJson = async () => ({ ok: true, body: cardBody({ cardData: { license, 'model-index': [] } }) });
  await importModelEvidence({ model: 'laya', checkpoint: 'acme/model-7b', artifact: 'artifact-1', fetchJson, store, now: () => now });
  license = 'mit';
  await importModelEvidence({ model: 'laya', checkpoint: 'acme/model-7b', artifact: 'artifact-1', fetchJson, store, now: () => now + 1 });
  await importModelEvidence({ model: 'laya', checkpoint: 'acme/model-7b', artifact: 'artifact-2', fetchJson, store, now: () => now + 2 });
  assert.equal(store.list().length, 3);
});

test('deriveExternal reports the artifact-matching record, falls back to stale, then unverified', () => {
  const records = [
    { model: 'laya', category: 'external_model_card', identityHash: artifactIdentityHash('old'), value: { license: 'mit' } },
    { model: 'laya', category: 'external_model_card', identityHash: artifactIdentityHash('new'), value: { license: 'apache-2.0' } },
  ];
  assert.equal(deriveExternal(records, { model: 'laya', artifactHash: artifactIdentityHash('new') }).state, 'reported');
  assert.equal(deriveExternal(records, { model: 'laya', artifactHash: artifactIdentityHash('unseen') }).state, 'stale');
  assert.equal(deriveExternal(records, { model: 'laya', artifactHash: null }).state, 'unavailable');
  assert.equal(deriveExternal([], { model: 'laya', artifactHash: artifactIdentityHash('new') }).state, 'unverified');
  assert.equal(deriveExternal(records, { model: 'other', artifactHash: artifactIdentityHash('new') }).state, 'unverified');
});
