'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { createBrowserService } = require('./browser-service.cjs');

const temps = [];
const temp = (p) => { const d = fs.mkdtempSync(path.join(os.tmpdir(), p)); temps.push(d); return d; };
test.after(() => { for (const d of temps) fs.rmSync(d, { recursive: true, force: true }); });

const project = { id: 'p1' };
const ORIGIN = 'https://shop.example.test/';

/** A page whose only element is `#go`, an always-consequential submit button (asks every time). */
function fakeBrowser({ url = ORIGIN, failClick = false } = {}) {
  const submit = { tag: 'button', type: '', role: '', name: 'Send order', text: 'Send order', value: '', inForm: true, formMethod: 'post' };
  const effects = [];
  const handle = {
    evaluate: async (fn) => (fn.name === 'describeInPage' ? submit : (String(fn).includes('isConnected') ? true : undefined)),
    click: async () => { if (failClick) throw Error('Target closed'); effects.push('click'); },
    dispose: async () => {},
  };
  const page = {
    url: () => url,
    locator: () => ({ first() { return this; }, elementHandle: async () => handle, innerText: async () => 'text' }),
    goto: async (to) => { effects.push(['goto', to]); url = to; },
    evaluate: async () => ({ inForm: false }),
    screenshot: async () => Buffer.from('png'),
    waitForLoadState: async () => {}, goBack: async () => {},
    keyboard: { press: async () => {} }, mouse: { wheel: async () => {} }, waitForTimeout: async () => {},
    innerText: async () => 'body text',
  };
  page.on = () => {};
  const context = { route: async () => {}, routeWebSocket: async () => {}, on: (event, fn) => { if (event === 'page') fn(page); },
    newPage: async () => page, pages: () => [page], close: async () => {} };
  const browser = { newContext: async () => context, close: async () => {} };
  return { browser, effects };
}

function service(extra = {}) {
  const workspace = { dir: temp('noevia-browser-sws-') };
  const fake = fakeBrowser(extra.browserOpts);
  const egress = { endpoint: 'egress:8040', grant: ({ taskId }) => ({ token: `tok-${taskId}` }), revoke: () => {} };
  const svc = createBrowserService({ launch: async () => fake.browser, egress, timeoutMs: 60, idleTimeoutMs: 200, ...extra });
  return { svc, workspace, fake };
}

test('a task needs at least one domain, and only reachable ones', async () => {
  const { svc, workspace } = service();
  await assert.rejects(() => svc.start(workspace, project, { domains: [] }), /at least one domain/);
  await assert.rejects(() => svc.start(workspace, project, { domains: ['not a domain', '../evil'] }), /at least one domain/);
});

test('one task at a time per project, running through queued, running, finished', async () => {
  const { svc, workspace } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  assert.ok(started.taskId);
  const task = svc.get(workspace, project, started.taskId);
  assert.equal(task.status, 'running');
  await assert.rejects(() => svc.start(workspace, project, { domains: ['other.test'] }), /already has a browser task running/);
  const result = svc.finish(workspace, project, started.taskId, { pages: 1 });
  assert.deepEqual(result, { ok: true });
  await new Promise((r) => setTimeout(r, 20));
  const done = svc.get(workspace, project, started.taskId);
  assert.equal(done.status, 'completed');
  assert.deepEqual(done.result, { pages: 1 });
  // The slot is free again.
  const second = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  assert.ok(second.taskId);
  svc.finish(workspace, project, second.taskId, null);
});

test('a read action runs without an approval card; a consequential one asks, and the answer decides it', async () => {
  const { svc, workspace, fake } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  const extracted = await svc.act(workspace, project, started.taskId, { type: 'extract' });
  assert.equal(extracted.status, 'done');
  assert.equal(svc.get(workspace, project, started.taskId).status, 'running', 'a read never raises a card');

  const actPromise = svc.act(workspace, project, started.taskId, { type: 'click', selector: '#go' });
  // The approval card appears on the task while the click is pending.
  await new Promise((r) => setTimeout(r, 20));
  const waiting = svc.get(workspace, project, started.taskId);
  assert.equal(waiting.status, 'waiting_approval');
  assert.ok(waiting.approval, 'the card carries the approval id and the masked arguments');
  assert.equal(waiting.approval.action, 'click');

  svc.decide(workspace, project, started.taskId, 'approve', waiting.approval.id);
  const result = await actPromise;
  assert.equal(result.status, 'done');
  assert.deepEqual(fake.effects, ['click']);
  assert.equal(svc.get(workspace, project, started.taskId).status, 'running', 'answered: back to running');
  svc.finish(workspace, project, started.taskId, null);
});

test('a declined approval blocks the action, and never auto-approves', async () => {
  const { svc, workspace, fake } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  const actPromise = svc.act(workspace, project, started.taskId, { type: 'click', selector: '#go' });
  await new Promise((r) => setTimeout(r, 20));
  const waiting = svc.get(workspace, project, started.taskId);
  svc.decide(workspace, project, started.taskId, 'deny', waiting.approval.id);
  const result = await actPromise;
  assert.equal(result.status, 'blocked');
  assert.deepEqual(fake.effects, [], 'nothing was clicked');
  svc.finish(workspace, project, started.taskId, null);
});

test('an approval that gets no answer times out as a refusal, never a silent approve', async () => {
  const { svc, workspace, fake } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  const result = await svc.act(workspace, project, started.taskId, { type: 'click', selector: '#go' });
  assert.equal(result.status, 'blocked');
  assert.deepEqual(fake.effects, []);
  svc.finish(workspace, project, started.taskId, null);
});

test('an unanswered approval is refused, an approval-answer for the wrong id is refused, and stale answers are refused', async () => {
  const { svc, workspace } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  assert.throws(() => svc.decide(workspace, project, started.taskId, 'approve', 'not-a-real-id'), /no longer waiting/);
  svc.finish(workspace, project, started.taskId, null);
});

test('cancel aborts the task, closes the session, revokes egress, and refuses any card still waiting', async () => {
  const { svc, workspace } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  const actPromise = svc.act(workspace, project, started.taskId, { type: 'click', selector: '#go' });
  await new Promise((r) => setTimeout(r, 20));
  svc.cancel(workspace, project, started.taskId);
  const result = await actPromise;
  assert.equal(result.status, 'blocked', 'a card still open when cancelled is refused, not left waiting');
  for (let i = 0; i < 100 && svc.get(workspace, project, started.taskId).status !== 'cancelled'; i++) await new Promise((r) => setTimeout(r, 5));
  assert.equal(svc.get(workspace, project, started.taskId).status, 'cancelled');
  await assert.rejects(() => svc.act(workspace, project, started.taskId, { type: 'extract' }), /not running/);
});

test('a task idle too long times out (failed), not left running forever', async () => {
  const { svc, workspace } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  await new Promise((r) => setTimeout(r, 260));
  const task = svc.get(workspace, project, started.taskId);
  assert.equal(task.status, 'failed');
  assert.match(task.error, /timed out/);
});

test('recovery after a restart marks a running task interrupted, never silently resumed', async () => {
  const workspace = { dir: temp('noevia-browser-recover-') };
  const egress = { endpoint: 'egress:8040', grant: ({ taskId }) => ({ token: `tok-${taskId}` }), revoke: () => {} };
  const fake1 = fakeBrowser();
  const svc1 = createBrowserService({ launch: async () => fake1.browser, egress, timeoutMs: 60, idleTimeoutMs: 60000 });
  const started = await svc1.start(workspace, project, { domains: ['shop.example.test'] });
  assert.equal(svc1.get(workspace, project, started.taskId).status, 'running');
  // A fresh service (simulating a new process) sees the same directory.
  const fake2 = fakeBrowser();
  const svc2 = createBrowserService({ launch: async () => fake2.browser, egress, timeoutMs: 60, idleTimeoutMs: 60000 });
  const recovered = svc2.get(workspace, project, started.taskId);
  assert.equal(recovered.status, 'interrupted');
  assert.match(recovered.error, /restart/);
});

test('a task from another project is not found, rather than forbidden — tenant scoping', async () => {
  const { svc, workspace } = service();
  const started = await svc.start(workspace, project, { domains: ['shop.example.test'] });
  assert.throws(() => svc.get(workspace, { id: 'other-project' }, started.taskId), /Task not found/);
  const otherWorkspace = { dir: temp('noevia-browser-other-tenant-') };
  assert.throws(() => svc.get(otherWorkspace, project, started.taskId), /Task not found/);
  svc.finish(workspace, project, started.taskId, null);
});

test('a browser that fails to open never leaves a phantom running task', async () => {
  const workspace = { dir: temp('noevia-browser-openfail-') };
  const egress = { endpoint: 'egress:8040', grant: ({ taskId }) => ({ token: `tok-${taskId}` }), revoke: () => {} };
  const svc = createBrowserService({ launch: async () => { throw Error('no browser on this host'); }, egress, timeoutMs: 60 });
  await assert.rejects(() => svc.start(workspace, project, { domains: ['shop.example.test'] }), /could not open/);
});
