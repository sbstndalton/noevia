# Browser ↔ core API contract (v1)

The browser uses same-origin `/api/*` routes served by the core web process. Every
response on that path, including an auth or validation error, carries
`X-Noevia-API: 1`. The header is a **protocol major**, not a release number.
`GET /api/ready` is public and returns `{ "ready": boolean, "version": string }`;
`version` is the identifier in the served `/version.json` artifact when present.
The SPA checks the major before starting session work and stops on a different
major with a reload action. During rollout, a missing header is treated as the
pre-contract v1 core, since its routes already define v1. A network/readiness
failure follows the existing connection error path. A later response through
the shared API client with an explicit different major also stops the app.

V1 is the browser surface shipped when this contract was declared. New optional
fields and routes may be added under v1. Removing or renaming a field, route,
method, status meaning, cookie, or header requires a new major and a release
period with both majors available. The provider must deploy before a consumer
requiring the new major; rollback reverses that order. The missing-header v1
allowance is only for the existing pre-contract release and must not be used to
signal a future major. Release SHAs remain image tags, pinned with
`COWORK_VERSION`; `/version.json` and `/api/ready.version` must
match the served image. Neither field describes sidecar API versions.

The browser sends the `cowork_session` cookie on the same origin. Mutating
authenticated requests carry `cowork_csrf` as `X-CSRF-Token` and pass the server's
Origin check. `401` means the session is unavailable, `403` means the action is
not permitted or the CSRF check failed; other errors use an `{ error: string }`
JSON body where the route is JSON. Core alone resolves tenant scope, tool policy,
and write approvals. No sidecar credential is exposed to the browser. The names
of the cookies, storage keys, and `COWORK_*` environment variables remain frozen
compatibility identifiers. See [service boundaries](spec-service-boundaries.md)
§§3.1, 4, 5 for ownership and mount order.

The table lists the browser's route families. `{id}`, `{path}`, `{name}`, and
similar braces are URL-encoded path segments; query strings are omitted unless
they select a distinct operation. The exact request and response fields are
defined by the linked browser client and route factory; those files must change
with this document when a v1 field changes. Routes under `/api/admin/*`, model
mutations, and code actions have additional role/feature gates in the route
factories. A method listed as `GET/POST` supports both methods, not a generic
write fallback.

| Browser operation | Paths used by the SPA | Methods | Route owner |
| --- | --- | --- | --- |
| Startup and account | `/api/ready`, `/api/setup/status`, `/api/setup/complete`, `/api/auth/login/password`, `/api/auth/login/passkey/options`, `/api/auth/login/passkey/verify`, `/api/auth/invitations/accept`, `/api/auth/recovery/complete`, `/api/auth/session`, `/api/auth/logout` | GET for readiness/status/session; POST for the rest | `routes/health.cjs`, `routes/auth.cjs` |
| Native-client sign-in (feature `nativeClientAuth`, see below) | `/api/auth/device/code`, `/api/auth/device/token`, `/api/auth/device/lookup`, `/api/auth/device/approve`, `/api/auth/devices`, `/api/auth/devices/{id}`, the `/device` page | POST for the flow; GET/DELETE for the device list | `routes/device-auth.cjs`, `device-auth.cjs` |
| Profile and security | `/api/profile`, `/api/profile/features`, `/api/profile/onboarding`, `/api/profile/appearance`, `/api/profile/sharing`, `/api/profile/app-passwords`, `/api/profile/app-passwords/{id}`, `/api/auth/passkeys/register/options`, `/api/auth/passkeys/register/verify`, `/api/auth/passkeys/{id}`, `/api/auth/sessions/{id}` | GET/PATCH/PUT/POST/DELETE by operation | `routes/auth.cjs` |
| Administration | `/api/admin/users`, `/api/admin/users/{id}`, `/api/admin/users/{id}/disabled`, `/api/admin/users/{id}/recovery`, `/api/admin/invitations`, `/api/admin/features`, `/api/admin/features/{name}`, `/api/admin/decision-settings`, `/api/admin/decision-settings/test`, `/api/admin/web-address` | GET/PUT/POST/DELETE by operation | `routes/auth.cjs`, `routes/features.cjs`, `routes/web-address.cjs` |
| Personal data | `/api/account/preferences`, `/api/account/instructions`, `/api/account/memory`, `/api/account/retention`, `/api/usage`, `/api/usage/aggregate`, `/api/export/conversations`, `/api/import/conversations` | GET/PUT/POST by operation | `routes/account.cjs`, `routes/usage.cjs`, `routes/export.cjs`, `routes/import.cjs` |
| Chat and approvals | `/api/workspace`, `/api/freechats`, `/api/freechats/{id}`, `/api/chats/{id}/history`, `/api/chats/{id}/context`, `/api/chats/{id}/context-window`, `/api/chat`, `/api/tool-approvals/{id}`, `/api/toolboxes`, `/api/toolboxes/permitted` | GET/POST/PUT/DELETE by operation | `routes/chat-lists.cjs`, `routes/chat.cjs`, `routes/approvals.cjs`, `routes/toolboxes.cjs` |
| Projects and sources | `/api/projects`, `/api/projects/{id}`, `/api/projects/{id}/config`, `/api/projects/{id}/chats`, `/api/projects/{id}/chats/{chatId}`, `/api/projects/{id}/upload`, `/api/projects/{id}/files`, `/api/projects/{id}/documents`, `/api/projects/{id}/documents/pages`, `/api/projects/{id}/documents/original`, `/api/projects/{id}/assets`, `/api/projects/{id}/assets/{assetId}`, `/api/projects/{id}/source-jobs/{jobId}`, `/api/projects/{id}/sources/sync`, `/api/projects/{id}/instruction-skills`, `/api/projects/{id}/instruction-skills/manifests`, `/api/projects/{id}/instruction-skills/manifests/{skillId}/content`, `/api/projects/{id}/skills/install` | GET/POST/PUT/DELETE by operation; uploads and downloads may be binary | `routes/projects.cjs` |
| Storage and connectors | `/api/integrations/storage`, `/api/integrations/storage/test`, `/api/integrations/storage/files/{path}`, `/api/integrations/storage/folder`, `/api/integrations/storage/file`, `/api/integrations/storage/nextcloud/start`, `/api/integrations/storage/nextcloud/poll`, `/api/connectors`, `/api/connectors/gdrive/connect`, `/api/connectors/gdrive/disconnect`, `/api/connectors/gdrive/policy`, `/api/connectors/gdrive/backup-copy`, `/api/connectors/nextcloud/policy` | GET/POST/PUT/DELETE by operation | `routes/storage.cjs`, `routes/connectors.cjs` |
| Diary | `/api/diary/source`, `/api/diary/today`, `/api/diary/history`, `/api/diary/exchanges`, `/api/diary/context`, `/api/diary/local-exchange`, `/api/diary/storage-status`, `/api/diary/storage-import`, `/api/diary/workspace-import`, `/api/diary/workspace-export`, `/api/diary/files`, `/api/diary/file`, `/api/profile/diary-connectors`, `/api/profile/diary-connectors/{id}`, plus the Diary workspace/entry calls made through `diaryRequest()` | GET/POST/PUT/DELETE by operation; exchange/export streams and archive bodies are route-specific | `routes/diary.cjs`, `routes/projects.cjs` |
| Models and routing | `/api/stats`, `/api/health`, `/api/providers`, `/api/providers/{id}`, `/api/providers/test`, `/api/auto-roles`, `/api/routing-default`, `/api/reasoning-settings`, `/api/sampling-settings`, `/api/models/installed`, `/api/models/capabilities`, `/api/models/hardware`, `/api/models/estimate`, `/api/models/evidence`, `/api/models/evidence/recheck`, `/api/models/evidence/import`, `/api/models/load`, `/api/models/unload`, `/api/models/delete`, `/api/models/presets/reload`, `/api/models/calibration`, `/api/models/calibration/cancel`, `/api/models/autotune`, `/api/models/autotune/cancel`, `/api/models/autotune/resume`, `/api/models/autotune/untuned`, `/api/model-manager/*` | GET/POST/PUT/DELETE by operation; jobs may stream | `routes/health.cjs`, `routes/providers.cjs`, `routes/models.cjs`, `routes/reasoning-settings.cjs`, `routes/sampling-settings.cjs` |
| ChatGPT connection | `/api/providers/chatgpt`, `/api/providers/chatgpt/device`, `/api/providers/chatgpt/device/poll`, `/api/providers/chatgpt/device/cancel`, `/api/providers/chatgpt/models` | GET/POST/DELETE by operation | `routes/providers.cjs` |
| MCP and plugins | `/api/mcp-keys/servers`, `/api/mcp-keys/{id}`, `/api/mcp-oauth/servers`, `/api/mcp-oauth/{id}/connect`, `/api/mcp-oauth/{id}`, `/api/admin/mcp-directory`, `/api/admin/mcp-directory/custom`, `/api/admin/mcp-directory/custom/preview`, `/api/admin/mcp-directory/{id}/oauth-client`, `/api/plugins/directory` | GET/POST/PUT/DELETE by operation | `routes/mcp-directory.cjs`, `routes/plugin-directory.cjs` |
| Backup and optional tools | `/api/admin/offsite-backup`, `/api/admin/offsite-backup/run`, `/api/admin/offsite-backup/verify`, `/api/admin/offsite-backup/copy`, `/api/admin/offsite-backup/recovery-key`, `/api/admin/offsite-backup/google/connect`, `/api/admin/offsite-backup/google/disconnect`, `/api/features`, `/api/code/active`, `/api/projects/{id}/code/*`, `/api/projects/{id}/browser/*` | GET/POST/PUT/DELETE by operation | `routes/offsite-backup.cjs`, `routes/features.cjs`, `routes/code.cjs`, `routes/browser.cjs` |

`POST /api/chat` and Diary exchange routes may return server-sent events. The
browser posts a tool decision to `/api/tool-approvals/{id}`; the core still
enforces `Allow once`, `Allow for this chat`, and `Deny`. Projects/assets,
documents, exports, and imports may use binary payloads. The browser's
[`api.ts`](../apps/web/src/api.ts) and component-specific clients contain the
request shapes; the corresponding `routes/*.cjs` factories define status and
response bodies.

## Native clients: authentication (#555)

A non-browser client (the macOS app's NoeviaKit, a script) has two ways to sign in.

**Browser-equivalent session.** `POST /api/auth/login/password` with the same cookies and
CSRF header as the browser. A request **without** an `Origin` header passes the Origin
check. This is part of the v1 contract. A request that does send `Origin` must send an
allowed one. When the public origin is https, the session cookies are `Secure`, so a
client on a LAN `http://` address cannot keep this session.

**Device sign-in (preferred).** This is available while the `nativeClientAuth` feature is
on (`NOEVIA_FEATURE_NATIVE_CLIENT_AUTH`, or Settings → Features). It is **off by default**,
and it **can only be switched on while `TRUST_PROXY=true`**. Otherwise it is reported as
unavailable ("Needs TRUST_PROXY on so sign-in limits can tell clients apart"), and even the
environment variable cannot enable it. Behind a reverse proxy such as the Cloudflare tunnel
without `TRUST_PROXY`, every request carries the proxy's address. Per-client limits on new
sign-ins would then be one shared bucket that anyone could fill. So enabling the feature
means configuring the proxy to append the client address to `X-Forwarded-For` and setting
`TRUST_PROXY=true`.
While it is off, every route below and the `/device` page answer `404`, and nothing else
changes. It is the OAuth 2.0 Device Authorization Grant (RFC 8628). A PKCE loopback redirect
was not used for three reasons. The core has no OAuth authorization endpoint or redirect
handling. The public address often differs from the address a LAN client uses. And a device
flow also works when the approving browser is on another device, such as a phone.

1. `POST /api/auth/device/code` with `{ "client_name": "Noevia for Mac" }` (JSON or
   form-encoded, no credential) returns `{ device_code, user_code, verification_uri,
   verification_uri_complete, expires_in: 600, interval: 5 }`. `user_code` is `XXXX-XXXX`
   from an alphabet with no vowels. `client_name` is required. It is shown to the person
   with control characters removed, cut to 60 characters. Limits (`429`): 10 per client name
   per 15 minutes, 200 per 15 minutes for the whole server, and 10 per address only when
   `TRUST_PROXY` is on. Behind the Cloudflare tunnel without it, every request carries the
   same address, so an address limit would let anyone block everyone.
2. The person opens `verification_uri` (`/device`, with `?code=` in the complete form) in a
   browser where they are signed in, or signs in there first. The page looks the code up
   with `POST /api/auth/device/lookup { user_code }`. It shows the app's name, the code to
   compare, the time, and which account the approval signs the app in to, with a "Not you?
   Sign out" action for shared browsers. It shows the requesting address only when
   `TRUST_PROXY` is on (`ip` is `null` otherwise). The person chooses Approve or Deny
   (`POST /api/auth/device/approve { user_code, approve }`). Both need a cookie session and
   CSRF. A device token, or the legacy `UI_AUTH_TOKEN` bearer, gets `403
   browser_session_required`. Lookups and decisions are limited to 20 per account per 15
   minutes (`429`). An unknown, expired or already decided code is `404`.
3. The client polls `POST /api/auth/device/token` with `{ grant_type:
   "urn:ietf:params:oauth:grant-type:device_code", device_code }`. It gets `400` with
   `authorization_pending`, `slow_down` (the interval grows by 5 s), `access_denied`,
   `expired_token` or `invalid_grant`, per RFC 6749 §5.2, until approval. It then gets `200
   { access_token, token_type: "Bearer", expires_in: 3600, refresh_token, scope: "api" }`,
   with `Cache-Control: no-store`. The device code is single use.
   Rate limits on this endpoint never use the address alone. A malformed request
   (`unsupported_grant_type`, `invalid_request`) is refused before anything is charged. A
   well-formed request is charged to the credential it presents (its device code or refresh
   token), 150 per credential per 15 minutes. Device-code polls also count toward a
   server-wide backstop of 5000, but each code counts only for its first 20 polls. So pending
   codes, at most 200 per window, cannot fill it by polling. Refreshes never count toward it:
   a refresh token cannot exist without an approval and has its own limit. A device code or
   refresh token the server does not know goes to a separate bucket of 300 per 15 minutes
   (per address when `TRUST_PROXY` is on). So junk requests, and polls from pending codes,
   can never use up a real device's refresh budget. Each grant may refresh at most 30 times
   per 15 minutes (`429 slow_down`, checked before rotating, so the current pair keeps
   working). Otherwise every refresh would mint a token with a fresh budget and one device
   could loop without limit.
4. `{ grant_type: "refresh_token", refresh_token }` on the same endpoint rotates both tokens.
   The previous access token stops working at once. A refresh token presented a second time
   is **reuse**: the server revokes the whole grant, audits `device.refresh_reuse`, and
   answers `invalid_grant`. There is one exception, for a client whose refresh answer was
   lost in transit. For 60 seconds after its first use, the previous refresh token is accepted
   again **if the token that replaced it has not been used**. The unused successor is then
   discarded and a new pair issued, and the event is audited as `device.refresh_grace`. The
   discarded successor is kept, marked used. **Presenting it later is reuse and revokes the
   grant.** So if a thief replays a stolen previous token inside the window, the real
   client's next refresh, with the token the thief made obsolete, signs both out and
   records `device.refresh_reuse`. The window counts from the first use and is not extended
   by retries. Once the successor has been used, the old token is reuse. A client must save a
   new pair durably (NoeviaKit: to the Keychain) before using it. Used refresh tokens older
   than the window are pruned on each rotation. Only the latest link, the token just
   replaced, is kept, together with any discarded successors. So reuse detection covers the
   previous token and every discarded one, and presenting an older, pruned token is
   `invalid_grant` without a revoke.

Tokens are 256-bit random values (`nva_…` access, `nvr_…` refresh). The server stores only
their SHA-256. Each approval creates one **grant**: a device, bound to the approving
account (the tenant). A grant ends after 7 idle days or 30 days in total, the same as a
session. Disabling the account, a password reset and account deletion revoke all of its
grants. **Turning the feature off revokes every device**: an administrator switching it off,
or the server starting with it off (including because `TRUST_PROXY` is not set), deletes
every grant and every pending or approved sign-in request. It records one
`device.revoke_all` entry per affected account. Turning it on again revives nothing; each device must be
approved again.

A device token is sent only as `Authorization: Bearer nva_…`. A query-string token is
ignored. It authorises the same v1 routes as the browser, as the same user, with three
differences:

- **Never an administrator.** The request's effective role is `member`, so every
  administrator gate refuses it. `GET /api/auth/session` returns that user plus
  `accountRole`, `csrfToken: null` and `device: { id, clientName, expiresAt }`.
- **Never account security.** The router answers `403 { code: "browser_session_required" }`
  before any route runs for these paths: `/api/admin/*`, `/api/auth/passkeys/*`,
  `/api/auth/sessions/*`, `/api/auth/devices*`, `/api/auth/device/lookup|approve`,
  `/api/profile` itself, `/api/profile/app-passwords*`, `/api/profile/diary-connectors*`,
  `/api/profile/sharing`, `/api/integrations/storage/nextcloud/*`, a write to
  `/api/integrations/storage` or `/api/integrations/storage/test`, `/api/mcp-keys/*`,
  `/api/mcp-oauth/*`, `/api/providers/chatgpt*`, and every write under `/api/connectors/`
  (linking or unlinking Google Drive, and the Drive and Nextcloud allow/ask/block tool
  policies). Reading `GET /api/connectors` stays allowed. A device therefore cannot mint more
  credentials, approve another device, link an account it controls, or pre-allow tools.
  Changes like those would outlive the device's revocation.
- **No CSRF.** A bearer token is not sent by the browser on its own, so the CSRF header
  does not apply. Cookies and a device bearer **together** are refused with `400
  ambiguous_credentials`, so neither can ride along with the other. A request with an
  `Origin` header on a write still has to pass the Origin check, as a browser write does.

Tenant scope, tool policy and all three write approvals are unchanged: a device answers its
own approval cards through `/api/tool-approvals/{id}`. `POST /api/auth/logout` with a device
token revokes that device.

**Devices in Settings.** `GET /api/auth/devices` lists the caller's own grants: `{ devices:
[{ id, clientName, createdAt, lastUsedAt, expiresAt, ip, userAgent }] }` (`ip` is `null`
unless `TRUST_PROXY` is on). `lastUsedAt` is
updated at most once a minute. `DELETE /api/auth/devices/{id}` revokes one. Its tokens are
deleted, so the next request with them is `401`. Another account's id is `404`. Both need a
browser session. The audit log records `device.approve`, `device.deny`, `device.token`
(tokens issued), `device.refresh_grace`, `device.refresh_reuse`, `device.revoke` and
`device.revoke_all`.

## Portable instruction Skill manifest v1

An authenticated web or native client lists project Skills with
`GET /api/projects/{id}/instruction-skills/manifests`. This additive route
returns `{ "schemaVersion": 1, "skills": [...] }` without instruction bodies.
The existing `GET/PUT /instruction-skills` response still contains bodies for
the current Sources UI. Both routes use the core's project ownership lookup.

Each manifest has a project-scoped stable `id` (derived from project ID and
filename), `file`, `name`, `description`, optional `versionLabel`, `version`
(the lowercase SHA-256 digest of the complete copied Markdown), `status`,
`valid`, `error`, `origin`, `compatibility`, `license`, `requirements`, and
`resolvable`. The digest, rather than the human version label, identifies the
exact artifact. `status` is `review`, `updated`, `enabled`, `disabled`, or
`invalid`. `requirements` contains declared `toolboxes` and `allowedTools`
plus `unsupportedToolboxes` and `unselectedToolboxes` at discovery time, and
`scripts`, the Skill's bundled executable files. The
former compares declarations with toolboxes currently offered by core; the
latter names known boxes not selected for the project. Requirements and `allowed-tools` are
informational metadata: they grant no tools, credentials, or approvals, and the
client must not treat them as an authorization result. An unknown toolbox blocks
portable content resolution with `422`; a merely unselected known toolbox is
reported for the user to configure through the existing toolbox picker, and is
enforced when the Skill is used (see below). `allowed-tools` is limited to 32
entries and 1,024 characters, `compatibility` to 500 characters.

`assets` lists the other project files in a `<dir>/SKILL.md` Skill's directory,
each with its own SHA-256 `version` and `executable` (a file under `scripts/`,
an executable extension, or a `#!` first line). A root `SKILL.md` or a
single-file Skill has no assets. Chat has no tool that executes project files,
so a Skill with any executable asset is `resolvable: false`: its content read
returns `422`, a pin is refused with `422 skill_scripts_unsupported`, and it is
never loaded automatically. Its assets stay ordinary text sources. A later
runner would have to go through the qualified code sandbox and the existing
approval gate.

The Sources list (`GET/PUT /instruction-skills`) additionally carries each
Skill's portable `id`, `origin` and `scripts`, so the web client shows where a
Skill came from, its SHA-256, and why bundled scripts block it.

To read the reviewed instructions, call
`GET /api/projects/{id}/instruction-skills/manifests/{skillId}/content?version={sha256}`.
It returns `{ "manifest": ..., "content": "..." }` only when that exact
version remains enabled and reviewed in the owning project. A missing project or
Skill returns `404`, an absent or malformed version `400`, a changed, disabled,
or unreviewed version `409`. A client must refresh discovery after `409`, then
obtain the owner's review before using a changed version. Disabling one Skill
blocks its subsequent reads and future chat injection without changing others.
It also revokes the Skill inside an exchange that is already running (see
"Revocation during an exchange" below).

An imported Skill's `origin` records `kind: published`, `publisher`,
`repository`, `sourceRef`, `sourcePath`, `digest`, and `retrievedAt`. The directory currently
copies `SKILL.md` from Anthropic's moving `main` branch. `sourceRef` is therefore
**not** an immutable Git commit; `digest` pins the exact copied bytes held by
this project. Local uploads and edits, including files in the project's own upload folder, are `project-file`; files from a linked (attached) folder
are `attached-folder`. Replacing imported content clears its published origin.
Updates require the existing explicit review step. No background update or
remote re-fetch occurs during resolution.

Portable v1 supports Markdown instructions only. It does not fetch or
execute bundled assets or scripts, and its restricted frontmatter rejects
executable metadata. `compatibility`, `license`, and `allowed-tools` are
descriptive fields, not runtime grants. To use a Skill in an assistant turn,
the client invokes the existing project chat route; core continues to select
tools and enforce tenant scope, tool policy, and every write approval. The
manifest/content pair lets clients select the same reviewed version; it does
not create an arbitrary Skill execution engine.

### Version-pinned invocation

A chat request may name one Skill version explicitly with an additive `skill`
field on `POST /api/chat`: either `"skill_<id>@<sha256>"` or
`{ "id", "version", "contentHash" }`, where `version` is the manifest's SHA-256
`version`, or its `versionLabel` together with `contentHash`. Core resolves the
pin only against the reviewed, enabled content of the chat's own project (loaded
through the tenant-scoped project store), re-hashes the stored Skill file itself
rather than trusting the cached manifest, and places that file's body (frontmatter
stripped, length-capped) in that turn's system prompt instead of automatic Skill
selection. Pin resolution precedes creating a new project chat, so a refused pin
leaves no empty chat entry.
Refusals happen before any retrieval, model or tool work and return
`{ "error", "code" }`: `400 skill_pin_invalid` (malformed, or on compaction),
`400 skill_pin_requires_project`, `404 skill_not_found` (including an id from
another project or tenant), `404 skill_version_unknown`,
`409 skill_version_changed` (the reviewed version was replaced on disk),
`409 skill_version_unreviewed`, `409 skill_disabled`, `409 skill_hash_mismatch`
(version, label and content hash disagree), `422 skill_invalid`,
`422 skill_unsupported_requirements`, `422 skill_scripts_unsupported`, and
`422 skill_requirements_unmet` (with `missing`: a required toolbox that this
request does not carry after the project selection, per-message
`turnToolboxes`, the Diary add-on and sign-in filters. The Skill never adds the
toolbox). If the chosen provider then strips a required box (the Diary is never
offered to an external provider), the stream ends with an `error` event carrying
`code: "skill_requirements_unmet"` before any model request. A resolved pin is echoed as `skill`
(`id`, `file`, `name`, `versionLabel`, `version`, `contentHash`, `origin`) on
the stream's `meta` event and recorded on the durable turn checkpoint when that
seam is enabled. Without `skill` the turn is unchanged. A pin selects
instructions only: tool choice, tool policy and every write approval are
unchanged. Cowork-mode requests refuse a pin with
`400 skill_pin_unsupported_mode` rather than drop it. Types
are in [`api-contract.ts`](../apps/web/src/api-contract.ts).

The web composer uses this same contract. Its Skill selector lists the
manifests that are `enabled` and `resolvable`, and sends `skill_<id>@<version>`
with that one message. "Automatic" (the default) sends no pin. The selector is
re-read after each reply, so a Skill that was disabled or changed drops out.
A native client does the same with the manifest list and `POST /api/chat`.

Automatic Skill loading uses the same checks. The router only considers
enabled Skills that are `resolvable` and whose required toolboxes this request
carries. If the provider strips a box that an automatically loaded Skill needs,
that Skill's body is removed from the prompt before any model request.

### Revocation during an exchange

A Skill counts as loaded in an exchange when the exchange pinned it or loaded it
automatically. It also counts when the model read it, which core tracks by what
was read rather than by tool name. A successful tool call counts if it names the
Skill's file (for example `read_project_file`, or the Project documents box's
`project_read_file`). It also counts if its result contains the Skill's
SHA-256. Core records the
SHA-256 it loaded and compares it with the project as stored now, not with the
exchange's snapshot. The check runs before each model round and before each tool
call. It runs again after an approval card is answered, before dispatch. While a
reply streams, it runs at most once a second. If a loaded Skill is disabled,
changed, awaiting review, removed, or its project is gone:

- The pending tool call is not run, even if it was approved. Its result is an
  `ERROR` telling the model it was not run, and the audit log records
  `tool.denied` with reason `skill-revoked`.
- A streaming reply is cut off. Text already shown stays. Each tool call
  already streamed in that round gets an `ERROR` `tool_result` saying it was not
  run.
- No further model round starts, and step supervision is not consulted. The reply ends with an `error` event carrying
  `code: "skill_revoked"`, and the durable turn is interrupted.

Skills the exchange did not load are not consulted, so disabling one never stops
an exchange that did not use it. "Allow for this chat" approvals belong to the
chat rather than to any Skill. They are unchanged, and so are all three approval
actions.

The durable turn checkpoint records the pin as `skill`, and every loaded Skill
as `skills: [{ file, name, contentHash }]`. `skills` is updated when a read
loads another Skill and is absent when none was loaded. The continuation seam
(`chat-turns.cjs` `resumeGeneration`) refuses the turn unless the caller's
`skillActive(record)` confirms that each of those exact versions is still
enabled (`instruction-skills.cjs` `pinActive`). This check exists but is **not
yet wired to a production caller**: `resumeGeneration` is an internal seam with
no route today. Any future caller must pass `skillActive`, because without it a
turn that loaded Skills is refused.

### Revoked Skills in earlier turns

The `history` a client sends with the next message can still hold a Skill from
an earlier reply: a replayed `tool`/`function` message with a
`read_project_file` or `project_read_file` result, or an assistant reply that
repeated the body. Core never trusts the client to say which text came from a
Skill. It decides from its own records (`server/skill-history.cjs`):

- Every Skill version an exchange loads (pinned, automatic or read) is recorded
  in a ledger in the account's own workspace directory, keyed by project. Each
  entry holds the file, name, SHA-256, the chats that loaded it, and SHA-256
  fingerprints of its lines. The ledger holds no copy of the body. It keeps up
  to 64 versions per project. Over the cap, versions that are still enabled are
  dropped before revoked ones. An unreadable ledger is moved aside to
  `skill-history.json.corrupt`, and malformed entries are dropped on load.
  Nothing is written for an account whose workspace was deleted.
- A Skill that is disabled now, and has no ledger entry, is recognised from the
  project by its SHA-256 only. That covers a Skill loaded before the ledger
  existed, and never matches text of a Skill that was switched off without ever
  being enabled.

A recorded version is revoked once its file and SHA-256 are no longer an enabled
Skill of the project, whether it was disabled, changed or removed. Before the
model request is built, core replaces revoked content in the history with
`[Skill "<name>" was disabled or changed, and its instructions were removed]`.
It checks again against the project as stored just before the first model
request, so a Skill disabled while the request was prepared is caught too.

- A `tool`/`function` message that is the Skill reader's output for that
  version is replaced as a whole, in any chat of the project.
- Any other line naming that version's SHA-256 is replaced, in any chat of the
  project.
- A verbatim echo of its body is replaced only in a chat the ledger says loaded
  that version. It must be a run of at least two identifying lines, or one
  identifying line of 80 characters or more. A single common line shared with a
  Skill is never enough, and code fences are never taken.

The reply also gets a `warning` event saying that earlier replies used the Skill.
Skills that are still enabled at the same SHA-256 are left untouched, and so is
any line that also belongs to an enabled Skill. Chats without Skills are left
untouched too: after the ledger's first read per account, the check runs in
memory.

Limits: user messages are never rewritten, because the person may have typed
the text themselves. System messages are not scrubbed either: core builds them
from the current project, and in-flight revocation (above) covers Skills loaded
into them. A paraphrase, or a quotation inside a longer
line, is not recognised. An echo in a chat with no ledger record of the Skill is
not recognised. Text that claims to be from a Skill but matches no server record
is ordinary history. A compaction summary over the old text stops applying once
the history it covered changes, and is rebuilt from the scrubbed history.
