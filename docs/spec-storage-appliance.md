# Storage appliance implementation contract

## Personal Diary SMB follow-up — 2026-09-12

The [SMB migration plan](spec-diary-smb.md) adds a deployment-specific option:
server-local tenant corpus, local bind mount for the companion, host SMB export
for the Mac. This does not turn the limited DAV listener into an SMB service.
Writable shared-volume access needs explicit conflict coordination; the current
local backend's per-instance lock does not protect external editors. Pilot and
migration are planned, not deployed; generic appliance/DAV work below stays separate.

This reconciles Workstream 7's repeated sections. Existing storage and corpus
paths remain unchanged; no production mount or migration is implied.

## Delivery boundaries

1. App passwords: tenant-owned create/list/revoke in Profile & security, hash-only
   storage, generated secret shown once, immutable LAN/public scope. Deployed as `2525de5`; normal account login remains separate.
2. Dedicated DAV listener in the web service: disabled by default and separately
   exposed by an operator. It calls the existing tenant diary file API, never the
   corpus volume. Begin with bounded Markdown listing/read/conditional-write
   operations. Explicitly reject unsupported verbs; do not advertise locks or
   generic filesystem/client compatibility until verified with real clients.
3. Sharing controls and appliance onboarding: Off / LAN endpoint / public HTTPS,
   derived mount URL with optional explicit override. Existing external storage
   remains supported; users must choose storage rather than receiving an assumed
   migration. Browser-local files are not server-hosted files.
4. Fresh-install managed volumes and Unraid path protection. Existing explicit
   state bindings must retain their meaning and contents. Do not silently switch
   deployed users to empty volumes.

## Credential contract

32 random secret bytes plus an independent 16-byte lookup id; Argon2id with the
same parameters as account passwords. Store no plaintext. Session and CSRF checks
protect management routes. Maximum 20 active credentials per user and five mint
attempts per minute. Transactional cap/account rechecks handle concurrent minting.
List metadata includes name, scope, created and last-used dates; creation and
revocation audit records contain ids/scope only. Revocation and account disabling
are rechecked after asynchronous verification. User deletion cascades credentials.
No credential is accepted by account login, general bearer compatibility or chat.
The future DAV listener must rate-limit before Argon2 and bound concurrency.

## Transport and ownership constraints

LAN/public is an endpoint policy, not a physical network detector. Never trust an
arbitrary Host or forwarded header as proof that a request is private or encrypted.
LAN authority must be explicitly configured and distinct from the public authority;
operator proxy/routing isolation remains required. Public access needs an HTTPS
origin and a defined trusted-proxy boundary. Plain LAN HTTP needs explicit user
acknowledgement that passwords cross the network in cleartext. Publishing a port
is never automatic, and the UI must not promise verified LAN-only reachability.

Only server-held local diary storage should be served initially; do not re-export
remote credentials or browser-local files. An authenticated credential selects its
own tenant, never a tenant supplied by request path/header. Disabling Diary/sharing
must stop DAV immediately. Existing path limits, ETags and dirty-index handling
must remain authoritative, including conflict failures. New directory/delete/move
semantics require companion API support first; direct disk shortcuts are forbidden.

## Acceptance

Synthetic tenants only: list/read/write isolation, traversal and encoding attacks,
credential lifecycle/races, scope and proxy refusal, no ordinary login acceptance,
conditional creation/overwrite conflict, interrupted request and worker failure,
OFF on fresh install, existing settings unchanged, and real client mount checks.
Verify HEAD/OPTIONS/PROPFIND response semantics and document unsupported methods.
Do not use the real diary corpus as a test dataset.


Initial endpoint implementation now covers step 2's bounded operations and step
3's settings control. See [dav.md](dav.md). Broad file-manager compatibility and
the appliance onboarding flow remain follow-ups; production sharing stays off.

### Boot-storage preflight — 2026-09-13

Implemented a host-side PHP mount validator and gated Compose-up wrapper. Resolves
symlink/missing-path aliases and checks a separately mounted boot device. Existing
state binds are unchanged; managed-volume fresh-install defaults remain open.
See deploy/preflight/README.md for invocation and the direct-start bypass limit.
