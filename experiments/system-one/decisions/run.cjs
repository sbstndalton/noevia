#!/usr/bin/env node
'use strict';
// Pilot runner for generic System-One backends (docs/research/system-one/13 §13.9).
// Offline, synthetic, local assets only. Each model backend runs as an ISOLATED worker: a
// llama-server subprocess this runner starts (bounded threads, context and slots) and stops.
// Decisions go through the production decide() layer (deadline, cancellation, validation) with
// the current deterministic behaviour (B0) as the fallback.
//
//   node experiments/system-one/decisions/run.cjs --model ~/noevia-models/gemma-4-E2B_q4_0-it.gguf \
//     [--label gemma-4-E2B] [--render compact|full] [--ngl 99] [--threads 4] [--splits calib,test] [--limit N]
//   node experiments/system-one/decisions/run.cjs --baselines        (B0/B1 only, no model)
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { spawn, execFileSync, spawnSync } = require('node:child_process');
const web = path.resolve(__dirname, '../../../apps/web/server');
const { createDecisions } = require(path.join(web, 'decision/index.cjs'));
const { llamaLogitBackend } = require(path.join(web, 'decision/backends.cjs'));
const { build } = require('./scenarios.cjs');
const { renderCompact, renderFull } = require('./state.cjs');
const { b0, b1 } = require('./baselines.cjs');

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : d; };
const flag = (n) => process.argv.includes(`--${n}`);
const MODEL = arg('model', null), LABEL = arg('label', MODEL ? path.basename(MODEL, '.gguf') : 'baselines');
const RENDER = arg('render', 'compact'), NGL = arg('ngl', '99'), THREADS = arg('threads', '4');
const SPLITS = arg('splits', 'calib,test').split(','), LIMIT = Number(arg('limit', '0'));
const PORT = Number(arg('port', '18095')), DEADLINE = Number(arg('deadline', '30000'));
const OUT = path.join(__dirname, 'results');

const rssMB = (pid) => { try { return Number(execFileSync('ps', ['-o', 'rss=', '-p', String(pid)]).toString().trim()) / 1024; } catch { return null; } };

async function startWorker() {
  const log = path.join(os.tmpdir(), `decision-worker-${PORT}.log`);
  const out = fs.openSync(log, 'w');
  const t0 = Date.now();
  const child = spawn('llama-server', ['-m', MODEL, '--port', String(PORT), '-c', '8192', '-np', '1', '-ngl', NGL, '-t', THREADS, '--jinja', '--no-webui'], { stdio: ['ignore', out, out] });
  for (;;) {
    if (child.exitCode != null) throw Error(`worker exited; see ${log}`);
    try { if ((await fetch(`http://127.0.0.1:${PORT}/health`)).ok) break; } catch {}
    if (Date.now() - t0 > 180000) throw Error('worker did not start');
    await new Promise((r) => setTimeout(r, 250));
  }
  const coldMs = Date.now() - t0;
  return { child, coldMs, log };
}

function option(state) { return state.actions.map((a) => ({ id: a.id, label: a.text })); }

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const items = build().filter((x) => SPLITS.includes(x.split)).slice(0, LIMIT || undefined);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const rows = [];
  if (flag('baselines')) {
    for (const x of items) for (const [name, f] of [['B0', b0], ['B1', b1]]) {
      const sel = f(x);
      rows.push({ id: x.id, family: x.family, split: x.split, backend: name, selected: sel, correct: x.acceptable.includes(sel), probs: null });
    }
  } else {
    const w = await startWorker();
    let peak = rssMB(w.child.pid) || 0;
    const sampler = setInterval(() => { const v = rssMB(w.child.pid); if (v > peak) peak = v; }, 500);
    const decisions = createDecisions({ backends: { 'llama-logit': llamaLogitBackend({ baseUrl: `http://127.0.0.1:${PORT}` }) }, chains: { 'system1.eval': ['llama-logit'] } });
    const t0 = Date.now();
    let i = 0;
    try {
      for (const x of items) {
        const stateText = RENDER === 'full' ? renderFull(x.canonical) : renderCompact(x.state);
        const started = Date.now();
        const r = await decisions.decide({ kind: 'choice', purpose: 'system1.eval', question: x.question, options: option(x.state), context: { stateText },
          fallback: { selected: b0(x), scores: {}, confidence: null }, constraints: { deadlineMs: DEADLINE } });
        rows.push({ id: x.id, family: x.family, split: x.split, backend: `${LABEL}/${RENDER}`, selected: r.selected, correct: x.acceptable.includes(r.selected),
          source: r.source, probs: r.metadata?.probs || null, acceptable: x.acceptable, ms: Date.now() - started,
          promptTokens: r.metadata?.promptTokens ?? null, promptMs: r.metadata?.promptMs ?? null, lettersSeen: r.metadata?.lettersSeen ?? null });
        if (++i % 25 === 0) process.stderr.write(`${i}/${items.length}\n`);
      }
    } finally { clearInterval(sampler); w.child.kill('SIGTERM'); }
    const wall = Date.now() - t0;
    rows.push({ meta: true, backend: `${LABEL}/${RENDER}`, model: MODEL, modelBytes: fs.statSync(MODEL).size, ngl: NGL, threads: THREADS,
      coldStartMs: w.coldMs, peakRssMB: Math.round(peak), promptsTruncated: (fs.readFileSync(w.log, 'utf8').match(/truncated = 1/g) || []).length, decisions: items.length, wallMs: wall, decisionsPerSec: items.length / (wall / 1000),
      host: `${os.cpus()[0].model} · ${Math.round(os.totalmem() / 2 ** 30)} GB`, llamaServer: (spawnSync('llama-server', ['--version'], { encoding: 'utf8' }).stderr || '').trim().split('\n')[0] });
  }
  const file = path.join(OUT, `${stamp}-${LABEL}-${flag('baselines') ? 'baselines' : RENDER}${NGL === '0' ? '-cpu' : ''}.jsonl`);
  fs.writeFileSync(file, rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
  console.log(file);
}
main().catch((e) => { console.error(e); process.exit(1); });
