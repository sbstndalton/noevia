'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { run, prepare, hash, skillId, boxId, toolId } = require('./contract.cjs');
const { fixture, proposal, pick, embed, cases } = require('./fixtures.cjs');
const decide = (f, value, extra = {}) => run(f, { mode: 'decision', enabled: true, answer: async () => value, ...extra });

test('default off performs no selector call; baseline retains metadata but loads no body', async () => {
  const f = fixture();
  const result = await run(f, { mode: 'decision', answer: () => { throw Error('must not run'); } });
  assert.equal(result.record.fallback, 'off');
  assert.deepEqual(result.record.loaded.skills, []);
  assert.equal(result.record.loaded.tools.length, 6);
  assert.match(result.index, /calendar\/SKILL.md/);
});

test('valid proposal loads actual reviewed content and real resolved schemas', async () => {
  const f = fixture(); const r = await decide(f, proposal(pick(f, 'calendar')));
  assert.equal(r.record.fallback, null);
  assert.deepEqual(r.record.accepted, pick(f, 'calendar'));
  assert.deepEqual(r.record.loaded.tools, ['calendar_read', 'calendar_write'].map(toolId));
  assert.deepEqual(r.record.loaded.skills, [skillId(f.project, 'calendar/SKILL.md')]);
  assert.match(r.bodies[0].body, /Cite the returned reference/);
  assert.equal(r.record.bodyBytes, Buffer.byteLength(r.bodies[0].body));
  assert.equal(r.record.schemaBytes, Buffer.byteLength(JSON.stringify(r.tools)));
});

for (const [name, change, reason] of [
  ['unknown', p => { p.selected.push('unknown-secret'); p.scores['unknown-secret'] = 1; }, 'unknown-id'],
  ['duplicate', p => p.selected.push(p.selected[0]), 'duplicate-id'],
  ['missing-score', p => { delete p.scores[p.selected[0]]; }, 'scores'],
  ['non-finite', p => { p.scores[p.selected[0]] = NaN; }, 'scores'],
  ['out-of-range', p => { p.scores[p.selected[0]] = 2; }, 'scores'],
  ['extra-score', p => { p.scores.other = 1; }, 'scores'],
  ['low-confidence', p => { p.confidence = 0.2; }, 'low-confidence'],
  ['non-finite-confidence', p => { p.confidence = Infinity; }, 'confidence'],
  ['low-score', p => { p.scores[p.selected[0]] = 0.1; }, 'low-score'],
  ['malformed', p => { p.selected = 'calendar'; }, 'cardinality'],
  ['executable-field', p => { p.command = 'secret-shell'; }, 'unexpected-field'],
  ['false-abstention', p => { p.abstain = true; }, 'abstention'],
]) test(`${name} fails to distinct fallbacks without echoing raw content`, async () => {
  const f = fixture(); const p = proposal(pick(f, 'calendar')); change(p);
  const r = await decide(f, p);
  assert.equal(r.record.fallback, reason);
  assert.deepEqual(r.record.loaded.skills, []);
  assert.equal(r.record.loaded.tools.length, 6);
  assert.doesNotMatch(JSON.stringify(r.record), /unknown-secret|secret-shell|Cite the returned/);
});

test('abstention and excessive skill cardinality fall back', async () => {
  const f = fixture();
  assert.equal((await decide(f, proposal([]))).record.fallback, 'abstained');
  assert.equal((await decide(f, proposal(['calendar', 'files'].map(t => skillId(f.project, `${t}/SKILL.md`))))).record.fallback, 'cardinality');
});

for (const name of ['changed-skill', 'disabled-skill', 'missing-dependency', 'account-unready', 'unselected', 'server-unready', 'config-changed']) {
  test(`${name} cannot propose an ineligible ID`, async () => {
    const c = cases().find(c => c.id === name);
    const r = await decide(c.input, c.answer);
    assert.equal(r.record.fallback, 'unknown-id');
    assert.deepEqual(r.record.loaded.skills, []);
    if (!name.endsWith('skill')) assert.ok(!r.record.loaded.tools.includes(toolId('calendar_read')));
  });
}

test('cross-project and cross-tenant IDs never load; wrong scope envelope fails closed', async () => {
  const f = fixture(); const other = structuredClone(f.project); other.id = 'other';
  const r = await decide(f, proposal([skillId(other, 'calendar/SKILL.md')]));
  assert.equal(r.record.fallback, 'unknown-id');
  f.current.owner = 'other-user';
  await assert.rejects(() => decide(f, proposal([])), /scope/);
});

test('dependencies are added within ceiling and rechecked against budgets and blocks', async () => {
  const f = fixture(); f.boxes[0].requires = ['files'];
  const r = await decide(f, proposal(pick(f, 'calendar')));
  assert.deepEqual(r.record.loaded.tools, ['calendar_read', 'calendar_write', 'files_read', 'files_write'].map(toolId));
  f.blocked = ['files_read'];
  const blocked = await decide(f, proposal(pick(f, 'calendar')));
  assert.equal(blocked.record.fallback, 'nothing-loadable');
  assert.ok(!blocked.record.loaded.tools.includes(toolId('files_read')));
  assert.equal(blocked.record.bodyBytes, 0);
});

test('body budgets do not count truncated bodies as loaded; schema budgets reflect resolver', async () => {
  for (const name of ['body-budget', 'tool-budget']) {
    const c = cases().find(c => c.id === name); const r = await decide(c.input, c.answer);
    assert.equal(r.record.loaded.skills.length, 0);
    assert.ok(r.record.rejected.some(x => x.reason === name));
    if (name === 'tool-budget') assert.ok(!r.record.loaded.tools.includes(toolId('calendar_read')));
  }
});

test('configured body budget controls the documented ceiling', async () => {
  const c = cases().find(c => c.id === 'body-budget');
  const r = await decide(c.input, c.answer, { config: { bodyBytes: 20000 } });
  assert.ok(r.record.accepted.includes(skillId(c.input.project, 'calendar/SKILL.md')));
  assert.ok(r.record.bodyBytes > 12000);
});

test('tool collisions reject the lower ranked box without duplicate schema names', async () => {
  const f = fixture(); f.boxes[1].tools[0] = structuredClone(f.boxes[0].tools[0]);
  const r = await decide(f, proposal([boxId('calendar'), boxId('files')]));
  assert.deepEqual(r.record.accepted, [boxId('calendar')]);
  assert.equal(r.record.rejected[0].reason, 'tool-collision');
});

test('selector error, timeout, remote policy and cancellation preserve fallback', async () => {
  const f = fixture();
  const error = await decide(f, null, { answer: async () => { throw Error('secret prompt'); } });
  assert.equal(error.record.fallback, 'backend-error');
  let aborted = false;
  const timeout = await decide(f, null, { config: { deadlineMs: 5 }, answer: (_r, signal) => new Promise(() => { signal.addEventListener('abort', () => { aborted = true; }); }) });
  assert.equal(timeout.record.fallback, 'timeout'); assert.equal(aborted, true);
  f.remote = true;
  const remote = await decide(f, null, { answer: () => { throw Error('must not call'); } });
  assert.equal(remote.record.fallback, 'remote-disallowed');
  f.remote = false;
  const ctl = new AbortController(); ctl.abort();
  assert.equal((await decide(f, proposal(pick(f, 'calendar')), { signal: ctl.signal })).record.fallback, 'cancelled');
  const during = new AbortController();
  const r = await decide(f, null, { signal: during.signal, answer: async () => { during.abort(); return proposal(pick(f, 'calendar')); } });
  assert.equal(r.record.fallback, 'cancelled');
  assert.doesNotMatch(JSON.stringify(error.record), /secret prompt/);
});

test('embedding mode invokes real routers with a declared synthetic embedder', async () => {
  const f = fixture(); const r = await run(f, { mode: 'embedding', enabled: true, embed });
  assert.deepEqual(r.record.loaded.tools, ['calendar_read', 'calendar_write'].map(toolId));
  assert.equal(r.record.loaded.skills.length, 1);
  f.task = 'no matching subject';
  const none = await run(f, { mode: 'embedding', enabled: true, embed });
  assert.equal(none.record.loaded.skills.length, 0);
  assert.equal(none.record.loaded.tools.length, 6);
});

test('hashes capture task, configuration and catalogue changes; telemetry excludes text', async () => {
  const f = fixture(); const a = await run(f); f.task += ' extra'; const b = await run(f);
  assert.notEqual(a.record.fixtureHash, b.record.fixtureHash);
  assert.equal(a.record.catalogueHash, b.record.catalogueHash);
  f.blocked.push('calendar_write'); const c = await run(f);
  assert.notEqual(b.record.configHash, c.record.configHash);
  f.boxes[0].description += ' malicious'; const d = await run(f);
  assert.notEqual(c.record.catalogueHash, d.record.catalogueHash);
  assert.doesNotMatch(JSON.stringify(d.record), /malicious|Find calendar|Cite the/);
  assert.equal(d.record.taskCompletion, null);
  assert.equal(d.record.instructionAdherence, null);
  assert.equal(d.record.measuredTokens, null);
  assert.equal(hash(f), d.record.fixtureHash);
});

test('frozen fixture groups are disjoint and all three modes use identical input hashes', async () => {
  const fixtures = cases();
  assert.equal(new Set(fixtures.map(c => c.id)).size, fixtures.length);
  assert.equal(fixtures.filter(c => c.split === 'held-out').length, 8);
  for (const c of fixtures) {
    const results = await Promise.all(['baseline', 'embedding', 'decision'].map(mode => run(c.input, { mode, enabled: true, embed, answer: async () => c.answer })));
    assert.equal(new Set(results.map(r => r.record.fixtureHash)).size, 1);
    for (const { record } of results) {
      assert.ok(record.loaded.tools.every(t => !c.input.blocked.map(toolId).includes(t)));
      assert.equal(record.modelQuality, 'unmeasured');
    }
  }
});

test('bounded request uses the real rank question/label shape without bodies', async () => {
  const f = fixture();
  await decide(f, null, { answer: async request => {
    assert.equal(request.question, f.task);
    assert.ok(request.items.every(i => typeof i.label === 'string' && i.label.length <= 1000));
    assert.doesNotMatch(JSON.stringify(request), /Cite the returned reference/);
    return proposal(pick(f, 'calendar'));
  } });
});

test('offline embedding wrapper bounds the otherwise unbounded skill embedder', async () => {
  const f = fixture();
  const r = await run(f, { mode: 'embedding', enabled: true, embed: () => new Promise(() => {}), config: { deadlineMs: 5 } });
  assert.equal(r.record.fallback, 'timeout');
  assert.equal(r.record.loaded.skills.length, 0);
  assert.equal(r.record.loaded.tools.length, 6);
});

test('embedding proposals stay inside eligibility, including requirement and readiness failures', async () => {
  for (const c of cases()) {
    const r = await run(c.input, { mode: 'embedding', enabled: true, embed });
    assert.ok(r.record.proposed.every(id => r.record.eligible.includes(id)), c.id);
    assert.ok(r.record.loaded.skills.every(id => r.record.eligible.includes(id)), c.id);
    if (['missing-dependency', 'account-unready', 'server-unready', 'config-changed'].includes(c.id)) {
      assert.equal(r.record.routingFallback.skills, 'no-skill-match', c.id);
    }
  }
});

test('catalogue-controlled box and tool names cannot carry text into telemetry', async () => {
  const f = fixture();
  f.boxes[0].id = 'SECRET_BOX_TEXT';
  f.boxes[0].tools[0].function.name = 'SECRET_TOOL_TEXT';
  f.project.toolboxes[0] = 'SECRET_BOX_TEXT';
  f.current.toolboxes[0] = 'SECRET_BOX_TEXT';
  const baseline = await run(f);
  const decision = await decide(f, proposal([boxId('SECRET_BOX_TEXT')]));
  for (const r of [baseline, decision]) {
    assert.doesNotMatch(JSON.stringify(r.record), /SECRET_BOX_TEXT|SECRET_TOOL_TEXT/);
    assert.ok(r.tools.some(t => t.function.name === 'SECRET_TOOL_TEXT'));
  }
});
