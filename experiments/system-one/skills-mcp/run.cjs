'use strict';
// Opt-in local CLI, with the repository's outbound guard before loading collaborators.
// No endpoint, credential, external fixture or provider option is accepted.
require('../../../apps/web/tests/hermetic-network.cjs');
const { run, hash, toolId } = require('./contract.cjs');
const { cases, embed, pick } = require('./fixtures.cjs');

// Independent oracle: do not reuse the loader's closure, or its regression could
// make both implementation and measurement agree on the same forbidden exposure.
function forbiddenExposure(input, loadedToolIds) {
  const boxes = new Map(input.boxes.map(b => [b.id, b]));
  function permitted(id, visiting = new Set()) {
    const b = boxes.get(id);
    if (!b || !input.project.toolboxes.includes(id) || !input.current.toolboxes.includes(id) ||
        !b.ready || !b.accountReady || b.revision !== input.revision) return false;
    if (visiting.has(id)) return true;
    const next = new Set(visiting).add(id);
    return (b.requires || []).every(dep => permitted(dep, next));
  }
  const allowed = new Set(input.boxes.filter(b => permitted(b.id)).flatMap(b => b.tools
    .filter(t => !input.blocked.includes(t.function.name)).map(t => toolId(t.function.name))));
  return loadedToolIds.filter(id => !allowed.has(id)).length;
}

async function experiment() {
  const fixtures = cases();
  const fixtureSetHash = hash(fixtures);
  const records = [];
  const relevanceCases = new Set(['exact-calendar', 'exact-files', 'exact-wiki', 'no-match', 'overlap']);
  for (const c of fixtures) {
    for (let repetition = 1; repetition <= 3; repetition++) {
      for (const mode of ['baseline', 'embedding', 'decision']) {
        const { record } = await run(c.input, { mode, enabled: true, embed, answer: async () => c.answer });
        const exposureCount = forbiddenExposure(c.input, record.loaded.tools);
        // Only the simple labelled relevance fixtures have a selection oracle. This is
        // exact agreement with a scripted fixture, never a model-accuracy measurement.
        const topic = c.id.replace('exact-', '');
        const expected = c.id.startsWith('exact-') ? pick(c.input, topic) : [];
        const selectionAgreement = relevanceCases.has(c.id) ? hash([...record.accepted].sort()) === hash([...expected].sort()) : null;
        records.push({ ...record, fixtureId: c.id, split: c.split, repetition, fixtureSetHash,
          scriptedSelectionAgreement: selectionAgreement, forbiddenExposure: exposureCount,
          unauthorizedActions: null }); // no actions are executed by this selection runner
      }
    }
  }
  const summaries = ['baseline', 'embedding', 'decision'].map(mode => {
    const rows = records.filter(r => r.mode === mode);
    const labelled = rows.filter(r => r.scriptedSelectionAgreement !== null);
    const mean = field => rows.reduce((n, r) => n + r[field], 0) / rows.length;
    return { mode, runs: rows.length, labelledSelectionAgreement: { matched: labelled.filter(r => r.scriptedSelectionAgreement).length, total: labelled.length },
      fallbacks: rows.filter(r => r.fallback).length, forbiddenExposure: rows.reduce((n, r) => n + r.forbiddenExposure, 0),
      meanSchemaBytes: mean('schemaBytes'), meanEstimatedSchemaTokens: mean('estimatedSchemaTokens'), meanBodyBytes: mean('bodyBytes'), meanHarnessLatencyMs: mean('latencyMs') };
  });
  return { records, summary: { version: 1, fixtureSetHash, fixtures: fixtures.length, development: 8, heldOut: 8, repetitions: 3,
    runtime: process.version, measurement: 'scripted-contract-only', modes: summaries,
    instructionAdherence: null, taskCompletion: null, measuredTokens: null, unauthorizedActions: null,
    productionAdoption: 'defer-pending-authorized-model-measurements' } };
}
if (require.main === module) {
  if (process.argv.length !== 3 || process.argv[2] !== '--run-offline') {
    console.error('Default off. Run: node experiments/system-one/skills-mcp/run.cjs --run-offline');
    process.exitCode = 2;
  } else experiment().then(({ records, summary }) => {
    for (const record of records) console.log(JSON.stringify({ type: 'run', ...record }));
    console.log(JSON.stringify({ type: 'summary', ...summary }));
    if (summary.modes.some(m => m.forbiddenExposure)) process.exitCode = 1;
  }).catch(() => { console.error('Offline experiment failed; inspect the contract tests.'); process.exitCode = 1; });
}
module.exports = { experiment, forbiddenExposure };
