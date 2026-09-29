'use strict';

// device-auth.cjs with a controllable clock: expiry, polling speed, rotation races and the
// browser-only path rules. Synthetic accounts in a throwaway auth database.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { createAuth, createRateLimiter } = require('./auth.cjs');
const device = require('./device-auth.cjs');

const ORIGIN = 'https://noevia.example.test';
const req = (ip = '10.1.0.1', extra = {}) => ({ headers: { origin: ORIGIN, 'user-agent': 'NoeviaKit/0.1 (macOS)', ...extra }, socket: { remoteAddress: ip } });
const res = () => ({ headers: {}, setHeader(k, v) { this.headers[k] = v; } });

async function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-device-unit-'));
  const warn = console.warn;
  console.warn = () => {}; // the first-run setup code is synthetic; keep it out of the output
  let auth;
  try { auth = createAuth({ dataDir: root, publicOrigin: ORIGIN }); } finally { console.warn = warn; }
  t.after(() => { auth.db.close(); fs.rmSync(root, { recursive: true, force: true }); });
  const setup = await auth.setup(req(), res(), { setupCode: fs.readFileSync(path.join(root, 'first-run-setup-code'), 'utf8').trim(), publicOrigin: ORIGIN, username: 'owner', password: 'synthetic unit password' });
  const clock = { t: 1_000_000 };
  const audits = [];
  const deviceAuth = device.createDeviceAuth({
    db: auth.db, publicUser: auth.publicUser, rate: createRateLimiter(), clientAddress: (r) => r.socket.remoteAddress,
    audit: (...a) => { audits.push(a); auth.audit(...a); }, origin: () => ORIGIN, now: () => clock.t,
  });
  return { auth, deviceAuth, clock, audits, userId: setup.body.user.id };
}

async function approved(f, name = 'Unit Mac') {
  const started = f.deviceAuth.start(req(), { client_name: name }).body;
  assert.equal(f.deviceAuth.decide(f.userId, started.user_code, true).status, 200);
  const tokens = f.deviceAuth.token(req(), { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.device_code });
  assert.equal(tokens.status, 200);
  return tokens.body;
}

const bearerReq = (token) => ({ headers: { authorization: `Bearer ${token}` } });

test('an unapproved device code expires after ten minutes and cannot be approved late', async (t) => {
  const f = await fixture(t);
  const started = f.deviceAuth.start(req(), { client_name: 'Slow Mac' }).body;
  f.clock.t += device.DEVICE_CODE_TTL_MS;
  assert.equal(f.deviceAuth.lookup(f.userId, started.user_code).status, 404);
  assert.equal(f.deviceAuth.decide(f.userId, started.user_code, true).status, 404);
  assert.equal(f.deviceAuth.token(req(), { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.device_code }).body.error, 'expired_token');
});

test('polling faster than the interval earns slow_down and a longer interval', async (t) => {
  const f = await fixture(t);
  const started = f.deviceAuth.start(req(), { client_name: 'Eager Mac' }).body;
  const poll = () => f.deviceAuth.token(req(), { grant_type: device.DEVICE_GRANT_TYPE, device_code: started.device_code }).body.error;
  assert.equal(poll(), 'authorization_pending');
  f.clock.t += 1000;
  assert.equal(poll(), 'slow_down');
  f.clock.t += device.POLL_INTERVAL_MS; // the interval is now 10 s, so 5 s later is still too fast
  assert.equal(poll(), 'slow_down');
  f.clock.t += 20_000;
  assert.equal(poll(), 'authorization_pending');
});

test('an access token expires after an hour; the refresh token still rotates', async (t) => {
  const f = await fixture(t);
  const tokens = await approved(f);
  assert.ok(f.deviceAuth.authenticate(bearerReq(tokens.access_token)));
  f.clock.t += device.ACCESS_TTL_MS;
  assert.equal(f.deviceAuth.authenticate(bearerReq(tokens.access_token)), null);
  const next = f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: tokens.refresh_token });
  assert.equal(next.status, 200);
  assert.ok(f.deviceAuth.authenticate(bearerReq(next.body.access_token)));
});

test('a grant idle for seven days, or older than thirty, needs a new approval', async (t) => {
  const f = await fixture(t);
  const idle = await approved(f, 'Idle Mac');
  f.clock.t += device.REFRESH_IDLE_MS;
  assert.equal(f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: idle.refresh_token }).body.error, 'invalid_grant');

  let tokens = await approved(f, 'Busy Mac');
  // Refreshing every six days keeps it alive, but only until the 30-day absolute limit.
  for (let day = 6; day < 30; day += 6) {
    f.clock.t += 6 * 24 * 60 * 60 * 1000;
    const r = f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: tokens.refresh_token });
    assert.equal(r.status, 200, `day ${day}`);
    tokens = r.body;
  }
  f.clock.t += 6 * 24 * 60 * 60 * 1000;
  assert.equal(f.deviceAuth.authenticate(bearerReq(tokens.access_token)), null);
  assert.equal(f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: tokens.refresh_token }).body.error, 'invalid_grant');
  assert.equal(f.deviceAuth.list(f.userId).length, 0);
});

test('reuse detection revokes the chain and is audited with the account as target', async (t) => {
  const f = await fixture(t);
  const tokens = await approved(f);
  const rotated = f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: tokens.refresh_token }).body;
  assert.equal(f.deviceAuth.token(req(), { grant_type: 'refresh_token', refresh_token: tokens.refresh_token }).body.error, 'invalid_grant');
  assert.equal(f.deviceAuth.authenticate(bearerReq(rotated.access_token)), null);
  assert.ok(f.audits.some(([action, , target]) => action === 'device.refresh_reuse' && target === f.userId));
});

test('a password reset revokes every device, like every session', async (t) => {
  const f = await fixture(t);
  const tokens = await approved(f);
  const recovery = f.auth.createRecovery(f.userId, f.userId);
  assert.equal(await f.auth.completeRecovery({ token: recovery.token, password: 'another synthetic password' }), true);
  assert.equal(f.deviceAuth.authenticate(bearerReq(tokens.access_token)), null);
});

test('user codes are unambiguous, normalised and hashed; client names are single-line and bounded', async (t) => {
  const f = await fixture(t);
  const started = f.deviceAuth.start(req(), { client_name: 'Name‮ with\ncontrols' + 'x'.repeat(100) }).body;
  assert.match(started.user_code, /^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/);
  const stored = f.auth.db.prepare('SELECT * FROM device_authorizations').get();
  assert.ok(!JSON.stringify(stored).includes(started.user_code.replace('-', '')));
  assert.ok(!JSON.stringify(stored).includes(started.device_code));
  assert.equal(stored.client_name.length, 60);
  assert.doesNotMatch(stored.client_name, /[‮\n]/);
  assert.equal(device.normalizeUserCode(' bcdf-ghjk '), 'BCDFGHJK');
  assert.equal(device.normalizeUserCode('BCDF-GHJA'), '', 'vowels are never part of a code');
  assert.equal(device.normalizeUserCode('BCDFGHJKL'), '');
});

test('browser-only paths match on segment boundaries, not on look-alike prefixes', () => {
  assert.equal(device.browserOnly('/api/admin'), true);
  assert.equal(device.browserOnly('/api/admin/users/x/disabled', 'PUT'), true);
  assert.equal(device.browserOnly('/api/administrator'), false);
  assert.equal(device.browserOnly('/api/profile'), true);
  assert.equal(device.browserOnly('/api/profile/appearance'), false);
  assert.equal(device.browserOnly('/api/integrations/storage', 'GET'), false);
  assert.equal(device.browserOnly('/api/integrations/storage', 'PUT'), true);
  assert.equal(device.browserOnly('/api/integrations/storage/files/a.md', 'GET'), false);
  assert.equal(device.browserOnly('/api/workspace'), false);
  assert.equal(device.browserOnly('/api/chat', 'POST'), false);
  assert.equal(device.browserOnly('/api/tool-approvals/abc', 'POST'), false, 'a device answers its own write approvals');
});

test('the request authenticator is exactly auth.cjs while the feature is off', async (t) => {
  const f = await fixture(t);
  const tokens = await approved(f);
  let on = false;
  const calls = [];
  const fakeAuth = { authenticate: (r) => { calls.push(r); return null; }, csrfValid: () => false };
  const gate = device.createRequestAuth({ enabled: () => on, deviceAuth: f.deviceAuth, authService: fakeAuth });
  assert.equal(gate.authenticate(bearerReq(tokens.access_token)), null);
  assert.equal(calls.length, 1, 'with the flag off, the bearer goes to auth.cjs untouched');
  on = true;
  const authn = gate.authenticate(bearerReq(tokens.access_token));
  assert.equal(authn.device.clientName, 'Unit Mac');
  assert.equal(calls.length, 1);
  assert.equal(gate.csrfValid(bearerReq(tokens.access_token), authn), true);
  assert.equal(gate.csrfValid({ headers: { ...bearerReq(tokens.access_token).headers, cookie: 'cowork_session=x' } }, authn), false);
  assert.equal(gate.authenticate({ headers: { ...bearerReq(tokens.access_token).headers, cookie: 'cowork_session=x' } }), null);
  assert.equal(gate.browserOnly(authn, '/api/admin/users', 'GET'), true);
  assert.equal(gate.browserOnly({ user: {}, session: {} }, '/api/admin/users', 'GET'), false);
  // Turning the feature off stops every device token at once.
  on = false;
  assert.equal(gate.authenticate(bearerReq(tokens.access_token)), null);
});
