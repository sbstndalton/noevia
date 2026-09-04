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

Open `http://localhost:8021`. Diary Companion is also available directly at `http://localhost:8010`.

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

## Data safety

Diary writes enter a SQLite write-ahead journal before the corpus is changed. Both local and WebDAV backends use conditional writes so concurrent changes are retried rather than overwritten. Back up the configured state directory and, for remote storage, the corpus itself.

Set `UI_AUTH_TOKEN` and `DIARY_AUTH_TOKEN` before exposing either HTTP service outside a trusted machine. Secrets belong in `.env` or a secret manager and must never be committed.
