#!/usr/bin/env node
'use strict';
// Live #518 study against the llama.cpp ROUTER, using the shipped role engine (role-engine.cjs, PR #712).
// NO RUN WITHOUT PER-RUN OWNER APPROVAL (--i-have-approval). One block per invocation, sequential
// requests only, no slot erase/save/restore, never touches models.ini or server config. Writes only
// under --out. Never logs prompt or model text: only token counts, timings and counters.
//
// Blocks:
//   probe       /metrics and /slots reachability through the router, one B call
//   ab          layout A (persona first) vs B (role-engine: shared frame + dossier, then persona),
//               N tasks x Planner -> Executor -> Reviewer -> Auditor, via createRoleEngine (json_schema)
//   interrupt   Planner prefix, Executor-sized interruption from another task, Planner again
//               (re-prefill cost; slot save/restore is not enabled on this router)
//   interleave  Planner -> Executor with and without a chat request in between
//   halt        Laya halt: forced schema violation; /metrics before/after the client abort
//   report      summarise all *.jsonl in --out into summary.md / summary.json (no network)
//
//   node live-518.cjs --i-have-approval --block ab --base-url http://cowork-llama-1:8080 --model <id> --out <dir> [--tasks 10]
const fs = require('node:fs');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { mean, median, percentile } = require('./study.cjs');
const F = require('./fixtures-518.cjs');

const args = Object.fromEntries((() => {
  const a = process.argv.slice(2), out = [];
  for (let i = 0; i < a.length; i++) if (a[i] === '--i-have-approval') out.push(['approved', true]); else out.push([a[i].replace(/^--/, ''), a[++i]]);
  return out;
})());
const BLOCK = args.block, OUT = args.out, BASE = String(args['base-url'] || '').replace(/\/+$/, ''), MODEL = args.model;
const NTASKS = Math.min(F.TASKS.length, Math.max(1, Number(args.tasks || F.TASKS.length)));
if (!OUT || !BLOCK) { console.error('need --block and --out'); process.exit(2); }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const r1 = (v) => (v == null || !Number.isFinite(v) ? null : Math.round(v * 10) / 10);

if (BLOCK !== 'report') {
  if (!args.approved) { console.error('refusing: real model run needs --i-have-approval (owner-approved run)'); process.exit(2); }
  if (!BASE || !MODEL) { console.error('need --base-url and --model'); process.exit(2); }
}
const SERVER = process.env.ROLE_ENGINE_DIR || '/src/apps/web/server';
const RE = BLOCK === 'report' ? null : require(path.join(SERVER, 'role-engine.cjs'));
const RC = BLOCK === 'report' ? null : require(path.join(SERVER, 'role-context.cjs'));
const ROLES = [...F.SEQUENCE];

fs.mkdirSync(OUT, { recursive: true });
const jsonl = path.join(OUT, `${BLOCK}.jsonl`);
let studyRequests = 0; // completion requests that reached the engine (for the owner-activity check)
const emit = (row) => fs.appendFileSync(jsonl, JSON.stringify({ t: new Date().toISOString(), block: BLOCK, ...row }) + '\n');

// ---------- engine helpers ----------
async function getText(url) {
  const r = await fetch(url, { signal: AbortSignal.timeout(15000) });
  return { status: r.status, text: await r.text() };
}
async function metrics() {
  for (const u of [`${BASE}/metrics?model=${encodeURIComponent(MODEL)}`, `${BASE}/metrics`]) {
    try {
      const r = await getText(u);
      if (r.status !== 200 || !/llamacpp:/.test(r.text)) continue;
      const m = { via: u.includes('?') ? 'router?model' : 'router' };
      for (const line of r.text.split('\n')) { const mm = /^llamacpp:(\w+)\s+([0-9.eE+-]+)\s*$/.exec(line); if (mm) m[mm[1]] = Number(mm[2]); }
      return m;
    } catch { /* next */ }
  }
  return null;
}
async function slots() {
  try {
    const r = await getText(`${BASE}/slots?model=${encodeURIComponent(MODEL)}`);
    if (r.status !== 200) return { status: r.status };
    const j = JSON.parse(r.text);
    return { status: 200, processing: Array.isArray(j) ? j.map((s) => s.is_processing === true) : null };
  } catch { return { status: null }; }
}

function project(role, state) {
  const shared = RC.projectSharedDossier(state, { roles: ROLES });
  const own = RC.projectRoleContext(role, state).projection;
  const persona = {};
  for (const k of Object.keys(own)) if (!Object.hasOwn(shared.dossier, k)) persona[k] = own[k];
  return { dossier: RC.serializeProjection(shared.dossier), fields: RC.serializeProjection(persona) };
}
const messagesB = (role, state, instructions = F.INSTRUCTIONS[role]) => { const p = project(role, state); return RE.buildMessages({ dossier: p.dossier, instructions, fields: p.fields }); };
// Layout A: the same bytes, persona block moved to the very start of the system message.
function toLayoutA(messages) {
  const user = messages[1].content, i = user.indexOf(RE.PERSONA_SEPARATOR);
  if (i < 0) throw Error('persona separator missing');
  return [{ role: 'system', content: `Your role:\n${user.slice(i + RE.PERSONA_SEPARATOR.length)}\n\n---\n${RE.SHARED_FRAME}` }, { role: 'user', content: user.slice(0, i) }];
}
const counting = (inner) => (url, init) => { if (init?.method === 'POST' && /\/chat\/completions$/.test(String(url))) studyRequests += 1; return inner(url, init); };
const fetchB = counting((u, i) => fetch(u, i));
const fetchA = counting((url, init) => {
  if (init?.method === 'POST' && /\/chat\/completions$/.test(String(url))) {
    const b = JSON.parse(init.body); b.messages = toLayoutA(b.messages); init = { ...init, body: JSON.stringify(b) };
  }
  return fetch(url, init);
});

// Raw streaming chat with the role engine's payload shape. Optionally aborts after `abortAfter` content deltas.
async function rawChat(messages, maxTokens, { abortAfter = null } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 300000);
  const started = performance.now();
  studyRequests += 1;
  const res = await fetch(`${BASE}/v1/chat/completions`, { method: 'POST', signal: controller.signal, headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, messages, stream: true, cache_prompt: true, stream_options: { include_usage: true }, temperature: 0, max_tokens: maxTokens, chat_template_kwargs: { enable_thinking: false } }) });
  if (!res.ok) { clearTimeout(timer); await res.body?.cancel(); throw Object.assign(Error('http'), { code: `http-${res.status}` }); }
  const reader = res.body.getReader(), dec = new TextDecoder();
  let buf = '', ttftMs = null, deltas = 0, timings = {}, aborted = false, abortedAtMs = null;
  try {
    outer: for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl).trim(); buf = buf.slice(nl + 1);
        if (!line.startsWith('data:')) continue;
        const d = line.slice(5).trim();
        if (d === '[DONE]') break outer;
        let e; try { e = JSON.parse(d); } catch { continue; }
        if (e.timings) for (const k of ['prompt_n', 'cache_n', 'prompt_ms', 'predicted_n', 'predicted_ms']) if (Number.isFinite(e.timings[k])) timings[k] = e.timings[k];
        if (e.usage && timings.cache_n === undefined && Number.isFinite(e.usage.prompt_tokens_details?.cached_tokens)) timings.cache_n_usage = e.usage.prompt_tokens_details.cached_tokens;
        const c = e.choices?.[0]?.delta?.content;
        if (typeof c === 'string' && c) {
          if (ttftMs === null) ttftMs = performance.now() - started;
          deltas += 1;
          if (abortAfter && deltas >= abortAfter) { aborted = true; abortedAtMs = performance.now() - started; controller.abort(); break outer; }
        }
      }
    }
  } catch (e) { if (!aborted) throw e; }
  finally { clearTimeout(timer); try { await reader.cancel(); } catch { /* closed */ } }
  return { ttftMs: r1(ttftMs), wallMs: r1(performance.now() - started), deltas, aborted, abortedAtMs: r1(abortedAtMs), ...timings };
}

// ---------- blocks ----------
async function probe() {
  const m = await metrics(), s = await slots();
  const st = F.TASKS[0];
  const c = await rawChat(messagesB('planner', st), 16);
  const m2 = await metrics();
  emit({ kind: 'probe', metricsVia: m?.via ?? null, metricsKeys: m ? Object.keys(m).filter((k) => k !== 'via') : null, slotsStatus: s.status, slotsProcessing: s.processing, call: c,
    predictedDelta: m && m2 ? m2.tokens_predicted_total - m.tokens_predicted_total : null });
}

async function ab() {
  const engineFor = (layout) => RE.createRoleEngine({ engine: () => ({ baseUrl: `${BASE}/v1`, model: MODEL, provider: { capabilities: { jsonSchemaParam: true } } }), fetch: layout === 'A' ? fetchA : fetchB });
  const engines = { A: engineFor('A'), B: engineFor('B') };
  for (let t = 0; t < NTASKS; t++) {
    const state = F.TASKS[t];
    for (const layout of t % 2 ? ['B', 'A'] : ['A', 'B']) {
      const pin = await engines[layout].pinModel({ taskId: state.taskId, model: MODEL, thinking: false, roles: ROLES });
      if (!pin.ok) { emit({ kind: 'pin', task: t, layout, ok: false, code: pin.code }); continue; }
      for (let step = 0; step < ROLES.length; step++) {
        const role = ROLES[step], before = pin.session.timings().length, t0 = performance.now();
        const r = await pin.session.call({ role, state, instructions: F.INSTRUCTIONS[role], schema: F.SCHEMAS[role], constrain: true });
        const attempts = pin.session.timings().slice(before).map((x) => ({ prompt_n: x.prompt_n, cache_n: x.cache_n, prompt_ms: r1(x.prompt_ms), predicted_n: x.predicted_n,
          predicted_ms: r1(x.predicted_ms), first_delta_ms: x.first_delta_ms, wall_ms: x.wall_ms, halted: x.halted, constrained: x.constrained, prefix: x.prefix }));
        emit({ kind: 'call', task: t, layout, step, role, ok: r.ok, code: r.ok ? null : r.code, corrected: r.corrected ?? null, constraint: r.constraint?.mode ?? null, callWallMs: r1(performance.now() - t0), attempts });
      }
    }
  }
}

async function interrupt() {
  for (let t = 0; t < NTASKS; t++) {
    const st = F.TASKS[t], other = F.TASKS[(t + 1) % F.TASKS.length];
    const P = messagesB('planner', st);
    emit({ kind: 'interrupt', task: t, phase: 'planner-warm', ...(await rawChat(P, 8)) });
    emit({ kind: 'interrupt', task: t, phase: 'planner-repeat', ...(await rawChat(P, 8)) });
    emit({ kind: 'interrupt', task: t, phase: 'executor-interruption', ...(await rawChat(messagesB('executor', other), 64)) });
    emit({ kind: 'interrupt', task: t, phase: 'planner-after-interruption', ...(await rawChat(P, 8)) });
  }
}

async function interleave() {
  for (let t = 0; t < NTASKS; t++) {
    const st = F.TASKS[t];
    for (const arm of t % 2 ? ['interleaved', 'control'] : ['control', 'interleaved']) {
      emit({ kind: 'interleave', task: t, arm, phase: 'planner', ...(await rawChat(messagesB('planner', st), 8)) });
      if (arm === 'interleaved') emit({ kind: 'interleave', task: t, arm, phase: 'chat', ...(await rawChat(F.CHAT_MESSAGES, 32)) });
      emit({ kind: 'interleave', task: t, arm, phase: 'executor', ...(await rawChat(messagesB('executor', st), 8)) });
    }
  }
}

async function halt() {
  const watch = async (label, extra, fn) => {
    const m0 = await metrics();
    const out = await fn();
    const tEnd = performance.now();
    await sleep(500); const m1 = await metrics(); const s1 = await slots();
    await sleep(4500); const m2 = await metrics();
    await sleep(15000); const m3 = await metrics(); const s3 = await slots();
    const d = (m, k) => (m0 && m ? m[k] - m0[k] : null);
    emit({ kind: 'halt', label, ...extra, out,
      predicted: { at0_5s: d(m1, 'tokens_predicted_total'), at5s: d(m2, 'tokens_predicted_total'), at20s: d(m3, 'tokens_predicted_total') },
      decode: { at0_5s: d(m1, 'n_decode_total'), at5s: d(m2, 'n_decode_total'), at20s: d(m3, 'n_decode_total') },
      processingAt0_5s: m1?.requests_processing ?? null, slotsAt0_5s: s1.processing ?? s1.status, slotsAt20s: s3.processing ?? s3.status, settleMs: r1(performance.now() - tEnd) });
  };
  const st = F.TASKS[0];
  const V = messagesB('planner', st, F.VIOLATION_INSTRUCTIONS);
  // Control: no abort, 200 tokens, proves the counters move when generation runs.
  await watch('control-no-abort', { maxTokens: 200 }, () => rawChat(V, 200));
  for (let rep = 1; rep <= 3; rep++) await watch('raw-abort', { rep, maxTokens: 1500, abortAfter: 8 }, () => rawChat(V, 1500, { abortAfter: 8 }));
  // The shipped path: createRoleEngine + runGuardedStream (first violation aborts, one bounded correction).
  const eng = RE.createRoleEngine({ engine: () => ({ baseUrl: `${BASE}/v1`, model: MODEL }), fetch: fetchB });
  for (let rep = 1; rep <= 2; rep++) {
    await watch('role-engine-guard', { rep, maxTokens: 1500 }, async () => {
      const pin = await eng.pinModel({ taskId: st.taskId, model: MODEL, thinking: false, roles: ROLES });
      if (!pin.ok) return { pin: pin.code };
      const r = await pin.session.call({ role: 'planner', state: st, instructions: F.VIOLATION_INSTRUCTIONS, schema: F.SCHEMAS.planner, constrain: false, maxTokens: 1500 });
      return { ok: r.ok, code: r.ok ? null : r.code, attempts: pin.session.timings().map((x) => ({ halted: x.halted, deltas: x.deltas, bytes: x.bytes, first_delta_ms: x.first_delta_ms, wall_ms: x.wall_ms, prompt_n: x.prompt_n ?? null, predicted_n: x.predicted_n ?? null })) };
    });
  }
}

// ---------- report ----------
function report() {
  const rows = [];
  for (const f of fs.readdirSync(OUT).filter((x) => x.endsWith('.jsonl'))) for (const l of fs.readFileSync(path.join(OUT, f), 'utf8').split('\n')) if (l.trim()) rows.push(JSON.parse(l));
  const f1 = (v) => (v == null ? 'n/a' : (Math.round(v * 10) / 10).toString());
  const pct = (a, b) => (a == null || b == null || a + b === 0 ? null : (100 * a) / (a + b));
  const S = {}, L = ['# #518 live study summary', ''];
  // A vs B
  const calls = rows.filter((r) => r.kind === 'call');
  if (calls.length) {
    L.push('## Layout A (persona first) vs B (role-engine shared prefix)', '', 'Switch = steps 1-3 (Executor, Reviewer, Auditor after the Planner). First attempt of each call.', '',
      '| Layout | Calls | ok | Corrected | TTFT mean ms | TTFT median | TTFT p95 | prompt_n mean | cache_n mean | cache share | prompt_ms mean |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
    S.ab = {};
    for (const layout of ['A', 'B']) for (const which of ['first (Planner)', 'switches']) {
      const rs = calls.filter((r) => r.layout === layout && (which === 'switches' ? r.step >= 1 : r.step === 0));
      const a = rs.map((r) => r.attempts[0] || {});
      const g = { calls: rs.length, ok: rs.filter((r) => r.ok).length, corrected: rs.filter((r) => r.corrected).length,
        ttftMean: mean(a.map((x) => x.first_delta_ms)), ttftMedian: median(a.map((x) => x.first_delta_ms)), ttftP95: percentile(a.map((x) => x.first_delta_ms), 95),
        promptN: mean(a.map((x) => x.prompt_n)), cacheN: mean(a.map((x) => x.cache_n)), promptMs: mean(a.map((x) => x.prompt_ms)) };
      g.cacheShare = pct(g.cacheN, g.promptN);
      S.ab[`${layout} ${which}`] = g;
      L.push(`| ${layout} ${which} | ${g.calls} | ${g.ok} | ${g.corrected} | ${f1(g.ttftMean)} | ${f1(g.ttftMedian)} | ${f1(g.ttftP95)} | ${f1(g.promptN)} | ${f1(g.cacheN)} | ${f1(g.cacheShare)}% | ${f1(g.promptMs)} |`);
    }
    L.push('', '### Per-role (first attempt) and whole-call wall time', '', '| Layout | Role | TTFT mean ms | prompt_n | cache_n | predicted_n | wall mean ms (call incl. correction) |', '|---|---|---:|---:|---:|---:|---:|');
    S.roles = {};
    for (const layout of ['A', 'B']) for (const role of ROLES) {
      const rs = calls.filter((r) => r.layout === layout && r.role === role), a = rs.map((r) => r.attempts[0] || {});
      const g = { ttft: mean(a.map((x) => x.first_delta_ms)), promptN: mean(a.map((x) => x.prompt_n)), cacheN: mean(a.map((x) => x.cache_n)), predictedN: mean(a.map((x) => x.predicted_n)), wall: mean(rs.map((r) => r.callWallMs)) };
      S.roles[`${layout}/${role}`] = g;
      L.push(`| ${layout} | ${role} | ${f1(g.ttft)} | ${f1(g.promptN)} | ${f1(g.cacheN)} | ${f1(g.predictedN)} | ${f1(g.wall)} |`);
    }
    const task = (layout) => mean([...new Set(calls.map((r) => r.task))].map((t) => calls.filter((r) => r.layout === layout && r.task === t).reduce((s, r) => s + (r.callWallMs || 0), 0)));
    S.taskWall = { A: task('A'), B: task('B') };
    L.push('', `Mean wall time per 4-role task: A ${f1(S.taskWall.A)} ms, B ${f1(S.taskWall.B)} ms.`);
  }
  const ir = rows.filter((r) => r.kind === 'interrupt');
  if (ir.length) {
    L.push('', '## Planner prefix around an Executor-sized interruption (no slot save/restore available)', '', '| Phase | n | TTFT mean ms | prompt_n | cache_n | prompt_ms mean |', '|---|---:|---:|---:|---:|---:|');
    S.interrupt = {};
    for (const ph of ['planner-warm', 'planner-repeat', 'executor-interruption', 'planner-after-interruption']) {
      const rs = ir.filter((r) => r.phase === ph);
      const g = { n: rs.length, ttft: mean(rs.map((r) => r.ttftMs)), promptN: mean(rs.map((r) => r.prompt_n)), cacheN: mean(rs.map((r) => r.cache_n)), promptMs: mean(rs.map((r) => r.prompt_ms)) };
      S.interrupt[ph] = g;
      L.push(`| ${ph} | ${g.n} | ${f1(g.ttft)} | ${f1(g.promptN)} | ${f1(g.cacheN)} | ${f1(g.promptMs)} |`);
    }
  }
  const il = rows.filter((r) => r.kind === 'interleave' && r.phase === 'executor');
  if (il.length) {
    L.push('', '## Chat request interleaved between Planner and Executor (Executor call measured)', '', '| Arm | n | TTFT mean ms | prompt_n | cache_n | prompt_ms mean |', '|---|---:|---:|---:|---:|---:|');
    S.interleave = {};
    for (const arm of ['control', 'interleaved']) {
      const rs = il.filter((r) => r.arm === arm);
      const g = { n: rs.length, ttft: mean(rs.map((r) => r.ttftMs)), promptN: mean(rs.map((r) => r.prompt_n)), cacheN: mean(rs.map((r) => r.cache_n)), promptMs: mean(rs.map((r) => r.prompt_ms)) };
      S.interleave[arm] = g;
      L.push(`| ${arm} | ${g.n} | ${f1(g.ttft)} | ${f1(g.promptN)} | ${f1(g.cacheN)} | ${f1(g.promptMs)} |`);
    }
  }
  const hl = rows.filter((r) => r.kind === 'halt');
  if (hl.length) {
    L.push('', '## Laya halt (tokens_predicted_total / n_decode_total deltas after the request)', '', '| Run | client deltas / attempts | predicted +0.5 s | +5 s | +20 s | decode +0.5 s | +20 s | slot busy +0.5 s |', '|---|---|---:|---:|---:|---:|---:|---|');
    S.halt = hl;
    for (const r of hl) {
      const cl = r.out?.attempts ? r.out.attempts.map((a) => `${a.deltas}${a.halted ? 'h' : ''}`).join('+') + ` (${r.out.code ?? 'ok'})` : `${r.out?.deltas}${r.out?.aborted ? ' aborted' : ''}`;
      L.push(`| ${r.label}${r.rep ? ` #${r.rep}` : ''} | ${cl} | ${r.predicted.at0_5s ?? 'n/a'} | ${r.predicted.at5s ?? 'n/a'} | ${r.predicted.at20s ?? 'n/a'} | ${r.decode.at0_5s ?? 'n/a'} | ${r.decode.at20s ?? 'n/a'} | ${JSON.stringify(r.slotsAt0_5s)} |`);
    }
  }
  fs.writeFileSync(path.join(OUT, 'summary.md'), L.join('\n') + '\n');
  fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(S, null, 2));
  console.log(L.join('\n'));
}

const blocks = { probe, ab, interrupt, interleave, halt };
(async () => {
  if (BLOCK === 'report') return report();
  if (!blocks[BLOCK]) { console.error('unknown block'); process.exit(2); }
  const t0 = Date.now();
  try { await blocks[BLOCK](); } catch (e) { emit({ kind: 'error', code: e?.code || e?.name || 'error', message: String(e?.message || e).slice(0, 200) }); fs.writeFileSync(path.join(OUT, `${BLOCK}.done`), JSON.stringify({ ok: false, studyRequests, ms: Date.now() - t0 })); process.exit(1); }
  fs.writeFileSync(path.join(OUT, `${BLOCK}.done`), JSON.stringify({ ok: true, studyRequests, ms: Date.now() - t0 }));
  console.log(`${BLOCK} done: requests=${studyRequests} ms=${Date.now() - t0}`);
})();
