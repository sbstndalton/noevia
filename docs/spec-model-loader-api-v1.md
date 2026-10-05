# Model Loader `/api/v1` contract (web to model-loader)

Status: current behaviour, documented for #269. Sits under `docs/spec-service-boundaries.md`
section 5 (versioned internal API) and section 6.3 (M3, one owner for `models.ini`).

Scope: the JSON API served by `services/model-manager/app/api.py` (the `model-loader`
container) and consumed by noevia web. It does **not** cover Lemonade's own `/api/v1/*`
(`pull`, `load`, `unload`, ...) that `apps/web/server/model-manager.cjs` speaks when
`MODEL_MANAGER_KIND=lemonade`; that is a different service with a different owner.
model-loader serves no pages: its server-rendered UI (`/`, `/models`, `/config`, ...) was
removed in #806, and `/api/v1/*` is the whole surface.

The route table below is checked by tests, so a route added to or removed from either
side fails CI until this file is updated:

- `apps/web/server/model-loader-contract.test.cjs` parses `api.py`, the web server
  callers and the browser callers and compares them with the table.
- `services/model-manager/tests/test_api_contract.py` compares the live FastAPI router
  with the table.

## 1. Transport, auth, versioning

| Item | Value |
| --- | --- |
| Base URL | `MODEL_LOADER_URL` (internal Compose network; not published) |
| Prefix | `/api/v1`; there is no negotiation header. Breaking changes need a new prefix. |
| Auth | `X-Model-Loader-Token: <MODEL_LOADER_TOKEN>` on every route except `GET /api/v1/health`. |
| Token unset on the sidecar | Auth is off (development only); web still sends the header when it has a token. |
| Bad or missing token | `401` with body `{"error":"unauthorized"}` (constant-time compare). |
| Format | JSON in and out. Errors from route code are FastAPI `{"detail": "<message>"}`; the auth error uses `error`. |
| Caller | Only noevia web. Browsers never reach model-loader; administrators go through the web proxy (section 5). |

The token value is never logged or echoed. Web maps `401`/`403` from `PUT /models-ini` to a
message that names `MODEL_LOADER_TOKEN` without revealing it.

## 2. Route table

"Web caller" column: `server` = called by the web server itself; `browser` = called by the
admin UI through the proxy in section 5; `proxy` = only reachable through the proxy, no UI
caller today; `healthcheck` = container healthcheck, not web.
Path parameters are written `{name}`; the tests normalise their names.

<!-- route-table:start -->
| Method | Path | Web caller | Purpose |
| --- | --- | --- | --- |
| GET | /api/v1/health | healthcheck | Liveness, `{"ok": true}`. The only unauthenticated route. |
| GET | /api/v1/overview | browser | Models folder, disk, backends, `revision`. |
| GET | /api/v1/models | server, browser | Folder scan of GGUF files, `unregistered` stems, `revision`. |
| GET | /api/v1/models/detail | browser | One file with GGUF summary; query `key`. |
| POST | /api/v1/models/delete | browser | Delete files by scan key; body `{"models": [key]}`. |
| POST | /api/v1/models/check-updates | browser | Ask Hugging Face whether downloaded models changed. |
| GET | /api/v1/models/updates | browser | Last update status per file. |
| GET | /api/v1/sections | browser | Parsed sections, schema, raw text, backups, `revision`. |
| GET | /api/v1/sections/{name} | browser | One section as form values; `?defaults=true` fills GGUF hints. |
| PUT | /api/v1/sections/{name} | browser | Save one section, pinned to `baseRevision`. |
| POST | /api/v1/sections/{name}/safe-defaults | server, browser | Register a fresh GGUF with conservative settings, once. |
| POST | /api/v1/sections/{name}/rename | browser | Rename a section, pinned to `baseRevision`. |
| DELETE | /api/v1/sections/{name} | browser | Delete a section; query `baseRevision`. |
| GET | /api/v1/sections/{name}/autoconfig | browser | Computed settings proposal for a section. |
| GET | /api/v1/sections/{name}/draft-heads | browser | Draft-head candidates for a section. |
| POST | /api/v1/sections/{name}/draft-heads/download | browser | Queue a draft-head download. |
| PUT | /api/v1/models-ini | server | Whole-file compare-and-swap replace (M3 single writer). |
| GET | /api/v1/backends | browser | Engine containers, stats, history. |
| POST | /api/v1/backends/{name}/restart | browser | Restart an engine container (Docker socket). |
| GET | /api/v1/backends/{name}/logs | browser | Redacted log tail; `q`, `level`, `tail`. |
| POST | /api/v1/backends/{name}/test | browser | Send a test prompt to a backend. |
| GET | /api/v1/backends/{name}/diagnose | browser | Diagnosis of start-up failures. |
| GET | /api/v1/host | browser | Host hardware history. |
| GET | /api/v1/settings | browser | Hugging Face token status (`hasToken`, `tokenHint`). |
| PUT | /api/v1/settings | browser | Set or clear the token; `test: true` validates it. |
| GET | /api/v1/search | browser | Hugging Face model search. |
| GET | /api/v1/search/repo | browser | Files of one repository; query `repo`. |
| GET | /api/v1/download-targets | browser | Folders downloads may land in. |
| GET | /api/v1/downloads | browser | Download jobs. |
| POST | /api/v1/downloads | browser | Queue downloads (Hugging Face or URL). |
| POST | /api/v1/downloads/{job_id}/cancel | browser | Cancel one job. |
| POST | /api/v1/downloads/clear | browser | Clear finished jobs. |
| GET | /api/v1/prompts | browser | Benchmark prompt suite. |
| POST | /api/v1/prompts | browser | Add a prompt `{name, body}`. |
| DELETE | /api/v1/prompts/{pid} | browser | Delete a prompt. |
| GET | /api/v1/benchmark | browser | Benchmark overview and recent runs. |
| POST | /api/v1/benchmark/start | browser | Start a prompt benchmark. |
| POST | /api/v1/benchmark/sweep | browser | Start a throughput sweep. |
| GET | /api/v1/benchmark/progress | browser | Current job. |
| POST | /api/v1/benchmark/cancel | browser | Cancel the current job. |
| GET | /api/v1/benchmark/runs/{run_id} | browser | One finished run with charts. |
| PUT | /api/v1/badges | browser | Set a rating badge. |
| DELETE | /api/v1/badges | browser | Clear a rating badge; query `alias`, `category`. |
<!-- route-table:end -->

## 3. Common behaviour

Status codes used by every route:

| Code | Meaning |
| --- | --- |
| 200 | Success. Mutating routes return `{"ok": true, ...}` or the new list. |
| 400 | Invalid input (bad name, missing field, unsafe path or value). Nothing changed. |
| 401 | Token missing or wrong. |
| 404 | Section, model, job, run, prompt or backend not found. |
| 409 | Conflict: stale `baseRevision`, name already used, or an operation already running. |
| 413 | `PUT /models-ini` body over 1 MiB. |
| 422 | FastAPI validation of query or path types (for example a non-integer `run_id`). |
| 500 | Unexpected failure. For `PUT /models-ini` this is a write that was rolled back, see section 4. |

Timeouts are chosen by the caller; model-loader imposes none of its own on a request:

| Caller | Timeout |
| --- | --- |
| `PUT /models-ini` (web `models-ini-writer.cjs`) | 30 s |
| `GET /models` folder-scan refresh and the delete guard | 60 s |
| `safe-defaults` and other server-side `managerFetch` calls | 120 s |
| Admin proxy (any route) | 10 min |

A timeout or transport failure on web's side is an unknown outcome for a write, not a
failure; see the reconciliation rules in section 4.

Idempotency: `GET` routes are read-only. `DELETE`/`POST` on sections, prompts, badges and
downloads are not idempotent (a repeat returns `404` or `409`). `safe-defaults` never
overwrites: a repeat returns `409`. `PUT /sections/{name}` and `PUT /models-ini` are
idempotent only through the revision pin described next.

## 4. `models.ini`: single writer, compare-and-swap

### Revision

`revision` is the lowercase hex SHA-256 of the exact bytes of `models.ini` (SHA-256 of the
empty string when the file does not exist). It is returned by `GET /overview`,
`GET /models`, `GET /sections`, `GET /sections/{name}` and every successful write.

### Compare-and-swap rules

Every pinned write to `models.ini` (`PUT /sections/{name}`, `POST .../rename`, `DELETE
/sections/{name}`, `PUT /models-ini`) takes the process-wide write lock, then compares
`baseRevision` with the current revision **inside the lock**:

| Condition | Response |
| --- | --- |
| `baseRevision` absent or empty | `400` `baseRevision is required` |
| `baseRevision` differs from the current revision | `409` `models.ini changed since you loaded it...`; nothing written |
| Match | write, then `200` with the new `revision` |

`POST .../safe-defaults` needs no revision; it is conditional on the section not existing
and the file not being claimed (`409` otherwise), evaluated under the same lock.

### `PUT /api/v1/models-ini`

Request `{"baseRevision": "<sha256>", "text": "<whole file>"}`. The text is stored
verbatim (comments and layout kept).

| Outcome | Status | Body | State of the file |
| --- | --- | --- | --- |
| Written | 200 | `{"ok": true, "revision": "<sha256 of text>"}` | new text |
| Missing or blank `text` | 400 | `text is required` | unchanged |
| Text does not parse as ini | 400 | `models.ini text does not parse` | unchanged |
| Same `[section]` more than once | 400 | `models.ini has duplicate sections: [name]` | unchanged |
| Over 1 MiB | 413 | `models.ini exceeds the editor limit` | unchanged |
| Stale or missing `baseRevision` | 409 / 400 | see above | unchanged |
| Filesystem error | 500 | `models.ini could not be written safely; nothing was changed` | unchanged |

Write procedure: keep an immutable `models.ini.noevia-backup-<baseRevision>` and a rotating
`.bak-<ts>` copy (a backup failure aborts before the file is touched), write a fsynced
temp file with the current mode, `rename` over `models.ini`, fsync the directory. The
engine therefore always sees a whole file.

Idempotency: replaying the same request after a success returns `409` (the file now has a
different revision), unless the text equals the old text. Clients settle an unknown
outcome by reading the file back rather than by retrying blindly.

### Web client behaviour (`MODELS_INI_WRITER`)

| Mode | Behaviour |
| --- | --- |
| `model-loader` (default in `compose.llamacpp.yaml`) | Model-loader is the single writer. Web prepares the whole file, sends `PUT /models-ini` with `baseRevision`, and never writes the file; its `/llamacpp-config` mount is `:ro`. Requires `MODEL_LOADER_URL`. Web still reads the file directly. |
| `web` (code default when unset; rollback) | Web writes `models.ini` itself, atomically, in process; needs the `:ro` removed from its mount. On a read-only mount, startup logs an error and every save returns 503 `models.ini is on a read-only mount while MODELS_INI_WRITER=web, so nothing was changed`. |
| anything else | Startup error `unsupported MODELS_INI_WRITER`. |

Mapping of `PUT /models-ini` results to web errors (`apps/web/server/models-ini-writer.cjs`):

| Result | Web response | Uncertain? |
| --- | --- | --- |
| 200 with `ok: true` | success, uses returned `revision` | no |
| 401, 403 | 503 token rejected, nothing changed | no |
| 404, 405 | 503 sidecar too old (route missing), nothing changed | no |
| 409 | 409 presets changed, reload before retrying | no |
| 400, 413 | same status, message from `detail` | no |
| 5xx, timeout, transport loss, unexpected body | 503 not confirmed | yes |

For an uncertain result web re-reads the file: current revision equals the SHA-256 of the
sent text means it committed (success); equals `baseRevision` means it did not (retryable
503); anything else means a third party changed it (409, left untouched).

## 5. How web reaches these routes

1. **Server callers** (rows marked `server`): `GET /models` (folder scan cache refresh and
   the delete guard, 60 s), `POST /sections/{stem}/safe-defaults` (auto-register a new
   file, 120 s), `PUT /models-ini` (flag-gated, 30 s). All send the token header.
2. **Admin proxy** `/api/model-manager/<rest>` to `MODEL_LOADER_URL/api/v1/<rest>`:
   - administrators only (`403` otherwise); `404` when `MODEL_LOADER_URL` is unset;
     `400` for a path outside `[\w./%:+@-]` or containing `..`;
   - same method, query and body (1 MiB body cap), token added by the server;
   - transport failure, timeout or unreadable reply gives `502`; otherwise the upstream
     status is returned with its JSON body;
   - guards applied before forwarding: `models/delete` refuses system and sidecar
     models; `sections/{name}` and `.../rename` refuse system models (and `DELETE` also
     sidecar models); `benchmark/start` refuses non-chat models;
   - any non-`GET` clears the folder-scan cache;
   - the proxy forwards any `/api/v1` path, including `PUT /models-ini`; the
     compare-and-swap above is the protection there.
3. The browser UI (`apps/web/src/components/models/*`) only ever calls the proxy.

## 6. Change rules

- Adding, removing or renaming a route: change `api.py`, this table and the callers in one
  PR; both contract tests must pass.
- Additive response fields are compatible; removing or retyping a field, or changing a
  status code documented here, is breaking and needs `/api/v2` or a coordinated release
  (model-loader image and web release together, see spec 5.7).

## 7. Single writer (#269, done)

- `MODELS_INI_WRITER=model-loader` went live on 2026-09-25 with model-loader f6444b4.
- `compose.llamacpp.yaml` now defaults the flag to `model-loader` and mounts web's
  `/llamacpp-config` read-only. Rollback: remove `:ro` and set `MODELS_INI_WRITER=web`, then
  recreate web (see docs/deployment.md, "models.ini writer").
