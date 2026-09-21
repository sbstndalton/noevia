'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const { createRunBudget } = require('./run-budget.cjs');
function fixture(fetchImpl = async () => ({ ok: true })) {
  let time = 0, fire, cutoffs = 0, cleared = 0;
  const budget = createRunBudget({ maxMs: 100, fetchImpl, now: () => time,
    onCutoff: () => cutoffs++, setTimer: (f) => { fire = f; return 1; }, clearTimer: () => cleared++ });
  return { budget, fire: () => fire(), advance: (ms) => time += ms, cuts: () => cutoffs, clears: () => cleared };
}
function hangingFetch(url, { signal }) {
  return new Promise((resolve, reject) => {
    signal.throwIfAborted();
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  });
}

test('independent deadline aborts an in-flight fetch without a next-decision check', async () => {
  const f = fixture(hangingFetch), request = f.budget.fetch('http://mock/completion');
  f.advance(100); f.fire();
  await assert.rejects(request, /wall-clock limit/);
  assert.equal(f.cuts(), 1); assert.equal(f.budget.cutoffMs(), 100);
});

test('deadline also aborts a stalled startup health fetch', async () => {
  const f = fixture(hangingFetch), request = f.budget.fetch('http://mock/health');
  f.advance(100); f.fire();
  await assert.rejects(request, /wall-clock limit/);
});

test('cancel prevents new requests even if caller catches an earlier abort', () => {
  let calls = 0; const f = fixture(() => { calls++; });
  f.budget.cancel(Error('signal SIGINT'));
  assert.throws(() => f.budget.fetch('http://mock'), /signal SIGINT/);
  assert.equal(calls, 0);
});

test('per-request cancellation is combined with, not substituted for, run cancellation', async () => {
  const f = fixture(hangingFetch), local = new AbortController();
  const request = f.budget.fetch('http://mock', { signal: local.signal });
  local.abort(Error('request expired'));
  await assert.rejects(request, /request expired/);
  assert.equal(f.budget.signal.aborted, false);
  f.budget.dispose();
});

test('monotonic check catches an overdue budget even before timer delivery', () => {
  const f = fixture(); f.advance(110);
  assert.throws(f.budget.check, /wall-clock limit/);
  assert.equal(f.cuts(), 1);
});

test('cutoff is idempotent and keeps the original reason', () => {
  const f = fixture(); f.budget.cancel('cancelled'); f.fire();
  assert.equal(f.cuts(), 1); assert.equal(f.budget.signal.reason.message, 'cancelled');
});

test('normal disposal removes the total timer', () => {
  const f = fixture(); f.budget.dispose();
  assert.equal(f.clears(), 1); assert.equal(f.budget.signal.aborted, false);
});

test('invalid time limits fail before starting any work', () => {
  for (const maxMs of [0, -1, NaN, Infinity, 2147483648]) assert.throws(() => createRunBudget({ maxMs }), /invalid run time/);
});
