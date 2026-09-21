'use strict';
// Deterministic baselines. Both see only the DecisionState (plus the role config noevia has).
//  B0 current: what noevia does today. Model choice = the auto-router's role heuristics
//     (apps/web/server/auto-router.cjs, reused, not copied); no mid-task switching (choose once);
//     retry while retries remain; finish when the model says it is done; never abstains.
//  B1 rules:   a simple rule over STRUCTURED fields only: highest measured success among
//     eligible models; keep unless a switch gains more than 0.10; verifier PASS/FAIL flags.
//     Where the deciding fact is only in free text, B1 falls back to B0. Note: labels for the
//     model-choice families come from these same structured facts, so B1 is near an upper bound
//     there by construction; it shows how much a plain rule gets without any model.
const path = require('node:path');
const { createAutoRouter } = require(path.resolve(__dirname, '../../../apps/web/server/auto-router.cjs'));
const router = createAutoRouter({ roles: () => null, provider: null, headers: {}, fetchJson: async () => ({ ok: false }), log: { warn() {} } });
const ROLES = { fast: 'gemma-4-E2B', smart: 'qwen3.5-9B', code: 'coder-7B' };
const has = (s, id) => s.actions.some((a) => a.id === id);

function currentRoute(s) {
  const role = router.heuristicWantsCode(s.task.text) || s.task.type === 'code' ? 'code' : router.heuristicWantsSmart(s.task.text) ? 'smart' : 'fast';
  const want = `USE:${ROLES[role]}`;
  // Role model not eligible (too big / unavailable): today noevia refuses (409 stale roles). The
  // nearest deterministic equivalent is the first offered model.
  return has(s, want) ? want : s.actions[0].id;
}

function b0(item) {
  const s = item.state;
  switch (item.family) {
    case 'initial_selection': case 'unavailable_or_memory': case 'general_vs_specialist': return currentRoute(s);
    case 'keep_vs_switch': return 'KEEP_CURRENT';
    case 'retry_vs_retrieve': case 'local_only': return has(s, 'RETRY') ? 'RETRY' : 'FINISH_WITH_NOTICE';
    case 'finish_vs_incomplete': case 'misleading_tool_output': return 'FINISH';
    case 'insufficient_evidence': return 'ANSWER';
    default: throw Error(item.family);
  }
}

function b1(item) {
  const s = item.state;
  const best = (list) => list.filter((p) => p.success != null).sort((a, b) => b.success - a.success || a.memGB - b.memGB)[0];
  switch (item.family) {
    case 'initial_selection': case 'unavailable_or_memory': case 'general_vs_specialist': {
      const opts = s.shortlist.filter((p) => has(s, `USE:${p.id}`));
      return opts.length ? `USE:${best(opts).id}` : b0(item);
    }
    case 'keep_vs_switch': {
      const alt = best(s.shortlist);
      return alt && s.budget.switchesLeft > 0 && alt.success - s.current.success > 0.1 && has(s, `SWITCH:${alt.id}`) ? `SWITCH:${alt.id}` : 'KEEP_CURRENT';
    }
    case 'finish_vs_incomplete': case 'misleading_tool_output': {
      const v = s.evidence.failures.at(-1);
      return v && v.pass === false ? 'CONTINUE' : 'FINISH';
    }
    default: return b0(item);
  }
}

module.exports = { b0, b1 };
