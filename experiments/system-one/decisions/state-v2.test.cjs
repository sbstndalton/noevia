'use strict';
// Integration: decision state v2 builds its shortlist through residency.cjs, and the rendered
// input shows the swap and its cost. (Unit tests of the helper alone are residency.test.cjs.)
const test = require('node:test'), assert = require('node:assert/strict');
const { extractV2, renderCompactV2 } = require('./state.cjs');
const { build } = require('./scenarios.cjs');

const model = (id, residentGB, success, extra = {}) => ({ id, memGB: residentGB, loadSec: 5, residentGB, loadPeakGB: 0.3, capabilities: { reasoning: { success, n: 100 } }, ...extra });
function canonical({ session = { durableCheckpoint: true, switchAuthorized: true }, models, resident, hostAvailableGB = 8 } = {}) {
  return {
    task: { id: 't1', text: 'Plan the migration.', type: 'reasoning', phase: 'planning' }, turns: [],
    models: models || [model('cur-4B', 6.7, 0.55), model('small-2B', 2.0, 0.6), model('big-20B', 12.6, 0.9), model('mystery-3B', null, 0.95, { residentGB: null }), model('huge-70B', 40, 0.97)],
    currentModel: 'cur-4B', policy: 'local-only', budget: { retriesLeft: 1, switchesLeft: 1 }, verifier: [], toolLog: [], costs: { reconstructSec: 6 },
    host: { limitGB: 14, hostAvailableGB, resident: resident || [{ id: 'cur-4B', residentGB: 6.7, pinned: false }, { id: 'reranker', residentGB: 1.0, pinned: true }] },
    session,
  };
}
const ids = (s) => s.shortlist.map((p) => p.id);
const blocked = (s, id) => s.notExecutable.find((n) => n.id === id);

test('a model that fits alongside the current one stays eligible', () => {
  const s = extractV2(canonical(), []);
  assert.ok(ids(s).includes('small-2B'));
  assert.equal(s.shortlist.find((p) => p.id === 'small-2B').fit, 'coexist');
});

test('a model that fits only after a swap reaches the shortlist when a durable, authorised checkpoint permits switching', () => {
  const s = extractV2(canonical(), []);
  const big = s.shortlist.find((p) => p.id === 'big-20B');
  assert.equal(big.fit, 'after_swap'); assert.deepEqual(big.swap.unload, ['cur-4B']);
  assert.equal(big.swap.estSec, 5 + 6);
  const text = renderCompactV2(s);
  assert.match(text, /big-20B: .*requires a checkpoint and unloading cur-4B \(frees about 6\.7 GB\); estimated switch cost 11s/);
});

test('the same swap is unavailable without durability or without authorisation', () => {
  for (const session of [{ durableCheckpoint: false, switchAuthorized: true }, { durableCheckpoint: true, switchAuthorized: false }, undefined]) {
    const c = canonical({ session }); if (!session) delete c.session;
    const s = extractV2(c, []);
    assert.equal(ids(s).includes('big-20B'), false);
    assert.equal(blocked(s, 'big-20B').fit, 'after_swap');
    assert.match(renderCompactV2(s), /Not executable now:\n(.|\n)*big-20B: after_swap/);
  }
});

test('pinned residents are not counted as reclaimable memory', () => {
  // Needs 13.3 GB: fits only if the pinned reranker (1.0) could be freed as well as cur-4B (6.7).
  const c = canonical({ models: [model('cur-4B', 6.7, 0.5), model('big-13B', 13.3, 0.9)], hostAvailableGB: 20 });
  const s = extractV2(c, []);
  assert.equal(ids(s).includes('big-13B'), false);
  assert.equal(blocked(s, 'big-13B').fit, 'no_fit');
});

test('unknown measurements stay explicitly unknown and are never offered', () => {
  const s = extractV2(canonical(), []);
  assert.equal(ids(s).includes('mystery-3B'), false);
  assert.deepEqual(blocked(s, 'mystery-3B'), { id: 'mystery-3B', fit: 'unknown', reason: 'candidate footprint not measured' });
  const c2 = canonical({ resident: [{ id: 'cur-4B', residentGB: null, pinned: false }] });
  assert.ok(extractV2(c2, []).notExecutable.every((n) => n.fit === 'unknown'), 'an unmeasured resident makes every candidate unknown');
});

test('no-fit candidates are not executable choices, in the state or in the generated actions', () => {
  const s = extractV2(canonical(), []);
  assert.equal(ids(s).includes('huge-70B'), false); assert.equal(blocked(s, 'huge-70B').fit, 'no_fit');
  for (const x of build(undefined, { stateVersion: 2 })) {
    const offered = new Set(x.state.actions.map((a) => a.id.replace(/^(USE|SWITCH):/, '')));
    for (const n of x.state.notExecutable) assert.equal(offered.has(n.id), false, `${x.id} offers ${n.id} (${n.fit})`);
  }
});

test('the v2 build offers swap-only candidates exactly when switching is permitted', () => {
  const swaps = build(undefined, { stateVersion: 2 }).filter((x) => x.family === 'swap_candidate');
  assert.ok(swaps.length > 0);
  for (const x of swaps) {
    const ok = x.canonical.session.durableCheckpoint && x.canonical.session.switchAuthorized;
    assert.equal(x.state.actions.some((a) => a.id === 'SWITCH:gpt-oss-20B'), ok, x.id);
    assert.equal(x.acceptable.includes('SWITCH:gpt-oss-20B'), ok, x.id);
  }
});
