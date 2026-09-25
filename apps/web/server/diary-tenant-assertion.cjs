'use strict';
// ── Per-request Diary tenant assertion (spec-service-boundaries §6.2 M2) ─────
// The shared DIARY_AUTH_TOKEN says "this is the web server"; it does not say
// which user a request acts for. With DIARY_TENANT_KEY set, web signs every
// tenant-scoped Diary request with an HMAC that binds the tenant id, a
// timestamp, a single-use nonce, the method and path, and the exact tenant
// headers (storage descriptor, legacy-owner and blocked markers). The sidecar
// (services/diary/agent/tenant_assertion.py) verifies the same canonical string.
//
// Header: X-Cowork-Tenant-Assertion: v1.<unix seconds>.<nonce hex>.<base64url sig>
// Canonical string (newline-joined):
//   "cowork-diary-tenant-v1", user id (lower case), ts, nonce, METHOD, path
//   (no query), sha256(X-Cowork-Storage or ""), X-Cowork-Legacy-Owner or "",
//   X-Cowork-Storage-Blocked or ""
//
// storageSecretRef() names a remote storage credential without carrying it
// (#292): the sidecar keys its cached tenant state by this reference and only
// needs the secret itself when it has no state for it (HTTP 428, see diary.cjs).

const crypto = require('node:crypto');

const ASSERTION_HEADER = 'X-Cowork-Tenant-Assertion';
const LABEL = 'cowork-diary-tenant-v1';

function pathOf(url) {
  try { return new URL(url, 'http://diary.invalid').pathname; } catch { return '/'; }
}

function canonical({ userId, ts, nonce, method, path, storage = '', legacyOwner = '', blocked = '' }) {
  const storageHash = crypto.createHash('sha256').update(String(storage)).digest('hex');
  return [LABEL, String(userId).toLowerCase(), String(ts), nonce, String(method || 'GET').toUpperCase(), path, storageHash, legacyOwner, blocked].join('\n');
}

/**
 * Sign one request. `headers` are the tenant headers already on the request.
 * @param {{ key:string, method:string, url:string, headers:Record<string,string>, now?:number, nonce?:string }} args
 * @returns {string} the header value
 */
function signTenantAssertion({ key, method, url, headers, now = Date.now(), nonce = crypto.randomBytes(16).toString('hex') }) {
  const ts = Math.floor(now / 1000);
  const message = canonical({
    userId: headers['X-Cowork-User-ID'], ts, nonce, method, path: pathOf(url),
    storage: headers['X-Cowork-Storage'] || '', legacyOwner: headers['X-Cowork-Legacy-Owner'] || '', blocked: headers['X-Cowork-Storage-Blocked'] || '',
  });
  const sig = crypto.createHmac('sha256', key).update(message).digest('base64url');
  return `v1.${ts}.${nonce}.${sig}`;
}

/** A stable, non-reversible name for a storage credential, scoped to one tenant. */
function storageSecretRef(key, userId, secret) {
  return crypto.createHmac('sha256', key).update(`${LABEL}:storage-secret\n${String(userId).toLowerCase()}\n${secret}`).digest('hex').slice(0, 32);
}

module.exports = { ASSERTION_HEADER, signTenantAssertion, storageSecretRef, canonical, pathOf };
