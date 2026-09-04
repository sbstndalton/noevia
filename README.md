# Cowork

Cowork is a self-hosted workspace for project-aware chat and durable diary capture. It is a monorepo with two independently testable applications:

- `apps/web` — React interface and Node API proxy
- `services/diary` — FastAPI diary pipeline with retrieval and crash-safe logging

The core requires only an OpenAI-compatible inference API. Local-folder corpus storage is the default; WebDAV and Lemonade model management are optional adapters.

## Quick start

```sh
cp .env.example .env
# Set your inference endpoint and model IDs in .env.
docker compose up --build -d
```

Open `http://localhost:8021`. The Diary service stays on the internal Compose
network unless an operator deliberately publishes its port for legacy clients.

On first launch, Cowork prints a one-time setup code and its protected file
location to the web container log. Enter that code in the onboarding screen to
create the first administrator. The code file is deleted after setup. For
passkeys, serve Cowork from a stable HTTPS origin and set `PUBLIC_ORIGIN` and
`WEBAUTHN_RP_ID`; plain HTTP is supported only for `localhost` development.

Persistent files live under `./state` by default. Set `COWORK_STATE_DIR` to an absolute durable path in production; do not place persistent state inside a disposable source checkout.

## Configuration

Cowork accepts any OpenAI-compatible chat and embeddings endpoint through `INFERENCE_BASE_URL` and `INFERENCE_API_KEY`. Each project can also select another provider in Settings.

Fresh installations use `CORPUS_BACKEND=local` and store Markdown files beneath the diary state directory. For WebDAV, set:

```dotenv
CORPUS_BACKEND=webdav
CORPUS_ROOT=Notes/Diary
WEBDAV_BASE_URL=https://cloud.example.com/remote.php/dav/files/username/
WEBDAV_USERNAME=username
WEBDAV_PASSWORD=app-password
```

Provider-specific model discovery, loading, downloads, and statistics are disabled by default. Enable the Lemonade adapter with `MODEL_MANAGER_KIND=lemonade` and `MODEL_MANAGER_BASE_URL`; see `deploy/examples/lemonade-webdav.compose.yaml`.

The deprecated `LEMONADE_BASE_URL`, `LEMONADE_API_KEY`, and `CORPUS_REMOTE_ROOT` variables remain readable for one compatibility release. New configuration should use the neutral names.

## Development

```sh
make test
make build
make compose-check
```

The web app can also be run from `apps/web` with `npm run dev`; Diary Companion can be run from `services/diary` with `uvicorn agent.app:app --reload`.

## Unraid Compose Manager

Use `deploy/examples/unraid-compose-manager.yml` as the stack file. Configure
Compose Manager's Environment Path to an untracked `.env` containing at least
`COWORK_SOURCE_DIR` and `COWORK_STATE_DIR`. The stack includes Unraid management
and Web UI labels, and its Update action rebuilds both images from the selected
source release.

Keep the Compose Manager project metadata on the Unraid boot device, application
state under appdata, and source releases separate from both. This lets the UI
start, stop, rebuild, and autostart the stack without coupling durable state to a
source checkout.

## Data safety

Diary writes enter a SQLite write-ahead journal before the corpus is changed. Both local and WebDAV backends use conditional writes so concurrent changes are retried rather than overwritten. Back up the configured state directory and, for remote storage, the corpus itself.

Cowork supports isolated administrator and member accounts, password login,
passkeys, single-use invitations, and administrator-issued recovery links.
Projects, chats, histories, and RAG indexes live under per-user directories.
Provider and storage credentials are encrypted with `state/web/secrets.key`;
backups are unusable without that mode-`600` key file.

The Diary service is internal-only by default. `DIARY_AUTH_TOKEN` protects the
Web-to-Diary connection. `UI_AUTH_TOKEN` is accepted only when
`LEGACY_AUTH_COMPAT=true`, allowing a one-release migration to the first
administrator. Direct Diary clients can be temporarily mapped to a user with
`DIARY_LEGACY_USER_ID`. Disable both compatibility settings after migration.

Application administrators cannot browse another user's private content, but a
host administrator with filesystem access can read unencrypted workspace and
corpus files. Secrets belong in `.env` or a secret manager and must never be
committed.
