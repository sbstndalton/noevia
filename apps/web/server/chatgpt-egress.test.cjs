'use strict';
// The chat loop on a Sign in with ChatGPT provider (#447), end to end through createChatHandler
// with the real adapter and a fake OpenAI (*.fixture.invalid). Proves the external-provider rules
// in provider-egress.cjs: flag off refuses, the OAuth bearer (not an apiKey) is on the wire, Diary
// tools, Diary extras and project images never reach it, and a refused refresh says "Reconnect".
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { EventEmitter } = require('node:events');
const Database = require('better-sqlite3');
const { createChatHandler } = require('./chat.cjs');
const { createToolExchange } = require('./tool-exchange.cjs');
const { createSecretStore } = require('./secrets.cjs');
const chatgpt = require('./chatgpt-oauth.cjs');
const egress = require('./provider-egress.cjs');

const ISSUER = 'https://auth.fixture.invalid';
const CODEX = 'https://codex.fixture.invalid';
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const idToken = `${b64({ alg: 'none' })}.${b64({ 'https://api.openai.com/auth': { chatgpt_account_id: 'acct-synthetic' } })}.sig`;
const reply = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const BOXES = [
  { id: 'core', tools: [{ type: 'function', function: { name: 'core_time' } }] },
  { id: 'diary', tools: [{ type: 'function', function: { name: 'diary_search' } }] },
];

async function setup(t, { flag = true, connected = true, refresh = 'ok' } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-chatgpt-egress-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'img-1'), Buffer.from('synthetic image bytes'));
  const upstream = { responses: [], queue: [] };
  const fakeOpenAI = async (url, init) => {
    url = String(url);
    if (url.endsWith('/deviceauth/usercode')) return reply({ device_auth_id: 'D', user_code: 'CODE-0000', interval: '1' });
    if (url.endsWith('/deviceauth/token')) return reply({ authorization_code: 'A', code_challenge: 'C', code_verifier: 'V' });
    if (url.endsWith('/oauth/token')) {
      if (String(init.body).includes('refresh_token') && refresh === 'invalid') return reply({ error: 'invalid_grant' }, 400);
      return reply({ access_token: String(init.body).includes('refresh_token') ? 'AT-new' : 'AT-first', refresh_token: 'RT', id_token: idToken, expires_in: 3600 });
    }
    if (url === `${CODEX}/responses`) {
      upstream.responses.push({ headers: init.headers, body: JSON.parse(init.body) });
      const next = upstream.queue.shift();
      if (next) return next();
      return new Response(['response.output_text.delta', 'response.completed'].map((type) => `data: ${JSON.stringify(type === 'response.completed' ? { type, response: { usage: { input_tokens: 3, output_tokens: 1 } } } : { type, delta: 'Hello from the fake' })}\n\n`).join(''), { status: 200 });
    }
    throw new Error('unexpected upstream ' + url);
  };
  const clock = { t: 1_800_000_000_000 };
  const oauth = chatgpt.createChatGptOAuth({ db: new Database(':memory:'), secrets: createSecretStore(dir, { env: {} }), fetchImpl: fakeOpenAI, now: () => clock.t, config: { issuer: ISSUER, codexBaseUrl: CODEX } });
  if (connected) {
    const l = await oauth.startDeviceLogin('user-a');
    clock.t += 1000;
    assert.equal((await oauth.pollDeviceLogin('user-a', l.loginId)).state, 'connected');
  }
  const row = chatgpt.providerRow();
  const localFetch = [];
  const run = async ({ body = {}, user = { id: 'user-a', role: 'member' }, workspaceUser = user.id, project = {} } = {}) => {
    const events = []; let refused = null; let offered = null;
    const res = new EventEmitter();
    res.writeHead = () => {}; res.write = (line) => { if (line.startsWith('data: ')) events.push(JSON.parse(line.slice(6))); };
    res.end = () => { res.writableEnded = true; res.emit('finish'); };
    const theProject = { id: 'fixture-project', model: 'gpt-synthetic', routing: 'manual', provider: 'chatgpt-oauth', toolboxes: ['core', 'diary'],
      assets: [{ id: 'img-1', name: 'receipt.png', mime: 'image/png' }], ...project };
    const { handleChat } = createChatHandler({
      // The default-provider fetch: must never carry a ChatGPT chat.
      fetch: async (url) => { localFetch.push(String(url)); throw new Error('the local fetch was used for an external provider'); },
      chatgptOAuth: oauth, chatgptEnabled: () => flag,
      modelManager: { enabled: true, health: async () => ({ ok: true, body: { all_models_loaded: [] } }) },
      reasoningEffort: require('./reasoning-effort.cjs'), authService: { audit() {}, diaryEnabled: () => true },
      crypto: require('node:crypto'), path, fs, HISTORY_CAP: 20, DEFAULT_PROVIDER_ID: 'default', createToolExchange,
      currentWorkspace: () => ({ userId: workspaceUser, dir, assetDir: () => dir }),
      getProject: (id) => (id === theProject.id || id === require('./diary-extras.cjs').PROJECT_ID ? { ...theProject, id } : null),
      skillsIndexFor: () => [], getProvider: (id) => (id === 'chatgpt-oauth' ? row : { id: 'default', baseUrl: 'http://fixture.invalid' }), providerHeaders: () => ({ 'Content-Type': 'application/json' }),
      autoRoles: () => null, visionDescriptions: new Map(), visionProbe: async () => { throw new Error('no vision probe for an external provider'); },
      chatSkillRouter: { select: async () => ({ loaded: [] }) }, oauthServerIds: () => new Set(), accountReady: () => true,
      chatToolRouter: { select: async (ids) => ({ ids, routed: false }) }, DEFAULT_TOOLBOXES: ['core'], CONNECTOR_BOXES: new Set(), connectedBoxes: () => [],
      toolPolicy: { mode: () => 'allow' }, requestScope: { getStore: () => ({ authn: { user } }) },
      resolveTools: (p, _m, blocked) => ({ tools: BOXES.filter((b) => p.toolboxes.includes(b.id)).flatMap((b) => b.tools).filter((x) => !blocked(x.function.name)), dropped: [] }),
      isWriteTool: () => false, rag: { filesContext: async () => null }, prefill: { recordSample() {} }, reduceToolResult: () => ({ text: 'reduced' }), diaryExtras: require('./diary-extras.cjs'),
      DIARY_BASE: 'http://fixture.invalid', TOOL_RESULT_CAP: 8000, json: (_res, status, b) => { refused = { status, body: b }; }, saveChats() {}, endpointApproved: () => false, diaryHeaders: () => ({}),
      lastLoadedModel: () => null, classifyFastOrSmart: async () => 'fast', servedCatalogue: async () => [], modelsInstalled: async () => [], missingRoles: () => [], staleRolesError: () => null,
      allToolboxes: () => BOXES, executeToolCall: async () => 'unused', chatWideApproved: () => false, awaitApproval: async () => 'deny', recordUsage() {}, recordToolUse() {},
    });
    await handleChat({}, res, { projectId: 'fixture-project', chatId: 'fixture-chat', message: 'synthetic question', ...body }, { user });
    const sent = upstream.responses.at(-1);
    if (sent) offered = (sent.body.tools || []).map((x) => x.name);
    return { events, refused, offered, sent };
  };
  return { run, upstream, localFetch, oauth };
}

test('flag off: a chat pinned to the ChatGPT provider is refused before anything is sent', { timeout: 20000 }, async (t) => {
  const f = await setup(t, { flag: false });
  const r = await f.run();
  assert.equal(r.refused.status, 409);
  assert.match(r.refused.body.error, /turned off/);
  assert.equal(f.upstream.responses.length, 0);
  assert.deepEqual(f.localFetch, []);
});

test('flag on: the chat streams through the adapter with the OAuth bearer; Diary tools and images stay home', { timeout: 20000 }, async (t) => {
  const f = await setup(t);
  const r = await f.run();
  assert.equal(r.refused, null, JSON.stringify(r.refused));
  assert.deepEqual(f.localFetch, [], 'the default provider fetch was not used');
  assert.equal(r.sent.headers.authorization, 'Bearer AT-first');
  assert.equal(r.sent.headers['chatgpt-account-id'], 'acct-synthetic');
  assert.deepEqual(r.offered, ['core_time'], 'the private Diary toolbox is not offered to an external provider');
  assert.equal(JSON.stringify(r.sent.body).includes('input_image'), false, 'project images are not attached');
  assert.equal(JSON.stringify(r.sent.body).includes('synthetic image bytes'), false);
  assert.ok(r.events.some((e) => e.type === 'warning' && /never sent to ChatGPT automatically/.test(e.text)));
  assert.equal(r.events.filter((e) => e.type === 'delta').map((e) => e.text).join(''), 'Hello from the fake');
  assert.ok(r.events.some((e) => e.type === 'done'));
  const usage = r.events.filter((e) => e.type === 'usage').at(-1);
  assert.equal(usage.promptTokens, 3);
});

test('Diary text never goes to an external provider: Diary extras on the ChatGPT provider are refused', { timeout: 20000 }, async (t) => {
  const f = await setup(t);
  const r = await f.run({ body: { spaceId: 'diary-extras', extrasEnabled: true, sessionId: 's1', message: 'Synthetic diary line' } });
  assert.equal(r.refused.status, 409);
  assert.match(r.refused.body.error, /Diary text is never sent to an external provider/);
  assert.equal(f.upstream.responses.length, 0);
});

test('a connection is its owner’s: another account, or a mismatched workspace, cannot use it', { timeout: 20000 }, async (t) => {
  const f = await setup(t);
  const other = await f.run({ user: { id: 'user-b', role: 'member' } });
  assert.equal(other.refused.status, 409, 'user B has no ChatGPT connection of their own');
  assert.match(other.refused.body.error, /not connected/);
  const mixed = await f.run({ user: { id: 'user-b', role: 'admin' }, workspaceUser: 'user-a' });
  assert.equal(mixed.refused.status, 403);
  const shared = await f.run({ project: {} });
  assert.equal(shared.refused, null);
  assert.equal(f.upstream.responses.length, 1, 'only the owner’s own request went out');
});

test('not connected, or reconnect needed, is said plainly; a refresh refused mid-chat surfaces "Reconnect needed"', { timeout: 20000 }, async (t) => {
  const none = await setup(t, { connected: false });
  assert.match((await none.run()).refused.body.error, /ChatGPT is not connected/);

  const f = await setup(t, { refresh: 'invalid' });
  f.upstream.queue.push(() => reply({ detail: 'expired' }, 401));
  const r = await f.run();
  assert.equal(r.refused, null);
  const error = r.events.find((e) => e.type === 'error');
  assert.match(error.text, /^Reconnect needed/);
  assert.equal(f.oauth.status('user-a').state, 'reconnect');
  const next = await f.run();
  assert.match(next.refused.body.error, /^Reconnect needed/);
});

test('the feature is off by default and only an operator env var or an administrator turns it on', () => {
  const { createFeatures } = require('./features.cjs');
  assert.equal(createFeatures({ env: {} }).enabled('chatgptOAuth'), false);
  assert.equal(createFeatures({ env: {} }).flags().chatgptOAuth, false);
  assert.equal(createFeatures({ env: { NOEVIA_FEATURE_CHATGPT_OAUTH: 'true' } }).enabled('chatgptOAuth'), true);
  const saved = new Map();
  const features = createFeatures({ env: {}, store: { get: (k) => saved.get(k), set: (k, v) => saved.set(k, v) } });
  features.set('chatgptOAuth', true, 'admin-id');
  assert.equal(features.enabled('chatgptOAuth'), true);
});

test('provider-egress rules in isolation', () => {
  const row = chatgpt.providerRow();
  assert.equal(egress.isExternalProvider(row), true);
  assert.equal(egress.isExternalProvider({ id: 'prov-1', baseUrl: 'https://openrouter.ai/api/v1' }), false, 'custom endpoints keep their behaviour');
  assert.equal(egress.isExternalProvider({ id: 'default' }), false);
  assert.match(egress.egressRefusal({ provider: row, spaceId: 'diary' }), /Diary text/);
  assert.match(egress.egressRefusal({ provider: row, projectId: 'cowork-diary-extras', diaryProjectId: 'cowork-diary-extras' }), /Diary text/);
  assert.equal(egress.egressRefusal({ provider: row, spaceId: 'free' }), null);
  assert.equal(egress.egressRefusal({ provider: { id: 'default' }, spaceId: 'diary-extras' }), null);
  const boxes = ['core', 'diary', 'web-search'];
  assert.deepEqual(egress.stripPrivateToolboxes(boxes, row), ['diary']);
  assert.deepEqual(boxes, ['core', 'web-search']);
  const local = ['core', 'diary'];
  assert.deepEqual(egress.stripPrivateToolboxes(local, { id: 'default' }), []);
  assert.deepEqual(local, ['core', 'diary']);
});
