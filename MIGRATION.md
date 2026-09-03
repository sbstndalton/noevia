# Cowork Workspace — migration & spike runbook (DaServer)

Companion to build-spec v0.4/v0.5. **Ground rules (binding):** nothing deleted, nothing
mutated on the server without explicit user sign-off per step, every infra change gets a
`DaServer.md` changelog row alongside the work. This runbook is a plan, not authorization.

## 0. What exists today (verified 2026-09-02, read-only recon)

| Fact | Value |
|---|---|
| Standalone diary-companion | running, `0.0.0.0:8010->8010`, healthcheck green, token auth active |
| Standalone appdata | `/mnt/docker/appdata/diary-companion/` (config/, data/, .env chmod 600) |
| Server config.yaml embed line | `nomic-embed-text-v1.5.Q4_K_M` — **stale**; runtime wins via `.env`: `nomic-embed-text-v1-GGUF` (doc-drift, Step A) |
| Server chat model | server `config.yaml` says `gpt-oss-20b-GGUF-MXFP4`, but that model is NOT in Lemonade's current catalog (verified via `/v1/models`: E4B, E2B, nomic-embed only). Runtime is unaffected — `.env` `LLM_CHAT_MODEL` wins (E4B per the verified-live deployment). **Second doc-drift; do not touch this session** — Phase 1b benchmark decides the final chat model. |
| Lemonade | live at `:13305`; usable friendly IDs: `Gemma-4-E4B-it-GGUF`, `gemma-4-E2B-it-GGUF-Q8_0`, `nomic-embed-text-v1-GGUF` (+ 2 cosmetic hash-ID dupes of E2B/E4B). GPT-OSS-20B absent (see chat-model row below) |
| Docker network | `lemonade_default` exists (fb1495f4237b) — cowork stack joins it, never re-exposes Lemonade |
| Port 8020 | free (verified against DaServer.md port table + listening ports) |
| open-webui | still running (healthy) on 3000 — untouched this session; decommission decision is gated on later sign-off |
| WebDAV | verified end-to-end earlier today (PROPFIND 207, conditional PUT 204); corpus `Diary/` |

## 1. Mac-side (done in this session, no server mutation)

- `~/.config/opencode/opencode.json` — Lemonade added as opencode/OpenWork provider
  (E4B default, E2B small_model, GPT-OSS-20B listed). Test by opening OpenWork.app and
  running one real task.
- Changelog row required for this config change per spec §3 → see CHANGELOG-drafts.md Row 0.

## 2. Server steps — each gated on explicit user "go" before it runs

### Step A — doc-drift fix (spec §4 flagged item; resolved *before* any retrieval work)
1. Read `/mnt/docker/appdata/diary-companion/config/config.yaml` line 9 (read-only, done).
2. **GO-gate.** Then edit exactly one line:
   `embed_model: nomic-embed-text-v1.5.Q4_K_M` → `nomic-embed-text-v1-GGUF`
   (matches the runtime value from `.env`; retrieval index still empty → zero re-index cost).
3. Restart NOT required yet — the running container's env already has the right value;
   the config file fix takes effect on the next container restart/recreation.
   Do not restart the standalone container just to apply it.
4. Changelog row → CHANGELOG-drafts.md Row 1.
5. Optional repo-side: update `diary-companion/README.md` config-quick-reference line
   (`nomic-embed-text-v1.5` → `nomic-embed-text-v1`) — Mac-side file edit, then push
   from the repo with the user's normal flow. (README-only; no server effect.)

### Step B — stage the stack
1. `ssh root@10.69.0.130 mkdir -p /mnt/docker/appdata/cowork` then rsync this `cowork/`
   folder (excluding `*.env` secrets — they're created server-side next; nothing here
   writes to the standalone appdata).
2. **GO-gate.** Then server-side secret setup (no regeneration, only copies):
   ```bash
   cd /mnt/docker/appdata/cowork
   cp /mnt/docker/appdata/diary-companion/.env diary-companion.env
   # add a line to diary-companion.env: CORPUS_REMOTE_ROOT is overridden by compose
   # environment for the spike (Diary-spike-test) — no edit needed.
   # Create the spike scratch folder in Nextcloud (via WebDAV, once):
   curl -u 'sebastian dalton:<APP PASSWORD from .env>' -X MKCOL \
     'http://10.69.0.130:11000/remote.php/dav/files/sebastian%20dalton/Diary-spike-test'
   cat > litellm/.env <<EOF
   LITELLM_MASTER_KEY=$(openssl rand -hex 24)
   LITELLM_SALT_KEY=$(openssl rand -hex 32)
   DIARY_AUTH_TOKEN=$(grep '^DIARY_AUTH_TOKEN=' diary-companion.env | cut -d= -f2-)
   EOF
   cat > anythingllm.env <<EOF
   JWT_SECRET=$(openssl rand -hex 32)
   DISABLE_TELEMETRY=true
   GENERIC_OPENAI_BASE_URL=http://litellm:4000/v1
   GENERIC_OPENAI_API_KEY=$(grep '^LITELLM_MASTER_KEY=' litellm/.env | cut -d= -f2-)
   GENERIC_OPENAI_MODEL_PREF=e4b
   EOF
   chmod 600 litellm/.env anythingllm.env diary-companion.env
   ```
   (New secrets: LITELLM_MASTER_KEY, LITELLM_SALT_KEY, JWT_SECRET. Copied secrets:
   DIARY_AUTH_TOKEN + all WebDAV credentials. Nothing about the diary setup regenerates.)
3. Changelog row → CHANGELOG-drafts.md Row 2.

### Step C — build + up
1. Pre-flight: `docker ps --format '{{.Names}}\t{{.Ports}}' | grep 8020` (must be empty),
   confirm `diary-companion:0.1.0` image exists (`docker images diary-companion`).
2. **GO-gate.** Then:
   ```bash
   cd /mnt/docker/appdata/cowork && docker compose up -d
   docker compose ps
   ```
3. Changelog row → CHANGELOG-drafts.md Row 3.

### Step D — spike verification (read-only against the real corpus; writes only to scratch)
Success criteria, checked in order:
1. AnythingLLM reachable at `http://10.69.0.130:8020`; set the admin password on first
   open; confirm Settings → AI Providers → LLM = Generic OpenAI → `http://litellm:4000/v1`
   with the master key; model list shows `e4b/e2b/diary` (fetched via LiteLLM;
   `gpt-oss-20b` is staged but commented out until the model is re-pulled — Phase 1b).
2. LiteLLM → Lemonade: create "Sandbox" workspace → model alias `e4b` → send a test
   message → coherent reply from E4B via the 890M.
3. Diary round-trip: create "Diary" workspace → model alias `diary` → send one
   substantive test exchange → verify:
   - reply streams back through the full pipeline (context assembly → Lemonade →
     skip-classifier pass → summarize → journal → WebDAV append)
   - `Diary-spike-test/2026-09.md` gains `## <day>` / `### <time> — topic` /
     `**Me:**` (near-verbatim) / `**Claude:**` (third-person prose, no bullets)
   - hidden `<!-- xid:<uuid> -->` marker present in the logged block
   - `Diary-spike-test/INDEX.md` auto-registers the month
4. Skip-classifier: send a meta/administrative message ("what time is it?") → ⊘ skipped,
   nothing journaled (`journal_pending` stays 0, no new block in the scratch file).
5. Scratch-corpus hygiene: the REAL `Diary/` folder must be byte-identical to before the
   spike (compare via WebDAV GET ETag or Nextcloud file versions) — prove the override
   worked.
6. Sidecar health: `docker exec cowork-diary-companion python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8010/api/health').read())"` →
   `ok: true`, `journal_pending: 0`, `vec_available: true`.
7. Results report to user → decide next: proceed to cutover prep / rebrand / more spaces.

### Step E — cleanup (gated, sign-off required — it's a delete)
1. **GO-gate.** Delete ONLY the scratch corpus folder `Diary-spike-test/` via WebDAV
   (created by this runbook; contains only spike test data) and stop the cowork stack:
   `docker compose down` (keeps volumes/images; `-v` NOT used — nothing gets deleted
   beyond the explicitly signed-off scratch folder).
   Decision recorded either way: leave the stack **running** for real-use burn-in
   (recommended once verified) or stop it until cutover session.
2. Changelog row → CHANGELOG-drafts.md Row 4.

## 2b. Frontend supersession (user decision 2026-09-03) — custom UI replaces the reskin plan

The user reviewed the AnythingLLM build against the ui-mockups and rejected it as the
final surface; per-workspace endpoint override (AnythingLLM's original raison d'être
here) was already replaced by the LiteLLM gateway. Decision: **build the mockups as a
real frontend** (`ui/`), light theme first with dark as a toggle. Implemented Mac-side
against the live stack via SSH tunnels (read-only diary + generation only); AnythingLLM
stays running untouched during burn-in.

Verified locally (2026-09-03): diary transcript + right rail render the real corpus
(`Documents/Important Documents/Diary`, human-named month files, `## <Weekday>, <Month>
<Day>, <Year>` day headers); Coding space chat streams E4B via the gateway; per-space
history persists; both themes render.

Design-language note (user feedback 2026-09-03): the two artboard directions are
declared one design language — the LIGHT artboard's (Manrope, rounded, warm) is
canonical for both themes; dark is a palette-only swap (DirectionB hues). The
dark artboard's terminal/IBM-Plex language is not carried forward. A full
color-theming rethink is explicitly deferred — revisit when the user asks.

Diary-tab decisions (Q&A round, 2026-09-03):
- **Deploy sequencing:** verified v1 deployed first (Step F, done), rework second
  (deployed same day). Daily-drive `:8021` now.
- **AnythingLLM:** burn-in fallback only; retire in a gated step once the UI
  proves out. Its backend is NOT reused (workspace CRUD/vectors/collector are
  unused by the UI; coupling to its internals would reintroduce upstream-drift
  risk for zero gained capability).
- **Diary tab:** dedicated tab, not a pinned workspace; chat inside the tab still
  logs through the sidecar pipeline (logged/skipped surfaced per exchange).
- **Corpus harness:** adapter layer lives in the UI proxy (`listMonths`/
  `readMonth`; `DIARY_SOURCE=sidecar|local`). A `local` folder source is designed
  (env: `DIARY_LOCAL_DIR`), not implemented — build it only when the corpus
  actually moves. If it does, diary-companion gains the same source switch
  server-side so writes keep the journal/ETag guarantees (planned, not scheduled).

### Step F — deploy the UI (each gated on explicit user "go" before it runs)
1. Stage: `rsync` per README (now excludes `ui/node_modules`, `ui/dist`,
   `ui/server/ui-data`). Create `ui.env` server-side by COPYING the two existing
   secrets (LITELLM_MASTER_KEY from `litellm/.env`, DIARY_AUTH_TOKEN from
   `diary-companion.env`) — nothing regenerated. `chmod 600 ui.env`.
2. **GO-gate.** Build + start on the host:
   ```bash
   cd /mnt/docker/appdata/cowork
   docker compose build ui && docker compose up -d ui
   docker compose ps
   ```
   (Port 8021 — re-verify unused against the DaServer.md port table first.)
3. Verify: open `http://10.69.0.130:8021` — Diary renders the real corpus; Coding
   chat round-trips via E4B; Settings shows the live alias roster; footer shows
   Lemonade online. Then burn-in: daily-drive the UI; AnythingLLM (:8020) stays up
   untouched until you sign off on retiring it.
4. Changelog row → Row 6 below.

## 5. De-duplication (Q&A round 2026-09-03; PENDING GO — plan only)

Docker inventory (2026-09-03, 29 containers): the app stack is fine (ui 17 MB, sidecar
83 MB); the redundancy is elsewhere. Proposed sequence, every step requires explicit GO,
nothing deleted (stop only; images retained for rollback):

| Order | Target | Why safe | Recovers |
|---|---|---|---|
| 1 | `open-webui` (:3000) | AnythingLLM replaced its job; UI supersedes that | 657 MB |
| 2 | standalone `diary-companion` (:8010) | after Solair AI re-point; NOTE currently UNHEALTHY — diagnose before/instead | 54 MB |
| 3 | `cowork-litellm` | proxy routes directly now; keep one burn-in week first | 793 MB |
| 4 | `cowork-anythingllm` | after UI burn-in (existing §2b gate) | 348 MB |

Also flagged: Gluetun publishes :8000 and :8080 (qBittorrent/other web UIs) — fine, but
worth a DaServer.md port-table cross-check someday.

## 6. Explicitly NOT in this session (deferred, not forgotten)

- Retiring the standalone container's port / Open WebUI decommission — gated on later
  sign-off after a real-use burn-in of the new UI (spec §10.6). **AnythingLLM
  retirement** now joins this list (after UI burn-in, per §2b).
- Crash drill against the sidecar (once sidecar is daily-driven), Phase 1a GPU
  experiments, Phase 1b benchmark (needs 10–20 real excerpts from the user),
  Cloudflare Tunnel hostname for the new app.
- Other-space provisioning beyond the default five, per-space model overrides in the
  UI, New-space flow (currently a stub alert in the UI).
- Model-router refinement beyond alias-per-task-class — waits on Phase 1b data.
- Solair AI re-pointing decision (open question §11): during migration it keeps talking
  to the standalone container at `:8010` — zero client changes required.

## 4. Cutover (separate session, sketch)

1. Sign-off → change compose override `SPIKE_CORPUS_ROOT` to `Diary` (or remove the
   environment override) and recreate only the sidecar.
2. Verify first real exchange lands in the real `Diary/2026-09.md` under today's headers.
3. Solair AI / AnythingLLM both live on the same pipeline via different front doors —
   no double-logging risk: one container owns the corpus at a time. Standalone stays
   RUNNING but any client pointing at it is now the thing to switch off (Solair AI
   base URL → new tunnel/LAN address), THEN standalone's public port is retired.
4. Changelog row for each of the above, alongside the work.
