'use strict';
// Owned synthetic CI only: production Core glue against the actual native image.
// No model calls, external data requests, real keys or application state.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const core = process.env.NOEVIA_EGRESS_CORE_SERVER;
assert.ok(core && path.isAbsolute(core), 'explicit reviewed Core server directory required');
const { startEgressFromEnv } = require(path.join(core, 'code-egress.cjs'));
const { defaultTransport, ROUTES } = require(path.join(core, 'code-egress-control.cjs'));
const key = process.env.CODE_EGRESS_CONTROL_KEY_FILE;
const uid = Number(process.env.CODE_EGRESS_KEY_UID), gid = Number(process.env.CODE_EGRESS_KEY_GID);
assert.equal(process.getuid(), uid);
const parent = fs.statSync(path.dirname(key));
assert.equal(parent.uid, uid); assert.equal(parent.gid, gid); assert.equal(parent.mode & 0o7777, 0o750);
let dropped = false;
const create = () => startEgressFromEnv(process.env, {
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
  let client, replacement;
  try {
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
    // The real mounted provider must observe a permission fault. Restoring file
    // permissions cannot revive the old Core client/session after that observation.
    fs.chmodSync(key, 0o444);
    await assert.rejects(client.renew(), { code: 'EGRESS_UNAVAILABLE' });
    fs.chmodSync(key, 0o440);
    await assert.rejects(client.ready(), { code: 'EGRESS_UNAVAILABLE' });
    await assert.rejects(client.grant({ taskId: 'owned.must.not.revive', domains: ['owned.invalid'] }), { code: 'EGRESS_UNAVAILABLE' });
    replacement = create();
    await replacement.ready(); await replacement.renew();
    const fresh = await replacement.grant({ taskId: 'owned.replacement', domains: ['owned.invalid'] });
    const ended = await replacement.revoke(fresh);
    assert.equal(ended.confirmed, true); assert.equal(ended.report.final, true);
    assert.equal((await replacement.forget(fresh, ended.report.snapshotId)).confirmed, true);
    console.log('PASS: control fixture current-key identity, authenticated Ready/renew, revoke retry/report/Forget, permission retirement and replacement');
  } finally {
    if (key && fs.existsSync(key)) fs.chmodSync(key, 0o440);
    if (replacement) await replacement.close();
    if (client) await client.close();
  }
}
run().catch(() => { console.error('FAIL: isolated native image qualification'); process.exitCode = 1; });
