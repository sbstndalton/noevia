'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const { feasibility } = require('./residency.cjs');
// A DaServer-like profile, with illustrative measured footprints (not real measurements).
const host = (over = {}) => ({ limitGB: 14, hostAvailableGB: 6, resident: [{ id: 'chat-20B', residentGB: 12.5, pinned: false }, { id: 'reranker', residentGB: 1.0, pinned: true }], ...over });

test('a small model that fits beside the residents coexists', () => {
  assert.equal(feasibility({ id: 'dec-0.6B', residentGB: 0.4, loadPeakGB: 0.05 }, host()).fit, 'coexist');
});
test('a larger model that cannot coexist is a swap candidate once the current chat model may be unloaded', () => {
  const c = { id: 'chat-9B', residentGB: 7.0, loadPeakGB: 0.5 };
  assert.equal(feasibility(c, host()).fit, 'no_fit', 'without an authorised swap');
  assert.equal(feasibility(c, host(), { swappable: ['chat-20B'] }).fit, 'after_swap');
});
test('the pinned reranker is never counted as reclaimable', () => {
  const c = { id: 'chat-13B', residentGB: 13.2, loadPeakGB: 0.5 };
  assert.equal(feasibility(c, host(), { swappable: ['chat-20B', 'reranker'] }).fit, 'no_fit');
});
test('the load peak counts: a model whose steady footprint fits can still fail to load', () => {
  assert.equal(feasibility({ id: 'x', residentGB: 0.4, loadPeakGB: 0.2 }, host({ hostAvailableGB: 0.5 })).fit, 'no_fit');
});
test('missing measurements give unknown, not an estimate from file size', () => {
  assert.equal(feasibility({ id: 'x', residentGB: null, loadPeakGB: 0.1 }, host()).fit, 'unknown');
  assert.equal(feasibility({ id: 'x', residentGB: 1, loadPeakGB: 0.1 }, host({ hostAvailableGB: null })).fit, 'unknown');
  assert.equal(feasibility({ id: 'x', residentGB: 1, loadPeakGB: 0.1 }, host({ resident: [{ id: 'chat', residentGB: null, pinned: false }] })).fit, 'unknown');
});
