#!/usr/bin/env node
'use strict';
// Regenerates NoeviaKit's JSON test fixtures by running the core's REAL route factories with
// synthetic inputs, so the Swift decoders are tested against what the server actually writes.
// No network, no database, no real account or Diary data. Run from anywhere:
//   node clients/macos/NoeviaKit/scripts/generate-fixtures.cjs
// The password sign-in body cannot be produced this way (auth.cjs needs better-sqlite3 and
// argon2), so auth-login-password__auth.cjs-passwordLogin.json is written by hand below from
// auth.cjs passwordLogin()/publicUser()/issueSession().

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

  // Error bodies: http.cjs unauthorized() and index.cjs's CSRF gate.
  write('error-unauthorized__http.cjs.json', { error: 'unauthorized' });
  write('error-csrf__index.cjs.json', { error: 'invalid CSRF token' });
  write('error-signin__auth.cjs-passwordLogin.json', { error: 'sign-in failed' });
  console.log(`fixtures written to ${path.relative(repo, out)}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
