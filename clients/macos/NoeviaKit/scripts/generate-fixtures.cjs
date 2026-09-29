#!/usr/bin/env node
'use strict';
// Regenerates NoeviaKit's JSON test fixtures by running the core's REAL route factories with
// synthetic inputs, so the Swift decoders are tested against what the server actually writes.
// No network, no database, no real account or Diary data. Run from anywhere:
//   node clients/macos/NoeviaKit/scripts/generate-fixtures.cjs
// The password sign-in body cannot be produced this way (auth.cjs needs better-sqlite3 and
// argon2), so auth-login-password__auth.cjs-passwordLogin.json is written by hand below from
// auth.cjs passwordLogin()/publicUser()/issueSession(). The device sign-in bodies (#555) run the
// real device-auth.cjs on node:sqlite (Node 22.5 or later); see deviceFixtures().

const fs = require('node:fs');
const path = require('node:path');
const { Readable } = require('node:stream');

const repo = path.resolve(__dirname, '../../../..');
const server = path.join(repo, 'apps/web/server');
const out = path.resolve(__dirname, '../Tests/NoeviaKitTests/Fixtures');

const captured = [];
const json = (_res, status, body) => { captured.push({ status, body }); return true; };
const take = () => captured.pop();
const write = (name, value) => fs.writeFileSync(path.join(out, name), JSON.stringify(value, null, 2) + '\n');
const request = (method) => Object.assign(Readable.from([]), { method, headers: {} });

async function main() {
  // GET /api/ready: routes/health.cjs createReadyRoutes.
  const { createReadyRoutes } = require(path.join(server, 'routes/health.cjs'));
  await createReadyRoutes({ json, isReady: () => true, version: '0123abc' })(request('GET'), {}, { path: '/api/ready' });
  write('api-ready__routes-health.cjs.json', take().body);
  await createReadyRoutes({ json, isReady: () => false, version: '0123abc' })(request('GET'), {}, { path: '/api/ready' });
  write('api-ready-starting__routes-health.cjs.json', take().body);

  // A synthetic publicUser() (auth.cjs) for the signed-in account.
  const user = { id: '7b0c2f6e-1111-4a4a-9c9c-000000000001', username: 'synthetic', displayName: 'Synthetic Owner', role: 'member', disabled: false, diaryEnabled: false, onboarded: true };

  // GET /api/auth/session: routes/auth.cjs createAuthRoutes().account.
  const { createAuthRoutes } = require(path.join(server, 'routes/auth.cjs'));
  const authRoutes = createAuthRoutes({ json, authResult: () => true, readJson: async () => ({}), authService: {}, publicAuthRoutes: new Set(), env: {} });
  const sessionReq = request('GET');
  sessionReq.headers.cookie = 'cowork_session=synthetic-session-token; cowork_csrf=synthetic-csrf-token';
  await authRoutes.account(sessionReq, {}, { path: '/api/auth/session', authn: { user, session: {}, legacy: false } });
  write('auth-session__routes-auth.cjs.json', take().body);

  // POST /api/auth/login/password 200: auth.cjs passwordLogin() returns
  // { user: publicUser(row), csrfToken: issueSession(req, res, row) }.
  write('auth-login-password__auth.cjs-passwordLogin.json', { user, csrfToken: 'synthetic-csrf-token' });

  // GET /api/workspace: routes/chat-lists.cjs. Projects are stored as projects.cjs createProject()
  // writes them. The internal Diary and chat-attachment projects and the non-object chat entry
  // are included on purpose: the real route filters and sanitizes them.
  const now = 1790000000000;
  const projects = [
    {
      icon: 'book', color: '#3a6ea5',
      id: 'proj-1790000000000-abc123', name: 'Synthetic research', goal: 'A synthetic goal', instructions: 'Answer briefly.',
      pinned: true, archived: false, sourceFolders: ['Noevia/Synthetic research'], memories: [],
      files: [{ name: 'notes.md', content: 'synthetic file body' }],
      model: 'synthetic-model', provider: undefined, reasoningEffort: undefined, routing: 'auto', modes: ['chat', 'code'],
      toolboxes: ['core'], projectFolder: 'Noevia/Synthetic research',
      chats: [
        { id: 'chat-a', title: 'First question', updatedAt: now - 5000, preview: 'What is…', pinned: true },
        { id: 'chat-b' },
        'chat-orphan',
      ],
      createdAt: now - 86400000, updatedAt: now,
    },
    {
      id: 'proj-legacy', name: 'Legacy project', goal: '', instructions: '', memories: [], files: [], chats: [],
    },
    { id: 'cowork-diary-extras', name: 'Diary', chats: [] },
    { id: 'cowork-chat-context-xyz', name: 'Chat attachments xyz', chats: [] },
  ];
  const freeChats = [
    { id: 'free-1', title: 'A free chat', updatedAt: now - 1000, preview: 'hello', pinned: false, archived: false },
    { id: 'free-2', title: 'A Cowork task', updatedAt: now - 2000, preview: '', pinned: false, archived: true, mode: 'cowork' },
  ];
  const { createChatListRoutes } = require(path.join(server, 'routes/chat-lists.cjs'));
  const { internalProject } = require(path.join(server, 'diary-extras.cjs'));
  const listRoutes = createChatListRoutes({
    json, readBody: async () => '', currentWorkspace: () => ({ dir: path.join(out, '.no-such-workspace') }),
    PROJECTS: projects, FREE_CHATS: freeChats, diaryExtras: { internalProject }, crypto: require('node:crypto'),
    STORED_HISTORY_BYTES: 0, STORED_HISTORY_CAP: 0, chatLists: () => ({ freeChats, projects }), removeChat: () => false,
    store: { sanitizeChats: (chats) => (chats || []).filter((c) => c && typeof c === 'object' && typeof c.id === 'string') }, // projects.cjs sanitizeChats()
  });
  await listRoutes(request('GET'), {}, { path: '/api/workspace', authn: { user } });
  write('workspace__routes-chat-lists.cjs.json', JSON.parse(JSON.stringify(take().body)));

  await deviceFixtures(user);

  // Error bodies: http.cjs unauthorized() and index.cjs's CSRF gate.
  write('error-unauthorized__http.cjs.json', { error: 'unauthorized' });
  write('error-csrf__index.cjs.json', { error: 'invalid CSRF token' });
  write('error-signin__auth.cjs-passwordLogin.json', { error: 'sign-in failed' });
  console.log(`fixtures written to ${path.relative(repo, out)}`);
}

// Native-client sign-in (#555). The bodies come from the REAL device-auth.cjs running on an
// in-memory node:sqlite database (a small shim supplies better-sqlite3's transaction()). Only the
// random values (device code, user code, tokens) are replaced with fixed synthetic ones after
// their shape is checked, so re-running produces identical files.
async function deviceFixtures(user) {
  const { DatabaseSync } = require('node:sqlite');
  const device = require(path.join(server, 'device-auth.cjs'));
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON; CREATE TABLE users(id TEXT PRIMARY KEY, disabled_at INTEGER);');
  db.transaction = (fn) => (...args) => {
    db.exec('BEGIN');
    try { const result = fn(...args); db.exec('COMMIT'); return result; } catch (e) { db.exec('ROLLBACK'); throw e; }
  };
  db.prepare('INSERT INTO users(id) VALUES(?)').run(user.id);
  let clock = 1790000000000;
  const auth = device.createDeviceAuth({
    db, audit: () => {}, publicUser: () => user, rate: { rateLimited: () => false },
    clientAddress: () => '192.168.1.20', origin: () => 'https://noevia.example.test', now: () => clock,
  });
  const req = { headers: { 'user-agent': 'NoeviaKit/0.1 (macOS)' } };
  const expect = (cond, what) => { if (!cond) throw new Error(`unexpected device-auth shape: ${what}`); };

  const started = auth.start(req, { client_name: 'Synthetic Mac' });
  expect(started.status === 200 && /^[A-Za-z0-9_-]{43}$/.test(started.body.device_code) && /^[A-Z]{4}-[A-Z]{4}$/.test(started.body.user_code), 'start');
  const pending = auth.token(req, { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.body.device_code });
  clock += 1000;
  const slow = auth.token(req, { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.body.device_code });
  expect(pending.body.error === 'authorization_pending' && slow.body.error === 'slow_down', 'polling');
  auth.decide(user.id, started.body.user_code, true);
  const issued = auth.token(req, { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.body.device_code });
  expect(issued.status === 200 && issued.body.access_token.startsWith('nva_') && issued.body.refresh_token.startsWith('nvr_'), 'token');
  const rotated = auth.token(req, { grant_type: 'refresh_token', refresh_token: issued.body.refresh_token });
  // Read before the reuse below, which (correctly) revokes the whole grant.
  const authn = auth.authenticate({ headers: { authorization: `Bearer ${rotated.body.access_token}` } });
  const reused = auth.token(req, { grant_type: 'refresh_token', refresh_token: issued.body.refresh_token });
  expect(rotated.status === 200 && reused.body.error === 'invalid_grant', 'refresh');
  const denied = auth.start(req, { client_name: 'Synthetic Mac' });
  auth.decide(user.id, denied.body.user_code, false);
  const deniedPoll = auth.token(req, { grant_type: device.DEVICE_GRANT_TYPE, device_code: denied.body.device_code });
  const late = auth.start(req, { client_name: 'Synthetic Mac' });
  clock += device.DEVICE_CODE_TTL_MS;
  const expired = auth.token(req, { grant_type: device.DEVICE_GRANT_TYPE, device_code: late.body.device_code });

  const code = 'BCDF-GHJK';
  write('device-code__device-auth.cjs-start.json', {
    ...started.body, device_code: 'synthetic-device-code', user_code: code,
    verification_uri_complete: started.body.verification_uri_complete.replace(started.body.user_code, code),
  });
  write('device-token__device-auth.cjs-token.json', { ...issued.body, access_token: 'nva_synthetic-access-1', refresh_token: 'nvr_synthetic-refresh-1' });
  write('device-token-rotated__device-auth.cjs-token.json', { ...rotated.body, access_token: 'nva_synthetic-access-2', refresh_token: 'nvr_synthetic-refresh-2' });
  write('device-pending__device-auth.cjs-token.json', pending.body);
  write('device-slow-down__device-auth.cjs-token.json', slow.body);
  write('device-denied__device-auth.cjs-token.json', deniedPoll.body);
  write('device-expired__device-auth.cjs-token.json', expired.body);
  write('device-refresh-reuse__device-auth.cjs-token.json', reused.body);

  // GET /api/auth/session for a device token: routes/device-auth.cjs createDeviceAuthRoutes().account.
  expect(authn && authn.device, 'authenticate');
  const { createDeviceAuthRoutes } = require(path.join(server, 'routes/device-auth.cjs'));
  const routes = createDeviceAuthRoutes({ json, authResult: () => true, readJson: async () => ({}), deviceAuth: auth, authService: {}, enabled: () => true });
  await routes.account(request('GET'), {}, { path: '/api/auth/session', authn: { ...authn, device: { ...authn.device, id: 'synthetic-device-id' } } });
  write('auth-session-device__routes-device-auth.cjs.json', take().body);
  // index.cjs's browser-only gate for a device token.
  write('error-browser-session__index.cjs.json', { error: 'This needs a signed-in browser session.', code: 'browser_session_required' });
  db.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
