'use strict';
// Offline experiment only. No registration, network client, process runner or production caller.
const { createHash } = require('node:crypto');
const skills = require('../../../apps/web/server/instruction-skills.cjs');
const { formatSkillIndex } = require('../../../apps/web/server/skill-index.cjs');
const { skillBlock, createChatSkillRouter } = require('../../../apps/web/server/chat-skill-routing.cjs');
const { createChatToolRouter } = require('../../../apps/web/server/chat-tool-routing.cjs');
const { createToolboxes } = require('../../../apps/web/server/toolboxes.cjs');
const { createDecisions } = require('../../../apps/web/server/decision/index.cjs');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const skillId = (project, file) => `skill:${hash([project.owner, project.id, file]).slice(0, 24)}`;
const boxId = id => `box:${hash(id).slice(0, 24)}`;
const toolId = name => `tool:${hash(name).slice(0, 24)}`;
const DEFAULTS = Object.freeze({ maxSkills: 1, maxBoxes: 3, bodyBytes: 12000, minConfidence: 0.6, minScore: 0.5, deadlineMs: 50, model: 'fixture-9b' });
const ids = tools => tools.map(t => t.function.name);

// This envelope is fixture state, not a second registry. Project files are inspected by
// the real reviewed-skill parser; boxes have the real discovery/resolver shape. Readiness
// is a frozen result of discovery/account checks, never a URL or credential.
function prepare(input, config = {}) {
  const state = structuredClone(input);
  const cfg = { ...DEFAULTS, ...config };
  for (const key of ['maxSkills', 'maxBoxes', 'bodyBytes', 'deadlineMs']) {
    if (!Number.isSafeInteger(cfg[key]) || cfg[key] < 1) throw Error('invalid experiment limit');
  }
  for (const key of ['minConfidence', 'minScore']) if (!Number.isFinite(cfg[key]) || cfg[key] < 0 || cfg[key] > 1) throw Error('invalid experiment threshold');
  if (state.project.owner !== state.userId || state.current.owner !== state.userId || state.project.id !== state.current.id) throw Error('invalid fixture scope');
  if (new Set(state.boxes.map(b => b.id)).size !== state.boxes.length) throw Error('duplicate catalogue ID');
  const current = skills.enabled(state.current);
  const pinned = skills.enabled(state.project).filter(s => current.some(c => c.file === s.file && c.hash === s.hash));
  const ceiling = state.project.toolboxes.filter(id => state.current.toolboxes.includes(id));
  const available = state.boxes.filter(b => ceiling.includes(b.id) && b.ready === true && b.accountReady === true && b.revision === state.revision);
  const byBox = new Map(available.map(b => [b.id, b]));
  function closure(id, seen = new Set()) {
    const b = byBox.get(id);
    if (!b) return null;
    if (seen.has(id)) return seen;
    seen.add(id);
    for (const dep of b.requires || []) if (!closure(dep, seen)) return null;
    return seen;
  }
  const permitted = ceiling.filter(id => closure(id));
  const api = createToolboxes({ mcpBoxes: () => available, offered: id => permitted.includes(id),
    prefill: { budgetFor: () => null, rateFor: () => 0 } });
  const blocked = name => state.blocked.includes(name);
  const resolve = selected => api.resolveTools({ toolboxes: selected }, cfg.model, blocked);
  const baseline = resolve(permitted);
  const skillRows = pinned.filter(s => s.requires.every(id => permitted.includes(id))).map(s => ({
    id: skillId(state.project, s.file), skill: s,
    description: `${s.name}: ${s.description}`.slice(0, 1000),
  }));
  const boxRows = available.filter(b => permitted.includes(b.id)).map(b => ({ id: boxId(b.id), box: b,
    description: `${b.label}: ${b.description}`.slice(0, 1000) }));
  const rows = [...skillRows, ...boxRows];
  return { state, cfg, pinned, permitted, rows, closure, resolve, baseline,
    index: formatSkillIndex(pinned),
    catalogueHash: hash(rows.map(r => r.skill ? [r.id, r.skill.hash, r.skill.requires] : [r.id, r.box])),
    configHash: hash([cfg, state.userId, ceiling, state.blocked, state.revision]),
  };
}

// rank is the shared primitive. This experiment adds completeness, confidence,
// bounded cardinality and strict-key checks that the generic rank API does not promise.
function validateProposal(value, rows, cfg) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'malformed';
  if (Object.keys(value).some(k => !['selected', 'scores', 'confidence', 'abstain'].includes(k))) return 'unexpected-field';
  if (!Array.isArray(value.selected) || value.selected.length > cfg.maxSkills + cfg.maxBoxes) return 'cardinality';
  if (typeof value.abstain !== 'boolean' || (value.abstain !== (value.selected.length === 0))) return 'abstention';
  const offered = new Set(rows.map(r => r.id));
  if (value.selected.some(id => typeof id !== 'string' || !offered.has(id))) return 'unknown-id';
  if (new Set(value.selected).size !== value.selected.length) return 'duplicate-id';
  if (!value.scores || typeof value.scores !== 'object' || Array.isArray(value.scores)) return 'scores';
  if (Object.keys(value.scores).length !== value.selected.length || value.selected.some(id => !Object.hasOwn(value.scores, id)) ||
      Object.entries(value.scores).some(([id, score]) => !value.selected.includes(id) || !Number.isFinite(score) || score < 0 || score > 1)) return 'scores';
  if (!Number.isFinite(value.confidence) || value.confidence < 0 || value.confidence > 1) return 'confidence';
  if (value.confidence < cfg.minConfidence) return 'low-confidence';
  if (value.abstain) return 'abstained';
  if (value.selected.some(id => value.scores[id] < cfg.minScore)) return 'low-score';
  if (value.selected.filter(id => id.startsWith('skill:')).length > cfg.maxSkills || value.selected.filter(id => id.startsWith('box:')).length > cfg.maxBoxes) return 'cardinality';
  return null;
}

// Log only offered opaque IDs. Unknown strings and extra keys can themselves contain
// prompts/secrets; never echo them, error messages, backend metadata, or raw answers.
function safeProposed(value, rows) {
  const allowed = new Set(rows.map(r => r.id));
  return Array.isArray(value?.selected) ? value.selected.slice(0, 64).filter(id => allowed.has(id)) : [];
}

async function selectDecision(env, answer, signal) {
  let proposed = [], failure = null;
  const backend = { locality: env.state.remote ? 'remote' : 'local', supports: () => true,
    async decide(request, { signal: deadlineSignal }) {
      if (signal?.aborted) { failure = 'cancelled'; throw Error('cancelled'); }
      let listener;
      const cancelled = new Promise((_, reject) => {
        listener = () => { failure = 'cancelled'; reject(Error('cancelled')); };
        signal?.addEventListener('abort', listener, { once: true });
        deadlineSignal.addEventListener('abort', listener, { once: true });
      });
      try {
        const value = await Promise.race([Promise.resolve().then(() => answer(request, deadlineSignal)), cancelled]);
        proposed = safeProposed(value, env.rows);
        failure = validateProposal(value, env.rows, env.cfg);
        if (failure) throw Error('invalid proposal');
        return value;
      } catch (error) { failure ||= deadlineSignal.aborted ? 'timeout' : 'backend-error'; throw error; }
      finally { signal?.removeEventListener('abort', listener); deadlineSignal.removeEventListener('abort', listener); }
    } };
  const decisions = createDecisions({ backends: { scripted: backend }, chains: { 'skills-mcp.offline': ['scripted'] },
    log: entry => { if (entry.failed === 'deadline') failure = 'timeout'; } });
  if (signal?.aborted) return { proposed, failure: 'cancelled', selected: [] };
  if (!env.rows.length) return { proposed, failure: 'empty-catalogue', selected: [] };
  const result = await decisions.rank({ purpose: 'skills-mcp.offline', question: String(env.state.task || '').slice(0, 2000), items: env.rows.map(r => ({ id: r.id, label: r.description })),
    context: { cloud: 'forbidden' }, constraints: { deadlineMs: env.cfg.deadlineMs },
    fallback: { selected: [], scores: {}, confidence: 0 } });
  if (result.source === 'fallback') failure ||= env.state.remote ? 'remote-disallowed' : 'backend-error';
  if (signal?.aborted) failure = 'cancelled';
  return { proposed, failure, selected: failure ? [] : result.selected };
}

function load(env, selected, failure) {
  const byId = new Map(env.rows.map(r => [r.id, r]));
  const accepted = [], rejected = [];
  let chosen = [], bodies = [], bytes = 0;
  if (!failure) {
    // Tools first so a skill's requirements must actually survive schema budgeting.
    for (const id of selected.filter(id => byId.get(id)?.box)) {
      const group = [...env.closure(byId.get(id).box.id)];
      const next = [...new Set([...chosen, ...group])];
      const result = env.resolve(next);
      const expected = next.flatMap(b => env.state.boxes.find(x => x.id === b).tools.map(t => t.function.name));
      const actual = ids(result.tools);
      if (new Set(expected).size !== expected.length) { rejected.push({ id, reason: 'tool-collision' }); continue; }
      if (expected.some(name => env.state.blocked.includes(name))) { rejected.push({ id, reason: 'account-blocked' }); continue; }
      if (expected.some(name => !actual.includes(name))) { rejected.push({ id, reason: 'tool-budget' }); continue; }
      chosen = next; accepted.push(id);
    }
    for (const id of selected.filter(id => byId.get(id)?.skill)) {
      const s = byId.get(id).skill;
      if (!s.requires.every(dep => chosen.includes(dep))) { rejected.push({ id, reason: 'missing-requirement' }); continue; }
      const body = skillBlock([s]);
      // Reject oversize bodies instead of counting a truncation as a full skill load.
      if (bytes + Buffer.byteLength(body) > env.cfg.bodyBytes) { rejected.push({ id, reason: 'body-budget' }); continue; }
      const read = skills.read(env.state.project, env.state.project.files.find(f => f.name === s.file), env.state.current, 0, 40000);
      if (!read.startsWith('Loaded instruction skill ')) { rejected.push({ id, reason: 'stale-skill' }); continue; }
      accepted.push(id); bodies.push({ id, body }); bytes += Buffer.byteLength(body);
    }
  }
  // A valid but wholly unusable proposal is a routing failure, not an empty tool ceiling.
  const fallback = failure || (selected.length && !accepted.length ? 'nothing-loadable' : null);
  const resolved = fallback ? env.baseline : env.resolve(chosen);
  return { accepted: fallback ? [] : accepted, rejected, fallback, bodies: fallback ? [] : bodies,
    resolved, bodyBytes: fallback ? 0 : bytes };
}

async function run(input, { mode = 'baseline', enabled = false, answer, embed, signal, config = {} } = {}) {
  if (!['baseline', 'embedding', 'decision'].includes(mode)) throw Error('invalid mode');
  const started = performance.now();
  const env = prepare(input, config);
  let selection = { proposed: [], selected: [], failure: 'baseline' };
  if (mode !== 'baseline' && !enabled) selection.failure = 'off';
  else if (mode === 'decision') {
    if (typeof answer !== 'function') selection.failure = 'unavailable';
    else selection = await selectDecision(env, answer, signal);
  } else if (mode === 'embedding') {
    if (typeof embed !== 'function') selection.failure = 'unavailable';
    else {
      const skillRouter = createChatSkillRouter({ enabled: () => true, embed });
      const toolRouter = createChatToolRouter({ enabled: () => true, embed, boxes: () => env.rows.filter(r => r.box).map(r => r.box), timeoutMs: env.cfg.deadlineMs });
      // The production skill router has no deadline; this offline wrapper bounds the
      // comparator without changing that production behavior or claiming it is fixed.
      let timer, listener;
      try {
        const interrupted = new Promise((_, reject) => {
          timer = setTimeout(() => reject(Error('timeout')), env.cfg.deadlineMs);
          listener = () => reject(Error('cancelled'));
          signal?.addEventListener('abort', listener, { once: true });
          if (signal?.aborted) listener();
        });
        const [s, t] = await Promise.race([Promise.all([skillRouter.select(env.rows.filter(r => r.skill).map(r => r.skill), input.task), toolRouter.select(env.permitted, input.task)]), interrupted]);
        selection = { proposed: [...s.loaded.map(s => skillId(env.state.project, s.file)), ...t.ids.map(boxId)],
          selected: [...s.loaded.map(s => skillId(env.state.project, s.file)), ...t.ids.map(boxId)], failure: null,
          routingFallback: { skills: s.loaded.length ? null : 'no-skill-match', tools: t.routed ? null : 'full-selection' } };
      } catch (error) { selection.failure = error.message === 'cancelled' ? 'cancelled' : 'timeout'; }
      finally { clearTimeout(timer); signal?.removeEventListener('abort', listener); }
    }
  }
  const result = load(env, selection.selected, selection.failure);
  const loaded = { skills: result.bodies.map(b => b.id), tools: ids(result.resolved.tools).map(toolId) };
  const record = { version: 1, fixtureHash: hash(input), catalogueHash: env.catalogueHash, configHash: env.configHash,
    mode, eligible: env.rows.map(r => r.id), proposed: selection.proposed, accepted: result.accepted,
    loaded, fallback: result.fallback, routingFallback: selection.routingFallback || { skills: result.fallback, tools: result.fallback }, rejected: result.rejected,
    indexBytes: Buffer.byteLength(env.index), bodyBytes: result.bodyBytes,
    schemaBytes: Buffer.byteLength(JSON.stringify(result.resolved.tools)), estimatedSchemaTokens: result.resolved.estTokens,
    schemaCount: result.resolved.tools.length, latencyMs: performance.now() - started,
    measuredTokens: null, instructionAdherence: null, taskCompletion: null, modelQuality: 'unmeasured' };
  return { record, index: env.index, bodies: result.bodies, tools: result.resolved.tools };
}
module.exports = { run, prepare, load, validateProposal, hash, skillId, boxId, toolId, DEFAULTS };
