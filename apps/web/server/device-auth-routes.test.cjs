'use strict';

// Native-client sign-in (#555) through the real router (index.cjs handleRequest), with the
// nativeClientAuth feature switched on by its environment variable BEFORE the server loads.
// Synthetic accounts only; no inference, Diary or storage service is reached.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Readable, Writable } = require('node:stream');
const test = require('node:test');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-device-auth-'));
process.env.UI_DATA_DIR = dataDir;
process.env.PUBLIC_ORIGIN = 'http://localhost';
process.env.LEGACY_AUTH_COMPAT = 'false';
process.env.NOEVIA_FEATURE_NATIVE_CLIENT_AUTH = 'true';

const originalWarn = console.warn;
console.warn = () => {};
const { handleRequest } = require('./index.cjs');
console.warn = originalWarn;

test.after(() => fs.rmSync(dataDir, { recursive: true, force: true }));

const ORIGIN = 'http://localhost';
const DEVICE_GRANT = 'urn:ietf:params:oauth:grant-type:device_code';
const PASSWORD = 'synthetic device password';

async function request(url, { method = 'GET', headers = {}, body, ip = '127.0.0.1' } = {}) {
  const payload = body === undefined ? '' : typeof body === 'string' ? body : JSON.stringify(body);
  const req = Readable.from(payload ? [payload] : []);
  req.url = url;
  req.method = method;
  req.headers = { host: 'localhost', ...(payload && typeof body !== 'string' ? { 'content-type': 'application/json' } : {}), ...headers };
  req.socket = { remoteAddress: ip };
  const chunks = [];
  const out = {};
  const res = new Writable({ write(chunk, _e, cb) { chunks.push(Buffer.from(chunk)); cb(); } });
  res.statusCode = 200;
  res.headersSent = false;
  res.setHeader = (k, v) => { out[k.toLowerCase()] = v; };
  res.writeHead = (status, h = {}) => { res.statusCode = status; res.headersSent = true; for (const [k, v] of Object.entries(h)) out[k.toLowerCase()] = v; return res; };
  const done = new Promise((resolve, reject) => { res.once('finish', resolve); res.once('error', reject); });
  await handleRequest(req, res);
  await done;
  const text = Buffer.concat(chunks).toString('utf8');
  let json = null; try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.statusCode, headers: out, text, json };
}

function sessionFrom(response) {
  const cookies = (response.headers['set-cookie'] || []).map((c) => c.split(';')[0]);
  const csrf = decodeURIComponent(cookies.find((c) => c.startsWith('cowork_csrf=')).split('=').slice(1).join('='));
  const cookie = cookies.join('; ');
  return {
    cookie, csrf,
    read: (url) => request(url, { headers: { cookie } }),
    write: (url, body, method = 'POST') => request(url, { method, body, headers: { cookie, origin: ORIGIN, 'x-csrf-token': csrf } }),
  };
}

const bearer = (token) => ({ authorization: `Bearer ${token}` });
const asDevice = (token, url, opts = {}) => request(url, { ...opts, headers: { ...bearer(token), ...(opts.headers || {}) } });

let admin; let member; let adminId; let memberId;

test.before(async () => {
  const setupCode = fs.readFileSync(path.join(dataDir, 'first-run-setup-code'), 'utf8').trim();
  const setup = await request('/api/setup/complete', { method: 'POST', headers: { origin: ORIGIN },
    body: { setupCode, publicOrigin: ORIGIN, username: 'adminqa', displayName: 'Synthetic admin', password: PASSWORD } });
  assert.equal(setup.status, 201);
  admin = sessionFrom(setup);
  adminId = setup.json.user.id;
  const invite = await admin.write('/api/admin/invitations', { role: 'member' });
  const accepted = await request('/api/auth/invitations/accept', { method: 'POST', headers: { origin: ORIGIN },
    body: { token: invite.json.token, username: 'memberqa', displayName: 'Synthetic member', password: PASSWORD } });
  assert.equal(accepted.status, 201);
  member = sessionFrom(accepted);
  memberId = accepted.json.user.id;
  // Each account gets one free chat so a token's view of "its" workspace is observable.
  assert.equal((await admin.write('/api/freechats', { chats: [{ id: 'admin-chat', title: 'Admin only' }] })).status, 200);
  assert.equal((await member.write('/api/freechats', { chats: [{ id: 'member-chat', title: 'Member only' }] })).status, 200);
});

async function startFlow(clientName = 'NoeviaKit test Mac', ip = '10.0.0.5') {
  const started = await request('/api/auth/device/code', { method: 'POST', body: { client_name: clientName }, ip });
  assert.equal(started.status, 200, started.text);
  return started.json;
}

async function signInDevice(session, clientName, ip) {
  const flow = await startFlow(clientName, ip);
  assert.equal((await session.write('/api/auth/device/approve', { user_code: flow.user_code, approve: true })).status, 200);
  const token = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: DEVICE_GRANT, device_code: flow.device_code }, ip });
  assert.equal(token.status, 200, token.text);
  return token.json;
}

test('full flow: start, approve in the browser, token, API call, refresh with rotation, reuse detection, revoke', async () => {
  const flow = await startFlow();
  assert.match(flow.user_code, /^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/);
  assert.equal(flow.verification_uri, 'http://localhost/device');
  assert.equal(flow.verification_uri_complete, `http://localhost/device?code=${flow.user_code}`);
  assert.equal(flow.expires_in, 600);
  assert.equal(flow.interval, 5);
  assert.ok(Buffer.from(flow.device_code, 'base64url').length >= 32, 'device code carries at least 256 bits');

  const pending = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: DEVICE_GRANT, device_code: flow.device_code } });
  assert.equal(pending.status, 400);
  assert.equal(pending.json.error, 'authorization_pending');
  assert.equal(pending.headers['cache-control'], 'no-store');

  // The approval screen's lookup shows the client name and the code; dashes and case do not matter.
  const lookup = await admin.write('/api/auth/device/lookup', { user_code: flow.user_code.toLowerCase().replace('-', ' ') });
  assert.equal(lookup.status, 200);
  assert.equal(lookup.json.clientName, 'NoeviaKit test Mac');
  assert.equal(lookup.json.userCode, flow.user_code);
  assert.equal(lookup.json.ip, null, 'TRUST_PROXY is off here: the socket address is not shown');

  // Approval without CSRF is refused like any other signed-in write.
  const noCsrf = await request('/api/auth/device/approve', { method: 'POST', body: { user_code: flow.user_code, approve: true }, headers: { cookie: admin.cookie, origin: ORIGIN } });
  assert.equal(noCsrf.status, 403);
  assert.equal((await admin.write('/api/auth/device/approve', { user_code: flow.user_code, approve: true })).status, 200);

  const issued = await request('/api/auth/device/token', { method: 'POST', body: `grant_type=${encodeURIComponent(DEVICE_GRANT)}&device_code=${flow.device_code}`, headers: { 'content-type': 'application/x-www-form-urlencoded' } });
  assert.equal(issued.status, 200, issued.text);
  assert.equal(issued.headers['cache-control'], 'no-store');
  const first = issued.json;
  assert.equal(first.token_type, 'Bearer');
  assert.equal(first.expires_in, 3600);
  assert.match(first.access_token, /^nva_[A-Za-z0-9_-]{43}$/);
  assert.match(first.refresh_token, /^nvr_[A-Za-z0-9_-]{43}$/);
  // The device code is single use.
  const again = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: DEVICE_GRANT, device_code: flow.device_code } });
  assert.equal(again.json.error, 'invalid_grant');

  // Only hashes are stored.
  const db = new (require('better-sqlite3'))(path.join(dataDir, 'cowork.db'), { readonly: true });
  try {
    const dump = JSON.stringify(db.prepare('SELECT * FROM device_tokens').all()) + JSON.stringify(db.prepare('SELECT * FROM device_grants').all());
    assert.ok(!dump.includes(first.access_token.slice(4)) && !dump.includes(first.refresh_token.slice(4)), 'raw tokens are never stored');
  } finally { db.close(); }

  // The token works for the versioned API as the same account, without CSRF.
  const session = await asDevice(first.access_token, '/api/auth/session');
  assert.equal(session.status, 200);
  assert.equal(session.headers['x-noevia-api'], '1');
  assert.equal(session.json.user.id, adminId);
  assert.equal(session.json.user.role, 'member', 'a device token never acts as an administrator');
  assert.equal(session.json.accountRole, 'admin');
  assert.equal(session.json.csrfToken, null);
  assert.equal(session.json.device.clientName, 'NoeviaKit test Mac');
  const workspace = await asDevice(first.access_token, '/api/workspace');
  assert.equal(workspace.status, 200);
  assert.deepEqual(workspace.json.freeChats.map((c) => c.id), ['admin-chat']);
  const wrote = await asDevice(first.access_token, '/api/freechats', { method: 'POST', body: { chats: [{ id: 'admin-chat', title: 'Renamed by device' }] } });
  assert.equal(wrote.status, 200, 'writes need no CSRF header with a bearer token');

  // Refresh rotates both tokens; the previous access token stops working at once.
  const refreshed = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: first.refresh_token } });
  assert.equal(refreshed.status, 200, refreshed.text);
  const second = refreshed.json;
  assert.notEqual(second.access_token, first.access_token);
  assert.notEqual(second.refresh_token, first.refresh_token);
  assert.equal((await asDevice(first.access_token, '/api/workspace')).status, 401);
  assert.equal((await asDevice(second.access_token, '/api/workspace')).status, 200);

  // Once the successor has been used, presenting the spent refresh token again revokes the chain.
  const successor = (await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: second.refresh_token } })).json;
  assert.ok(successor.access_token);
  const reuse = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: first.refresh_token } });
  assert.equal(reuse.status, 400);
  assert.equal(reuse.json.error, 'invalid_grant');
  assert.equal((await asDevice(successor.access_token, '/api/workspace')).status, 401);
  const chainDead = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: successor.refresh_token } });
  assert.equal(chainDead.json.error, 'invalid_grant');

  // A fresh device, revoked from Settings, is refused on its very next request.
  const third = await signInDevice(admin, 'Revoke me', '10.0.0.6');
  assert.equal((await asDevice(third.access_token, '/api/workspace')).status, 200);
  const listed = await admin.read('/api/auth/devices');
  assert.equal(listed.status, 200);
  const row = listed.json.devices.find((d) => d.clientName === 'Revoke me');
  assert.ok(row && row.lastUsedAt && row.createdAt, 'the list carries last-used time');
  assert.equal((await admin.write(`/api/auth/devices/${row.id}`, undefined, 'DELETE')).status, 200);
  assert.equal((await asDevice(third.access_token, '/api/workspace')).status, 401);
  assert.equal((await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: third.refresh_token } })).json.error, 'invalid_grant');
  assert.equal((await admin.read('/api/auth/devices')).json.devices.some((d) => d.id === row.id), false);

  // Audit entries for approve, refresh reuse and revoke, in the existing audit_events table.
  const audit = new (require('better-sqlite3'))(path.join(dataDir, 'cowork.db'), { readonly: true });
  try {
    const actions = audit.prepare("SELECT action, target_user_id FROM audit_events WHERE action LIKE 'device.%'").all();
    for (const action of ['device.approve', 'device.refresh_reuse', 'device.revoke']) {
      assert.ok(actions.some((a) => a.action === action && a.target_user_id === adminId), `audited ${action}`);
    }
  } finally { audit.close(); }
});

test('a device can sign itself out, and a denied request never yields a token', async () => {
  const tokens = await signInDevice(member, 'Member laptop', '10.0.1.1');
  assert.equal((await asDevice(tokens.access_token, '/api/auth/logout', { method: 'POST', body: {} })).status, 200);
  assert.equal((await asDevice(tokens.access_token, '/api/workspace')).status, 401);

  const flow = await startFlow('Unwanted', '10.0.1.2');
  const denied = await member.write('/api/auth/device/approve', { user_code: flow.user_code, approve: false });
  assert.equal(denied.status, 200);
  assert.equal(denied.json.approved, false);
  const poll = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: DEVICE_GRANT, device_code: flow.device_code }, ip: '10.0.1.2' });
  assert.equal(poll.json.error, 'access_denied');
  // A decided code cannot be decided again.
  assert.equal((await member.write('/api/auth/device/approve', { user_code: flow.user_code, approve: true })).status, 404);
});

test('tenant isolation: a token sees only its account, and nobody else can list or revoke it', async () => {
  const memberTokens = await signInDevice(member, 'Member phone', '10.0.2.1');
  const view = await asDevice(memberTokens.access_token, '/api/workspace');
  assert.deepEqual(view.json.freeChats.map((c) => c.id), ['member-chat']);
  const memberDevice = (await member.read('/api/auth/devices')).json.devices.find((d) => d.clientName === 'Member phone');
  assert.ok(memberDevice);
  assert.equal((await admin.read('/api/auth/devices')).json.devices.some((d) => d.id === memberDevice.id), false);
  // Even an administrator cannot revoke another account's device through this route.
  assert.equal((await admin.write(`/api/auth/devices/${memberDevice.id}`, undefined, 'DELETE')).status, 404);
  assert.equal((await asDevice(memberTokens.access_token, '/api/workspace')).status, 200);
  // A code approved by the member mints the member's token, whoever started it.
  const session = await asDevice(memberTokens.access_token, '/api/auth/session');
  assert.equal(session.json.user.id, memberId);
  // Disabling the account revokes its devices, like its sessions.
  assert.equal((await admin.write(`/api/admin/users/${memberId}/disabled`, { disabled: true }, 'PUT')).status, 200);
  assert.equal((await asDevice(memberTokens.access_token, '/api/workspace')).status, 401);
  assert.equal((await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: memberTokens.refresh_token } })).json.error, 'invalid_grant');
  assert.equal((await admin.write(`/api/admin/users/${memberId}/disabled`, { disabled: false }, 'PUT')).status, 200);
  assert.equal((await asDevice(memberTokens.access_token, '/api/workspace')).status, 401, 're-enabling does not revive a revoked device');
});

test('scope limits: a device token never reaches administration or account security', async () => {
  const tokens = await signInDevice(admin, 'Scoped Mac', '10.0.3.1');
  const refused = [
    ['GET', '/api/admin/users'],
    ['POST', '/api/admin/invitations', { role: 'admin' }],
    ['GET', '/api/admin/features'],
    ['PUT', '/api/admin/features/nativeClientAuth', { enabled: false }],
    ['POST', '/api/auth/passkeys/register/options', {}],
    ['DELETE', '/api/auth/passkeys/some-id'],
    ['DELETE', '/api/auth/sessions/some-id'],
    ['GET', '/api/profile'],
    ['GET', '/api/profile/app-passwords'],
    ['POST', '/api/profile/app-passwords', { name: 'x', scope: 'lan' }],
    ['POST', '/api/profile/diary-connectors', {}],
    ['PUT', '/api/profile/sharing', {}],
    ['GET', '/api/auth/devices'],
    ['DELETE', `/api/auth/devices/${'a'.repeat(32)}`],
    ['POST', '/api/auth/device/lookup', { user_code: 'BCDF-GHJK' }],
    ['POST', '/api/auth/device/approve', { user_code: 'BCDF-GHJK', approve: true }],
    ['PUT', '/api/integrations/storage', { kind: 'local' }],
    ['POST', '/api/integrations/storage/nextcloud/start', {}],
  ];
  for (const [method, url, body] of refused) {
    const r = await asDevice(tokens.access_token, url, { method, body });
    assert.equal(r.status, 403, `${method} ${url} -> ${r.status}`);
    assert.equal(r.json.code, 'browser_session_required', `${method} ${url}`);
  }
  // Role-gated routes outside /api/admin see a member, too.
  assert.equal((await asDevice(tokens.access_token, '/api/reasoning-settings', { method: 'PUT', body: { default: 'low' } })).status, 403);
  // The admin's own browser session can still do all of it.
  assert.equal((await admin.read('/api/admin/users')).status, 200);
  assert.equal((await admin.read('/api/profile')).status, 200);
});

test('bearer tokens cannot carry cookies, and a cookie session cannot borrow a bearer', async () => {
  const tokens = await signInDevice(admin, 'Mixed credentials', '10.0.4.1');
  const both = await request('/api/workspace', { headers: { ...bearer(tokens.access_token), cookie: admin.cookie } });
  assert.equal(both.status, 400);
  assert.equal(both.json.code, 'ambiguous_credentials');
  // A cookie-authenticated write with a bearer attached is refused before any route runs, so a
  // bearer can never stand in for the CSRF header.
  const smuggled = await request('/api/freechats', { method: 'POST', body: { chats: [] }, headers: { ...bearer(tokens.access_token), cookie: admin.cookie, origin: ORIGIN } });
  assert.equal(smuggled.status, 400);
  // A csrf cookie alone alongside a bearer is refused too.
  assert.equal((await request('/api/workspace', { headers: { ...bearer(tokens.access_token), cookie: `cowork_csrf=${admin.csrf}` } })).status, 400);
  // Unknown, malformed and query-string tokens are 401.
  assert.equal((await asDevice('nva_not-a-real-token', '/api/workspace')).status, 401);
  assert.equal((await asDevice(tokens.refresh_token, '/api/workspace')).status, 401, 'a refresh token is not an access token');
  assert.equal((await request(`/api/workspace?access_token=${tokens.access_token}`)).status, 401);
  // A foreign browser origin is refused on the public endpoints.
  assert.equal((await request('/api/auth/device/code', { method: 'POST', body: { client_name: 'x' }, headers: { origin: 'https://evil.example' } })).status, 403);
  // The approval page is served while the feature is on.
  const page = await request('/device');
  assert.notEqual(page.status, 404);
});

test('requests are validated and rate limited', async () => {
  assert.equal((await request('/api/auth/device/code', { method: 'POST', body: {}, ip: '10.0.5.1' })).json.error, 'invalid_request');
  assert.equal((await request('/api/auth/device/code', { method: 'POST', body: { client_name: '‮\u0000  ' }, ip: '10.0.5.1' })).json.error, 'invalid_request');
  assert.equal((await request('/api/auth/device/code', { method: 'GET' })).status, 405);
  assert.equal((await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'password' } })).json.error, 'unsupported_grant_type');
  assert.equal((await request('/api/auth/device/token', { method: 'POST', body: 'not json' })).json.error, 'invalid_request');
  // Behind the tunnel every request shares one address (TRUST_PROXY off, as here), so starts are
  // limited per client name, not per address: ten per name per 15 minutes, other names unaffected.
  const ip = '10.0.6.1';
  for (let i = 0; i < 10; i++) assert.equal((await request('/api/auth/device/code', { method: 'POST', body: { client_name: 'Burst Mac' }, ip })).status, 200);
  const limited = await request('/api/auth/device/code', { method: 'POST', body: { client_name: 'Burst Mac' }, ip });
  assert.equal(limited.status, 429);
  assert.equal((await request('/api/auth/device/code', { method: 'POST', body: { client_name: 'Another app' }, ip })).status, 200, 'the same address can still start other sign-ins');
});

test('F1: junk token requests from the shared address never lock out a real device', async () => {
  const tokens = await signInDevice(admin, 'Flooded Mac', '10.0.7.1');
  const ip = '10.0.7.9'; // the attacker shares the address of every other client behind the tunnel
  let unknownLimited = 0;
  for (let i = 0; i < 800; i++) { // well over 241, and 400 unknown credentials exceed their bucket
    const body = i % 4 === 0 ? { grant_type: 'password' }
      : i % 4 === 1 ? 'not json'
      : i % 4 === 2 ? { grant_type: 'refresh_token', refresh_token: `nvr_junk${i}` }
      : { grant_type: DEVICE_GRANT, device_code: `junk${i}` };
    const r = await request('/api/auth/device/token', { method: 'POST', body, ip });
    assert.ok([400, 429].includes(r.status), `junk request ${i} -> ${r.status}`);
    if (r.status === 429) unknownLimited++;
  }
  assert.ok(unknownLimited > 0, 'unknown credentials have their own, bounded bucket');
  const refreshed = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: tokens.refresh_token }, ip });
  assert.equal(refreshed.status, 200, refreshed.text);
  // A pending device's polls are not blocked by the flood either.
  const flow = await startFlow('Polling after flood', ip);
  const poll = await request('/api/auth/device/token', { method: 'POST', body: { grant_type: DEVICE_GRANT, device_code: flow.device_code }, ip });
  assert.equal(poll.json.error, 'authorization_pending');
});

test('F1: with TRUST_PROXY off the shared socket address is not shown as the requester', async () => {
  const flow = await startFlow('Addressless Mac', '10.0.8.1');
  const lookup = await admin.write('/api/auth/device/lookup', { user_code: flow.user_code });
  assert.equal(lookup.status, 200);
  assert.equal(lookup.json.ip, null);
  await admin.write('/api/auth/device/approve', { user_code: flow.user_code, approve: false });
});

test('F2: a device token cannot link connectors or change their tool policy', async () => {
  const tokens = await signInDevice(admin, 'Connector Mac', '10.0.9.1');
  for (const [method, url, body] of [
    ['POST', '/api/connectors/gdrive/connect', {}],
    ['POST', '/api/connectors/gdrive/disconnect', {}],
    ['PUT', '/api/connectors/gdrive/policy', { tools: ['drive_write'], mode: 'allow' }],
    ['PUT', '/api/connectors/gdrive/backup-copy', { enabled: true }],
    ['PUT', '/api/connectors/nextcloud/policy', { tools: [], mode: 'allow' }],
  ]) {
    const r = await asDevice(tokens.access_token, url, { method, body });
    assert.equal(r.status, 403, `${method} ${url} -> ${r.status}`);
    assert.equal(r.json.code, 'browser_session_required');
  }
  assert.notEqual((await asDevice(tokens.access_token, '/api/connectors')).status, 403, 'reading the connector list stays allowed');
});

test('F3: a retried refresh within the grace window succeeds; reuse after the successor is used revokes', async () => {
  const first = await signInDevice(admin, 'Retrying Mac', '10.0.10.1');
  const refresh = (token) => request('/api/auth/device/token', { method: 'POST', body: { grant_type: 'refresh_token', refresh_token: token } });
  const lost = await refresh(first.refresh_token); // the client never saw this answer
  assert.equal(lost.status, 200);
  const retried = await refresh(first.refresh_token);
  assert.equal(retried.status, 200, 'the previous refresh token is accepted while its successor is unused');
  assert.equal((await asDevice(retried.json.access_token, '/api/workspace')).status, 200);
  // The discarded successor is now an unknown credential: invalid_grant, or 429 once the F1 flood
  // above has filled the unknown-credential bucket. Either way it no longer works.
  const discarded = await refresh(lost.json.refresh_token);
  assert.ok([400, 429].includes(discarded.status) && discarded.json.error !== undefined && !discarded.json.access_token, 'the unused successor is replaced');
  assert.equal((await asDevice(retried.json.access_token, '/api/workspace')).status, 200, 'replacing an unused successor is not reuse');
  // Once the newest successor has been used, the old token is reuse and the device is revoked.
  const next = await refresh(retried.json.refresh_token);
  assert.equal(next.status, 200);
  assert.equal((await refresh(first.refresh_token)).json.error, 'invalid_grant');
  assert.equal((await asDevice(next.json.access_token, '/api/workspace')).status, 401);
});

// Last, because it uses up the administrator's lookup budget for the rest of the window.
test('code guessing in the browser is limited per account', async () => {
  let last;
  for (let i = 0; i < 21; i++) last = await admin.write('/api/auth/device/lookup', { user_code: 'BCDF-GHJK' });
  assert.equal(last.status, 429);
});
