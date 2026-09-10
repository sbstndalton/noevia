# Security model

This document describes how Cowork protects itself and its users, what is
trusted and why, and what an operator must do before exposing the deployment
beyond a trusted machine. The design goal is that a self-hosted deployment on
a home server or small VPS is safe by default, and that every deviation from
the safe default is an explicit, documented setting.

Related reading: the root `README.md` (deployment and accounts) and
`services/diary/README.md` (diary configuration, including its own trust-model
section).

## The two services and their boundary

- **Web server** (`apps/web/server/index.cjs`): the only service that talks to
  browsers. It authenticates users, enforces CSRF and origin checks, and is
  the single published port in the reference `compose.yaml`.
- **Diary sidecar** (`services/diary/agent/app.py`): the journaling service.
  It is internal-only: `compose.yaml` uses `expose` (container-network only),
  never `ports`. It trusts the web server; see the trust model below.

## Accounts, sessions, and request validation

- Accounts are created by the first-run setup (administrator) or by
  single-use administrator-issued invitations (members). Passwords are hashed
  with Argon2id (12–128 character minimum enforced at hashing time). Passkeys
  (WebAuthn) are supported for passwordless sign-in; account recovery uses
  single-use administrator-issued links.
- Session cookies are `HttpOnly`, `SameSite=Lax`, and marked `Secure` when the
  public origin is HTTPS. A double-submit CSRF token (cookie + `x-csrf-token`
  header, bound to the session) is required on every non-GET API request, and
  the `Origin` header is validated against the configured public origin.
- Setup and sign-in routes are rate-limited per client address. Set
  `TRUST_PROXY=true` behind a reverse proxy so per-IP limits and audit logs
  see the real client IP (rightmost `X-Forwarded-For` entry).

## Diary sidecar trust model (hard requirement)

**The diary sidecar must only ever be reachable from the web server on an
internal network. Do not publish its port, and do not route public traffic
to it.**

`DIARY_AUTH_TOKEN` is a single shared service token, not a per-user
credential. Any holder of that token can act as any tenant by supplying an
arbitrary `X-Cowork-User-ID` header — including permanently deleting that
tenant's corpus. The web server is what authenticates real users and decides
which tenant ID to forward. Tenant isolation is therefore a network-topology
property: keep the sidecar internal. When `DIARY_AUTH_TOKEN` is unset the
sidecar runs in open mode; that mode is for local development only.

## Outbound-request policy (SSRF)

Custom inference and remote storage endpoints are administrator-controlled by
 default. Members can use shared providers, local diary storage, and remote
 origins explicitly listed by the operator in `MEMBER_OUTBOUND_ORIGINS` (a
 comma-separated list of scheme + hostname + optional port, without paths).

- Exact origin matching rejects lookalike hostnames and alternate ports.
- Administrators can connect private/local servers for self-hosted inference and storage.
- A DNS pre-check alone is not a security boundary: a hostile hostname could
  change its DNS answer between validation and connection. Members cannot
  supply arbitrary hostnames, including apparently public ones. Only approve
  origins whose DNS and service are trusted by the operator.
- Saved provider chat, storage tests/browsing, Nextcloud poll and returned
  credential URLs, and headers sent to the diary sidecar enforce the same policy.
- Operator-configured external import folders are visible only to administrators.
  Do not mount a shared import library containing another person's private files.
- JSON requests are capped at 1 MiB. Import reads are capped at 2 MiB. Browser
  responses include a Content Security Policy, anti-framing, and MIME-sniffing protection.

## Redirect refusal

URL checks alone are not enough when fetches follow redirects, so every
request to a user-configured target is sent with redirects disabled
(`redirect: 'error'` in Node, `follow_redirects=False` in the sidecar). A
server that bounces requests inward gets a refused request, not a followed
one. A server that legitimately redirects should be configured by its final
URL instead. The sidecar's LLM client is the deliberate exception: its
endpoint comes from the operator's `config.yaml`, not from user input.

## Shared-endpoint throttling

Ordinary chat and diary conversation requests trigger model calls through the
chat endpoint. Requests to them are
throttled per user (60 requests/minute by default, adjustable via
`LLM_RATE_LIMIT`) with a shared bucket, so one account cannot starve the
endpoint for everyone. Sign-in and setup have their own stricter per-IP
limits.

## Credential storage

Provider API keys, storage secrets, and the diary WebDAV/S3 credentials are
encrypted at rest with `state/web/secrets.key` (mode `0600`, generated on
first run). Backups are unusable without that key file — include it in your
own backup strategy or deliberately exclude it. Secrets belong in `.env` or a
secret manager and must never be committed. Note that a host administrator
with filesystem access can always read unencrypted workspace and corpus
files; that trust boundary is the machine itself.

## Operator hardening checklist

Before exposing the deployment beyond a trusted machine:

1. Set `DIARY_AUTH_TOKEN` (protects the web→diary connection) and keep the
   sidecar off public networks.
2. Set `PUBLIC_ORIGIN` (and `WEBAUTHN_RP_ID`) to your real HTTPS origin so
   cookies are `Secure` and origin checks bind to your domain.
3. Put the web server behind HTTPS — a reverse proxy is fine; set
   `TRUST_PROXY=true` so rate limits and audit logs see real client IPs.
4. Set `UI_AUTH_TOKEN` only if you need the legacy direct-token login; it is
   accepted only when `LEGACY_AUTH_COMPAT=true` (one-release migration path —
   disable both after migrating).
5. Rotate `state/web/secrets.key` only alongside a full re-entry of stored
   credentials; losing it makes existing encrypted credentials unreadable.
6. Keep the diary sidecar's port unpublished in your own compose overrides —
   the reference `compose.yaml` gets this right with `expose` rather than
   `ports`.

## Reporting issues

If you find a security problem, please open an issue with the minimum detail
needed to reproduce it, or a fix — this is a self-hosted project, and
reports from real deployments are the most useful kind.

### Diary workspace files and browser folders

Markdown editing is scoped to the current user's configured corpus, rejects unsafe
relative paths, requires the read version, and performs conditional writes. The
editor limit is 512 KiB per file. Browser-folder conversations have a separate bounded
16 MiB request allowance and process snapshots in memory; normal requests retain the
1 MiB limit. Local folder handles are never persisted. Optional sync only writes to
the existing approved storage connection and refuses conflicting remote contents.
See [the diary doc](docs/diary.md) for limits and browser behavior.


## Device app passwords and optional Diary sharing

Device credentials have immutable LAN/public scope, independent revocation and
256-bit random secrets stored only as Argon2id hashes. Only creation returns the
secret (`Cache-Control: no-store`); list metadata never returns a hash. Creation is
limited to five attempts/minute and 20 active credentials per user. These tokens
cannot authenticate account login, chat or general APIs. User deletion cascades
credentials, and disabling an account prevents verification.

The optional separate listener is disabled by default (COWORK_DAV_PORT=0), and
reference Compose files publish no DAV port. Users must also opt in and have Diary
enabled with server-held local storage. The authenticated credential selects the
tenant; paths/headers cannot override it. Writes use the companion file API with
conditional versions, never a direct corpus mount. Read/write limits and supported
operations are documented in [docs/dav.md](docs/dav.md).

LAN scope does not verify physical network reach. Public HTTPS and LAN HTTPS both
require a separate high-entropy secret injected by a trusted TLS-terminating proxy,
plus the configured Host and HTTPS protocol. The proxy must strip incoming copies
of the secret header and keep the backend port private. General TRUST_PROXY and
forwarded IP headers are not treated as encryption or private-network proof.
Direct LAN HTTP requires explicit acknowledgement before opt-in. Scope matching
prevents LAN credentials from authenticating a public-scope listener.

DAV bounds concurrent requests and rate-limits by direct socket address before
Argon2; proxy traffic shares that budget. Response caching is disabled. Credential
creation/revocation and file writes are audited without secrets or file bodies.
Unsupported methods fail explicitly; this initial endpoint does not advertise
full DAV class compliance or general file-manager mounting.
