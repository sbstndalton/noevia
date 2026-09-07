# DEPLOY.md — agent-executable deployment playbook

Deploy this app (web UI + diary sidecar) on any Docker host with Compose v2,
following the steps in order. Every command is copy-runnable. This file is the
authoritative narrative; `cowork.setup.json` mirrors the same facts in a form a
program can `jq` over. If the two ever disagree, trust this file — and file an
issue, because that's a bug.

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

Collect these before generating `.env`. `HUMAN-REQUIRED` rows need the operator;
`HAS-SAFE-DEFAULT` rows can ship as-is and be revisited later.

| Variable | Purpose | How to obtain | Secret | Status |
| --- | --- | --- | --- | --- |
| `DIARY_AUTH_TOKEN` | Shared bearer token: web→diary API calls, used by the web server to authenticate to the sidecar | Generate on the Docker host: `openssl rand -hex 32` | **yes** | `HUMAN-REQUIRED` (set it before any network exposure; browser accounts remain authenticated) |
| `INFERENCE_BASE_URL` | OpenAI-compatible chat endpoint used by both containers (chat completions + embeddings). Should end in `/v1` | Ask the human for their endpoint, e.g. `http://host.docker.internal:11434/v1` (Ollama), a LAN llama.cpp server, or a hosted OpenAI-compatible API | no | `HUMAN-REQUIRED` |
| `INFERENCE_API_KEY` | Bearer key for that endpoint, if it requires one | Ask the human | **yes** | `HUMAN-REQUIRED` if the endpoint authenticates; otherwise leave empty |
| `PUBLIC_ORIGIN` | The URL humans type into the browser (scheme + host + port). Locks the auth origin allow-list and derives the passkey ID | Ask the human, e.g. `http://192.168.1.20:8021` or `https://cowork.example.com` | no | `HUMAN-REQUIRED` for anything beyond localhost use |
| `COWORK_PORT` | Host port for the web UI | Pick a free port | no | `HAS-SAFE-DEFAULT` (`8021`) |
| `COWORK_STATE_DIR` | Host directory for all durable state (diary corpus + SQLite journal, web accounts/secrets/first-run code) | Pick a host path on a volume that survives restarts | no | `HAS-SAFE-DEFAULT` (`./state`) |
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
| `COWORK_VERSION` | Image tag for built images | Leave as `dev` unless the human asks for a pinned tag | no | `HAS-SAFE-DEFAULT` (`dev`) |

`STOP AND ASK THE HUMAN:` for every `HUMAN-REQUIRED` row above you lack a value
for — at minimum the inference endpoint (and its key if any), the public origin,
and confirmation that a generated token is acceptable. Do not proceed to `.env`
creation with guesses in these fields.

## 3. Deploy steps

Run from the repository root. Each block is idempotent; re-running a failed
block after fixing the cause is safe.

### 3.1 Create `.env`

```sh
cp .env.example .env
```

Then fill it in — either with an editor, or non-interactively (values shown
with the placeholders the human gave you; adjust all of them):

```sh
TOKEN="$(openssl rand -hex 32)"   # confirm with the human that generating is OK
cat >> .env <<EOF
DIARY_AUTH_TOKEN=${TOKEN}
INFERENCE_BASE_URL=<ask-the-human>
INFERENCE_API_KEY=<ask-the-human-if-needed>
PUBLIC_ORIGIN=<ask-the-human>
EOF
chmod 600 .env
```

Sanity-check the result: every value you were given is present, no real
credential is committed anywhere (`git status --short` must not list `.env` —
it is already git-ignored; if it isn't, stop and report).

### 3.2 Build and start

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

1. Open `PUBLIC_ORIGIN` (e.g. `http://<host>:8021`).
2. The setup wizard walks them through: setup code + admin username/password,
   inference provider check, diary opt-in, model-manager guidance, display
   preferences, optional passkey.
3. They land in the app when done. If they skip the inference check because the
   endpoint isn't reachable yet, the app shows an "inference unreachable"
   banner until it is — that is expected and self-heals.

Agents: do not perform this step yourself, and do not work around it by
touching the database or flags (see §6).

## 4. Verification

Run all of these and compare against the expected results. The deployment is
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
ls "${COWORK_STATE_DIR:-./state}/diary" "${COWORK_STATE_DIR:-./state}/web"
# expect: both directories non-empty (SQLite DB, corpus/, accounts data)

# 4.7 End-to-end: the human logs one diary entry from the UI, then:
find "${COWORK_STATE_DIR:-./state}/diary/users" -path '*/corpus/*' -name '*.md' -mmin -5 -print
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
