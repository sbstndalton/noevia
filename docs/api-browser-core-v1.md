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
| Profile and security | `/api/profile`, `/api/profile/features`, `/api/profile/onboarding`, `/api/profile/appearance`, `/api/profile/sharing`, `/api/profile/app-passwords`, `/api/profile/app-passwords/{id}`, `/api/auth/passkeys/register/options`, `/api/auth/passkeys/register/verify`, `/api/auth/passkeys/{id}`, `/api/auth/sessions/{id}` | GET/PATCH/PUT/POST/DELETE by operation | `routes/auth.cjs` |
| Administration | `/api/admin/users`, `/api/admin/users/{id}`, `/api/admin/users/{id}/disabled`, `/api/admin/users/{id}/recovery`, `/api/admin/invitations`, `/api/admin/features`, `/api/admin/features/{name}`, `/api/admin/decision-settings`, `/api/admin/decision-settings/test`, `/api/admin/web-address` | GET/PUT/POST/DELETE by operation | `routes/auth.cjs`, `routes/features.cjs`, `routes/web-address.cjs` |
| Personal data | `/api/account/preferences`, `/api/account/instructions`, `/api/account/memory`, `/api/account/retention`, `/api/usage`, `/api/usage/aggregate`, `/api/export/conversations`, `/api/import/conversations` | GET/PUT/POST by operation | `routes/account.cjs`, `routes/usage.cjs`, `routes/export.cjs`, `routes/import.cjs` |
| Chat and approvals | `/api/workspace`, `/api/freechats`, `/api/freechats/{id}`, `/api/chats/{id}/history`, `/api/chats/{id}/context`, `/api/chats/{id}/context-window`, `/api/chat`, `/api/tool-approvals/{id}`, `/api/toolboxes`, `/api/toolboxes/permitted` | GET/POST/PUT/DELETE by operation | `routes/chat-lists.cjs`, `routes/chat.cjs`, `routes/approvals.cjs`, `routes/toolboxes.cjs` |
| Projects and sources | `/api/projects`, `/api/projects/{id}`, `/api/projects/{id}/config`, `/api/projects/{id}/chats`, `/api/projects/{id}/chats/{chatId}`, `/api/projects/{id}/upload`, `/api/projects/{id}/files`, `/api/projects/{id}/documents`, `/api/projects/{id}/documents/pages`, `/api/projects/{id}/documents/original`, `/api/projects/{id}/assets`, `/api/projects/{id}/assets/{assetId}`, `/api/projects/{id}/source-jobs/{jobId}`, `/api/projects/{id}/sources/sync`, `/api/projects/{id}/instruction-skills`, `/api/projects/{id}/skills/install` | GET/POST/PUT/DELETE by operation; uploads and downloads may be binary | `routes/projects.cjs` |
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
