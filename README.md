# Cowork Workspace — DaServer

One `docker compose up` on DaServer: **Cowork UI** (the surface you open — the
mockup-faithful frontend, `ui/`) + **LiteLLM** (the routing gateway) +
**diary-companion sidecar** (the diary pipeline, untouched code).
AnythingLLM remains in the stack only during burn-in; it is superseded by the UI
(user decision 2026-09-03 — the mockups are not reachable inside AnythingLLM, whose
per-workspace endpoint feature the gateway already replaced).

## The UI (`ui/`)

React + Vite implementation of the four artboards in `../ui mockups/` (Main, Diary,
Settings, DirectionB): pinned Diary above a Spaces list, month/day/time transcript
structure rendered from the real corpus, right rail (This month / Open questions /
Timeline), model-pill headers, and a Settings roster driven by the gateway's live
alias table. Light and dark themes via a sidebar toggle — one design language (the light
artboard's: Manrope, rounded, warm), palette-only swap for dark (user feedback
2026-09-03; a full color-theming rethink is deferred).

- `ui/src/` — frontend. `ui/server/index.cjs` — zero-dependency proxy: SSE chat,
  project-context injection, stats passthrough, diary corpus reads through the
  **corpus-source adapter**, per-project history (JSON files, atomic writes,
  40-turn cap), SPA serving. Secrets stay in `ui.env`.
- **Projects (v4)**: the sidebar is Claude-style — a Projects row of tabs, an
  overview grid, and a create modal (name / goal / instructions / text-file
  attachments). Each project has an editable Instructions/Files/Memory rail and
  its own chats; project context is injected server-side into every chat in it.
  A **live stats bar** docks at the bottom of every view, polling Lemonade's
  `/v1/stats` + `/v1/system-stats` (tok/s, TTFT, tokens, requests, CPU/GPU/VRAM)
  through the proxy every 2.5s.
- **Diary is a dedicated tab**, not a workspace: its composer routes through the
  `diary` alias (full sidecar pipeline; the tab shows logged/skipped per
  exchange), and all corpus reads go through the adapter (`listMonths` /
  `readMonth`). v1 source: `sidecar` (Nextcloud). A `local` folder source is
  designed behind `DIARY_SOURCE=local` + `DIARY_LOCAL_DIR=…` and implemented
  when/if the corpus moves; if that happens, diary-companion gains the same
  source switch server-side so the WRITE path keeps the journal/ETag
  guarantees (sidecar extension planned, not scheduled — MIGRATION §2b).
- Diary data flow is read-only from the UI's perspective: the right rail and
  transcript read `/api/day`; writes happen only through the sidecar's pipeline
  when the Diary space is chatted with (via the `diary` alias, same as Solair AI).
- Local dev: `cd ui && npm install && npm run dev` (proxies to a deployed stack via
  `UI_PROXY_TARGET`), or `npm start` with `LITELLM_MASTER_KEY`/`DIARY_AUTH_TOKEN` set.
- Deploy: gated Step F in `MIGRATION.md` (build image on host, `docker compose up -d ui`).

Companion repos/deployments:
- `sbstndalton/diary-companion` — the diary pipeline this stack sidecars.
- `DaServer.md` (Nextcloud) — canonical ops doc + changelog.

## Routing (v2 — proxy-native, LiteLLM retired from the chat path)

The UI proxy (`ui/server/index.cjs`) routes each chat directly: ordinary chats hit
Lemonade's `/v1/chat/completions` with the project's pinned model + goal/instructions +
persistent memories (projects.json, editable in the UI); the Diary tab routes through the
sidecar pipeline. The model button (top-right of any view) opens the in-tab model
manager: switch per space, search Hugging Face, pick a quantized variant, download with
progress, load/unload/delete — all against Lemonade's management API.

LiteLLM remains in the compose stack only until the UI's direct routing proves out in
daily use, then it is removed (gated step — MIGRATION §5). Lemonade's own native
routing engine (collection.router policies) is the longer-term replacement for
per-space pinning if auto-routing by task is wanted.

Lemonade's `:13305/v1` stays directly reachable for everything else (OpenWork, Solair AI,
Hermes Agent).

## Diary sidecar config (live)

```
CORPUS_REMOTE_ROOT=Documents/Important Documents/Diary
DIARY_MONTH_FILE_TEMPLATE=Diary - {month_name} {year}.md
DIARY_INDEX_ENABLED=false
```

The app adapts to the human-named corpus (no INDEX.md is created; month files are
`Diary - September 2026.md` style).

**Sidecar version contract:** the compose pin must reference a tag that already
exists on the host — never the other way around. Requires **diary-companion ≥ 0.1.1**
(human-named month files, INDEX disable) and **≥ 0.1.2** for the Apache `-gzip` ETag
suffix fix that broke `If-Match` conditional writes against large files. The deployed
pin is `diary-companion:0.1.5` (all fixes included). Releases flow per `UPGRADES.md`:
bump → tag → rebuild on the host → re-pin here in a tracked commit.

Upstream images (`anything-llm`, `litellm`) are pinned by digest so upstream pushes
cannot move a running stack; upgrades are deliberate, gated, one-commit changes —
see `UPGRADES.md`.

## Deploy on DaServer

```bash
# stage (files only; secrets are created server-side)
rsync -a --exclude='.DS_Store' --exclude='*.env' --exclude='backup/' \
  --exclude='ui/node_modules' --exclude='ui/dist' --exclude='ui/server/ui-data' \
  cowork/ root@10.69.0.130:/mnt/docker/appdata/cowork/

ssh root@10.69.0.130
cd /mnt/docker/appdata/cowork
# create anythingllm.env + litellm/.env (see *.env.example; DIARY_AUTH_TOKEN is COPIED
# from /mnt/docker/appdata/diary-companion/.env, never regenerated)
# then:
docker compose up -d
```

- Cowork UI (after gated Step F): `http://10.69.0.130:8021` — the intended surface.
- AnythingLLM (retired by the de-dup decision, container stopped): `http://10.69.0.130:8020`.
  Port 8020 answers nothing — the UI is on **8021**. The compose file keeps the
  service definition for reference; the base image is Debian (glibc) because the
  project-RAG `sqlite-vec` extension has no musl build (see UPGRADES.md).
- Ops runbook, spike evidence, and changelog rows: `MIGRATION.md`, `CHANGELOG-drafts.md`,
  and `DaServer.md` in the Nextcloud docs folder.
- One-off scripts (`spike_*`, `verify_*`, `first_real_append.py`,
  `exchange_from_gateway.py`) were session tooling; the two that contain real diary
  text are gitignored by design.
