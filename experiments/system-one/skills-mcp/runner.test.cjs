'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { forbiddenExposure, experiment } = require('./run.cjs');
const { cases } = require('./fixtures.cjs');
const { toolId } = require('./contract.cjs');

test('exposure oracle catches dependency-excluded schemas even if the loader regresses', () => {
  const input = cases().find(c => c.id === 'missing-dependency').input;
  assert.equal(forbiddenExposure(input, ['calendar_read', 'calendar_write'].map(toolId)), 2);
  assert.equal(forbiddenExposure(input, ['files_read', 'wiki_read'].map(toolId)), 0);
  input.boxes[1].requires = ['calendar'];
  assert.equal(forbiddenExposure(input, ['files_read'].map(toolId)), 1, 'transitive dependency also excluded');
});

test('report has identical frozen inputs across modes and explicitly unavailable quality fields', async () => {
  const { records, summary } = await experiment();
  assert.equal(records.length, 144);
  assert.equal(new Set(records.map(r => r.fixtureSetHash)).size, 1);
  assert.equal(summary.fixtures, 16);
  assert.equal(summary.modes.reduce((n, m) => n + m.forbiddenExposure, 0), 0);
  for (const row of records) {
    assert.equal(row.unauthorizedActions, null);
    assert.equal(row.taskCompletion, null);
    assert.equal(row.instructionAdherence, null);
    assert.equal(row.measuredTokens, null);
  }
  for (const id of new Set(records.map(r => r.fixtureId))) {
    assert.equal(new Set(records.filter(r => r.fixtureId === id).map(r => r.fixtureHash)).size, 1);
  }
});
