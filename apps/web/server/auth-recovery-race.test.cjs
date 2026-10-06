'use strict';
// #928 review: recovery must also beat credential requests already in flight. A passkey
// registration or app-password creation that is past its checks but still in its slow step when the
// recovery commits must not insert afterwards. Also: pending challenges die with the recovery, and
// the recovering admin's own session and app passwords are untouched.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Stand-in for the passkey library's verification step, so the test decides when it finishes.
const webauthnPath = require.resolve('@simplewebauthn/server');
const realWebauthn = require(webauthnPath);
let verifyRegistration = null;
require.cache[webauthnPath] = { id: webauthnPath, filename: webauthnPath, loaded: true,
  exports: { ...realWebauthn, verifyRegistrationResponse: (...args) => verifyRegistration(...args) } };
const { createAuth } = require('./auth.cjs');
const { createAppPasswords } = require('./app-passwords.cjs');

const ORIGIN = 'https://cowork.example.test';
const request = (cookie = '') => ({ headers: { origin: ORIGIN, 'user-agent': 'test', cookie }, socket: { remoteAddress: '127.0.0.1' } });
const response = () => ({ headers: {}, setHeader(k, v) { this.headers[k] = v; } });
const cookieOf = (res) => res.headers['Set-Cookie'][0].split(';')[0];
const gate = () => { let open; const opened = new Promise((resolve) => { open = resolve; }); return { opened, open }; };
const registered = (id) => ({ verified: true, registrationInfo: { credential: { id, publicKey: new Uint8Array([1, 2, 3]), counter: 0, transports: ['internal'] }, credentialDeviceType: 'singleDevice', credentialBackedUp: false } });

async function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cowork-recovery-race-'));
  const auth = createAuth({ dataDir: root, publicOrigin: ORIGIN });
  t.after(() => { auth.db.close(); fs.rmSync(root, { recursive: true, force: true }); });
  const adminRes = response();
  const admin = await auth.setup(request(), adminRes, { setupCode: fs.readFileSync(path.join(root, 'first-run-setup-code'), 'utf8').trim(), publicOrigin: ORIGIN, username: 'admin', password: 'synthetic admin password' });
  const member = await auth.acceptInvite(request(), response(), { token: auth.createInvite(admin.body.user.id).token, username: 'member', password: 'synthetic member password' });
  return { auth, adminId: admin.body.user.id, adminCookie: cookieOf(adminRes), memberId: member.body.user.id };
}

test('passkey registration still verifying when recovery commits does not add the passkey', async (t) => {
  const { auth, adminId, memberId } = await fixture(t);
  // Control: without a recovery in between, the stubbed ceremony registers.
  verifyRegistration = async () => registered('control-key');
  const control = await auth.registrationOptions(memberId);
  assert.deepEqual(await auth.registrationVerify(memberId, { challengeToken: control.challengeToken, response: {} }), { verified: true });
  assert.equal(auth.listPasskeys(memberId).length, 1);

  const slow = gate(); let entered; const inside = new Promise((resolve) => { entered = resolve; });
  verifyRegistration = async () => { entered(); await slow.opened; return registered('intruder-key'); };
  const { challengeToken } = await auth.registrationOptions(memberId);
  const pending = auth.registrationVerify(memberId, { challengeToken, response: {} });
  await inside;
  assert.equal(await auth.completeRecovery({ token: auth.createRecovery(adminId, memberId).token, password: 'synthetic recovered password' }), true);
  slow.open();
  await assert.rejects(pending, /registration challenge expired/);
  assert.deepEqual(auth.listPasskeys(memberId), [], 'a passkey was added after the recovery');
});

test('app password still hashing when recovery commits is not created', async (t) => {
  const { auth, adminId, memberId } = await fixture(t);
  const slow = gate(); let entered; const inside = new Promise((resolve) => { entered = resolve; });
  const passwords = createAppPasswords({ db: auth.db, audit: auth.audit, rateLimited: () => false,
    hashPassword: async () => { entered(); await slow.opened; return '$argon2id$synthetic'; } });
  const pending = passwords.create(memberId, { name: 'Intruder laptop', scope: 'public' });
  await inside;
  assert.equal(await auth.completeRecovery({ token: auth.createRecovery(adminId, memberId).token, password: 'synthetic recovered password' }), true);
  slow.open();
  await assert.rejects(pending, /Account unavailable/);
  assert.deepEqual(auth.appPasswords.list(memberId), [], 'an app password was added after the recovery');
});

test('pending passkey challenges are refused after recovery', async (t) => {
  const { auth, adminId, memberId } = await fixture(t);
  verifyRegistration = async () => registered('late-key');
  const register = await auth.registrationOptions(memberId);
  auth.db.prepare('INSERT INTO passkeys(id,user_id,name,public_key,webauthn_user_id,counter,device_type,backed_up,transports,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
    .run('member-passkey', memberId, 'Synthetic key', Buffer.from('pk'), 'w', 0, 'singleDevice', 0, JSON.stringify(['internal']), Date.now());
  const signIn = await auth.authenticationOptions('member');
  assert.equal(await auth.completeRecovery({ token: auth.createRecovery(adminId, memberId).token, password: 'synthetic recovered password' }), true);
  assert.equal(auth.db.prepare('SELECT count(*) AS n FROM challenges WHERE user_id=?').get(memberId).n, 0);
  await assert.rejects(auth.registrationVerify(memberId, { challengeToken: register.challengeToken, response: {} }), /registration challenge expired/);
  await assert.rejects(auth.authenticationVerify(request(), response(), { challengeToken: signIn.challengeToken, response: { id: 'member-passkey' } }), /authentication failed/);
  assert.deepEqual(auth.listPasskeys(memberId), []);
});

test("the recovering admin's own session and app passwords survive", async (t) => {
  const { auth, adminId, adminCookie, memberId } = await fixture(t);
  const adminDav = await auth.appPasswords.create(adminId, { name: 'Admin phone', scope: 'lan' });
  const memberDav = await auth.appPasswords.create(memberId, { name: 'Member phone', scope: 'lan' });
  const used = auth.createRecovery(adminId, memberId);
  assert.equal(await auth.completeRecovery({ token: auth.createRecovery(adminId, memberId).token, password: 'synthetic recovered password' }), true);
  assert.equal(auth.authenticate(request(adminCookie))?.user?.id, adminId, "the admin's session was signed out");
  assert.ok(await auth.appPasswords.verifyDav('admin', adminDav.password, 'lan'), "the admin's app password was revoked");
  assert.equal(await auth.appPasswords.verifyDav('member', memberDav.password, 'lan'), null);
  assert.equal(await auth.completeRecovery({ token: used.token, password: 'synthetic other password' }), false);
});

test('the audit counts only recovery links that still worked', async (t) => {
  const { auth, adminId, memberId } = await fixture(t);
  const spent = auth.createRecovery(adminId, memberId);
  assert.equal(await auth.completeRecovery({ token: spent.token, password: 'synthetic first password' }), true);
  auth.createRecovery(adminId, memberId);
  const expired = auth.createRecovery(adminId, memberId);
  auth.db.prepare('UPDATE recoveries SET expires_at=? WHERE token_hash=?').run(Date.now() - 1, require('./auth.cjs').digest(expired.token));
  assert.equal(await auth.completeRecovery({ token: auth.createRecovery(adminId, memberId).token, password: 'synthetic second password' }), true);
  const details = auth.db.prepare("SELECT detail FROM audit_events WHERE action='recovery.complete' ORDER BY id").all().map((r) => JSON.parse(r.detail).revoked.recoveries);
  assert.deepEqual(details, [0, 1]);
});
