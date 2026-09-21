#!/usr/bin/env node
'use strict';
// Readout smoke-test report: node smoke-report.cjs results/<run>.jsonl
// Answers only "does the adapter extract and report the intended scores from the pinned runtime?"
// It deliberately reports NO accuracy: the smoke test does not rank models or fit thresholds.
const fs = require('node:fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const meta = rows.filter((r) => r.meta), d = rows.filter((r) => !r.meta);
const count = (f) => d.reduce((m, r) => { const k = f(r); m[k] = (m[k] || 0) + 1; return m; }, {});
const nums = (f) => d.map(f).filter((x) => typeof x === 'number').sort((a, b) => a - b);
const q = (a, p) => (a.length ? a[Math.min(a.length - 1, Math.floor(p * a.length))] : null);
const lm = nums((r) => r.diagnostics?.labelMassAtAnswer), res = nums((r) => r.diagnostics?.residual);
const identity = [...new Set(d.map((r) => JSON.stringify(r.diagnostics?.runtime || null)))];
const byLetter = {}; // label letter -> set of variant-id signatures seen
for (const r of d) for (const l of Object.values(r.diagnostics?.labels || {})) (byLetter[l.label] ||= new Set()).add(JSON.stringify(l.variants.map((v) => v.ids)));
const checks = {
  'every decision has diagnostics': d.every((r) => r.diagnostics),
  'one runtime identity': identity.length === 1,
  'every canonical label is a single token': d.every((r) => !/not a single token/.test(r.rejection || '')),
  'each label letter always maps to the same token ids': Object.values(byLetter).every((set) => set.size === 1),
  'no prompt truncated': meta.every((m) => m.promptsTruncated == null || m.promptsTruncated === 0),
  'run ended normally': meta.some((m) => m.phase === 'end' && !m.stopped),
};
console.log(JSON.stringify({
  decisions: d.length, readout: count((r) => r.readout), rejections: count((r) => (r.rejection || 'none').replace(/\d[\d.e+-]*/g, '#')),
  labelMassAtAnswer: { min: lm[0] ?? null, p50: q(lm, 0.5), max: lm.at(-1) ?? null }, residual: { p50: q(res, 0.5), max: res.at(-1) ?? null },
  firstTokens: count((r) => r.diagnostics?.request1?.top?.[0]?.token ?? null), unsupportedVariants: d.flatMap((r) => r.diagnostics?.unsupportedVariants || []).length,
  unobservedVariants: d.flatMap((r) => r.diagnostics?.unobservedVariants || []).length, runtime: identity.map((x) => JSON.parse(x)),
  msPerDecision: { p50: q(nums((r) => r.ms), 0.5), max: nums((r) => r.ms).at(-1) ?? null }, end: meta.find((m) => m.phase === 'end') || null, checks,
}, null, 2));
