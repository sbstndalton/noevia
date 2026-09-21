'use strict';
// One decision through decide(), recorded with its readout diagnostics (success or failure), and
// appended to the results file immediately so an interrupted run keeps everything done so far.
// Diagnostics come from the backend via decide()'s opt-in onDiagnostic hook and contain
// measurements only (no prompt/state text). Synthetic experiment use only.
const fs = require('node:fs');
const path = require('node:path');
const { createDecisions } = require(path.resolve(__dirname, '../../../apps/web/server/decision/index.cjs'));

function createHarness({ backend, file, now = Date.now }) {
  let attempts = [];
  const decisions = createDecisions({ backends: { [backend.id]: backend }, chains: { 'system1.eval': [backend.id] }, onDiagnostic: (e) => attempts.push(e) });
  function append(row) { fs.appendFileSync(file, `${JSON.stringify(row)}\n`); }
  async function decideOne({ item, stateText, fallback, deadlineMs, label }) {
    attempts = [];
    const started = now();
    const r = await decisions.decide({ kind: 'choice', purpose: 'system1.eval', question: item.question, options: item.state.actions.map((a) => ({ id: a.id, label: a.text })),
      context: { stateText }, fallback: { selected: fallback, scores: {}, confidence: null }, constraints: { deadlineMs } });
    const a = attempts.at(-1) || null;
    const row = { id: item.id, family: item.family, split: item.split, backend: label, schema: item.state.schema,
      selected: r.selected, correct: item.acceptable.includes(r.selected), acceptable: item.acceptable, source: r.source, fellBack: r.metadata?.fellBack || null,
      readout: r.source === 'fallback' ? 'invalid' : r.metadata?.readout ?? null,  // exact | bounded | invalid (see backends.cjs)
      ratios: r.source === 'fallback' ? null : r.metadata?.ratios ?? null,       // readout ratios, NOT calibrated correctness
      bounds: r.source === 'fallback' ? null : r.metadata?.bounds ?? null,
      rejection: a && !a.ok ? a.reason : null, diagnostics: a?.diagnostics ?? null, ms: now() - started };
    append(row);
    return row;
  }
  return { decideOne, append };
}

module.exports = { createHarness };
