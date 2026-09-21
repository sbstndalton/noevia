'use strict';
// Real runner + backend + decision layer + harness. Only the scenario/render/baseline inputs
// are isolated. The explicit worker is a Node HTTP fixture, never a discovered llama binary.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { setTimeout: delay } = require('node:timers/promises');
const runPath = path.join(__dirname, 'run.cjs');

async function unusedPort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}
const fixtureSource = String.raw`
'use strict';
const fs = require('node:fs'), http = require('node:http');
const mode = process.env.CUTOFF_FAKE_MODE;
if (process.argv.includes('--version')) {
  if (mode === 'version-hang') {
    fs.writeFileSync(process.env.CUTOFF_PIDFILE, String(process.pid));
    setInterval(() => {}, 1000);
  } else { process.stderr.write('mock-worker/no-model\n'); process.exit(0); }
} else {
  if (mode === 'startup-exit') process.exit(2);
  fs.writeFileSync(process.env.CUTOFF_PIDFILE, String(process.pid));
  if (process.env.CUTOFF_IGNORE_TERM === 'yes') process.on('SIGTERM', () => {});
  const port = Number(process.argv[process.argv.indexOf('--port') + 1]);
  let completed = 0;
  http.createServer(async (req, res) => {
    const buffers = []; for await (const b of req) buffers.push(b);
    const body = buffers.length ? JSON.parse(Buffer.concat(buffers).toString()) : {};
    fs.appendFileSync(process.env.CUTOFF_REQUESTS, req.url + '\n');
    if (req.url === '/health' && mode === 'health-hang') return;
    if (req.url === '/completion' && mode === 'inference-hang' && completed >= Number(process.env.CUTOFF_HANG_AFTER || 0)) return;
    let out;
    if (req.url === '/health') out = { status: 'ok' };
    else if (req.url === '/props') out = { model_path: 'mock/no-model', build_info: 'fixture', default_generation_settings: { n_ctx: 8192 } };
    else if (req.url === '/tokenize') out = { tokens: [{ id: 100 + (body.content.trim().charCodeAt(0) - 65) * 2 + Number(body.content.startsWith(' ')) }] };
    else if (req.url === '/apply-template') out = { prompt: 'synthetic' };
    else if (req.url === '/completion' && body.logit_bias) {
      completed++;
      out = { completion_probabilities: [{ top_probs: body.logit_bias.map(([id], i, ids) => ({ id, token: 'x', prob: i === 0 ? 0.9 : 0.1 / (ids.length - 1) })) }] };
    } else out = { completion_probabilities: [{ top_logprobs: [{ id: 100, token: 'A', logprob: Math.log(0.9) }] }] };
    res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(out));
  }).listen(port, '127.0.0.1');
}
`;

async function launch(t, mode, args = [], env = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-cutoff-test-'));
  const fake = path.join(dir, 'only-mock-worker.cjs'), preload = path.join(dir, 'scenario-fixture.cjs');
  const model = path.join(dir, 'not-a-model.gguf'), pidfile = path.join(dir, 'worker.pid'), requests = path.join(dir, 'requests.log');
  fs.writeFileSync(fake, fixtureSource); fs.writeFileSync(model, 'synthetic, never loaded');
  const item = { id: 'mock', family: 'fixture', split: 'calib', question: 'synthetic', acceptable: ['FINISH'],
    canonical: {}, state: { schema: 'noevia.decision-state/2', actions: [{ id: 'FINISH', text: 'finish' }, { id: 'CONTINUE', text: 'continue' }, { id: 'ASK', text: 'ask' }] } };
  fs.writeFileSync(preload, `
const Module = require('node:module'); const load = Module._load;
Module._load = function(name, parent, ...rest) {
  if (parent && parent.filename === ${JSON.stringify(runPath)}) {
    if (name === './scenarios.cjs') return { build: () => Array.from({ length: 20 }, (_, i) => ({ ...${JSON.stringify(item)}, id: 'mock-' + i })) };
    if (name === './state.cjs') return { renderCompact: () => 'fixture', renderFull: () => 'fixture', renderCompactV2: () => 'fixture' };
    if (name === './baselines.cjs') return { b0: () => 'CONTINUE', b1: () => 'CONTINUE' };
  }
  return load.call(this, name, parent, ...rest);
};
`);
  const p = spawn(process.execPath, ['--require', preload, runPath, '--model', model, '--label', 'cutoff-fixture', '--ngl', '0', '--threads', '1', '--port', String(await unusedPort()),
    ...args, '--splits', 'calib', '--limit', '10', '--deadline', '10000', '--max-minutes', '0.02'], {
    env: { ...process.env, LLAMA_SERVER_BIN: fake, DECISION_RESULTS_DIR: dir, CUTOFF_PIDFILE: pidfile, CUTOFF_REQUESTS: requests, CUTOFF_FAKE_MODE: mode, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stderr = ''; p.stderr.on('data', (x) => stderr += x); p.stdout.resume();
  const done = new Promise((resolve, reject) => { p.once('error', reject); p.once('exit', (code) => resolve(code)); });
  const workerAlive = () => { try { process.kill(Number(fs.readFileSync(pidfile, 'utf8')), 0); return true; } catch { return false; } };
  const rows = () => {
    const f = fs.readdirSync(dir).find((name) => name.endsWith('.jsonl'));
    if (!f) return [];
    return fs.readFileSync(path.join(dir, f), 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
  };
  const watchdog = setTimeout(() => p.kill('SIGKILL'), 8500);
  t.after(async () => {
    clearTimeout(watchdog);
    if (p.exitCode == null && p.signalCode == null) p.kill('SIGKILL');
    if (workerAlive()) { try { process.kill(Number(fs.readFileSync(pidfile, 'utf8')), 'SIGKILL'); } catch {} }
    await delay(30); fs.rmSync(dir, { recursive: true, force: true });
  });
  return { p, done, rows, workerAlive, stderr: () => stderr, requests: () => fs.existsSync(requests) ? fs.readFileSync(requests, 'utf8') : '' };
}

for (const mode of ['health-hang', 'inference-hang', 'version-hang']) {
  test(`total cutoff interrupts ${mode} before the longer per-operation timeout`, { timeout: 8000 }, async (t) => {
    const r = await launch(t, mode);
    assert.equal(await r.done, 0, r.stderr());
    const end = r.rows().at(-1);
    assert.equal(end.phase, 'end'); assert.match(end.stopped, /wall-clock limit/);
    assert.ok(end.wallMs < 3500, `cutoff took ${end.wallMs} ms`);
    assert.ok(end.cutoffMs >= 1100 && end.cutoffMs < 2500);
    assert.equal(end.workerStopped, true); assert.equal(r.workerAlive(), false);
    if (mode === 'inference-hang') assert.match(r.requests(), /\/completion/);
    if (mode === 'health-hang') assert.doesNotMatch(r.requests(), /\/completion/);
  });
}

test('normal end records the corrected contract and confirmed cleanup', { timeout: 8000 }, async (t) => {
  const r = await launch(t, 'normal', ['--limit', '2']);
  assert.equal(await r.done, 0, r.stderr());
  const rows = r.rows(), end = rows.at(-1);
  assert.equal(end.stopped, null); assert.equal(end.cutoffMs, null);
  assert.equal(end.readoutContract, 'equal-bias-v4');
  assert.equal(rows.filter((x) => !x.meta).length, 2);
  assert.equal(end.workerStopped, true); assert.equal(r.workerAlive(), false);
});

test('completed rows survive a cutoff during the next decision', { timeout: 8000 }, async (t) => {
  const r = await launch(t, 'inference-hang', [], { CUTOFF_HANG_AFTER: '1' });
  await r.done;
  const rows = r.rows(), decisions = rows.filter((x) => !x.meta);
  assert.equal(decisions[0].readout, 'exact');
  assert.ok(decisions[0].diagnostics.request2);
  assert.match(rows.at(-1).stopped, /wall-clock limit/);
  assert.equal(r.workerAlive(), false);
});

test('SIGINT cancels the active request and retains an end record', { timeout: 8000 }, async (t) => {
  const r = await launch(t, 'inference-hang', ['--max-minutes', '0.1']);
  for (let i = 0; i < 100 && !r.requests().includes('/completion'); i++) await delay(20);
  assert.match(r.requests(), /\/completion/);
  r.p.kill('SIGINT');
  assert.equal(await r.done, 130, r.stderr());
  assert.match(r.rows().at(-1).stopped, /signal SIGINT/); assert.equal(r.workerAlive(), false);
});

test('worker ignoring TERM is killed after the separately recorded cleanup grace', { timeout: 8000 }, async (t) => {
  const r = await launch(t, 'inference-hang', [], { CUTOFF_IGNORE_TERM: 'yes' });
  await r.done;
  const end = r.rows().at(-1);
  assert.match(end.stopped, /wall-clock limit/);
  assert.ok(end.cleanupMs >= 2500 && end.cleanupMs < 5000);
  assert.equal(end.workerStopped, true); assert.equal(r.workerAlive(), false);
});

test('startup failure still records the reason and does not leave a worker', { timeout: 8000 }, async (t) => {
  const r = await launch(t, 'startup-exit'); await r.done;
  assert.match(r.rows().at(-1).stopped, /worker exited during startup/);
  assert.equal(r.workerAlive(), false);
});
