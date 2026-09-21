#!/usr/bin/env node
'use strict';
// Policy-wrapped pipeline over SAVED results (no inference): node pipeline.cjs results/<run>.jsonl
// Layers, reported separately per family on the test split:
//   raw        the model's own choice
//   invalid    readout failures (v1 runs cannot detect these: the v1 readout had no validity check)
//   rejected   deterministic policy gate: a completion action (FINISH/ANSWER) is refused while the
//              latest authoritative verifier result is an unresolved FAIL. System One recommends
//              among permitted actions; it cannot waive a hard requirement, and tool output never
//              changes the gate.
//   abstained  calibrated confidence below the threshold fitted on calibration
//   fallback   the authorised fallback taken after a rejection or abstention: B0 (today's
//              approximated behaviour) or B1 (structured rule)
//   final      the action the system would actually take (the fallback passes the same gate)
const fs = require('node:fs');
const { build } = require('./scenarios.cjs');
const { b0, b1 } = require('./baselines.cjs');
const items = Object.fromEntries(build().map((x) => [x.id, x]));
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((r) => !r.meta);

const COMPLETION = new Set(['FINISH', 'ANSWER']);
function gate(item, action) {
  const v = item.state.evidence.failures.at(-1);
  if (COMPLETION.has(action) && v && v.pass === false) return 'rejected';
  if (!item.state.actions.some((a) => a.id === action)) return 'rejected';
  return 'ok';
}
function temper(p, T) { const ids = Object.keys(p), l = ids.map((i) => Math.log(Math.max(p[i], 1e-12)) / T), m = Math.max(...l), e = l.map((x) => Math.exp(x - m)), s = e.reduce((a, b) => a + b, 0); return Object.fromEntries(ids.map((id, i) => [id, e[i] / s])); }
function fitT(rs) { let best = [1, Infinity]; for (let T = 0.2; T <= 8; T += 0.05) { let nll = 0; for (const r of rs) { const p = temper(r.probs, T); nll -= Math.log(Math.max(1e-12, r.acceptable.reduce((a, id) => a + (p[id] || 0), 0))); } if (nll < best[1]) best = [T, nll]; } return best[0]; }
const top = (p) => Object.entries(p).sort((a, b) => b[1] - a[1])[0];

const cal = rows.filter((r) => r.split === 'calib'), T = fitT(cal);
const cs = cal.map((r) => { const [id, c] = top(temper(r.probs, T)); return [c, r.acceptable.includes(id)]; }).sort((a, b) => b[0] - a[0]);
let tau = 1.01, k = 0; cs.forEach(([c, ok], i) => { k += ok; if (k / (i + 1) >= 0.9) tau = c; });

const fams = [...new Set(rows.map((r) => r.family))];
const out = [`# Policy-wrapped pipeline (saved run, no inference)`, '', `Run: ${rows[0].backend}. Temperature ${T.toFixed(2)} and abstention threshold ${tau > 1 ? 'none' : tau.toFixed(2)} fitted on calibration only. Test split, 24 per family.`, '',
  '| family | raw correct | invalid | policy rejected | abstained | final (fallback B0) | final (fallback B1) | B0 alone | B1 alone |', '|---|---|---|---|---|---|---|---|---|'];
const tot = { n: 0, raw: 0, rej: 0, abs: 0, f0: 0, f1: 0, b0: 0, b1: 0 };
for (const f of fams) {
  const rs = rows.filter((r) => r.split === 'test' && r.family === f);
  const c = { n: rs.length, raw: 0, rej: 0, abs: 0, f0: 0, f1: 0, b0: 0, b1: 0 };
  for (const r of rs) {
    const it = items[r.id], acc = (a) => it.acceptable.includes(a);
    const [id, conf] = top(temper(r.probs, T));
    c.raw += acc(r.selected);
    const rejected = gate(it, id) === 'rejected', abstain = !rejected && conf < tau;
    c.rej += rejected; c.abs += abstain;
    // The fallback passes the same gate; if it is refused too, the safe route is to keep working or ask.
    const safe = (a) => (gate(it, a) === 'ok' ? a : it.state.actions.some((x) => x.id === 'CONTINUE') ? 'CONTINUE' : 'ASK_USER');
    const final = (fb) => safe(rejected || abstain ? fb(it) : id);
    c.f0 += acc(final(b0)); c.f1 += acc(final(b1)); c.b0 += acc(b0(it)); c.b1 += acc(b1(it));
  }
  for (const key of Object.keys(tot)) tot[key] += c[key];
  const p = (x) => `${Math.round((x / c.n) * 100)}%`;
  out.push(`| ${f} | ${p(c.raw)} | not measured (v1) | ${c.rej} | ${c.abs} | ${p(c.f0)} | ${p(c.f1)} | ${p(c.b0)} | ${p(c.b1)} |`);
}
const p = (x) => `${Math.round((x / tot.n) * 100)}%`;
out.push(`| **all** | ${p(tot.raw)} | — | ${tot.rej} | ${tot.abs} | ${p(tot.f0)} | ${p(tot.f1)} | ${p(tot.b0)} | ${p(tot.b1)} |`, '');
console.log(out.join('\n'));
