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
// Readout contract v3 (backends.cjs). Saved v1 results were made with the old readout and the v1
// state; `--state-version 1` rebuilds exactly that decision set.
//
//   node run.cjs --model <gguf> --label <name> [--state-version 2] [--splits calib] [--limit 10]
//     [--ngl 99] [--threads 4] [--ctx 8192] [--deadline 30000] [--max-minutes 10] [--max-invalid 5]
//   node run.cjs --baselines [--state-version 1|2]
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { spawn, execFileSync, spawnSync } = require('node:child_process');
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

const rssMB = (pid) => { try { return Number(execFileSync('ps', ['-o', 'rss=', '-p', String(pid)]).toString().trim()) / 1024; } catch { return null; } };
const render = (x) => (RENDER === 'full' ? renderFull(x.canonical) : V === 2 ? renderCompactV2(x.state) : renderCompact(x.state));

let child = null, interrupted = null;
function stopWorker() { if (child && child.exitCode == null) { try { child.kill('SIGTERM'); } catch {} setTimeout(() => { try { if (child.exitCode == null) child.kill('SIGKILL'); } catch {} }, 3000).unref(); } }
// On a signal: stop the worker now, let the loop record the in-flight decision and the end record,
// and force-exit after 5 s whatever happens.
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => { interrupted = `signal ${sig}`; stopWorker(); process.exitCode = 130; setTimeout(() => process.exit(130), 5000).unref(); });
process.on('exit', stopWorker);

async function startWorker(log) {
  const out = fs.openSync(log, 'w');
  const t0 = Date.now();
  child = spawn(...binCmd(['-m', MODEL, '--port', String(PORT), '-c', CTX, '-np', '1', '-ngl', NGL, '-t', THREADS, '--jinja', '--no-webui']), { stdio: ['ignore', out, out] });
  try {
    for (;;) {
      if (child.exitCode != null) throw Error(`worker exited during startup; see ${log}`);
      try { if ((await fetch(`http://127.0.0.1:${PORT}/health`)).ok) break; } catch {}
      if (Date.now() - t0 > 120000) throw Error('worker did not start within 120 s');
      await new Promise((r) => setTimeout(r, 250));
    }
  } catch (e) { stopWorker(); throw e; }
  return Date.now() - t0;
}

async function main() {
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
  const meta = { meta: true, readoutContract: 'equal-bias-v3', schema: `noevia.decision-state/${V}`, backend: `${LABEL}/${RENDER}`, model: MODEL, modelBytes: fs.statSync(MODEL).size,
    ngl: NGL, threads: THREADS, ctx: CTX, deadlineMs: DEADLINE, maxMinutes: MAX_MIN, maxInvalid: MAX_INVALID, cases: items.length,
    host: `${os.cpus()[0].model} · ${Math.round(os.totalmem() / 2 ** 30)} GB`, llamaServer: (spawnSync(...binCmd(['--version']), { encoding: 'utf8' }).stderr || '').trim().split('\n')[0] };
  fs.appendFileSync(file, `${JSON.stringify({ ...meta, phase: 'start', at: new Date().toISOString() })}\n`);
  let stopped = null, peak = 0, done = 0, invalidRun = 0, sampler = null;
  const t0 = Date.now();
  try {
    meta.coldStartMs = await startWorker(log);
    sampler = setInterval(() => { const v = rssMB(child.pid); if (v > peak) peak = v; }, 500);
    const h = createHarness({ backend: llamaLogitBackend({ baseUrl: `http://127.0.0.1:${PORT}` }), file });
    for (const x of items) {
      if (interrupted) { stopped = interrupted; break; }
      if (Date.now() - t0 > MAX_MIN * 60000) { stopped = `wall-clock limit ${MAX_MIN} min`; break; }
      if (child.exitCode != null) { stopped = 'worker exited'; break; }
      const row = await h.decideOne({ item: x, stateText: render(x), fallback: b0(x), deadlineMs: DEADLINE, label: `${LABEL}/${RENDER}` });
      done++;
      if (interrupted) { stopped = interrupted; break; }
      invalidRun = row.readout === 'invalid' ? invalidRun + 1 : 0;
      if (invalidRun >= MAX_INVALID) { stopped = `${MAX_INVALID} invalid readouts in a row`; break; }
    }
  } catch (e) { stopped = interrupted || `error: ${e.message}`; }
  finally {
    if (sampler) clearInterval(sampler);
    stopWorker();
    const wall = Date.now() - t0;
    const truncated = fs.existsSync(log) ? (fs.readFileSync(log, 'utf8').match(/truncated = 1/g) || []).length : null;
    fs.appendFileSync(file, `${JSON.stringify({ ...meta, phase: 'end', stopped, decisions: done, wallMs: wall, peakRssMB: Math.round(peak), promptsTruncated: truncated })}\n`);
    console.log(file, stopped ? `(stopped: ${stopped})` : '');
  }
}
main().catch((e) => { console.error(e); stopWorker(); process.exitCode = 1; });
