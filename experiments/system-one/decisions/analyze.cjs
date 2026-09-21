#!/usr/bin/env node
'use strict';
// Summarise pilot results: node analyze.cjs results/*.jsonl > results/summary.md
// - Accuracy = the selected action is in the acceptable set. Per family, with Wilson 95% intervals.
// - Calibration: one temperature per backend, fitted on the CALIBRATION split only (NLL of the
//   probability mass on acceptable actions); ECE (10 bins) reported raw and calibrated on TEST.
// - Abstention: the threshold is fitted on calibration (lowest confidence whose selective accuracy
//   on calibration is >= 0.90). On test: coverage, selective accuracy, false acceptance (answered
//   and wrong, over all), and system accuracy when an abstention falls back to B0 (today's
//   behaviour). Abstention never escalates to a remote model.
// Confidence here is confidence in the chosen action, NOT a probability that the task succeeds.
const fs = require('node:fs');
const { build } = require('./scenarios.cjs');
const { b0 } = require('./baselines.cjs');
const items = Object.fromEntries(build().map((x) => [x.id, x]));

const rows = process.argv.slice(2).flatMap((f) => fs.readFileSync(f, 'utf8').trim().split('\n').map((l) => JSON.parse(l)));
const meta = rows.filter((r) => r.meta);
const data = rows.filter((r) => !r.meta);
const backends = [...new Set(data.map((r) => r.backend))];
const FAM = [...new Set(Object.values(items).map((x) => x.family))];

function wilson(k, n) {
  if (!n) return [0, 0];
  const z = 1.96, p = k / n, d = 1 + z * z / n, c = p + z * z / (2 * n), m = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n));
  return [(c - m) / d, (c + m) / d];
}
const pc = (x) => `${Math.round(x * 100)}%`;
const ci = (k, n) => { const [a, b] = wilson(k, n); return `${pc(k / n)} (${pc(a)}–${pc(b)})`; };

function temper(probs, T) {
  const ids = Object.keys(probs), l = ids.map((i) => Math.log(Math.max(probs[i], 1e-12)) / T), m = Math.max(...l);
  const e = l.map((x) => Math.exp(x - m)), s = e.reduce((a, b) => a + b, 0);
  return Object.fromEntries(ids.map((id, i) => [id, e[i] / s]));
}
const pick = (p) => Object.entries(p).sort((a, b) => b[1] - a[1])[0];
function fitT(rs) {
  let best = [1, Infinity];
  for (let T = 0.2; T <= 8; T += 0.05) {
    let nll = 0;
    for (const r of rs) { const p = temper(r.probs, T); nll -= Math.log(Math.max(1e-12, r.acceptable.reduce((a, id) => a + (p[id] || 0), 0))); }
    if (nll < best[1]) best = [T, nll];
  }
  return best[0];
}
function ece(pairs) { // [conf, correct]
  const bins = Array.from({ length: 10 }, () => [0, 0, 0]);
  for (const [c, ok] of pairs) { const b = bins[Math.min(9, Math.floor(c * 10))]; b[0]++; b[1] += c; b[2] += ok ? 1 : 0; }
  return bins.reduce((a, [n, c, k]) => a + (n ? (n / pairs.length) * Math.abs(c / n - k / n) : 0), 0);
}

const out = ['# Generic System-One pilot — results', '', `Backends: ${backends.join(', ')}. Split by template family; test = template t4 of each family.`, ''];
out.push('## Accuracy by family (test split; 95% Wilson interval)', '', `| family | n | ${backends.join(' | ')} |`, `|---|---|${backends.map(() => '---').join('|')}|`);
for (const f of FAM) {
  const cells = backends.map((b) => { const rs = data.filter((r) => r.backend === b && r.split === 'test' && r.family === f); return rs.length ? ci(rs.filter((r) => r.correct).length, rs.length) : '—'; });
  const n = data.find((r) => r.split === 'test' && r.family === f) ? data.filter((r) => r.backend === backends[0] && r.split === 'test' && r.family === f).length : 0;
  out.push(`| ${f} | ${n} | ${cells.join(' | ')} |`);
}
const all = backends.map((b) => { const rs = data.filter((r) => r.backend === b && r.split === 'test'); return rs.length ? ci(rs.filter((r) => r.correct).length, rs.length) : '—'; });
out.push(`| **all** | | ${all.join(' | ')} |`, '');

out.push('## Calibration and abstention (test; fitted on calibration only)', '', '| backend | T | ECE raw | ECE calibrated | τ | coverage | selective acc | false acceptance | system acc (abstain → B0) |', '|---|---|---|---|---|---|---|---|---|');
for (const b of backends) {
  const cal = data.filter((r) => r.backend === b && r.split === 'calib' && r.probs), test = data.filter((r) => r.backend === b && r.split === 'test' && r.probs);
  if (!cal.length || !test.length) continue;
  const T = fitT(cal);
  const scored = (rs, t) => rs.map((r) => { const p = temper(r.probs, t); const [id, c] = pick(p); return { r, id, c, ok: r.acceptable.includes(id) }; });
  const calS = scored(cal, T).sort((a, b) => b.c - a.c);
  let tau = 1.01, k = 0;
  calS.forEach((s, i) => { k += s.ok ? 1 : 0; if (k / (i + 1) >= 0.9) tau = s.c; });
  const ts = scored(test, T), raw = scored(test, 1);
  const ans = ts.filter((s) => s.c >= tau);
  const sys = ts.filter((s) => (s.c >= tau ? s.ok : items[s.r.id].acceptable.includes(b0(items[s.r.id])))).length;
  out.push(`| ${b} | ${T.toFixed(2)} | ${ece(raw.map((s) => [s.c, s.ok])).toFixed(3)} | ${ece(ts.map((s) => [s.c, s.ok])).toFixed(3)} | ${tau > 1 ? 'none' : tau.toFixed(2)} | ${pc(ans.length / ts.length)} | ${ans.length ? pc(ans.filter((s) => s.ok).length / ans.length) : '—'} | ${pc(ans.filter((s) => !s.ok).length / ts.length)} | ${ci(sys, ts.length)} |`);
}
out.push('');

out.push('## Cost of running it (measured)', '', '| backend | model file | cold start | peak RSS | p50 / p95 per decision | prompt tokens (median) | decisions/s | truncated prompts | host |', '|---|---|---|---|---|---|---|---|---|');
const q = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };
for (const m of meta) {
  const rs = data.filter((r) => r.backend === m.backend && r.ms != null && (m.ngl === '0' ? true : true));
  const same = rs.filter((r) => (m.ngl === '0') === r.backend.endsWith('-cpu'));
  const ms = rs.map((r) => r.ms), tok = rs.map((r) => r.promptTokens).filter((x) => x != null);
  out.push(`| ${m.backend}${m.ngl === '0' ? ' (CPU, ' + m.threads + ' threads)' : ' (GPU)'} | ${(m.modelBytes / 2 ** 30).toFixed(2)} GiB | ${(m.coldStartMs / 1000).toFixed(1)} s | ${(m.peakRssMB / 1024).toFixed(2)} GiB | ${q(ms, 0.5)} / ${q(ms, 0.95)} ms | ${q(tok, 0.5)} | ${m.decisionsPerSec.toFixed(2)} | ${m.promptsTruncated} | ${m.host}; ${m.llamaServer} |`);
}
out.push('');
console.log(out.join('\n'));
