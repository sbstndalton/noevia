# Diary Markdown sharing (initial DAV operations)

The web service can expose a separate authenticated Markdown endpoint. It is
**disabled by default**, and neither reference Compose file publishes its port.
It serves only opted-in users with enabled Diary and server-held local storage.
Remote storage and browser-local folders are not re-exported. No files are
migrated, and the Diary sidecar must remain private.

This is a limited endpoint for clients that explicitly issue HTTP file operations,
not yet a general file-manager mount. Supported: OPTIONS, HEAD, GET, PROPFIND
(Depth 0/1; allprop or named properties), conditional PUT of UTF-8 Markdown. The current candidate adds bodyless MKCOL
through the companion; it is not yet deployed. Unsupported: DELETE, MOVE, COPY,
PROPPATCH, LOCK, UNLOCK, REPORT and infinite
depth. Consequently it does **not** advertise DAV class 1/2 compliance. Mounting in
Finder/Windows/Nextcloud is not claimed. Existing folders can be listed; new files
must have an existing parent. No last-modified timestamp is fabricated.

## Operator configuration

Set COWORK_DAV_PORT to an unused container port (e.g. 8031), COWORK_DAV_SCOPE to
lan or public, and COWORK_DAV_ORIGIN to the exact external scheme/authority, with
no path, credentials, query or fragment. Public scope may inherit PUBLIC_ORIGIN
when COWORK_DAV_ORIGIN is empty. LAN scope requires a distinct authority and an
explicit origin. The mount path is derived as `/dav/<username>/`.

For direct LAN HTTP, an explicit override can publish the port:

```yaml
services:
  web:
    ports:
      - "<server-LAN-address>:8031:8031"
```

This binding is operator configuration, not network-reachability verification.
Firewalls, forwards and proxies still determine who can reach it. A LAN user must
acknowledge in Settings that HTTP sends device credentials unencrypted.

For HTTPS at either scope, set COWORK_DAV_PROXY_TOKEN to a generated secret of
32–64 random bytes encoded as hex. Keep it out of client configuration and logs.
The trusted TLS-terminating proxy must strip any incoming
`X-Cowork-Dav-Proxy-Token`, inject the configured secret, set
`X-Forwarded-Proto: https`, and preserve the configured Host. Only route requests
from that HTTPS virtual host to the dedicated port. The listener verifies both
secret and protocol; a client-supplied forwarded header alone is refused. Do not
publish the backend port to untrusted clients or route LAN credentials through a
public proxy. TLS certificates remain the operator's responsibility.

Forward PROPFIND/PUT/HEAD/OPTIONS and preserve ETag, If-Match and If-None-Match.
Configure proxy request limits to allow 512 KiB Markdown writes; larger uploads
remain rejected. Never route to the sidecar or mount its corpus into the web image.

## User setup

In Settings → Diary & storage, choose the configured sharing scope and save.
Off is always available. Copy the displayed URL. In Profile & security, generate
a device app password of the **same scope** and save it once. Use your noevia
username and that password with HTTP Basic on the separate endpoint. An app
password cannot sign in to noevia or access its ordinary APIs. Revoke lost-device
credentials individually; disabling sharing or Diary stops file access.

Read a file to obtain its strong ETag, then PUT with exactly that If-Match value.
Create with If-None-Match: *. A stale version returns 412 and an unconditional
write returns 428. This preserves the companion's existing guarded write path and
dirty-index processing. Unsupported operations return 405 with the Allow header.

## Limits and verification

At most four concurrent authenticated requests and 120 requests/minute per direct
socket address; proxies share that limit deliberately (untrusted forwarded IPs
cannot evade it). A file is capped at 512 KiB, property XML at 8 KiB/128 nodes,
listings at 100 children, and no recursive traversal is offered. Property reads
have a bounded time window. Credentials and response bodies are not logged.
Audit records retain credential id, path, byte count and write/setting actions.

Protocol references: [RFC 4918](https://www.rfc-editor.org/info/rfc4918/) for
property discovery and method semantics. This limited implementation deliberately
omits unsupported compliance claims. Automated real HTTP and synthetic app/worker
boundary tests cover supported operations; broad desktop client compatibility is
remaining work.


## Folder creation candidate — 2026-09-13

MKCOL creates exactly one directory through the authenticated tenant companion
API. It never makes missing ancestors or overwrites an existing resource. Empty
body only; conditional MKCOL and encoded bodies are explicitly unsupported.
Existing path, transport, opt-in, credential and concurrency checks apply; access
is rechecked after body reading. A missing parent returns409, an existing resource
405, and success201. Local volume identity is checked before filesystem access.
No direct web-service corpus mount or new sharing exposure is introduced.

Empty folders have no document to index or capture operation to replay. Writes
inside them retain the existing guarded file path. Folder operations require
server-local storage. The endpoint still does not claim DAV class1/2 compliance
or desktop mount interoperability. Rename/delete scope awaits the user's choice
about protecting managed Diary paths; no destructive method is implemented here.

Verification:373 web tests, typecheck/build;195 Diary tests plus the new dedicated
volume-identity test (15-test dedicated suite passes), three existing skips and
two dependency warnings. Real web+Diary HTTP verifies create/list/child-write,
missing parent, duplicate resource, opt-in denial and credential revocation using
only disposable state. Candidate image/rollout checks remain pending.


## Storage contract for rename, delete, copy and locks — proposal, 2026-09-17

Status (2026-09-17, D6): **DELETE, MOVE and COPY implemented; no LOCK.** Companion:
`services/diary/agent/workspace_ops.py` via `POST /api/workspace-ops` (`stat`/`delete`/`move`/`copy`);
web: `apps/web/server/dav-ops.cjs`, wired into `dav.cjs` only when the companion call is provided.
`OPTIONS` sends `DAV: 1`. Protected set confirmed and extended with `AI Memory/**` (DAV only; the
in-app Trash rule is unchanged). Deviations: replacing a *folder* destination is refused (409 —
delete it first); a destination precondition is read from a tagged `If: <dest> (["etag"])`
header; COPY needs no source `If-Match` (non-destructive); the interoperability matrix below has
not been run yet, so `DAV: 1` ships ahead of it by decision D6.

Original status: **contract only; no destructive or locking method is implemented.** It fixes the
rules that DELETE, MOVE, COPY and LOCK must obey before any of them ships, so each can be
built and tested against one definition. The protected-path set below reuses the rule the app
already enforces for Trash (`workspace_trash.allowed`); widening or narrowing it is the user's
decision recorded at the end.

### Invariants (all methods)

1. **One write path.** Every mutation goes through the tenant companion's guarded file API
   (journal, ETag check, dirty-index processing). The web service never touches the corpus
   directly and never mounts it.
2. **Tenant root only.** Source and destination are normalised with the existing `safe_path`
   rules; `..`, absolute paths, dot-segments, encoded separators and hidden prefixes
   (`.noevia-trash/`, other dot-folders) are refused with 403.
3. **Protected paths.** Diary capture files under `Entries/**`, month files matching the
   configured month-file template, and the Diary index (`INDEX.md` or configured name) can
   never be deleted, moved, overwritten by COPY or MOVE, or locked by a client. Attempts return
   **403** with a plain-text reason. Versioned PUT edits to them stay allowed, matching the
   in-app Markdown editor and the Claude Diary bridge, which use the same guarded file API.
4. **Conditional by default.** Destructive methods require `If-Match` with the current strong
   ETag of the source (and of an existing destination when overwriting). Missing precondition →
   **428**; stale → **412**. Folders use a folder version derived from their listing.
5. **Reversible delete.** DELETE is a move into app Trash with a recovery capsule, exactly like
   the in-app action; it is refused (**409**) where Trash is unavailable (non-managed storage),
   rather than falling back to a hard delete.
6. **No partial trees.** Folder DELETE/MOVE/COPY are all-or-nothing within the companion
   transaction and bounded (≤ 500 entries, ≤ 50 MiB copied). Over the bound → **507** without
   changes. `Depth: infinity` is accepted only for these bounded folder operations, never for
   PROPFIND.
7. **Uncertain outcomes are explicit.** If the companion times out after accepting a mutation,
   the endpoint returns **503** with `Retry-After` and the journal id is audited; a retry with
   the same `If-Match` then yields either success or 412, never a second effect.
8. **Index and retrieval stay consistent.** Moves and deletes enqueue dirty-index work for both
   old and new paths in the same transaction as the file change.
9. **Audit.** Credential id, method, source, destination, byte count and result; never contents.

### Method rules

| Method | Semantics | Success | Notable refusals |
|---|---|---|---|
| DELETE file | Move to Trash with capsule | 204 | 403 protected, 409 no Trash, 412/428 precondition |
| DELETE folder | Trash every child, then the folder, one transaction | 204 | 403 if any descendant is protected, 507 over bound |
| MOVE | Rename within tenant root; `Overwrite: F` default; `T` only with destination `If-Match` | 201 new / 204 replaced | 403 protected source or destination, 409 missing parent, 412 destination exists with `Overwrite: F` |
| COPY | Bounded copy; new ETags; never onto protected paths | 201 / 204 | 403, 409, 412, 507 |
| LOCK / UNLOCK | Advisory, short-lived (≤ 15 min, refreshable) exclusive write locks stored by the companion; writes by other credentials without the lock token get 423 | 200 / 204 | 403 protected paths, 423 already locked |
| PROPPATCH | Still unsupported (405) — no dead properties are stored | — | — |

`DAV:` compliance header: advertise `1` only after DELETE/MOVE/COPY pass the interoperability
matrix below; add `2` only if LOCK ships and passes it too. Until then `OPTIONS` keeps the
current `Allow` list and no `DAV:` class.

### Interoperability matrix (must pass before advertising)

`litmus` basic, copymove and (for class 2) locks suites; rclone webdav (sync, move, delete);
macOS Finder (mount, create, rename, delete, Finder's lock/`._` sidecar behaviour); Windows
Explorer and WinSCP; iOS Files through a WebDAV-capable client; Obsidian with a WebDAV sync
plugin. Each run uses a disposable managed tenant copied from `diary-test`, records the client
version and every refused request, and confirms protected paths stayed byte-identical.

### Build order

1. Companion API: move-to-trash and rename with the invariants above and unit tests
   (protected paths, preconditions, bounds, uncertain outcome replay).
2. DAV DELETE and MOVE on top, with real-HTTP tests; then COPY.
3. Interop matrix for class 1; advertise `DAV: 1`.
4. LOCK/UNLOCK only if a client in the matrix needs it to write reliably.

### Interoperability run 1 — 2026-09-21 (rclone v1.75.1)

`apps/web/qa/dav-interop.cjs`: rclone against the real web server and the real Diary companion on
a throwaway tenant (temp folder; nothing on DaServer). **Protection holds; ordinary writes do not
work.** PROPFIND, MKCOL and `DAV: 1` pass; deleting or moving the protected `INDEX.md` is refused
and it stays byte-identical. Every PUT, MOVE, COPY-then-read, DELETE, sync and purge fails with
**428**, because rclone (like Finder, Explorer and Obsidian WebDAV sync) never sends `If-Match` /
`If-None-Match`, and invariant 4 requires them. Overwrites keep no prior version (Trash covers
removal only), so relaxing PUT would allow silent lost updates; DELETE and MOVE are reversible.
**Decision (user, 2026-09-21): relax invariant 4, keeping a version.** Without `If-Match`:
DELETE and MOVE read the current version and proceed (both reversible); an untagged
`Overwrite: T` reads the destination's version (the replaced file goes to Trash); a PUT over an
existing file first keeps its bytes in Trash via the companion's `preserve` op, restoring beside
it as `<name> (replaced <UTC time>).md`, then writes against the version just read. Protected
files still require `If-Match` (428). Run 2, same harness: **18/18 pass** — create, mkdir,
rename, server-side copy, delete, sync, purge, overwrite with the old version in Trash, and
every attempt on `INDEX.md` refused with it byte-identical.

### Decision (D6, 2026-09-17)

Protected set confirmed — capture files, month files, the index — plus `AI Memory/**`.
