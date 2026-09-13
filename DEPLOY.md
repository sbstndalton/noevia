# DEPLOY.md — agent-executable deployment playbook

This playbook covers **generic fresh installs** on a Docker host with Compose v2.
Its declarative companion is [cowork.setup.json](cowork.setup.json); keep both
consistent with implemented behavior. Read [docs/agent-brief.md](docs/agent-brief.md)
first. Cowork-prefixed identifiers are intentional and must not be renamed.

**For the live Unraid instance, use [docs/deployment.md](docs/deployment.md).**
That existing runbook documents tarball releases, the `current` symlink, and
the separate Compose Manager configuration. The commands below do not update
that deployment.

Two ground rules before you start:

- **Do not invent values.** Anything marked `STOP AND ASK THE HUMAN` needs a
  value only the operator can supply. Ask, wait for the answer, then proceed.
- **Never commit `.env`.** It holds real credentials by design.

`SECURITY.md` describes the trust model you are deploying into — read its
operator hardening checklist (sidecar stays internal, real `PUBLIC_ORIGIN`,
HTTPS via reverse proxy) before exposing this stack beyond one machine.

---

## 1. Preconditions

Verify all of these before touching anything else. If any check fails, stop and
install the missing piece — do not improvise around it.

```sh
docker --version          # expect: Docker version 20.10 or newer
docker compose version    # expect: Docker Compose version v2.x
git rev-parse --is-inside-work-tree   # expect: true (you are in a checkout)
test -f compose.yaml && test -f .env.example && echo "checkout ok"
#                       ^ expect: "checkout ok"
```

Network access is needed only for the initial image build (base images are
pulled from public registries). The running stack itself needs no outbound
internet except to whatever inference endpoint the operator configures.

## 2. Required inputs

None of these are needed to *start* the stack: every service env var in
`compose.yaml` is `${VAR:-default}`, so `docker compose up` with no `.env` at
all reaches a healthy running state. Start it, open the app at whatever address
you reach it on (a bare LAN IP is fine), and the first-run wizard collects the
public origin and the inference endpoint itself. `HUMAN-REQUIRED` rows below
still need the operator *for a non-default choice* — mostly external storage
credentials and model management, which the wizard does not cover.
`HAS-SAFE-DEFAULT` rows can ship as-is and be revisited later.

| Variable | Purpose | How to obtain | Secret | Status |
| --- | --- | --- | --- | --- |
| `DIARY_AUTH_TOKEN` | Shared bearer token: web→diary API calls, used by the web server to authenticate to the sidecar | Generate on the Docker host: `openssl rand -hex 32` | **yes** | `HAS-SAFE-DEFAULT` (empty runs the internal web→diary link unauthenticated in LAN-only mode with a log warning; set it before any network exposure) |
| `INFERENCE_BASE_URL` | OpenAI-compatible chat endpoint used by both containers (chat completions + embeddings). Should end in `/v1` | Ask the human for their endpoint, e.g. `http://host.docker.internal:11434/v1` (Ollama), a LAN llama.cpp server, or a hosted OpenAI-compatible API | no | `HAS-SAFE-DEFAULT` (the wizard's provider step collects this in-app; setting it here only pre-seeds the default) |
| `INFERENCE_API_KEY` | Bearer key for that endpoint, if it requires one | Ask the human | **yes** | `HUMAN-REQUIRED` if the endpoint authenticates; otherwise leave empty |
| `PUBLIC_ORIGIN` | The URL humans type into the browser (scheme + host + port). Locks the auth origin allow-list and derives the passkey ID | The wizard prefills it from the address the operator loaded the app at and writes what they confirm; set it here only to pre-seed. `https://` is recommended; a private-network `http://` address (LAN IP, bare LAN hostname, localhost) is accepted with a warning, a public `http://` domain is not | no | `HAS-SAFE-DEFAULT` (`http://localhost:8021`) |
| `COWORK_PORT` | Host port for the web UI | Pick a free port | no | `HAS-SAFE-DEFAULT` (`8021`) |
| `COWORK_STATE_DIR` | Existing/explicit host bind root, used when storage overrides are empty | Preserve the current path on upgrades | no | Compatibility fallback: `./state` |
| `COWORK_WEB_STORAGE`, `COWORK_DIARY_STORAGE` | Explicit generic Compose mount sources, taking precedence over `COWORK_STATE_DIR` | Fresh initializer selects `web-data` and `diary-data`; never point existing state at empty volumes | no | Managed volumes for initialized fresh installs |
| `DIARY_CHAT_MODEL`, `DIARY_AUX_MODEL`, `EMBEDDING_MODEL` | Model names the inference endpoint serves | Ask the human which models their endpoint exposes | no | `HAS-SAFE-DEFAULT` (`default`) |
| `UI_AUTH_TOKEN` | Optional UI API token; falls back to `DIARY_AUTH_TOKEN` when empty | Leave empty unless the human wants it distinct | **yes** | `HAS-SAFE-DEFAULT` (empty = reuse `DIARY_AUTH_TOKEN`) |
| `WEBAUTHN_RP_ID` | Passkey identifier; must match the browser's hostname | Derived from `PUBLIC_ORIGIN` when empty; override only for unusual proxy setups | no | `HAS-SAFE-DEFAULT` (derived) |
| `TRUST_PROXY` | Set `true` only behind a reverse proxy so rate limiting/audit logs see real client IPs | Depends on deployment shape — ask if unclear | no | `HAS-SAFE-DEFAULT` (`false`) |
| `LLM_RATE_LIMIT` | Per-user requests/minute cap on model-backed routes (chat and diary conversations) — all users share one inference endpoint | Raise it only if the inference host has headroom | no | `HAS-SAFE-DEFAULT` (`60`) |
| `LEGACY_AUTH_COMPAT` | Allows machine clients to authenticate with the shared token | Leave `false` unless explicitly migrating trusted machine clients; humans use password/passkey | no | `HAS-SAFE-DEFAULT` (`false`) |
| `AUX_INFERENCE_BASE_URL` | Optional separate endpoint for the diary's auxiliary classification model | Only if the human runs a dedicated aux endpoint | no | `HAS-SAFE-DEFAULT` (falls back to `INFERENCE_BASE_URL`) |
| `DEFAULT_PROVIDER_ID`, `DEFAULT_PROVIDER_LABEL` | Identity/label of the pre-seeded default inference provider shown in Settings | Only if the human wants a different label than "Local inference" | no | `HAS-SAFE-DEFAULT` (`default` / `Local inference`) |
| `DIARY_MONTH_FILE_TEMPLATE`, `DIARY_ENTRY_LAYOUT`, `DIARY_ENTRIES_PREFIX`, `DIARY_INDEX_ENABLED` | Diary file layout knobs (month filename template, daily vs monthly layout, heading prefix, standing sections on/off) | Leave defaults unless the human wants specific file shapes in storage | no | `HAS-SAFE-DEFAULT` (see `.env.example`) |
| `DIARY_LEGACY_USER_ID` | Optional one-release direct Diary API user mapping for legacy clients | Only if the human runs a legacy Diary client | no | `HAS-SAFE-DEFAULT` (empty) |
| `CORPUS_BACKEND`, `CORPUS_ROOT`, `WEBDAV_BASE_URL`, `WEBDAV_USERNAME`, `WEBDAV_PASSWORD` | Optional external diary storage backend | Only if the human wants storage outside the local state volume; see `services/diary/README.md` | `WEBDAV_PASSWORD` **yes** | `HAS-SAFE-DEFAULT` (`local`) |
| `S3_ENDPOINT_URL`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_SESSION_TOKEN`, `S3_REGION`, `S3_PREFIX` | S3-compatible diary storage (MinIO, Backblaze B2, AWS S3, Garage, ...) when `CORPUS_BACKEND=s3`; per-account S3 connections from the app's Settings ignore these | Only if the human wants object storage; obtain endpoint/bucket/keys from them | `S3_SECRET_ACCESS_KEY`, `S3_SESSION_TOKEN` **yes** | `HAS-SAFE-DEFAULT` (`local`) |
| `DIARY_EXTERNAL_SOURCES` | Optional comma-separated folders of pre-existing `.txt`/`.md` files surfaced (read-only) for import in the diary empty state | Only if the human has old journal files to import; paths must be mounted into the diary container | no | `HAS-SAFE-DEFAULT` (empty) |
| `MODEL_MANAGER_KIND`, `MODEL_MANAGER_BASE_URL`, `MODEL_MANAGER_API_KEY` | Optional provider-specific local model management | Only if the human runs a supported model manager | API key **yes** | `HAS-SAFE-DEFAULT` (`none`) |
| `MCP_SERVER_URL` | Optional MCP server exposing curated Nextcloud toolboxes to the model; streamable-http endpoint, usually ending `/mcp` | Only if the human runs an MCP server; it must be in multi-user mode so noevia can pass each user's own credential per request | no | `HAS-SAFE-DEFAULT` (empty — no MCP toolboxes, only the built-in `core` box) |
| `MCP_NEXTCLOUD_ORIGINS` | Comma-separated origins that are the **same** Nextcloud the MCP server is configured against. A user's stored app password is forwarded only when their storage connection points at one of these | Required for MCP tools to work at all; ask the human for every address that reaches their Nextcloud (a LAN address and a public hostname are usually both needed) | no | `HAS-SAFE-DEFAULT` (empty — credentials are never forwarded, so MCP tools return an actionable error instead of leaking) |
| `COWORK_VERSION` | Image tag for built images | Leave as `dev` unless the human asks for a pinned tag | no | `HAS-SAFE-DEFAULT` (`dev`) |

`STOP AND ASK THE HUMAN:` for every `HUMAN-REQUIRED` row above you lack a value
for. Do not guess in those fields. The public origin, the inference endpoint and
its key, and the diary token are no longer among them — start the stack without
them and let the operator finish setup in the browser.

## 3. Deploy steps

Run from the repository root. The fresh-install initializer refuses reinitialization;
keep any existing configuration when resuming setup.

### 3.1 Create `.env`

For a **new installation**, initialize Docker-managed web and Diary volumes:

```sh
bash deploy/init-managed.sh
```

This creates a private `.env` only after checking that no environment file, state
path, Cowork containers or managed state volumes already exist. It creates no
volumes and starts no services. The next Compose startup allocates `web-data` and
`diary-data` under the existing `cowork` project name.

For an **existing installation**, keep its `.env` and storage bindings. The
initializer deliberately refuses it. For an explicitly chosen host bind on a new
installation, copy `.env.example` only when `.env` does not exist and set
`COWORK_STATE_DIR`; leave `COWORK_WEB_STORAGE` and `COWORK_DIARY_STORAGE` empty.
Running Compose without the initializer still retains the legacy `./state` fallback;
that compatibility path does not silently move an existing installation.

Then fill in only the rows the operator actually chose, e.g.:

```sh
TOKEN="$(openssl rand -hex 32)"   # confirm with the human that generating is OK
cat >> .env <<EOF
DIARY_AUTH_TOKEN=${TOKEN}
INFERENCE_BASE_URL=<optional-pre-seed>
INFERENCE_API_KEY=<ask-the-human-if-needed>
PUBLIC_ORIGIN=<optional-pre-seed; the wizard sets this otherwise>
EOF
chmod 600 .env
```

Sanity-check the result: every value you were given is present, no real
credential is committed anywhere (`git status --short` must not list `.env` —
it is already git-ignored; if it isn't, stop and report).

### 3.2 Build and start

On Unraid, use the host-side boot-storage preflight before starting services;
see [deploy/preflight/README.md](deploy/preflight/README.md). From the repo root:
`bash deploy/preflight/up.sh -- -d --build`. This checks resolved writable mounts
before `up`; it preserves the current state directory. Other hosts can use the
same helper with PHP 8+, or the ordinary commands below.

```sh
docker compose build          # first run pulls base images; several minutes is normal
docker compose up -d
```

### 3.3 Wait for health

```sh
docker compose ps
```

Expected: `diary` shows `healthy` (it has a healthcheck); `web` shows
`running` (it has no healthcheck — verify it with the curl in §4 instead).
If `diary` is stuck `starting`/`restarting`, jump to §5.

### 3.4 Retrieve the first-run setup code

On a fresh state directory, the web server generates a one-time setup code at
startup, prints it to its log, and writes it to the state volume:

```sh
docker compose logs web | grep "FIRST-RUN SETUP CODE"
# expect exactly one line:  FIRST-RUN SETUP CODE: <one-time code>
```

If the logs have rotated, read the file instead (same value):

```sh
docker compose exec -T web cat /app/server/ui-data/first-run-setup-code
```

`STOP AND ASK THE HUMAN:` hand them the code — the setup wizard asks them to
type it. Never auto-fill it into anything, never skip this step; the code is
the proof that whoever creates the first account controls the server.

### 3.5 Onboard the human

`STOP AND ASK THE HUMAN:` this step is theirs, in a browser:

1. Open the app at whatever address they reach the host on — `PUBLIC_ORIGIN`
   if it was pre-seeded, otherwise just the host's LAN IP and port
   (e.g. `http://192.168.1.20:8021`).
   The wizard's first step confirms this address as the canonical origin: it is
   prefilled from what they loaded, warns when it is a plain-http LAN address
   (passkeys need HTTPS), and rejects a public `http://` domain.
2. The account step collects setup code, admin username/password, display name,
   origin, and the diary opt-in checkbox. Next come the provider check, diary
   storage setup (if enabled), model-manager guidance, display/timezone
   preferences, and optional passkey. A standalone diary-first question and
   removal of the models guidance step remain proposed changes.
3. They land in the app when done. If they skip the inference check because the
   endpoint isn't reachable yet, the app shows an "inference unreachable"
   banner until it is — that is expected and self-heals.

Agents: do not perform this step yourself, and do not work around it by
touching the database or flags (see §6).

## 4. Verification

Run the applicable checks and compare against the expected results.
Agents must never prompt the real diary or modify its corpus for testing. The deployment is
not done until every check passes.

```sh
# If COWORK_PORT or COWORK_STATE_DIR were set to non-defaults in .env, load
# them into the shell first (docker compose reads .env itself; these curls don't):
set -a; . ./.env; set +a

# 4.1 Before onboarding this must say configured:false (skip if already onboarded)
curl -s "http://localhost:${COWORK_PORT:-8021}/api/setup/status"
# expect: {"configured":false,...}

# 4.2 After onboarding it must flip — if it still says false, onboarding didn't complete
curl -s "http://localhost:${COWORK_PORT:-8021}/api/setup/status"
# expect: {"configured":true,...}

# 4.3 The one-time code is consumed and removed after successful setup
docker compose exec -T web test ! -f /app/server/ui-data/first-run-setup-code && echo "code consumed"
# expect: "code consumed"

# 4.4 Diary sidecar reachable from the web container, authenticated
docker compose exec -T web node -e "fetch('http://diary:8010/api/health',{headers:{Authorization:'Bearer '+process.env.DIARY_AUTH_TOKEN}}).then(r=>r.text()).then(console.log)"
# expect: {"ok":true,...}

# 4.5 Inference endpoint reachable from inside the network (see §5 if this fails)
docker compose exec -T web node -e "fetch(process.env.INFERENCE_BASE_URL.replace(/\/+$/,'').replace(/\/v1$/,'')+'/v1/models',{headers:process.env.INFERENCE_API_KEY?{Authorization:'Bearer '+process.env.INFERENCE_API_KEY}:{}}).then(r=>console.log('models',r.status)).catch(e=>console.log('unreachable',e.cause?.code||e.message))"
# expect: models 200

# 4.6 Durable state exists on the host volume
docker compose exec -T web test -f /app/server/ui-data/secrets.key
docker compose exec -T diary test -d /app/data
# Works for managed volumes and host binds. Inspect the selected mounts with
# docker inspect when locating host storage; do not assume ./state is in use.

# 4.7 Optional, only if diary is enabled and the human chooses to verify:
# the human logs an entry from the UI, then:
docker compose exec -T diary find /app/data/users -path '*/corpus/*' -name '*.md' -mmin -5 -print
# For the account that wrote the entry, expect a path under users/<user-id>/corpus.
# Remote storage: inspect the configured bucket/WebDAV path instead; no local
# Markdown file is expected. Do not read or print another user's diary content.
# expect: the new entry file for that account (local storage only)
```

## 5. Common failure modes

- **Web port conflict (`EADDRINUSE` in `docker compose logs web`).** Something
  else holds `COWORK_PORT`. Pick another port in `.env`, `docker compose up -d`
  again. Diagnose the holder with `sudo lsof -i :8021` on the host.
- **Inference unreachable from containers (4.5 fails) but reachable from the
  host.** The most common cause: the endpoint binds to loopback only. Inside
  Compose, use `http://host.docker.internal:<port>/v1` (the compose file already
  maps `host.docker.internal` to the host gateway on Linux). Test from inside:
  the 4.5 command. If the endpoint truly only listens on 127.0.0.1, it must be
  reconfigured to listen on the LAN interface or a tunnel — that's a human
  decision; ask.
- **`/v1` confusion.** The sidecar appends paths to `INFERENCE_BASE_URL`
  verbatim, so it should end in `/v1`. The web server tolerates either form.
  Symptom of getting it wrong: 404s in `docker compose logs diary` against
  `/v1/chat/completions`.
- **Diary container unhealthy or restarting.** `docker compose logs diary`.
  Usual causes: state volume not writable by the container user, or a bad
  `CORPUS_BACKEND`/WebDAV configuration. The SQLite index and write journal
  live under `${COWORK_STATE_DIR}/diary` — never point two deployments at the
  same directory.
- **Setup code rejected by the wizard.** Copy it again from §3.4 — preserve its exact characters and trim surrounding whitespace. If the file is gone but no admin account
  exists, the state directory was partially reset; see the next bullet for a
  clean start.
- **Botched onboarding, start over.** Stop the stack
  (`docker compose down`), move the state directory aside
  (`mv state state.broken.$(date +%s)`), `docker compose up -d`, and begin
  again at §3.4. **Destructive:** this discards all accounts, diary entries,
  and settings — confirm with the human before doing it.
- **Passkeys won't register.** WebAuthn requires a secure context: it works on
  `localhost` and on HTTPS origins, not on plain-HTTP LAN IPs. Either serve
  `PUBLIC_ORIGIN` over HTTPS (reverse proxy with TLS) or have humans use
  password login; `WEBAUTHN_RP_ID` must also match the browser's hostname.
- **Auth disabled warning in logs** (`API authentication is disabled`):
  `DIARY_AUTH_TOKEN` is empty. Browser login is still required, but the internal
  diary connection is unprotected. Set the service token before network exposure.

## 6. Non-goals — things an agent must never do

- **Never fabricate the first-run setup code**, generate a replacement, or
  auto-fill it. It comes only from the container log or the state file (§3.4),
  and only the human completes onboarding with it.
- **Never bypass onboarding**: no direct inserts into the accounts SQLite DB,
  no pre-creating users, no flipping flags to make `/api/setup/status` report
  configured. `LEGACY_AUTH_COMPAT` exists for legacy shared-token API login,
  not as an onboarding shortcut.
- **Never commit `.env`** or paste real credentials into the repo, docs, or
  commit messages.
- **Never reuse or echo the `DIARY_AUTH_TOKEN`** into logs, issue bodies, or
  screenshots. It grants full API access.
- **Never wipe the state directory** (or any data inside it) without the
  human's explicit confirmation.

## Endpoint approval and auxiliary inference

`MEMBER_OUTBOUND_ORIGINS` defaults to empty, reserving custom inference/storage
hosts for administrators. Set a comma-separated list of trusted origins to let
members connect those services. Include the exact scheme and port, omit paths,
and approve only operator-trusted DNS names. Restart the web container after changes.

`AUX_INFERENCE_BASE_URL` defaults to `INFERENCE_BASE_URL`.
`AUX_INFERENCE_API_KEY` defaults to `INFERENCE_API_KEY` when unset; set it to an
explicit empty value for an unauthenticated auxiliary server. Configure actual
model IDs for both clients; `default` works only if the server supports that alias.


### Local PDF OCR

Compose also builds a private `ocr` service (Poppler/Tesseract, English/German)
and connects web through `OCR_BASE_URL=http://ocr:8030`. No OCR host port or
external credentials are needed. Check it with:

```sh
docker compose exec -T web node -e "fetch(process.env.OCR_BASE_URL+'/health').then(r=>console.log(r.status))"
```

Direct Node development without `OCR_BASE_URL` remains native-text-only. See
`docs/spec-document-understanding.md` for processing limits and retry behavior.

Managed-volume lifecycle: ordinary `docker compose down` retains state; never use
`down -v` or prune these volumes unless deliberately discarding their data. Include
both selected volumes and the matching web encryption key in backups. Changing
`COWORK_STATE_DIR` has no effect while explicit storage overrides are set. A later
storage change requires a separate copy/restore and verification, not only editing
these variables. The live Unraid Compose Manager template keeps explicit host binds.
