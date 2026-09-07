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
