#!/usr/bin/env node
'use strict';
// Persona-swap KV-cache study for issue #518. NO RUN WITHOUT PER-RUN OWNER APPROVAL.
//
// Compares, against one llama.cpp server slot, how expensive it is to switch persona (Planner, Executor,
// Laya, Auditor) under five arms:
//   cold             persona after the shared prefix, slot erased before every request (full prefill)
//   persona-first    persona placed BEFORE the shared prefix, prompt cache only
//   after-prefix     persona placed AFTER the shared prefix, prompt cache only
//   restore-prefix   after-prefix layout, slot restored from a saved prefix-only state before each request
//   restore-persona  after-prefix layout, slot restored from a per-persona saved state on revisits
// Per request it records client-side time to first token and llama.cpp's timings (cache_n, prompt_n).
//
// It only calls /health, /props, POST /completion and POST /slots/{id}?action=erase|save|restore.
// It never reads or writes models.ini or any server configuration, and writes only under --out.
// Slot save/restore needs the server started with --slot-save-path; without it those arms are
// recorded as unavailable and skipped.
//
//   node study.cjs --dry-run --base-url <url>
//   node study.cjs --i-have-approval --base-url <url> --out <dir> [--smoke] [--repeats 3]
//     [--timeout-ms 120000] [--n-predict 8] [--prefix-paragraphs 40] [--slot-id 0] [--arms a,b]
//     [--run-id <id>]
// Env equivalents (flags win): PERSONA_KV_BASE_URL, PERSONA_KV_API_KEY (optional bearer token).
const fs = require('node:fs');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { PERSONAS, ROLES, TASKS, SEQUENCE, sharedPrefix } = require('./fixtures.cjs');

const ARMS = Object.freeze(['cold', 'persona-first', 'after-prefix', 'restore-prefix', 'restore-persona']);
const SLOT_ARMS = Object.freeze(['restore-prefix', 'restore-persona']);
const LAYOUT = Object.freeze({ cold: 'after-prefix', 'persona-first': 'persona-first', 'after-prefix': 'after-prefix',
  'restore-prefix': 'after-prefix', 'restore-persona': 'after-prefix' });
const LIMITS = Object.freeze({ repeats: 10, timeoutMs: 300000, nPredict: 64, prefixParagraphs: 200, slotId: 63, httpCalls: 5000, consecutiveErrors: 3 });
const SMOKE = Object.freeze({ repeats: 1, steps: 3, prefixParagraphs: 4 });

// ---------- metrics maths (pure) ----------
const finite = xs => xs.filter(x => typeof x === 'number' && Number.isFinite(x));
function mean(xs) { const v = finite(xs); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; }
function percentile(xs, p) { // nearest-rank
  const v = finite(xs).sort((a, b) => a - b);
  if (!v.length) return null;
  return v[Math.min(v.length - 1, Math.max(0, Math.ceil((p / 100) * v.length) - 1))];
}
const median = xs => percentile(xs, 50);
// Share of the prompt that came from the KV cache: cache_n / (cache_n + prompt_n).
function reuseRatio(cacheN, promptN) {
  if (!Number.isFinite(cacheN) || !Number.isFinite(promptN) || cacheN < 0 || promptN < 0 || cacheN + promptN === 0) return null;
  return cacheN / (cacheN + promptN);
}
// Ratio > 1 means `value` is faster than `baseline`.
const speedup = (baseline, value) => (Number.isFinite(baseline) && Number.isFinite(value) && value > 0) ? baseline / value : null;

// Normalise one llama.cpp final stream chunk / response into the fields the study uses.
// cache_n = prompt tokens served from the KV cache; prompt_n = prompt tokens actually evaluated.
function extractTimings(json) {
  const t = json && typeof json.timings === 'object' && json.timings ? json.timings : {};
  const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  return { cacheN: num(t.cache_n), promptN: num(t.prompt_n), promptMs: num(t.prompt_ms), predictedN: num(t.predicted_n), predictedMs: num(t.predicted_ms) };
}

function summarizeGroup(rows) {
  const ok = rows.filter(r => !r.error);
  return { requests: rows.length, errors: rows.length - ok.length,
    ttftMsMean: mean(ok.map(r => r.ttftMs)), ttftMsMedian: median(ok.map(r => r.ttftMs)), ttftMsP95: percentile(ok.map(r => r.ttftMs), 95),
    switchMsMean: mean(ok.map(r => r.switchMs)), promptNMean: mean(ok.map(r => r.promptN)), cacheNMean: mean(ok.map(r => r.cacheN)),
    reuseRatioMean: mean(ok.map(r => r.reuseRatio)), promptMsMean: mean(ok.map(r => r.promptMs)) };
}

// Steps >= 1 are role switches; step 0 of each repetition is the first fill and is reported apart.
function summarize(records, { arms = ARMS, skipped = {} } = {}) {
  const steps = records.filter(r => r.type === 'step');
  const perArm = arms.map(arm => {
    const rows = steps.filter(r => r.arm === arm && r.step >= 1);
    const first = steps.filter(r => r.arm === arm && r.step === 0);
    const byRole = Object.fromEntries(ROLES.map(role => [role, summarizeGroup(rows.filter(r => r.role === role))]));
    return { arm, skipped: skipped[arm] || null, switches: summarizeGroup(rows), revisits: summarizeGroup(rows.filter(r => r.revisit)),
      firstFill: summarizeGroup(first), byRole,
      saveMsMean: mean(records.filter(r => r.type === 'save' && r.arm === arm && !r.error).map(r => r.ms)) };
  });
  const cold = perArm.find(a => a.arm === 'cold');
  for (const a of perArm) {
    a.speedupVsCold = { ttft: speedup(cold?.switches.ttftMsMean, a.switches.ttftMsMean), switch: speedup(cold?.switches.switchMsMean, a.switches.switchMsMean) };
    a.promptTokensSavedVsCold = (cold?.switches.promptNMean != null && a.switches.promptNMean != null) ? cold.switches.promptNMean - a.switches.promptNMean : null;
  }
  return { arms: perArm };
}

// ---------- request matrix (pure) ----------
function buildPrompt(layout, role, task, prefix) {
  const persona = PERSONAS[role];
  if (layout === 'persona-first') return `${persona}\n\n${prefix}\n\n${task}`;
  if (layout === 'after-prefix') return `${prefix}\n\n${persona}\n\n${task}`;
  throw Error(`unknown layout ${layout}`);
}

// The ordered actions each repetition performs for each arm. step -1 rows are per-arm setup.
function buildMatrix(cfg) {
  const sequence = SEQUENCE.slice(0, cfg.steps);
  const rows = [];
  for (let repeat = 1; repeat <= cfg.repeats; repeat++) {
    for (const arm of cfg.arms) {
      const seen = new Set();
      const setup = ['erase'];
      if (SLOT_ARMS.includes(arm)) setup.push('completion:prefix-only', 'save:prefix');
      rows.push({ repeat, arm, step: -1, role: null, layout: LAYOUT[arm], actions: setup });
      sequence.forEach((role, step) => {
        const revisit = seen.has(role);
        const actions = [];
        if (arm === 'cold') actions.push('erase');
        if (arm === 'restore-prefix') actions.push('restore:prefix');
        if (arm === 'restore-persona') actions.push(revisit ? `restore:${role}` : 'restore:prefix');
        actions.push('completion');
        if (arm === 'restore-persona' && !revisit) actions.push(`save:${role}`);
        rows.push({ repeat, arm, step, role, task: step % TASKS.length, layout: LAYOUT[arm], revisit, actions });
        seen.add(role);
      });
    }
  }
  return rows;
}
const countCalls = matrix => matrix.reduce((n, r) => n + r.actions.length, 0);

// ---------- config ----------
function parseArgs(argv, env = process.env) {
  const out = { dryRun: false, approved: false, smoke: false };
  const takes = { '--base-url': 'baseUrl', '--out': 'out', '--repeats': 'repeats', '--timeout-ms': 'timeoutMs', '--n-predict': 'nPredict',
    '--prefix-paragraphs': 'prefixParagraphs', '--slot-id': 'slotId', '--arms': 'arms', '--run-id': 'runId' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') out.dryRun = true;
    else if (a === '--i-have-approval') out.approved = true;
    else if (a === '--smoke') out.smoke = true;
    else if (takes[a] && i + 1 < argv.length) out[takes[a]] = argv[++i];
    else throw Error(`unknown or incomplete option: ${String(a).slice(0, 40)}`);
  }
  const int = (v, d, name, min, max) => {
    const n = v === undefined ? d : Number(v);
    if (!Number.isSafeInteger(n) || n < min || n > max) throw Error(`invalid ${name} (${min}..${max})`);
    return n;
  };
  const smoke = out.smoke;
  return {
    dryRun: out.dryRun, approved: out.approved, smoke,
    baseUrl: out.baseUrl ?? env.PERSONA_KV_BASE_URL ?? '',
    apiKey: env.PERSONA_KV_API_KEY || '',
    out: out.out || '',
    repeats: smoke ? SMOKE.repeats : int(out.repeats, 3, 'repeats', 1, LIMITS.repeats),
    steps: smoke ? SMOKE.steps : SEQUENCE.length,
    timeoutMs: int(out.timeoutMs, 120000, 'timeout-ms', 1, LIMITS.timeoutMs),
    nPredict: int(out.nPredict, 8, 'n-predict', 1, LIMITS.nPredict),
    prefixParagraphs: smoke ? SMOKE.prefixParagraphs : int(out.prefixParagraphs, 40, 'prefix-paragraphs', 1, LIMITS.prefixParagraphs),
    slotId: int(out.slotId, 0, 'slot-id', 0, LIMITS.slotId),
    arms: (out.arms || ARMS.join(',')).split(',').map(s => s.trim()).filter(Boolean),
    runId: out.runId ?? Date.now().toString(36),
  };
}

function validateConfig(cfg) {
  const problems = [];
  let url = null;
  try { url = new URL(cfg.baseUrl); } catch { problems.push('base URL missing or invalid (--base-url or PERSONA_KV_BASE_URL)'); }
  if (url && !['http:', 'https:'].includes(url.protocol)) problems.push('base URL must be http or https');
  if (url && (url.username || url.password)) problems.push('base URL must not embed credentials; use PERSONA_KV_API_KEY');
  if (!cfg.arms.length || cfg.arms.some(a => !ARMS.includes(a))) problems.push(`arms must be a subset of ${ARMS.join(',')}`);
  else if (new Set(cfg.arms).size !== cfg.arms.length) problems.push('duplicate arm');
  else if (!cfg.arms.includes('cold')) problems.push('the cold arm is required (it is the baseline for every comparison)');
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(cfg.runId)) problems.push('run-id must match [A-Za-z0-9_-]{1,32}');
  if (!cfg.dryRun && !cfg.out) problems.push('--out <dir> is required for a run');
  if (!problems.length && countCalls(buildMatrix(cfg)) > LIMITS.httpCalls) problems.push(`planned HTTP calls exceed the cap of ${LIMITS.httpCalls}`);
  return problems;
}

// ---------- HTTP ----------
const errorCode = e => (typeof e?.code === 'string' && /^(http-\d{3}|empty-stream)$/.test(e.code)) ? e.code
  : e?.name === 'TimeoutError' ? 'timeout' : e?.name === 'AbortError' ? 'aborted' : 'request-failed';

function makeClient(cfg) {
  const base = cfg.baseUrl.replace(/\/+$/, '');
  const headers = { 'content-type': 'application/json', ...(cfg.apiKey ? { authorization: `Bearer ${cfg.apiKey}` } : {}) };
  const call = async (method, p, body) => {
    const res = await fetch(base + p, { method, headers, signal: AbortSignal.timeout(cfg.timeoutMs), body: body === undefined ? undefined : JSON.stringify(body) });
    if (!res.ok) { await res.body?.cancel(); throw Object.assign(Error('endpoint error'), { code: `http-${res.status}` }); }
    return res;
  };
  const json = async (method, p, body) => {
    const t0 = performance.now(); const res = await call(method, p, body);
    const j = await res.json().catch(() => ({}));
    return { json: j, ms: performance.now() - t0 };
  };
  return {
    get: p => json('GET', p),
    slot: (action, name) => json('POST', `/slots/${cfg.slotId}?action=${action}`, action === 'erase' ? {} : { filename: name }),
    // Streaming completion. TTFT = time to the first chunk carrying content; timings come from the last chunk.
    async completion(prompt, nPredict = cfg.nPredict) {
      const started = performance.now();
      const res = await call('POST', '/completion', { prompt, n_predict: nPredict, temperature: 0, cache_prompt: true, stream: true, id_slot: cfg.slotId });
      const reader = res.body.getReader(); const dec = new TextDecoder();
      let buf = '', ttftMs = null, last = null;
      const onLine = line => {
        if (!line.startsWith('data:')) return;
        let j; try { j = JSON.parse(line.slice(5).trim()); } catch { return; }
        if (ttftMs === null && typeof j.content === 'string' && j.content.length) ttftMs = performance.now() - started;
        last = j;
      };
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let nl; while ((nl = buf.indexOf('\n')) >= 0) { onLine(buf.slice(0, nl).replace(/\r$/, '')); buf = buf.slice(nl + 1); }
      }
      if (buf) onLine(buf.replace(/\r$/, ''));
      if (!last) throw Object.assign(Error('empty stream'), { code: 'empty-stream' });
      const wallMs = performance.now() - started;
      return { ttftMs: ttftMs ?? wallMs, wallMs, ...extractTimings(last) };
    },
  };
}

const slotFile = (cfg, name) => `noevia-persona-kv-${cfg.runId}-${name}.bin`;
const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// ---------- run ----------
async function evaluate(cfg, { client = makeClient(cfg), log = () => {} } = {}) {
  const prefix = sharedPrefix(cfg.prefixParagraphs);
  const sequence = SEQUENCE.slice(0, cfg.steps);
  const records = [], skipped = {};
  let consecutiveErrors = 0;
  const emit = row => { records.push(row); log(row); return row; };

  const props = await client.get('/props').then(r => r.json).catch(() => null);
  const health = await client.get('/health').then(r => r.json).catch(() => null);
  if (health === null && props === null) throw Object.assign(Error('server unreachable (/health and /props both failed)'), { code: 'unreachable' });
  const server = { health: health?.status ?? null, modelPath: typeof props?.model_path === 'string' ? path.basename(props.model_path) : null,
    totalSlots: num(props?.total_slots), nCtx: num(props?.default_generation_settings?.n_ctx) };
  if (server.totalSlots !== null && cfg.slotId >= server.totalSlots) throw Error(`slot ${cfg.slotId} does not exist (server reports ${server.totalSlots} slots)`);

  const tally = ok => {
    consecutiveErrors = ok ? 0 : consecutiveErrors + 1;
    if (consecutiveErrors >= LIMITS.consecutiveErrors) throw Error(`aborting after ${LIMITS.consecutiveErrors} consecutive request errors`);
  };
  // Runs a slot/setup call, records it, returns the result or null on failure.
  const action = async (base, kind, fn) => {
    try {
      const r = await fn();
      emit({ type: kind, ...base, ms: r.ms, error: null, nTokens: num(r.json?.n_saved ?? r.json?.n_restored) });
      return r; // only completed completions reset the consecutive-error count
    } catch (e) {
      emit({ type: kind, ...base, ms: null, error: errorCode(e) });
      tally(false); return null;
    }
  };

  for (let repeat = 1; repeat <= cfg.repeats; repeat++) {
    for (const arm of cfg.arms) {
      if (skipped[arm]) continue;
      const slotArm = SLOT_ARMS.includes(arm);
      const base = { repeat, arm };
      await action({ ...base, step: -1, what: 'erase' }, 'erase', () => client.slot('erase'));
      const files = new Map(); // state name -> filename saved this repetition
      if (slotArm) {
        const warm = await action({ ...base, step: -1, what: 'prefill-prefix' }, 'setup', async () => { const r = await client.completion(prefix, 1); return { json: {}, ms: r.wallMs }; });
        const saved = warm && await action({ ...base, step: -1, what: 'prefix' }, 'save', () => client.slot('save', slotFile(cfg, 'prefix')));
        if (!saved) { skipped[arm] = 'slot-save-unavailable (start llama.cpp with --slot-save-path)'; continue; }
        files.set('prefix', slotFile(cfg, 'prefix'));
      }
      const seen = new Set();
      for (let step = 0; step < sequence.length; step++) {
        const role = sequence[step], revisit = seen.has(role);
        const taskIdx = step % TASKS.length;
        const rowBase = { repeat, arm, step, role, task: taskIdx, layout: LAYOUT[arm], revisit };
        let actionMs = 0, restored = null, restoreError = null;
        if (arm === 'cold') await action({ ...base, step, what: 'erase' }, 'erase', () => client.slot('erase'));
        if (slotArm) {
          const state = arm === 'restore-persona' && revisit && files.has(role) ? role : 'prefix';
          const r = await action({ ...base, step, what: state }, 'restore', () => client.slot('restore', files.get(state)));
          if (r) { actionMs += r.ms; restored = { state, nRestored: num(r.json?.n_restored) }; } else restoreError = 'restore-failed';
        }
        try {
          const r = await client.completion(buildPrompt(LAYOUT[arm], role, TASKS[taskIdx], prefix));
          emit({ type: 'step', ...rowBase, ttftMs: r.ttftMs, wallMs: r.wallMs, switchMs: r.ttftMs + actionMs, actionMs, promptN: r.promptN, cacheN: r.cacheN,
            promptMs: r.promptMs, predictedN: r.predictedN, reuseRatio: reuseRatio(r.cacheN, r.promptN), restored, error: restoreError });
          tally(true);
        } catch (e) {
          emit({ type: 'step', ...rowBase, ttftMs: null, wallMs: null, switchMs: null, actionMs, promptN: null, cacheN: null, promptMs: null,
            predictedN: null, reuseRatio: null, restored, error: errorCode(e) });
          seen.add(role); tally(false); continue;
        }
        if (arm === 'restore-persona' && !revisit) {
          const name = slotFile(cfg, role);
          const s = await action({ ...base, step, what: role }, 'save', () => client.slot('save', name));
          if (s) files.set(role, name);
        }
        seen.add(role);
      }
    }
  }
  return { server, records, skipped, summary: summarize(records, { arms: cfg.arms, skipped }) };
}

// ---------- reporting ----------
function markdown(result, cfg) {
  const f = (v, d = 1) => v === null || v === undefined ? 'n/a' : v.toFixed(d);
  const pct = v => v === null || v === undefined ? 'n/a' : `${(v * 100).toFixed(1)}%`;
  const lines = ['# Persona-swap KV-cache study (issue #518)', '',
    `Model: \`${result.server.modelPath ?? 'unknown'}\` · slot ${cfg.slotId} · repeats: ${cfg.repeats} · steps/repeat: ${cfg.steps} · prefix paragraphs: ${cfg.prefixParagraphs} · n_predict: ${cfg.nPredict} · run: ${cfg.runId}`, '',
    'Role switches only (step 0 of each repetition, the first fill, is excluded). "Switch ms" = restore time + time to first token.', '',
    '| Arm | Switches | Errors | TTFT mean ms | TTFT median ms | TTFT p95 ms | Switch mean ms | Prompt tok evaluated | Tok from cache | Cache reuse | Speed-up vs cold (TTFT) | Speed-up vs cold (switch) |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'];
  for (const a of result.summary.arms) {
    if (a.skipped) { lines.push(`| ${a.arm} | skipped: ${a.skipped} | | | | | | | | | | |`); continue; }
    const g = a.switches;
    lines.push(`| ${a.arm} | ${g.requests} | ${g.errors} | ${f(g.ttftMsMean)} | ${f(g.ttftMsMedian)} | ${f(g.ttftMsP95)} | ${f(g.switchMsMean)} | ${f(g.promptNMean)} | ${f(g.cacheNMean)} | ${pct(g.reuseRatioMean)} | ${f(a.speedupVsCold.ttft, 2)}x | ${f(a.speedupVsCold.switch, 2)}x |`);
  }
  lines.push('', '## Revisited personas only (role already seen earlier in the same repetition)', '',
    '| Arm | Requests | TTFT mean ms | Switch mean ms | Prompt tok evaluated | Cache reuse |', '|---|---:|---:|---:|---:|---:|');
  for (const a of result.summary.arms) if (!a.skipped) lines.push(`| ${a.arm} | ${a.revisits.requests} | ${f(a.revisits.ttftMsMean)} | ${f(a.revisits.switchMsMean)} | ${f(a.revisits.promptNMean)} | ${pct(a.revisits.reuseRatioMean)} |`);
  lines.push('', '## Decision (human)', '', '- Adopt / revise / defer persona-after-prefix and slot restore: _to be recorded by the owner_',
    `- Slot files left on the server (\`noevia-persona-kv-${cfg.runId}-*.bin\` under --slot-save-path): _owner removes after the run_`, '');
  return lines.join('\n');
}

const publicConfig = cfg => ({ baseUrl: (() => { try { const u = new URL(cfg.baseUrl); return `${u.protocol}//${u.host}`; } catch { return ''; } })(),
  repeats: cfg.repeats, steps: cfg.steps, timeoutMs: cfg.timeoutMs, nPredict: cfg.nPredict, prefixParagraphs: cfg.prefixParagraphs,
  slotId: cfg.slotId, arms: cfg.arms, runId: cfg.runId, smoke: cfg.smoke });

async function main(argv, env = process.env) {
  let cfg;
  try { cfg = parseArgs(argv, env); } catch (e) { console.error(e.message); return 2; }
  const problems = validateConfig(cfg);
  if (problems.length) { for (const p of problems) console.error(`config: ${p}`); return 2; }
  if (cfg.dryRun) {
    const matrix = buildMatrix(cfg);
    console.log(JSON.stringify({ type: 'dry-run', ok: true, config: publicConfig(cfg), plannedHttpCalls: countCalls(matrix) + 2,
      plannedSteps: matrix.filter(r => r.step >= 0).length,
      endpoints: ['GET /health', 'GET /props', 'POST /completion (stream)', `POST /slots/${cfg.slotId}?action=erase|save|restore`], matrix }, null, 2));
    return 0;
  }
  if (!cfg.approved) {
    console.error('refusing to run: this study drives real model inference and needs owner approval for this run. Re-run with --i-have-approval only after the owner has approved the run plan (docs/handoffs/2026-09-28-run-plan-518.md). Use --dry-run to see the plan.');
    return 2;
  }
  fs.mkdirSync(cfg.out, { recursive: true });
  const json = path.join(cfg.out, 'results.json'), md = path.join(cfg.out, 'summary.md');
  for (const f of [json, md]) if (fs.existsSync(f)) { console.error(`refusing to overwrite ${f}`); return 2; }
  const rows = [];
  let result;
  try {
    result = await evaluate(cfg, { log: r => rows.push(r) });
  } catch (e) {
    fs.writeFileSync(json, JSON.stringify({ version: 1, config: publicConfig(cfg), aborted: String(e?.message || e), records: rows }, null, 2));
    console.error(`Study aborted: ${e?.message || e}`);
    return 1;
  }
  fs.writeFileSync(json, JSON.stringify({ version: 1, runtime: process.version, config: publicConfig(cfg), server: result.server, skipped: result.skipped,
    records: result.records, summary: result.summary, decision: 'human: adopt | revise | defer (not decided by this harness)' }, null, 2));
  const text = markdown(result, cfg);
  fs.writeFileSync(md, text);
  console.log(text);
  return 0;
}
if (require.main === module) main(process.argv.slice(2)).then(code => { process.exitCode = code; },
  () => { console.error('Study failed.'); process.exitCode = 1; });
module.exports = { ARMS, SLOT_ARMS, LIMITS, mean, median, percentile, reuseRatio, speedup, extractTimings, summarize, buildPrompt, buildMatrix, countCalls,
  parseArgs, validateConfig, evaluate, markdown, main };
