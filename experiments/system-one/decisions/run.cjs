#!/usr/bin/env node
'use strict';
// Pilot runner for generic System-One backends (docs/research/system-one/13 §13.9–13.11).
//
// NO RUN WITHOUT PER-RUN APPROVAL: host, model/config, cases, CPU/GPU, peak memory, concurrency,
// hard wall-clock limit, stop conditions, impact on other apps. Smoke test first.
//
// One isolated worker: a llama-server subprocess started and always stopped by this runner
// (normal end, error, startup failure, timeout, SIGINT/SIGTERM). Every decision goes through
// production decide() with a per-decision deadline and B0 as the fallback, and is appended to the
// results file as it completes, together with its readout diagnostics (harness.cjs).
// Readout contract v4 (backends.cjs). Saved v1 results were made with the old readout and the v1
// state; `--state-version 1` rebuilds exactly that decision set.
//
//   node run.cjs --model <gguf> --label <name> [--state-version 2] [--splits calib] [--limit 10]
//     [--ngl 99] [--threads 4] [--ctx 8192] [--deadline 30000] [--max-minutes 10] [--max-invalid 5]
//   node run.cjs --baselines [--state-version 1|2]
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { spawn, execFile } = require('node:child_process');
const { setTimeout: delay } = require('node:timers/promises');
const { performance } = require('node:perf_hooks');
const { createRunBudget } = require('./run-budget.cjs');
const web = path.resolve(__dirname, '../../../apps/web/server');
const { llamaLogitBackend } = require(path.join(web, 'decision/backends.cjs'));
const { build } = require('./scenarios.cjs');
const { renderCompact, renderFull, renderCompactV2 } = require('./state.cjs');
const { b0, b1 } = require('./baselines.cjs');
const { createHarness } = require('./harness.cjs');

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : d; };
const flag = (n) => process.argv.includes(`--${n}`);
const MODEL = arg('model', null), LABEL = arg('label', MODEL ? path.basename(MODEL, '.gguf') : 'baselines');
const V = Number(arg('state-version', '2')), RENDER = arg('render', 'compact');
const NGL = arg('ngl', '99'), THREADS = arg('threads', '4'), CTX = arg('ctx', '8192');
const SPLITS = arg('splits', 'calib,test').split(','), LIMIT = Number(arg('limit', '0'));
const PORT = Number(arg('port', '18095')), DEADLINE = Number(arg('deadline', '30000'));
const MAX_MIN = Number(arg('max-minutes', '10')), MAX_INVALID = Number(arg('max-invalid', '5'));
// LLAMA_SERVER_BIN: tests point this at a mock server script (.cjs, run with node); default is the real binary.
const BIN = process.env.LLAMA_SERVER_BIN || 'llama-server';
const binCmd = (args) => (BIN.endsWith('.cjs') ? [process.execPath, [BIN, ...args]] : [BIN, args]);
const OUT = process.env.DECISION_RESULTS_DIR || path.join(__dirname, 'results'); // tests redirect this

const rssMB = (pid) => new Promise((resolve) => {
  execFile('ps', ['-o', 'rss=', '-p', String(pid)], { encoding: 'utf8', timeout: 200, killSignal: 'SIGKILL' },
    (error, stdout) => resolve(error ? null : Number(stdout.trim()) / 1024));
});
const render = (x) => (RENDER === 'full' ? renderFull(x.canonical) : V === 2 ? renderCompactV2(x.state) : renderCompact(x.state));

let child = null, interrupted = null, budget = null, stopping = null;
const alive = (p) => p && p.pid != null && p.exitCode == null && p.signalCode == null;
// Workload cutoff and cleanup are separate: TERM now, KILL after 3 s, at most 5 s waiting
// for exit confirmation. Never assume ChildProcess.killed means the process has exited.
function stopWorker() {
  if (stopping) return stopping;
  const target = child;
  if (!alive(target)) return Promise.resolve(true);
  stopping = new Promise((resolve) => {
    let killTimer, finalTimer;
    const finish = (confirmed) => {
      clearTimeout(killTimer); clearTimeout(finalTimer);
      target.removeListener('exit', exited);
      resolve(confirmed);
    };
    const exited = () => finish(true);
    target.once('exit', exited);
    killTimer = setTimeout(() => { if (alive(target)) { try { target.kill('SIGKILL'); } catch {} } }, 3000);
    finalTimer = setTimeout(() => finish(!alive(target)), 5000);
    try { target.kill('SIGTERM'); } catch { finish(!alive(target)); }
  });
  return stopping;
}
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => {
  interrupted = `signal ${sig}`;
  if (budget) budget.cancel(Error(interrupted)); else void stopWorker();
  process.exitCode = 130;
});
// Emergency best effort only; ordinary paths await stopWorker() and record confirmation.
process.on('exit', () => { if (alive(child)) { try { child.kill('SIGKILL'); } catch {} } });

async function startWorker(log) {
  budget.check();
  const out = fs.openSync(log, 'w');
  const t0 = performance.now();
  let spawnError = null;
  try {
    child = spawn(...binCmd(['-m', MODEL, '--port', String(PORT), '-c', CTX, '-np', '1', '-ngl', NGL, '-t', THREADS, '--jinja', '--no-webui']), { stdio: ['ignore', out, out] });
    child.once('error', (error) => { spawnError = error; });
  } finally { fs.closeSync(out); }
  const startupSignal = AbortSignal.timeout(120000);
  for (;;) {
    budget.check();
    if (spawnError) throw spawnError;
    if (child.exitCode != null || child.signalCode != null) throw Error(`worker exited during startup; see ${log}`);
    if (startupSignal.aborted) throw Error('worker did not start within 120 s');
    try {
      const signal = AbortSignal.any([startupSignal, AbortSignal.timeout(1000)]);
      const response = await budget.fetch(`http://127.0.0.1:${PORT}/health`, { signal });
      const ok = response.ok;
      await response.body?.cancel();
      budget.check();
      if (ok) break;
    } catch (error) {
      budget.check();
      if (startupSignal.aborted) throw Error('worker did not start within 120 s');
    }
    await delay(100, undefined, { signal: budget.signal });
  }
  return performance.now() - t0;
}

async function readVersion() {
  budget.check();
  return new Promise((resolve) => {
    // Unlike spawnSync, an async version probe cannot prevent the total-run timer firing.
    execFile(...binCmd(['--version']), { encoding: 'utf8', signal: budget.signal,
      timeout: 2000, killSignal: 'SIGKILL', maxBuffer: 65536 },
    (error, stdout, stderr) => resolve((stderr || stdout || '').trim().split('\n')[0] || null));
  });
}

async function main() {
  for (const [name, value] of [['max-minutes', MAX_MIN], ['deadline', DEADLINE]]) {
    const ms = name === 'max-minutes' ? value * 60000 : value;
    if (!Number.isFinite(ms) || ms <= 0 || ms > 2147483647) throw Error(`invalid ${name}`);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const items = build(undefined, { stateVersion: V }).filter((x) => SPLITS.includes(x.split)).slice(0, LIMIT || undefined);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(OUT, `${stamp}-${LABEL}-${flag('baselines') ? 'baselines' : RENDER}-s${V}${NGL === '0' ? '-cpu' : ''}.jsonl`);
  if (flag('baselines')) {
    for (const x of items) for (const [name, f] of [['B0', b0], ['B1', b1]]) {
      const sel = f(x);
      fs.appendFileSync(file, `${JSON.stringify({ id: x.id, family: x.family, split: x.split, backend: name, schema: x.state.schema, selected: sel, correct: x.acceptable.includes(sel) })}\n`);
    }
    console.log(file); return;
  }
  const log = path.join(os.tmpdir(), `decision-worker-${PORT}.log`);
  const meta = { meta: true, readoutContract: 'equal-bias-v4', schema: `noevia.decision-state/${V}`, backend: `${LABEL}/${RENDER}`, model: MODEL, modelBytes: fs.statSync(MODEL).size,
    ngl: NGL, threads: THREADS, ctx: CTX, deadlineMs: DEADLINE, maxMinutes: MAX_MIN, maxInvalid: MAX_INVALID, cases: items.length,
    host: `${os.cpus()[0].model} · ${Math.round(os.totalmem() / 2 ** 30)} GB`, llamaServer: null, startupLimitMs: 120000, healthRequestLimitMs: 1000, cleanupGraceMs: 3000, cleanupWaitMs: 5000 };
  fs.appendFileSync(file, `${JSON.stringify({ ...meta, phase: 'start', at: new Date().toISOString() })}\n`);
  let stopped = null, peak = 0, done = 0, invalidRun = 0, sampler = null;
  const t0 = performance.now();
  budget = createRunBudget({ maxMs: MAX_MIN * 60000, onCutoff: () => { void stopWorker(); } });
  try {
    if (interrupted) budget.cancel(Error(interrupted));
    meta.llamaServer = await readVersion();
    budget.check();
    meta.coldStartMs = await startWorker(log);
    let sampling = false;
    sampler = setInterval(async () => {
      if (sampling || !alive(child)) return;
      sampling = true;
      try { const v = await rssMB(child.pid); if (v > peak) peak = v; } finally { sampling = false; }
    }, 500);
    const h = createHarness({ backend: llamaLogitBackend({ baseUrl: `http://127.0.0.1:${PORT}`, fetchImpl: budget.fetch }), file });
    for (const x of items) {
      budget.check();
      if (child.exitCode != null) { stopped = 'worker exited'; break; }
      const row = await h.decideOne({ item: x, stateText: render(x), fallback: b0(x), deadlineMs: DEADLINE, label: `${LABEL}/${RENDER}` });
      done++;
      budget.check();
      invalidRun = row.readout === 'invalid' ? invalidRun + 1 : 0;
      if (invalidRun >= MAX_INVALID) { stopped = `${MAX_INVALID} invalid readouts in a row`; break; }
    }
  } catch (e) { stopped = interrupted || (budget.signal.aborted ? budget.signal.reason.message : `error: ${e.message}`); }
  finally {
    if (sampler) clearInterval(sampler);
    budget.dispose();
    const cleanupStart = performance.now();
    const workerStopped = await stopWorker();
    const cleanupMs = performance.now() - cleanupStart;
    if (!workerStopped) { stopped = `${stopped || 'normal end'}; worker exit not confirmed`; process.exitCode = 1; }
    const wall = performance.now() - t0;
    const truncated = fs.existsSync(log) ? (fs.readFileSync(log, 'utf8').match(/truncated = 1/g) || []).length : null;
    fs.appendFileSync(file, `${JSON.stringify({ ...meta, phase: 'end', stopped, decisions: done, wallMs: wall, cutoffMs: budget.cutoffMs(), cleanupMs, workerStopped, peakRssMB: Math.round(peak), promptsTruncated: truncated })}\n`);
    console.log(file, stopped ? `(stopped: ${stopped})` : '');
  }
}
main().catch(async (e) => { console.error(e); budget?.dispose(); await stopWorker(); process.exitCode = 1; });
