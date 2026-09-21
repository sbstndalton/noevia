'use strict';
// Mocked end-to-end: backend failure/success → decide() → harness → saved result row. And the
// runner's worker lifecycle against a fake llama-server (no model, no inference).
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { spawn } = require('node:child_process');
const { llamaLogitBackend } = require('../../../apps/web/server/decision/backends.cjs');
const { createHarness } = require('./harness.cjs');
const { build } = require('./scenarios.cjs');
const { renderCompactV2 } = require('./state.cjs');

const item = build(undefined, { stateVersion: 2 }).find((x) => x.family === 'finish_vs_incomplete' && x.split === 'calib');
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'decisions-test-'));
const readRows = (f) => fs.readFileSync(f, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

function mockFetch(firstTop) {
  return async (url, init) => {
    const b = init.body ? JSON.parse(init.body) : null;
    let out;
    if (url.endsWith('/props')) out = { model_path: '/m/x.gguf', build_info: 'b-test', default_generation_settings: { n_ctx: 8192 } };
    else if (url.endsWith('/tokenize')) { const t = b.content.trim(); out = { tokens: [{ id: 100 + 'ABC'.indexOf(t) * 2 + (b.content.startsWith(' ') ? 1 : 0), piece: b.content }] }; }
    else if (url.endsWith('/apply-template')) out = { prompt: 'P' };
    else if (b.logit_bias) out = { completion_probabilities: [{ top_probs: b.logit_bias.map(([id], i) => ({ id, token: String(id), prob: i < 2 ? 0.35 : 0.3 / (b.logit_bias.length - 2) })) }] };
    else out = { completion_probabilities: [{ top_logprobs: firstTop }], timings: { prompt_n: 20, prompt_ms: 4 } };
    return { ok: true, json: async () => out };
  };
}

test('a failed readout survives backend → decide() → saved row, with its full diagnostics', async () => {
  const dir = tmp(), file = path.join(dir, 'r.jsonl');
  const h = createHarness({ backend: llamaLogitBackend({ baseUrl: 'http://w', fetchImpl: mockFetch([{ id: 1, token: '<|channel>', logprob: -0.02 }]) }), file });
  await h.decideOne({ item, stateText: renderCompactV2(item.state), fallback: 'CONTINUE', deadlineMs: 1000, label: 'mock' });
  const [row] = readRows(file);
  assert.equal(row.source, 'fallback'); assert.equal(row.selected, 'CONTINUE'); assert.equal(row.readout, 'invalid');
  assert.match(row.rejection, /answer position holds/);
  const d = row.diagnostics;
  assert.deepEqual(d.runtime, { modelPath: '/m/x.gguf', build: 'b-test', nCtx: 8192 });
  assert.equal(Object.keys(d.labels).length, item.state.actions.length);
  assert.deepEqual(d.labels.FINISH.variants.map((v) => v.ids[0]), [100, 101]);
  assert.equal(d.request1.top[0].token, '<|channel>'); assert.equal(d.request1.promptTokens, 20);
  assert.equal(d.labelMassAtAnswer, 0); assert.match(d.rejection, /answer position/);
  assert.equal(typeof d.timings.totalMs, 'number'); assert.equal(typeof row.ms, 'number');
  assert.equal(JSON.stringify(row).includes(item.state.task.text), false, 'no state text in the saved row');
});

test('a successful readout is saved with both requests, the class and the bounds', async () => {
  const dir = tmp(), file = path.join(dir, 'r.jsonl');
  const h = createHarness({ backend: llamaLogitBackend({ baseUrl: 'http://w', fetchImpl: mockFetch([{ id: 102, token: 'B', logprob: -0.1 }, { id: 100, token: 'A', logprob: -2.5 }]) }), file });
  await h.decideOne({ item, stateText: renderCompactV2(item.state), fallback: 'CONTINUE', deadlineMs: 1000, label: 'mock' });
  const [row] = readRows(file);
  assert.equal(row.source, 'llama-logit'); assert.equal(row.readout, 'exact');
  assert.ok(row.diagnostics.request2.top.length >= 6); assert.equal(row.diagnostics.residual, 0);
  assert.deepEqual(row.diagnostics.unobserved, []); assert.ok(row.bounds && row.ratios);
});

// ---- runner lifecycle, against the fake server ---------------------------------------------------
const fixtures = path.join(__dirname, 'test-fixtures');
function runner(args, env = {}) {
  const dir = tmp(), model = path.join(dir, 'fake.gguf'); fs.writeFileSync(model, 'x');
  const pidfile = path.join(dir, 'pid');
  const p = spawn(process.execPath, [path.join(__dirname, 'run.cjs'), '--model', model, '--label', 'fake', '--splits', 'calib', '--port', String(19000 + Math.floor(Math.random() * 900)), ...args],
    { env: { ...process.env, LLAMA_SERVER_BIN: path.join(fixtures, 'fake-llama-server.cjs'), DECISION_RESULTS_DIR: dir, FAKE_PIDFILE: pidfile, ...env }, stdio: 'ignore' });
  const done = new Promise((r) => p.on('exit', (code) => r(code)));
  const rows = () => { const f = fs.readdirSync(dir).find((x) => x.endsWith('.jsonl')); return f ? readRows(path.join(dir, f)) : []; };
  const alive = () => { try { process.kill(Number(fs.readFileSync(pidfile, 'utf8')), 0); return true; } catch { return false; } };
  return { p, done, rows, alive };
}
const settle = (ms) => new Promise((r) => setTimeout(r, ms));

test('runner: a normal run writes start, one row per decision and an end record, and stops the worker', async () => {
  const r = runner(['--limit', '3']);
  assert.equal(await r.done, 0); await settle(300);
  const rows = r.rows();
  assert.equal(rows[0].phase, 'start'); assert.equal(rows.at(-1).phase, 'end'); assert.equal(rows.at(-1).stopped, null);
  assert.equal(rows.filter((x) => !x.meta).length, 3); assert.equal(r.alive(), false);
});

test('runner: startup failure is recorded and leaves no worker behind', async () => {
  const r = runner(['--limit', '3'], { FAKE_MODE: 'exit' });
  await r.done; await settle(300);
  assert.match(r.rows().at(-1).stopped, /worker exited during startup/); assert.equal(r.alive(), false);
});

test('runner: repeated invalid readouts stop the run as configured', async () => {
  const r = runner(['--limit', '10', '--max-invalid', '2'], { FAKE_MODE: 'format' });
  await r.done; await settle(300);
  const rows = r.rows();
  assert.equal(rows.filter((x) => !x.meta).length, 2); assert.match(rows.at(-1).stopped, /2 invalid readouts in a row/);
  assert.ok(rows.filter((x) => !x.meta).every((x) => x.diagnostics && x.rejection));
  assert.equal(r.alive(), false);
});

test('runner: the wall-clock limit stops the run and the worker', async () => {
  const r = runner(['--limit', '10', '--max-minutes', '0.01'], { FAKE_MODE: 'slow', FAKE_DELAY_MS: '300' });
  await r.done; await settle(300);
  assert.match(r.rows().at(-1).stopped, /wall-clock limit/); assert.equal(r.alive(), false);
});

test('runner: SIGINT mid-run keeps the rows so far, writes the end record and stops the worker', async () => {
  const r = runner(['--limit', '10'], { FAKE_MODE: 'slow', FAKE_DELAY_MS: '400' });
  for (let i = 0; i < 100 && r.rows().filter((x) => !x.meta).length < 1; i++) await settle(100);
  r.p.kill('SIGINT');
  await r.done; await settle(500);
  const rows = r.rows();
  assert.ok(rows.filter((x) => !x.meta).length >= 1);
  assert.equal(rows.at(-1).phase, 'end'); assert.match(rows.at(-1).stopped, /signal SIGINT/);
  assert.equal(r.alive(), false);
});
