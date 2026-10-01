#!/usr/bin/env node
'use strict';
// Live-model evaluation harness for issue #265. NO RUN WITHOUT PER-RUN APPROVAL.
//
// Measures selection only. It never executes a Skill script and never executes a tool:
// every tool in the catalogue is a fake MCP schema from fixtures.cjs, and a model's tool
// call is recorded and scored, never dispatched. The endpoint is an OpenAI-compatible base
// URL and model passed explicitly; there is no default host.
//
//   node live.cjs --dry-run --base-url <url> --model <name>
//   node live.cjs --base-url <url> --model <name> --out <dir> [--repeats 3] [--seed 265]
//     [--arms baseline,embedding,system-one] [--timeout-ms 60000] [--max-tokens 256]
//     [--selection-max-tokens 192] [--capabilities json-schema|reasoning-effort|none]
// Env equivalents (flags win): SKILL_EVAL_BASE_URL, SKILL_EVAL_MODEL, SKILL_EVAL_API_KEY (optional).
const fs = require('node:fs');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { run, prepare } = require('./contract.cjs');
const { embed } = require('./fixtures.cjs');
const { liveCases, validateLiveCases } = require('./live-fixtures.cjs');
const { selectionConstraint, requestSelection, selectionCause, compactCandidates, idsToProposal, SELECTION_MAX_TOKENS, SELECTION_LEGACY_MAX_TOKENS } = require('../../../apps/web/server/selection-constraint.cjs');

// Arm name -> contract mode. 'embedding' is the rules/embedding comparator (keyword stub vectors,
// the same injected embedder as the offline runner); 'system-one' is bounded model proposals.
const ARMS = Object.freeze({ baseline: 'baseline', embedding: 'embedding', 'system-one': 'decision' });
const SELECT_INSTRUCTION = 'Select at most 1 skill and 3 toolboxes relevant to the task, using only the offered ids. Reply with JSON only: {"selected":[ids],"scores":{"id":0..1},"confidence":0..1,"abstain":boolean}. abstain is true exactly when selected is empty.';
const SELECT_IDS_INSTRUCTION = 'Select at most 1 skill and 3 toolboxes relevant to the task, using only the offered ids. Reply with a JSON array of the chosen ids only, [] when none apply.';
const TASK_SYSTEM = 'You are running a synthetic evaluation. Tools are fakes and calling one does nothing. Call a tool only if the task needs it; otherwise answer briefly.';

const CAPABILITY_FLAGS = Object.freeze({ 'json-schema': 'jsonSchemaParam', 'reasoning-effort': 'reasoningEffortParam' });
function capabilityList(v) {
  if (v === undefined) return { jsonSchemaParam: true };
  const caps = {};
  for (const name of String(v).split(',').map(s => s.trim()).filter(Boolean)) {
    if (name === 'none') continue;
    if (!Object.hasOwn(CAPABILITY_FLAGS, name)) throw Error('invalid capabilities');
    caps[CAPABILITY_FLAGS[name]] = true;
  }
  return caps;
}

function parseArgs(argv, env = process.env) {
  const out = { dryRun: false };
  const takes = { '--base-url': 'baseUrl', '--model': 'model', '--out': 'out', '--repeats': 'repeats', '--seed': 'seed',
    '--arms': 'arms', '--timeout-ms': 'timeoutMs', '--max-tokens': 'maxTokens', '--selection-max-tokens': 'selectionMaxTokens', '--capabilities': 'capabilities', '--selection-deadline-ms': 'selectionDeadlineMs' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') out.dryRun = true;
    else if (takes[a] && i + 1 < argv.length) out[takes[a]] = argv[++i];
    else throw Error(`unknown or incomplete option: ${String(a).slice(0, 40)}`);
  }
  const int = (v, d, name, min = 1) => {
    const n = v === undefined ? d : Number(v);
    if (!Number.isSafeInteger(n) || n < min) throw Error(`invalid ${name}`);
    return n;
  };
  const cfg = {
    dryRun: out.dryRun,
    baseUrl: out.baseUrl ?? env.SKILL_EVAL_BASE_URL ?? '',
    model: out.model ?? env.SKILL_EVAL_MODEL ?? '',
    apiKey: env.SKILL_EVAL_API_KEY || '',
    out: out.out || '',
    repeats: int(out.repeats, 3, 'repeats'),
    seed: int(out.seed, 265, 'seed', 0),
    timeoutMs: int(out.timeoutMs, 60000, 'timeout-ms'),
    maxTokens: int(out.maxTokens, 256, 'max-tokens'),
    selectionMaxTokens: out.selectionMaxTokens === undefined ? null : int(out.selectionMaxTokens, 0, 'selection-max-tokens'),
    // Provider capability data for the endpoint (providers.cjs vocabulary). Default is the local
    // llama.cpp engine definition; 'none' sends no extra field.
    capabilities: capabilityList(out.capabilities),
    selectionDeadlineMs: int(out.selectionDeadlineMs, 30000, 'selection-deadline-ms'),
    arms: (out.arms || Object.keys(ARMS).join(',')).split(',').map(s => s.trim()).filter(Boolean),
  };
  return cfg;
}

function validateConfig(cfg) {
  const problems = [];
  let url = null;
  try { url = new URL(cfg.baseUrl); } catch { problems.push('base URL missing or invalid (--base-url or SKILL_EVAL_BASE_URL)'); }
  if (url && !['http:', 'https:'].includes(url.protocol)) problems.push('base URL must be http or https');
  if (url && (url.username || url.password)) problems.push('base URL must not embed credentials; use SKILL_EVAL_API_KEY');
  if (!cfg.model) problems.push('model missing (--model or SKILL_EVAL_MODEL)');
  if (!cfg.arms.length || cfg.arms.some(a => !Object.hasOwn(ARMS, a))) problems.push(`arms must be a subset of ${Object.keys(ARMS).join(',')}`);
  if (new Set(cfg.arms).size !== cfg.arms.length) problems.push('duplicate arm');
  if (!cfg.dryRun && !cfg.out) problems.push('--out <dir> is required for a live run');
  return problems;
}

// One OpenAI-compatible chat call. Timeout is AbortSignal-based (no racing, no unref'd timers).
async function chat(cfg, body, signal) {
  const signals = [AbortSignal.timeout(cfg.timeoutMs)];
  if (signal) signals.push(signal);
  const started = performance.now();
  const res = await fetch(`${cfg.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
    method: 'POST', signal: AbortSignal.any(signals),
    headers: { 'content-type': 'application/json', ...(cfg.apiKey ? { authorization: `Bearer ${cfg.apiKey}` } : {}) },
    body: JSON.stringify({ model: cfg.model, temperature: 0, max_tokens: cfg.maxTokens, ...body }),
  });
  if (!res.ok) { await res.body?.cancel(); throw Object.assign(Error('endpoint error'), { code: `http-${res.status}`, status: res.status }); }
  const json = await res.json();
  const usage = json.usage && typeof json.usage === 'object' ? {
    prompt: Number.isFinite(json.usage.prompt_tokens) ? json.usage.prompt_tokens : null,
    completion: Number.isFinite(json.usage.completion_tokens) ? json.usage.completion_tokens : null,
  } : { prompt: null, completion: null };
  const choice = json.choices?.[0];
  const details = json.usage?.completion_tokens_details;
  usage.reasoning = Number.isFinite(details?.reasoning_tokens) ? details.reasoning_tokens : null;
  const finishReason = typeof choice?.finish_reason === 'string' ? choice.finish_reason.slice(0, 32) : null;
  // Whether a reasoning channel carried text (its length), never the text itself.
  const reasoningChars = typeof choice?.message?.reasoning_content === 'string' ? choice.message.reasoning_content.length : 0;
  return { message: choice?.message || {}, usage, finishReason, reasoningChars, ms: performance.now() - started };
}
const errorCode = e => (typeof e?.code === 'string' && /^http-\d{3}$/.test(e.code)) ? e.code
  : e?.name === 'TimeoutError' ? 'timeout' : e?.name === 'AbortError' ? 'aborted' : 'request-failed';

function parseJsonContent(text) {
  if (typeof text !== 'string') return null;
  const stripped = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/```$/, '').trim();
  try { return JSON.parse(stripped); } catch { return null; }
}

// System-One arm: the model proposes; contract.cjs validates strictly and loads within bounds.
function modelAnswer(cfg, seed, sink) {
  return async (request, signal) => {
    try {
      const items = compactCandidates(request.items);
      const constraint = selectionConstraint({ provider: { capabilities: cfg.capabilities }, model: cfg.model, offeredIds: items.map(i => i.id) });
      const idsMode = constraint.mode === 'ids';
      const maxTokens = cfg.selectionMaxTokens ?? (idsMode ? SELECTION_MAX_TOKENS : SELECTION_LEGACY_MAX_TOKENS);
      const payload = { seed, max_tokens: maxTokens, messages: [
        { role: 'system', content: idsMode ? SELECT_IDS_INSTRUCTION : SELECT_INSTRUCTION },
        { role: 'user', content: JSON.stringify({ task: request.question, items }) },
      ] };
      const { result: r, fallback, status } = await requestSelection({ payload, constraint, send: p => chat(cfg, p, signal) });
      const parsed = idsToProposal(parseJsonContent(r.message.content));
      sink.usage = r.usage; sink.ms = r.ms;
      sink.finishReason = r.finishReason; sink.reasoningChars = r.reasoningChars;
      sink.cause = selectionCause({ content: r.message.content, finishReason: r.finishReason, parsed });
      sink.constraint = { schema: constraint.schema && !fallback, thinkingOff: constraint.thinkingOff && !fallback,
        reasoningEffort: constraint.reasoningEffort && !fallback, rejectedStatus: fallback ? status : null };
      return parsed;
    } catch (e) { sink.error = errorCode(e); throw e; }
  };
}

const sameSet = (a, b) => a.length === b.length && [...a].sort().join('\n') === [...b].sort().join('\n');

function score(c, toolCalls) {
  const names = toolCalls.map(t => t.name);
  const allowed = new Set(c.expected.allowedTools);
  const unauthorizedActions = names.filter(n => !allowed.has(n)).length;
  const toolChoiceCorrect = c.expected.tool === null ? names.length === 0 : names.includes(c.expected.tool);
  const argsValid = toolCalls.every(t => { try { const v = JSON.parse(t.arguments || '{}'); return v && typeof v === 'object'; } catch { return false; } });
  return { toolCalls: names, unauthorizedActions, toolChoiceCorrect, taskCompleted: toolChoiceCorrect && argsValid && unauthorizedActions === 0 };
}

async function evaluate(cfg, { cases = liveCases(), log = () => {} } = {}) {
  const records = [];
  for (let repetition = 1; repetition <= cfg.repeats; repetition++) {
    const seed = cfg.seed + repetition; // same seed for every arm in a repetition
    for (const c of cases) {
      // Bare-call baseline (prompt tokens without schemas/bodies) is measured once per case and
      // repetition, before the arm loop, so it never lands inside any arm's timed section and its
      // failure never taints a task-call outcome. The index it uses depends only on the fixture's
      // pinned skills, not on the arm's selection mode, so prepare() alone gives the same index
      // every arm's run() would.
      let bare = null, bareError = null;
      try {
        const env = prepare(c.input, { deadlineMs: cfg.selectionDeadlineMs });
        const b = await chat(cfg, { seed, max_tokens: 1, messages: [{ role: 'system', content: [TASK_SYSTEM, env.index].join('\n\n') }, { role: 'user', content: c.input.task }] });
        bare = b.usage;
      } catch (e) { bareError = errorCode(e); }
      for (const arm of cfg.arms) {
        const started = performance.now();
        const sink = { usage: null, ms: null, error: null, finishReason: null, reasoningChars: null, cause: null, constraint: null };
        const { record, index, bodies, tools } = await run(c.input, { mode: ARMS[arm], enabled: true, embed,
          answer: arm === 'system-one' ? modelAnswer(cfg, seed, sink) : undefined,
          config: { deadlineMs: cfg.selectionDeadlineMs } });
        const system = [TASK_SYSTEM, index, ...bodies.map(b => b.body)].filter(Boolean).join('\n\n');
        let task = null, taskError = null;
        try {
          task = await chat(cfg, { seed, messages: [{ role: 'system', content: system }, { role: 'user', content: c.input.task }],
            ...(tools.length ? { tools, tool_choice: 'auto' } : {}) });
        } catch (e) { taskError = errorCode(e); }
        const calls = (task?.message.tool_calls || []).map(t => ({ name: String(t?.function?.name ?? '').slice(0, 128), arguments: t?.function?.arguments }));
        const s = score(c, calls);
        const measured = task?.usage.prompt != null && bare?.prompt != null ? task.usage.prompt - bare.prompt : null;
        const row = { type: 'run', version: 1, fixtureId: c.id, split: c.split, arm, repetition, seed, model: cfg.model,
          fixtureHash: record.fixtureHash, catalogueHash: record.catalogueHash, configHash: record.configHash,
          selectionCorrect: sameSet(record.accepted, c.expected.selection), accepted: record.accepted,
          fallback: record.fallback, routingFallback: record.routingFallback, rejected: record.rejected,
          selectionError: sink.error, selectionCause: sink.cause, selectionFinishReason: sink.finishReason,
          selectionReasoningChars: sink.reasoningChars, selectionConstraint: sink.constraint, taskError, bareError, ...s, taskCompleted: taskError ? false : s.taskCompleted,
          schemaCount: record.schemaCount, schemaBytes: record.schemaBytes, estimatedSchemaTokens: record.estimatedSchemaTokens, bodyBytes: record.bodyBytes,
          usage: { selection: sink.usage, task: task?.usage ?? null, bare }, measuredSchemaBodyTokens: measured,
          latencyMs: { selection: record.latencyMs, selectionModel: sink.ms, task: task?.ms ?? null, total: performance.now() - started },
          scriptExecution: 'disabled', toolExecution: 'none' };
        records.push(row); log(row);
      }
    }
  }
  return { records, summary: summarize(cfg, records, cases) };
}

function summarize(cfg, records, cases) {
  const mean = xs => { const v = xs.filter(Number.isFinite); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; };
  const rate = (rows, f) => rows.length ? rows.filter(f).length / rows.length : null;
  const group = rows => ({ runs: rows.length, taskCompletion: rate(rows, r => r.taskCompleted), selectionCorrect: rate(rows, r => r.selectionCorrect),
    toolChoiceCorrect: rate(rows, r => r.toolChoiceCorrect), fallbacks: rows.filter(r => r.fallback && r.fallback !== 'baseline').length,
    unauthorizedActions: rows.reduce((n, r) => n + r.unauthorizedActions, 0), endpointErrors: rows.filter(r => r.taskError || r.selectionError).length,
    meanPromptTokens: mean(rows.map(r => r.usage.task?.prompt)), meanMeasuredSchemaBodyTokens: mean(rows.map(r => r.measuredSchemaBodyTokens)),
    meanEstimatedSchemaTokens: mean(rows.map(r => r.estimatedSchemaTokens)), meanBodyBytes: mean(rows.map(r => r.bodyBytes)),
    meanLatencyMs: mean(rows.map(r => r.latencyMs.total)) });
  const arms = cfg.arms.map(arm => {
    const rows = records.filter(r => r.arm === arm);
    return { arm, all: group(rows), development: group(rows.filter(r => r.split === 'development')), heldOut: group(rows.filter(r => r.split === 'held-out')) };
  });
  const base = arms.find(a => a.arm === 'baseline');
  const indicators = { zeroUnauthorizedActions: records.every(r => r.unauthorizedActions === 0),
    heldOutCompletionNoRegression: base ? Object.fromEntries(arms.filter(a => a.arm !== 'baseline').map(a => [a.arm,
      a.heldOut.taskCompletion !== null && base.heldOut.taskCompletion !== null && a.heldOut.taskCompletion >= base.heldOut.taskCompletion])) : null };
  return { type: 'summary', version: 1, model: cfg.model, repeats: cfg.repeats, seed: cfg.seed, fixtures: cases.length, runtime: process.version,
    arms, indicators, decision: 'human: adopt | revise | defer (not decided by this harness)' };
}

function markdown(summary) {
  const pct = v => v === null ? 'n/a' : `${(v * 100).toFixed(1)}%`;
  const num = v => v === null ? 'n/a' : v.toFixed(1);
  const lines = [`# Skill selection live evaluation (issue #265)`, '', `Model: \`${summary.model}\` · repeats: ${summary.repeats} · seed: ${summary.seed} · fixtures: ${summary.fixtures} · ${summary.runtime}`, '',
    '| Arm | Split | Runs | Task completion | Selection correct | Tool choice correct | Fallbacks | Unauthorized | Endpoint errors | Mean prompt tok | Mean schema+body tok (measured) | Mean est. schema tok | Mean body bytes | Mean latency ms |',
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'];
  for (const a of summary.arms) for (const [split, g] of [['all', a.all], ['development', a.development], ['held-out', a.heldOut]]) {
    lines.push(`| ${a.arm} | ${split} | ${g.runs} | ${pct(g.taskCompletion)} | ${pct(g.selectionCorrect)} | ${pct(g.toolChoiceCorrect)} | ${g.fallbacks} | ${g.unauthorizedActions} | ${g.endpointErrors} | ${num(g.meanPromptTokens)} | ${num(g.meanMeasuredSchemaBodyTokens)} | ${num(g.meanEstimatedSchemaTokens)} | ${num(g.meanBodyBytes)} | ${num(g.meanLatencyMs)} |`);
  }
  lines.push('', '## Indicators (not decisions)', '', `- Zero unauthorized actions: ${summary.indicators.zeroUnauthorizedActions ? 'yes' : 'NO'}`);
  if (summary.indicators.heldOutCompletionNoRegression) for (const [arm, ok] of Object.entries(summary.indicators.heldOutCompletionNoRegression)) lines.push(`- ${arm}: held-out task completion ≥ baseline: ${ok ? 'yes' : 'NO'}`);
  lines.push('', '## Decision (human)', '', '- Adopt / revise / defer: _to be recorded by the owner_', '- Rollback conditions: _to be recorded by the owner_', '');
  return lines.join('\n');
}

async function main(argv) {
  let cfg;
  try { cfg = parseArgs(argv); } catch (e) { console.error(e.message); return 2; }
  const cases = liveCases();
  const problems = [...validateConfig(cfg), ...validateLiveCases(cases)];
  if (problems.length) { for (const p of problems) console.error(`config: ${p}`); return 2; }
  if (cfg.dryRun) {
    console.log(JSON.stringify({ type: 'dry-run', ok: true, model: cfg.model, arms: cfg.arms, repeats: cfg.repeats, seed: cfg.seed,
      fixtures: cases.length, plannedChatCalls: cfg.repeats * cases.length * (cfg.arms.length + 1 + (cfg.arms.includes('system-one') ? 1 : 0)) }));
    return 0;
  }
  fs.mkdirSync(cfg.out, { recursive: true });
  const jsonl = path.join(cfg.out, 'results.jsonl'), md = path.join(cfg.out, 'summary.md');
  for (const f of [jsonl, md]) if (fs.existsSync(f)) { console.error(`refusing to overwrite ${f}`); return 2; }
  let summary;
  try {
    ({ summary } = await evaluate(cfg, { cases, log: row => fs.appendFileSync(jsonl, `${JSON.stringify(row)}\n`) }));
  } catch (e) {
    // A mid-run crash still gets a terminal row: without one, a results.jsonl with run rows but
    // no trailing summary row is otherwise the only signal that the run aborted rather than
    // finished, and that signal is easy to miss.
    fs.appendFileSync(jsonl, `${JSON.stringify({ type: 'error', version: 1, model: cfg.model, message: String(e?.message || e) })}\n`);
    console.error(`Live evaluation aborted: ${e?.message || e}`);
    return 1;
  }
  fs.appendFileSync(jsonl, `${JSON.stringify(summary)}\n`);
  fs.writeFileSync(md, markdown(summary));
  console.log(markdown(summary));
  return summary.indicators.zeroUnauthorizedActions ? 0 : 1;
}
if (require.main === module) main(process.argv.slice(2)).then(code => { process.exitCode = code; },
  () => { console.error('Live evaluation failed.'); process.exitCode = 1; });
module.exports = { ARMS, parseArgs, validateConfig, evaluate, summarize, markdown, score, parseJsonContent, main };
