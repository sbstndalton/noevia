# Egress grant contract, version 1 (#926)

How the web tells the Rust egress proxy (sbstndalton/noevia-rs `bins/egress-proxy`) which hosts a
sandboxed task may reach. The web mints a grant when it starts a networked Code or browser task.
The proxy verifies it and enforces exactly its hosts. Anything else is denied.

Status: dark. It is used only with `CODE_EGRESS_IMPL=rust`; the default `node` keeps the
in-process proxy (`apps/web/server/code-egress.cjs`).

Files:

- `apps/web/contracts/egress-grant.v1.schema.json` is the payload schema.
- `apps/web/contracts/egress-grant.v1.vectors.json` holds the cross-language test vectors. An
  identical copy lives at noevia-rs `crates/egress/tests/fixtures/egress-grant.v1.vectors.json`.
- The minting side is `code-egress.cjs` (`mintGrant`, `createRustEgressClient`).
- The verifying side is noevia-rs `crates/egress/src/grant.rs` (`verify`, `Ledger`).

## Token

```text
token  = "ngr1." B64(payload) "." B64(tag)
tag    = HMAC-SHA256(key, "ngr1." B64(payload))      ; 32 bytes
B64    = base64url, RFC 4648 §5, no padding
```

The prefix `ngr1` names the contract version, and the MAC covers it. The token travels where the
task token always went: as the password in `Proxy-Authorization: Basic base64("task:" token)`,
which is the `http://task:<token>@egress-rs:8040` proxy URL the sandbox receives. Every character
of a token is URL-safe.

## Payload

Canonical JSON: these eight keys, **in this order**, with no whitespace and ASCII only:

```json
{"v":1,"act":"grant","task":"<id>","hosts":["a.example","b.example"],"iat":1800000000000,"exp":1800043200000,"idle":21600000,"nonce":"<22 chars>"}
```

| key | rule |
|---|---|
| `v` | `1` |
| `act` | `"grant"` (needs ≥ 1 host) or `"revoke"` (needs `[]`) |
| `task` | `[A-Za-z0-9._:-]{1,128}` (job ids are UUIDs) |
| `hosts` | ≤ 64 unique entries, each `^[a-z0-9-]+(\.[a-z0-9-]+)*$`, ≤ 253 chars. The web lowercases and drops outer dots first, as `hostAllowed` does. A host also grants its subdomains, but not lookalike suffixes. |
| `iat` | issued at, Unix ms, > 0 |
| `exp` | absolute expiry, Unix ms. `iat < exp`, `exp - iat` ≤ 86 400 000 (24 h). The web uses 12 h (`CODE_EGRESS_GRANT_LIFETIME_MS`). |
| `idle` | idle TTL ms, `1 ≤ idle ≤ exp - iat`. The web uses `CODE_EGRESS_TOKEN_TTL_MS` (default 6 h). |
| `nonce` | 16 random bytes, base64url (22 chars) |

Every string value is restricted to characters JSON never escapes, so plain concatenation gives
the canonical bytes. Integers are plain decimal.

## Key

`secretStore.derive('code-egress-grant')` produces it: HKDF-SHA256 over `secrets.key` with the
info `noevia:code-egress-grant`, 32 bytes. This key is separate from every other derived key. In
rust mode the web writes it as 64 lowercase hex digits plus a newline to
`CODE_EGRESS_GRANT_KEY_FILE`. The file is replaced atomically with mode 0444 on the
`code-egress-key` volume. Only web (read-write) and the proxy (read-only) mount that volume; the
sandbox never does. The proxy re-reads the file every 5 s, so it can appear after the proxy
starts and is picked up after a `secrets.key` rotation and web restart. Without a key, signed
tokens are refused with 503. `CODE_EGRESS_GRANT_KEY` (the hex value itself) is an alternative for
tests. Keys and tokens are never logged.

## Verification (proxy, stateless part)

The checks run in this order. Each refusal is a 407 with the reason shown, and the reason never
includes the token.

1. The token is no longer than 8192 bytes and starts with `ngr1.`. Another `ngr…` prefix is
   refused with *grant version is not supported*.
2. Split at the last `.` and decode the tag (strict base64url). Recompute the HMAC over everything
   before that dot and **compare in constant time** before parsing anything. A mismatch is
   refused with *grant signature is invalid*.
3. Decode and parse the payload. `v` ≠ 1 is refused with *version not supported*. The payload
   must re-encode to **the identical bytes** and satisfy every rule above; otherwise it is
   refused with *grant is malformed*.
4. If `iat > now + 60 s`, the grant is refused with *grant is not valid yet*. If `now ≥ exp`, it
   is refused with *grant has expired*.

## Ledger (proxy, stateful part)

Replay and ordering:

- **Supersession.** For each task, the grant with the highest `(iat, nonce)` wins. A newer grant
  replaces the current one and closes its connections. An older grant presented later is refused
  with *superseded*. The web stamps a task's grants and revokes with strictly increasing `iat`,
  even within the same millisecond.
- **Revocation.** When a task ends, the web posts `POST /v1/revoke` with
  `Authorization: Bearer <token with act "revoke">` to the proxy on the internal `code` network.
  The proxy answers 204, drops the task's grant and its tunnels, and from then on refuses any
  grant with `iat ≤` the revoke's `iat` (*grant was revoked*). It answers 403 to a forged revoke,
  to a grant token or to an unsigned token. Replaying a revoke does nothing. A revoke is never a
  proxy credential.
- **No replay of dropped grants.** A grant that was superseded, revoked, idle past `idle` or
  past `exp` has its nonce retired until its `exp`. Presenting the same token again is refused
  with *grant was already retired*. Everything is forgotten once its `exp` has passed, because
  `verify` refuses such a grant anyway. Memory is therefore bounded by live lifetimes, plus a cap
  of 65 536 tasks; past the cap the proxy refuses with 503 rather than forget.
- **Idle and absolute expiry** close the grant's live tunnels, as they do in the Node proxy.

A grant is installed the first time it is presented. After that, the stored token is matched in
constant time, exactly like a static token.

## Enforcement

Enforcement is unchanged from the Node proxy and covered by the differential fixtures (3412
cases, 100 % agreement against noevia 0395ff98). A request must be on port 80 or 443, its host
must be one of `hosts` or a subdomain of one, every resolved address must be public, and the
proxy connects to the address it checked. `Proxy-Authorization` and other hop-by-hop headers are
stripped. Connection caps and the tunnel idle timeout are the same.

## Changing the contract

A breaking change gets a new prefix (`ngr2.`), a new `v`, a new schema file and new vectors. The
proxy must accept both versions before the web switches. Both repositories' tests check the
vectors file byte for byte: Rust regenerates it with `GRANT_VECTORS_WRITE=1 cargo test -p egress
--test grant_vectors`, and the result is copied here unchanged.

## Not covered

- The per-task host summary (`egress.activity`, "github.com was refused") is a Node-proxy
  feature. In rust mode the task result has no `network` block. The refusals are still logged by
  the proxy as JSON lines with `taskId` and `host`.
- If web cannot reach the proxy when a task ends, the revoke is lost and logged as
  `egress.revoke_failed`. The grant then still dies at its idle TTL or `exp`, and the sandbox
  container that held it is gone.
