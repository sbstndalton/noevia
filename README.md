# Cowork Workspace — DaServer

One `docker compose up` on DaServer: **AnythingLLM** (the surface you open) + **LiteLLM**
(the routing gateway) + **diary-companion sidecar** (the diary pipeline, untouched code).

Companion repos/deployments:
- `sbstndalton/diary-companion` — the diary pipeline this stack sidecars.
- `DaServer.md` (Nextcloud) — canonical ops doc + changelog.

## Why a gateway container

AnythingLLM's Generic OpenAI base URL is **instance-wide** (upstream issues #4243,
#4493, #5084): the per-workspace override switches provider/model, not endpoint.
LiteLLM fills that gap config-only: AnythingLLM points once at `http://litellm:4000/v1`,
and each workspace picks a **model alias**:

| Alias | Routes to | Notes |
|---|---|---|
| `diary` | diary-companion sidecar `/v1` | every exchange goes through the real pipeline (skip-classifier → summarize → journal → ETag-guarded WebDAV) |
| `e4b` | Lemonade `Gemma-4-E4B-it-GGUF` | default workhorse |
| `e2b` | Lemonade `gemma-4-E2B-it-GGUF-Q8_0` | fast aux |
| `gpt-oss-20b` | (staged, commented) | model absent from Lemonade's catalog — enable after a `/v1/pull` |
| cloud blocks | (staged, commented) | Phase 2 escape hatch: paste a key, uncomment, zero code |

Lemonade's `:13305/v1` stays directly reachable for everything else (OpenWork, Solair AI,
Hermes Agent) — the gateway fronts only this app's calls.

## Diary sidecar config (live)

```
CORPUS_REMOTE_ROOT=Documents/Important Documents/Diary
DIARY_MONTH_FILE_TEMPLATE=Diary - {month_name} {year}.md
DIARY_INDEX_ENABLED=false
```

The app adapts to the human-named corpus (no INDEX.md is created; month files are
`Diary - September 2026.md` style). Requires diary-companion ≥ 0.1.1, which also fixed
the Apache `-gzip` ETag suffix that broke `If-Match` conditional writes against large
files (≥ 0.1.2).

## Deploy on DaServer

```bash
# stage (files only; secrets are created server-side)
rsync -a --exclude='.DS_Store' --exclude='*.env' --exclude='backup/' \
  cowork/ root@10.69.0.130:/mnt/docker/appdata/cowork/

ssh root@10.69.0.130
cd /mnt/docker/appdata/cowork
# create anythingllm.env + litellm/.env (see *.env.example; DIARY_AUTH_TOKEN is COPIED
# from /mnt/docker/appdata/diary-companion/.env, never regenerated)
# then:
docker compose up -d
```

- AnythingLLM: `http://10.69.0.130:8020` (set the admin password on first open;
  Settings → AI Providers → LLM = Generic OpenAI → `http://litellm:4000/v1` + master key).
- Ops runbook, spike evidence, and changelog rows: `MIGRATION.md`, `CHANGELOG-drafts.md`,
  and `DaServer.md` in the Nextcloud docs folder.
- One-off scripts (`spike_*`, `verify_*`, `first_real_append.py`,
  `exchange_from_gateway.py`) were session tooling; the two that contain real diary
  text are gitignored by design.
