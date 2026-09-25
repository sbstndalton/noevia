"""Per-request tenant assertion (docs/spec-service-boundaries.md §6.2 M2).

The shared DIARY_AUTH_TOKEN proves "this is the web server"; it does not prove
which tenant a request acts for. With DIARY_TENANT_KEY set, the web server signs
every tenant-scoped request (apps/web/server/diary-tenant-assertion.cjs) and
this module verifies it:

  X-Cowork-Tenant-Assertion: v1.<unix seconds>.<nonce hex>.<base64url HMAC-SHA256>

over the newline-joined canonical string
  "cowork-diary-tenant-v1", user id (lower case), ts, nonce, METHOD, path,
  sha256(X-Cowork-Storage or ""), X-Cowork-Legacy-Owner or "",
  X-Cowork-Storage-Blocked or ""

Checks: constant-time signature compare, |now - ts| <= SKEW_S, and each nonce
accepted once while its timestamp is inside the window (in-process cache; the
sidecar runs one uvicorn worker). The key is read per call so an operator
change takes effect on restart and tests can patch the environment.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import re
import threading
import time
from collections import OrderedDict
from typing import Mapping, Optional

HEADER = "X-Cowork-Tenant-Assertion"
LABEL = "cowork-diary-tenant-v1"
SKEW_S = 60
_NONCE_CAP = 100_000
_ASSERTION_RE = re.compile(r"v1\.(\d{1,12})\.([0-9a-f]{32})\.([A-Za-z0-9_-]{43})")

_seen: "OrderedDict[str, float]" = OrderedDict()
_seen_lock = threading.Lock()


def tenant_key() -> str:
    return (os.environ.get("DIARY_TENANT_KEY") or "").strip()


def canonical(user_id: str, ts: int, nonce: str, method: str, path: str, storage: str, legacy_owner: str, blocked: str) -> str:
    storage_hash = hashlib.sha256(storage.encode()).hexdigest()
    return "\n".join([LABEL, user_id.lower(), str(ts), nonce, method.upper(), path, storage_hash, legacy_owner, blocked])


def sign(key: str, user_id: str, method: str, path: str, headers: Mapping[str, str], ts: int, nonce: str) -> str:
    """Reference signer (tests, tooling). Web has its own in diary-tenant-assertion.cjs."""
    message = canonical(user_id, ts, nonce, method, path, headers.get("X-Cowork-Storage", ""),
                        headers.get("X-Cowork-Legacy-Owner", ""), headers.get("X-Cowork-Storage-Blocked", ""))
    sig = base64.urlsafe_b64encode(hmac.new(key.encode(), message.encode(), hashlib.sha256).digest()).rstrip(b"=").decode()
    return f"v1.{ts}.{nonce}.{sig}"


def _remember_nonce(nonce: str, now: float) -> bool:
    """False when the nonce was already used inside the window."""
    with _seen_lock:
        while _seen:
            oldest, expiry = next(iter(_seen.items()))
            if expiry > now and len(_seen) < _NONCE_CAP:
                break
            _seen.popitem(last=False)
        if nonce in _seen:
            return False
        # Expire after the latest moment the same timestamp could still verify.
        _seen[nonce] = now + 2 * SKEW_S
        return True


def verify(key: str, headers: Mapping[str, str], method: str, path: str, now: Optional[float] = None) -> Optional[str]:
    """None when the request carries a valid assertion for its X-Cowork-User-ID, else a reason.

    Reasons are for logs only; callers answer every failure the same way."""
    now = time.time() if now is None else now
    user_id = headers.get("X-Cowork-User-ID", "")
    raw = headers.get(HEADER, "")
    if not user_id:
        return "missing tenant"
    match = _ASSERTION_RE.fullmatch(raw or "")
    if not match:
        return "missing or malformed assertion"
    ts, nonce, _ = int(match.group(1)), match.group(2), match.group(3)
    expected = sign(key, user_id, method, path, headers, ts, nonce)
    if not hmac.compare_digest(expected.encode(), raw.encode()):
        return "bad signature"
    if abs(now - ts) > SKEW_S:
        return "outside clock window"
    if not _remember_nonce(nonce, now):
        return "replayed"
    return None


def storage_secret_ref(key: str, user_id: str, secret: str) -> str:
    """Same derivation as web's storageSecretRef (diary-tenant-assertion.cjs)."""
    msg = f"{LABEL}:storage-secret\n{user_id.lower()}\n{secret}"
    return hmac.new(key.encode(), msg.encode(), hashlib.sha256).hexdigest()[:32]


def _reset_for_tests() -> None:
    with _seen_lock:
        _seen.clear()
