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
