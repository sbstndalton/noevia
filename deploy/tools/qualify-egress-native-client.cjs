'use strict';
// Owned synthetic CI only: the reviewed Core's control issuer against the actual native image.
// No model calls, external data requests, real keys or application state.
// Since noevia-core 09a2710 (row V) the Rust front is the only production issuer and Node is a
// fail-closed client of it (server/code-egress-client.cjs). The retired Node issuer is kept in the
// reviewed Core as the frozen oracle (tests/reference/code-egress-control.cjs, the old server glue
// verbatim as startControlledEgressFromEnv), the one the native issuer is differentially tested
// against and Core's own real-binary tests drive. It drives the native image here, and the production
// glue must still accept the rendered profile while publishing nothing itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const core = process.env.NOEVIA_EGRESS_CORE_ROOT;
assert.ok(core && path.isAbsolute(core) && path.resolve(core) === core, 'explicit reviewed Core checkout required');
const { startEgressFromEnv } = require(path.join(core, 'server', 'code-egress.cjs'));
const { startControlledEgressFromEnv, defaultTransport, ROUTES } = require(path.join(core, 'tests', 'reference', 'code-egress-control.cjs'));
assert.equal(typeof startEgressFromEnv, 'function'); assert.equal(typeof startControlledEgressFromEnv, 'function');
assert.equal(typeof defaultTransport, 'function'); assert.equal(typeof ROUTES.revoke, 'string');
const key = process.env.CODE_EGRESS_CONTROL_KEY_FILE;
const uid = Number(process.env.CODE_EGRESS_KEY_UID), gid = Number(process.env.CODE_EGRESS_KEY_GID);
assert.equal(process.getuid(), uid);
const parent = fs.statSync(path.dirname(key));
assert.equal(parent.uid, uid); assert.equal(parent.gid, gid); assert.equal(parent.mode & 0o7777, 0o750);
let dropped = false;
const create = () => startControlledEgressFromEnv(process.env, {
  secrets: { derive: () => Buffer.alloc(32, 29) },
  transport: async (request) => {
    const response = await defaultTransport(request);
    if (request.route === ROUTES.revoke && !dropped) {
      dropped = true;
      throw Error('synthetic reply lost after native commit');
    }
    return response;
  },
});
async function run() {
  let client, replacement, production;
  try {
    // Production glue: the rendered profile is valid, the client fails closed without the front's
    // store, and Node publishes no control key of its own.
    production = startEgressFromEnv({ ...process.env, NOEVIA_PROJECT_STORE_PORT: '9', NOEVIA_PROJECT_STORE_TOKEN: 'q'.repeat(32) },
      { fetchImpl: async () => { throw Error('no front in this qualification'); } });
    assert.ok(production, 'production Core glue must accept the rendered profile');
    assert.equal(production.endpoint, `egress-rs-code:${process.env.CODE_EGRESS_PORT}`);
    assert.equal(production.available(), false);
    await assert.rejects(production.grant({ taskId: 'owned.production.glue', domains: ['owned.invalid'] }), { code: 'EGRESS_UNAVAILABLE' });
    assert.equal(fs.existsSync(key), false, 'production Core glue must not publish a control key');
    await production.close(); production = null;
    client = create();
    const published = fs.statSync(key);
    assert.equal(published.uid, uid); assert.equal(published.gid, gid);
    assert.equal(published.mode & 0o7777, 0o440); assert.equal(published.nlink, 1);
    assert.equal(fs.readFileSync(key).length, 65);
    await client.ready(); await client.renew();
    const lease = await client.grant({ taskId: 'owned.image.qualification', domains: ['owned.invalid'] });
    assert.equal((await client.activity(lease)).final, false);
    const result = await client.revoke(lease);
    assert.equal(result.confirmed, true); assert.equal(result.report.final, true);
    assert.equal(result.report.available, true); assert.equal(result.report.allowed, 0); assert.equal(result.report.refused, 0);
    assert.equal(dropped, true);
    assert.equal((await client.activity(lease)).snapshotId, result.report.snapshotId);
    assert.equal((await client.forget(lease, result.report.snapshotId)).confirmed, true);
    const forgotten = await client.activity(lease);
    assert.equal(forgotten.available, false); assert.equal(Object.hasOwn(forgotten, 'hosts'), false);
    // The real mounted provider must observe a permission fault: authority stops while it lasts.
    // Afterwards the same client recovers by itself, and only through a new session (#2226).
    fs.chmodSync(key, 0o444);
    await assert.rejects(client.renew(), { code: 'EGRESS_UNAVAILABLE' });
    await assert.rejects(client.grant({ taskId: 'owned.not.during.fault', domains: ['owned.invalid'] }), { code: 'EGRESS_UNAVAILABLE' });
    assert.equal(client.available(), false);
    fs.chmodSync(key, 0o440);
    const end = Date.now() + 40000;
    while (!client.available()) { assert.ok(Date.now() < end, 'client did not recover'); await new Promise((resolve) => setTimeout(resolve, 250)); }
    const revived = await client.grant({ taskId: 'owned.revived', domains: ['owned.invalid'] });
    assert.notEqual(revived.token, lease.token);
    const closed = await client.revoke(revived);
    assert.equal(closed.confirmed, true); assert.equal(closed.report.final, true);
    assert.equal((await client.forget(revived, closed.report.snapshotId)).confirmed, true);
    // A new web incarnation still takes over with a new key.
    replacement = create();
    await replacement.ready(); await replacement.renew();
    const fresh = await replacement.grant({ taskId: 'owned.replacement', domains: ['owned.invalid'] });
    const ended = await replacement.revoke(fresh);
    assert.equal(ended.confirmed, true); assert.equal(ended.report.final, true);
    assert.equal((await replacement.forget(fresh, ended.report.snapshotId)).confirmed, true);
    console.log('PASS: control fixture current-key identity, authenticated Ready/renew, revoke retry/report/Forget, permission retirement, self-recovery and replacement');
  } finally {
    if (key && fs.existsSync(key)) fs.chmodSync(key, 0o440);
    if (production) await production.close();
    if (replacement) await replacement.close();
    if (client) await client.close();
  }
}
run().catch(() => { console.error('FAIL: isolated native image qualification'); process.exitCode = 1; });
