# noevia roadmap

The one planning document. Consolidated 2026-09-16 from the previous roadmap, the
roadmap audit, the backlog, the continuation checkpoint, both Codex handoffs, the live
and settings audits, the UI-overhaul plan, the Freebuff report and every master prompt.
Their dated evidence is in git history and [changelog.md](changelog.md); design detail
stays in the `spec-*.md` files linked below. The executable brief is
[master-prompt.md](master-prompt.md).

Status words: **Shipped** = deployed and verified · **Open** = to build ·
**Research** = ends in a written recommendation · **Decision** = waiting on the user · **Decided** = settled 2026-09-17 by delegation (table in master-prompt.md § Decisions).

## Where things stand — end of 2026-09-17

Branch `claude/compaction-correctness-fix-ltyu9p` (GitHub `sbstndalton/noevia`), last release
**`127b300`** live on DaServer (`https://cowork.daserver.work`, see `deployment.md`).

### Live and verified in production
- Services: web, Diary, OCR, model-loader (token + `models` network, D1), native llama.cpp
  (`--models-max 1`), Kiwix (`wikipedia_en_all_nopic_2026-06`, internal network). All healthy
  after the 08:24 reboot.
- Models (D3): Qwen3.5-4B-Q5_K_M (ctx 24 576, 22.7k-token prompt in 46 s), Ornith-1.5-9B-Q5_K_M
  (16 384, 15.1k in 50 s), nomic-embed-text-v1 (768 dims). Auto roles: Fast 4B, Smart 9B, Vision 4B.
- MCP: Nextcloud, Tavily, in-app server (loopback 8022; diary + project-docs boxes, 10 tools).
- Features on through env: previews, Diary append tool, deep research (admin), offline Wikipedia.
- New in 127b300: Settings → Data (export ZIP, import, archived chats with Restore, delete old
  chats), Settings → Personalization (custom instructions, response style, background
  notifications), keyboard shortcuts (⌘/Ctrl K, ⇧O, comma, slash), HIG type scale and
  cleanups, plain-language tool rows, stale Auto-role 409 and alert, shared-memory (GTT)
  warning on the Hardware tab, glass pointer glint.

### Implemented, off or not yet proven
- **Tool router** (`features.toolRouter`, off): gate passed on synthetic fixtures (14/14, 9.7 s vs
  10.6 s, −23 % input tokens). Not measured on real Nextcloud boxes. With `--models-max 1` every
  routed message loads the embedding model and evicts the chat model, so leave it off until
  memory allows two models.
- **Deep research** is on for admins, but the spec §8 gate never finished (run cut off by the
  outage). Harness is ready: 12 questions + 4 project + 2 adversarial, variants A/B/C.
- **Off-site backups** (D7): built, no target configured.
- **DAV ops** (D6): built; the sharing listener is still unconfigured.
- **Diary append** (D10): live, tested on synthetic corpora only (by rule), never against the real
  Diary.
- **Kiwix tool**: search verified from the web container, not yet used in a real model chat.
- **Vision role** on the 4B: configured, no image test on the new presets.

### Broken or risky right now
- **Outage cause unknown.** DaServer went unresponsive around 04:15 (SSH banner timeouts, Unraid
  UI down, later Cloudflare 530) after `--models-max 2`, a 52 GB ZIM download and an appdata
  backup. Syslog is in RAM and was lost. Docker network overlap ruled out. Leading hypothesis:
  unified-memory GTT allocations outside the container limit (findings §5, §7). Do not return to
  `--models-max 2` before a GTT cap / `--fit` and a measured peak.
- **Retrieval evicts chat** under `--models-max 1` (embedding and chat model swap on RAG turns).
- **`EMBEDDING_MODEL` renamed** (`nomic-embed-text-v1-GGUF` → `nomic-embed-text-v1`). Project RAG
  indexes built before today may be stale or empty; reindexing is unverified.
- Glass banding on real devices: still the user's check (D13).
- `llama-vulkan-test` container stopped and kept for rollback (user's request).
- QA runner false alarms: `qa/nav.cjs` (helper) and `qa/workspace-preview.cjs` (manual preview
  server) are not suites; `qa/native-live.cjs` needs the GPU window and leaves a server on 31329
  if it crashes.

### Research written today
`research-findings-2026-09-17.md` §1–11: D3 caps, tool routing, deep-research status, HIG audit,
outage, APU memory bounds (GTT, `--fit`), backend portability (stay on llama.cpp Vulkan), Unsloth
GGUFs, BrowserExecutor boundary (egress proxy), ACP for CodeHarness plus the local spike
(`experiments/acp-spike`: OpenCode writes silently by default; with `ask`, writes go through
client fs, but approved shell commands run in the agent's own process).

### Needs the user
Enable the Unraid syslog mirror · GTT cap decision · SMB pilot share and credentials (D11) · an
off-site target and budget (D7) · live-credit research run · a maintenance window for larger
context probes · sign-in/billing for Claude or Codex harness adapters.

## Shipped (do not rebuild)

Reliability fixes · PDF originals, OCR, images, DOCX · unified uploads · shared composers
across chat, projects and Diary · onboarding and invite flows · Diary scaffolding,
landing, day navigation, Markdown editing, calendar, recovery, trash, import/export,
date/tag filters · thinking modes v1 ([spec](spec-reasoning-effort.md)) · duplicate
tool-call guard · timezone handling · app passwords and limited Markdown DAV · instruction
skills lifecycle · backups with verified restore · direct native llama.cpp · Model Loader
folded into `services/model-manager` · page-load performance · MCP multi-server with
bearer tokens, compose drift test and preflight check · in-app MCP server (Diary reads,
project documents; off by default) · models refresh on change · unified Models & routing
page · minimal chat model panel · General settings (profile, preferences, capabilities) ·
cost estimates removed · Freebuff batch (parallel-test isolation, Markdown task lists,
mobile composer and tap targets).

## Open work

### A. Mobile and visual quality
- **Shipped** — At ≤600px the sidebar leaves the layout (no icon rail); one 44px "Open
  navigation" toggle opens a full-width drawer (≤420px) that traps focus, returns it to the
  toggle, closes on Escape/close/backdrop/selection, fits the software-keyboard viewport and
  closes itself when the window grows past 600px.
- **Shipped** — Search button hidden under the chat header between 601px and tablet widths
  (and with 44px touch targets): the header drops the wordmark there so the tools fit on one row;
  `mobile-viewport` asserts search is reachable at every width.
- **Shipped, device check pending** — Both traced to the WebGL light field (`public/glass.js`):
  a non-premultiplied, unclamped canvas (composited differently by WebKit and Blink) and a
  5–12% gradient with only a few dozen 8-bit steps. It now outputs premultiplied, clamped
  colour with ±½-step screen-space dither. Chrome looks unchanged; confirm on the iPhone and
  the Mac display.
- **Shipped** — One shared `CloseButton` for every dialog/popup close control (settings ✕ no longer differs).
- **Shipped** — Short-height populated sidebar reachability: `sidebar-reachability` covers 320×360, 375×360, 667×375 and a keyboard-height case, now through the phone drawer.
- **Shipped** — Phone checks for the setup wizard, Settings, Projects and Code with a software
  keyboard (`qa/mobile-surfaces.cjs`, real throwaway server). Fixed what it found: setup and
  sign-in screens did not follow the visible viewport, so focused fields could sit behind the
  keyboard; the phone Settings dialog stayed vertically centred while shrinking, hiding its
  lower half; both now fit the visible viewport.
- **Shipped (D4)** — Deterministic design-rule check: run Impeccable (`detect --json`, plain CSS
  supported) once against `apps/web/src`, triage findings against existing tests, mobile QA
  and screenshots, then adopt as a dev-only check, borrow selected rules, or reject. Also
  assess a lightweight post-edit scan for agent-driven UI work. Complements screenshot
  review; never replaces it. No app dependency.
- **Shipped (D5: hidden behind `features.previews`)** — Scheduled, Plugins, Explore and Coding are preview surfaces: keep them as
  labelled previews, or hide them until built.

8. **Shipped, first pass (2026-09-17) — UI polish from the user.** Applied: vendored Lucide icons with one distinct symbol per concept; System appearance by default (HIG dark-mode guidance); calmer status pill replacing the monospace stats bar; plain-language composer controls; shared empty states; sentence-case disclosures; inspector icon actions; aligned Diary breadcrumb; phone title sizes. Iterate on real-device feedback. Original request: The interface still reads as
   AI-generated. Study Apple's Human Interface Guidelines
   (https://developer.apple.com/design/human-interface-guidelines) and the skill collections
   `justinwetch/HIGAgentSkills` and `aka-kika/akakika-skills` as references (patterns and checklists,
   not dependencies); use open-source icon sets (license-compatible, vendored as SVG paths, no CDN)
   and design tooling; apply to the shell, chat, projects, settings and Diary within the agreed
   layout (`spec-ui-direction.md`), with the usual 375/768/1440 light/dark screenshots.

### B. Settings structure
- **Shipped (first split)** — General held profile, preferences and capabilities, and profile
  identity was duplicated under "Profile & security". Personal settings are now Profile
  (identity), Security (passkeys, sessions, sign-out, app passwords), Appearance, Capabilities,
  Diary & storage, Your connections, Usage & activity, Planned features. Personalization and
  Notifications stay under Planned until built. **Keyboard shortcuts shipped 2026-09-17** (⌘/Ctrl+K
  search, ⌘/Ctrl+⇧O new chat, ⌘/Ctrl+, Settings, ⌘/Ctrl+/ list; `components/shortcuts/`, `qa/shortcuts.cjs`). **Personalization → Custom instructions shipped** (per-user, 4000 chars, added to every non-Diary chat, project instructions win; `account-instructions.cjs`, `qa/personalization.cjs`), response style, and opt-in background notifications (reply finished / approval needed, content-free, per device; `components/notifications/`, `qa/notifications.cjs`). **Data → Export conversations shipped 2026-09-17**
  (ZIP of Markdown per chat + conversations.json, no reasoning text; `routes/export.cjs`,
  `qa/data-export.cjs`), and **Import conversations** (export ZIP or JSON; adds only, skips chats
  already present, restores deleted ones under new ids, creates missing projects;
  `chat-import.cjs`, `routes/import.cjs`). Retention and archived view remain planned. Still open: deeper pages at
  ChatGPT-level depth with Claude-level polish. References:
  `ui mockups/inspiration/`, [spec-ui-direction.md](spec-ui-direction.md),
  [ui-reference-review.md](ui-reference-review.md).
- **Shipped** — The model manager is its own full page (← Settings back button); Settings →
  Models & routing shows engine status, installed/loaded models, Auto routing and "Open model
  manager". The chat panel's "Model settings" opens the page directly.

### C. Model management
- **Shipped** — Per-model settings open in Easy mode (remembered per browser): "Tune for this
  machine" runs autoconfig's VRAM-fit estimate and "Use and save" writes it through the
  revision-checked save; plain MTP and KV-cache choices. Advanced keeps every `models.ini`
  field. Measured verification stays with native calibration.
- **Shipped** — Parity audit against Model Loader (2026-09-16). Its own HTMX UI was run
  locally from `services/model-manager` on a synthetic models folder (no Docker socket, so
  container pages were empty; the live `cowork-model-loader-1` was not touched) and compared
  with noevia's model manager page and the model-manager JSON API.

  | Model Loader feature | noevia | Outcome |
  |---|---|---|
  | HF search (sort), repo files, fit estimates, download by URL, companion mmproj | Discover | Parity |
  | Parallel chunked downloads, cancel, clear, HF token + test | Discover | Parity (chunk bars; no per-chunk speed sparklines — not ported, low value) |
  | `models.ini` editor with tooltips, show CLI, rename, delete, revision-safe saves | Model detail (Advanced) | Parity |
  | Raw `models.ini` and rolling backups | — | **Ported**: "Raw file & backups" (read-only; restore stays an operator task) |
  | Models directory disk free/used | — | **Ported**: shown on Your models |
  | Autoconfig: sessions, presets, fine-tune, spec profiles, vision, measured throughput, config history | Autoconfig panel | Parity |
  | Benchmarks, sweeps, output, badges incl. clear | Benchmarks | Parity |
  | Check for updates, delete model | Your models | Parity |
  | Bulk delete | — | Not ported: rare and destructive; single delete with confirmation kept |
  | Backend dashboard, logs + filter, restart, test prompt, failure diagnosis | Hardware | Parity (live-following log is G2) |
  | Prompt library | Prompt library | Parity |
  | Command palette (Cmd/Ctrl-K) | — | Not ported: app-wide concern, not model-specific |
  | OpenWebUI sync, per-connection visibility, dead-id cleanup, capability sync | — | N/A: noevia is the client; no OpenWebUI |
  | "Serves on" per backend, add another backend | — | N/A: one native engine; revisit with multi-backend |
- **Shipped** — A finished download registers itself once via model-manager
  `POST /sections/{name}/safe-defaults`: context capped at 8k, `draft-mtp` only with a draft
  head beside the file, `jinja` for the GGUF template, no sampler keys. Never overwrites an
  existing section; the preset reload never unloads, and a loaded model deferring it is shown.
- **Shipped** — A project or chat whose model is no longer installed shows "No model
  selected" (only when the local catalogue was read successfully; other providers exempt).
- **Shipped** — Download location: Discover shows where downloads land (host path via
  `MODELS_HOST_PATH`, free space) and a **Save to** choice of the models folder or folders
  directly inside it that are mount points or listed in `MODEL_DOWNLOAD_TARGETS`; the server
  rejects anything else. DEPLOY.md §3.6 documents moving the models share and mounting more.
- **Shipped** — Routing clarity: roles read "Fast — quick answers", "Smart — harder questions",
  "Vision — reads images (optional)" everywhere; "How Auto decides" states the real rules
  (heuristic → one-word Fast check → fail-open to Fast; Vision describes images first); the
  per-project table lists every project with Auto/Manual and the model it uses (or "No model
  selected"). Copy lives in `src/routing-copy.ts` beside the server logic it mirrors.
- **Closed, not reproducible (2026-09-17)** — Hugging Face cache hex identifiers. A real
  HF-cache fixture (`models--org--repo/snapshots/<commit>/file.gguf` symlinked into
  `blobs/<sha256>`) lists by file name and stem in `/models` and `/sections`; no hex-only name
  appears (test `test_hugging_face_cache_layout_never_surfaces_hex_names`). The live native
  router lists three plain ids, and the web layer already drops bare 32–40 hex ids. Reopen with
  a screenshot if it recurs.
- **First wave shipped 2026-09-17** — Configuration-scoped qualification evidence (design in [spec §1](spec-agent-execution.md)): `server/evidence.cjs` (identity hash, cheap artifact fingerprints, append-only store, derived states); the native manager computes live identity (build, endpoint hash, preset hash, model/projector/draft fingerprints, context, MTP); native calibration and the vision probe record evidence; `GET /api/models/evidence`; model details show verified/failed/stale/unverified/unavailable rows. MTP acceptance (from chat replies) and throughput (median of warm requests from a benchmark run of the saved preset, recorded when a run finished within 30 min is viewed) producers shipped 2026-09-17. Admin recheck (`POST /api/models/evidence/recheck`, image input; context stays with Measure context) shipped 2026-09-17. Design: states (reported,
  unverified, verified for this configuration, failed, stale, unavailable) tied to an identity
  tuple (backend, model, artifact, projector, runtime, context, MTP profile, harness, prompt
  preparation, suite, date); changes mark evidence stale. No universal score.
  ([spec §1](spec-agent-execution.md))
- **Baseline written 2026-09-17, measurements need scheduling** — Known-good settings ([research-known-good-settings.md](research-known-good-settings.md)): live presets ask 131K–262K context while the only calibrations verified 16K (9B) and 24K (E4B); all presets set `draft-eagle3` without a draft model. Provisional limits and a measurement plan; production presets untouched.
- **Research** — Wider model evidence: accuracy, reasoning budgets, MTP, multi-GPU; and
  applying the qualified Gemma 131k / Qwen 262k profiles beyond their exact configuration.
- **Research** — Backend portability (llama.cpp vs vLLM), measured, no silent migration
  ([spec](spec-backend-portability.md)).

### D. Modes, projects and harnesses
- **Shipped** — Projects carry `modes` (`chat`/`cowork`/`code`, at least one). Existing
  projects migrate to `['chat']` on workspace load and are saved once; create/patch validate.
  The chat sidebar lists Chat-enabled projects, the Projects page lists all with an
  availability chip, a project not enabled for Chat shows why and hides its composer, and
  `/api/chat` refuses it (409) before any inference. Project settings → "Available in".
  Tenant isolation unchanged (per-user `projects.json`). Cowork and Code are recorded only;
  they are enforced when those modes get routes.
- **Blocked on a second working mode** — Optional shared context layer across a project's
  modes (per project, per mode, off by default). Nothing can share context until Cowork or
  Code exists, so no flag is stored yet; design it with that mode.
- **Design before Code build; ACP evaluated 2026-09-17 → adopt** — `CodeHarness` (contract v0 mapping ACP kinds/permissions to noevia approvals, OS-level enforcement note, spike plan in [spec §3](spec-agent-execution.md)): noevia-owned contract that external harnesses
  (Codex, Claude Code, DeepSeek Harness, OpenCode, Hermes) adapt to; Harness and Prompt
  preparation dropdowns beside Model; coding evidence scoped to model × harness × architect;
  every harness action classified through noevia's approval gate; one writer per workspace
  first. Evaluate ACP as the adapter protocol. ([spec §3](spec-agent-execution.md))
- **Research, benchmark designed 2026-09-17 (not run)** — `PromptArchitect` (schema, P0–P3 variants, 18 fixtures, metrics, outbound audit and decision rules in [spec §2](spec-agent-execution.md)): optional stronger model (local or cloud,
  provider-neutral, official auth only) writes a structured execution prompt for the local
  model. Modes Direct (default) / Local / Frontier; Auto only after paired fixtures prove a
  benefit. Outbound context allowlist enforced in code, disclosure shown, original request
  stays authoritative, no hidden reasoning stored. ([spec §2](spec-agent-execution.md))
- **Later** — Cowork browser capability through a noevia-owned `BrowserExecutor` on an
  execution node: isolated profiles, domain allowlists, secrets substituted outside model
  context, consequential actions through approvals, run as durable jobs. Browser Use is one
  candidate implementation. ([spec §6](spec-agent-execution.md))

### E. Tools
- **Shipped** — Tool calls render as one collapsible list under the thinking block in chat,
  projects and Diary: a line per call with state, name and one-line result; each expands to
  pretty-printed arguments and the result (kept up to 4,000 chars, stored with history).
  Open while calls run, collapsed after. Approvals stay outside the fold with full arguments.
  Replies saved in the old "name ✓" format still display.
- **Measured and built 2026-09-17 (gate passed; `features.toolRouter`, off by default)** — router 14/14 vs baseline 14/14, median 9.7 s vs 10.6 s, 23% fewer input tokens on Qwen3.5-4B ([results](../experiments/tool-routing/README.md)); chat narrows the project's own toolboxes per message and fails open. Original item: Task-conditional tool loading: a pre-turn embedding router picks
  toolboxes for the task from the manifest, loads them for the session, and adds no
  discovery round. A tool-search/unlock variant was already measured slower on these
  models (12.91 s vs 8.64 s median). Adopt only if the `experiments/tool-routing` runner
  shows equal-or-better completion without higher latency. Model-driven tool search (as in
  Row-Bot) stays rejected on that evidence. Add manifest fields only as this work needs them
  (example tasks, `autoLoad`, `requires`, `resultReducer`); one registry, policy never in the
  prompt, auto-loading never pre-approves a write.
  Prepared 2026-09-16: `server/tool-router.cjs` (pure routing policy with unit tests: ceiling,
  `never`, `requires` closure, whole-box cap, collisions, user selection, fallback) and a
  `router` mode in `experiments/tool-routing`. Not wired into chat or the tool menu, and no
  flag exists yet: that follows only if the benchmark passes once models are served again.
  Manifest fields (`examples`, `autoLoad`, `requires`) get added with that wiring.
- **Shipped (D10, live 2026-09-17)** — Approval-gated, append-only `diary_append` in the in-app MCP server.
- **Live (D9, 2026-09-17)** — Kiwix-serve with `wikipedia_en_all_nopic_2026-06` on an internal network; feature on.

### F. Diary and storage
- **Shipped (audit + last composer fork)** — Diary already reuses the composer actions, model
  control, reasoning control, send icon, thinking block, tool-call list, Markdown renderer,
  modal close button, live timer, scroll hook and the app-level stats footer. The message
  textarea (Enter to send, Shift+Enter newline, IME-safe) was copied in chat, projects and
  Diary; it is now one `ComposerTextarea`. Deliberately still separate: the Diary reply layout,
  whose capture/recovery states and edit-by-xid semantics differ from chat replies.
- **Shipped (read path confirmed)** — Diary reads go browser → `/api/diary/today` →
  sidecar `/api/day` → the tenant's corpus backend. "App-hosted copy first, WebDAV after" is
  already managed mode (`managed_storage.py`: SQLite primary, debounced append-only WebDAV
  backup outbox); fresh tenants default to it and legacy tenants move with "Copy verified files
  & use app storage". The remaining latency was legacy WebDAV tenants on the daily layout:
  a month view fetched every day file one at a time (up to 31 round trips). The WebDAV backend
  now declares `concurrent_reads = 6` and those reads run together, in order, with the same
  partial-failure behaviour (synthetic 20×50 ms month: ~1 s → under ⅓). Month listing
  (`list_months`) is still sequential PROPFINDs; measure on the SMB/WebDAV pilot before
  changing it.
- **Shipped (already in place, verified 2026-09-16)** — Generic WebDAV is a first-class storage
  kind alongside Nextcloud and S3: the picker offers it, `storage-client.cjs` and the Diary
  sidecar treat `webdav` and `nextcloud` identically apart from Nextcloud's login flow, managed
  backups accept either, and `storage-client.test.cjs` / `restore-http.cjs` exercise it against a
  local WebDAV server. No Nextcloud-only copy remains in the storage UI.
- **Open** — Mac SMB authenticated pilot, then the real Diary cutover
  ([spec](spec-diary-smb.md)).
- **Contract written; decided (D6: add `AI Memory/**`, build without LOCK)** — DAV rename/delete/copy/locks:
  [dav.md § Storage contract](dav.md) fixes invariants (single guarded write path, tenant root,
  protected capture/month/index paths reusing the Trash rule, If-Match required, DELETE =
  Trash, bounded all-or-nothing folder ops, explicit uncertain outcomes), per-method status
  codes, when to advertise `DAV: 1`/`2`, and the client interoperability matrix. Decision:
  confirm the protected set (optionally add `AI Memory/**`).
- **Shipped (verified 2026-09-17)** — Fresh-install managed volumes and the `/boot` guard were
  already in place: `deploy/init-managed.sh` selects `web-data`/`diary-data` only for new
  installs and refuses existing state (tests pass), and the preflight check rejects writable
  `/boot` binds after resolving symlinks, loops, parents and volume driver options (PHP test
  passed on DaServer in a temp dir). Existing `COWORK_STATE_DIR` binds keep their meaning.
- **Shipped (verified 2026-09-17, synthetic)** — Claude Diary bridge: bridge (3) and server
  connector (3) tests pass; against a disposable sandbox tenant a created credential listed,
  read, created and updated files with versions, got 409 for stale and duplicate creates, 400
  for traversal, 401 for a bad token and after revocation. Logging behaviour differs from the
  in-app companion by design: the bridge makes explicit, versioned, Claude-approved Markdown
  edits (it can edit capture files and the index, like the in-app editor) rather than appending
  structured exchanges with xid markers through capture.
- **Partly verified (2026-09-17)** — Diary corpus in backups: the latest nightly archive
  (`ab_20260916_151428`, `cowork-diary-1.tar.gz`) contains app-managed Diary storage
  (`users/<id>/managed-diary.db`) and the per-user corpus folder. Re-check once the real Diary
  moves to the SMB/dedicated root, since that path is not mounted yet.
- **Built on branch (D7)** — encrypted S3-compatible snapshots module; the provider and budget are still the user's.
- **Shipped on branch (D8: guarded empty-only sweep)** — Empty-folder cleanup after project deletion; see Current phase.

### G. Telemetry and logs
- **Shipped** — Footer tokens/s updates the moment each round's SSE `usage` event arrives instead of waiting on the 2.5s poll. A single long round still can't tick mid-generation: llama.cpp reports the rate only when a request finishes.
- **Shipped** — Engine log (model manager → Hardware → Logs): "Follow live" polls the tail
  every 2 s (paused when the tab is hidden), stays pinned to the newest line, pauses when you
  scroll up with "Jump to latest", keeps a 1,000-line window, filters by text/level. The model
  manager scrubs secret-shaped strings (auth headers, bearer/HF/sk-/GitHub/AWS/JWT tokens,
  secret-named key=values, URL credentials) before filtering or returning lines; members get
  403. Polling rather than SSE: no per-viewer Docker stream through the JSON proxy.

### I. Deep research mode
- **Spec written** ([spec-deep-research.md](spec-deep-research.md)) — cited reports as a
  background job on the durable-work primitive: optional editable plan, per-sub-question
  gather with deterministic reduction, bounded map-reduce synthesis, deterministic citation
  check, report + sources saved via `uploads.ingest`. Why a plan step is permitted here despite
  the chat planner result, and the measurement gate (chat+web vs pipeline with/without plan vs
  `tavily_research`, on a local fixture site). Build waits for R6. Decisions listed in §10.
- **Shipped 2026-09-17 (build steps 2–3, not user-reachable)** — `server/research-sources.cjs`
  (source registry, deterministic boilerplate strip / heading-aware chunking / capped excerpts,
  citation verifier with no model call) and `server/research-runner.cjs` (variant B on the jobs
  primitive: web-call and time budgets, untrusted-source framing, window preflight, checkpoints,
  cancel), with unit tests. Offline fixture site + measurement script in
  `experiments/deep-research/` (seed set; verified with a stub model only). Finding: citation
  checks can't catch faithfully quoted injected text — adversarial resistance is measured, not
  verified. **Next needs the user:** a sandbox model run, Tavily wiring/budget, members, and
  where reports are saved (§10).

### H. Platform
- **Researched 2026-09-17** — Headscale vs NetBird ([research-remote-access.md](research-remote-access.md)): don't migrate yet; neither changes the data path, the recorded slowness was WAN loss, DaServer's NAT allows direct paths. Measure with `tailscale ping`/`iperf3`/`mtr` from a remote client; if self-hosting is still wanted, Headscale.
- **Researched 2026-09-17** — AIO-style master container ([research-master-container.md](research-master-container.md)): don't build; keep Compose Manager. Found model-loader's socket-backed API reachable unauthenticated from the Diary container; repository fix adds `MODEL_LOADER_TOKEN` and a `models` network. Applied live 2026-09-17 (657d21b).
- **Later** — Mac-native app as both client and optional trusted **execution node** (local
  files, terminal, repositories, browser, notifications): server orchestrates, node executes
  advertised capabilities after explicit pairing; never blanket control of the Mac. Idea: Swiftlet
  as an optional local runtime for that node.
  ([spec §5](spec-agent-execution.md))

## Research priorities

Ranked. Each ends in a written recommendation in `docs/` with measurements from this
deployment's models. Can run alongside the build order.

**Near-term**
1. **Context efficiency: scripts before tokens** ([spec](spec-context-projection.md)). Measurement log shipped 2026-09-16 (`CONTEXT_LOG=1`, counts and tool names only); collecting data and reducers still to do.
   Measure tool/context consumption first; then trim deterministic waste with tool-aware
   reducers (full results kept authoritative); collapse recurring sequences into task-shaped
   tools; handle mechanical work without the model; summarize only where still needed. Script only
   sequences the logs show repeating. Includes
   the protected-input preflight, validate-before-commit compaction, atomic tool-call groups and
   the authoritative / model-facing / UI layer split. Acceptance: fewer model-facing tokens, no
   lost results, no worse completion, fewer LLM compaction calls.
2. Configuration-scoped model qualification design (C).
3. Impeccable UI-QA evaluation (A).
4. Prompt Architect spec and benchmark design (D).

**Before Code mode is built**
5. `CodeHarness` contract, harness/prompt-preparation selectors, model × harness × architect
   evidence, workspace ownership (D).

**Before Cowork or Deep Research is built** ([spec §4](spec-agent-execution.md))
6. **Built 2026-09-17** (`server/jobs.cjs`, first consumer: source processing; [spec §4](spec-agent-execution.md)). Shared durable-work primitive: append-only events, derived state, restart recovery,
   explicit uncertain side effects, fixed worker capability scope.

**Before browser automation**
7. `ExecutionNode` and `BrowserExecutor` contracts, browser security/approval model, then a
   Browser Use evaluation on a node. *Idea to explore, not a commitment:* cua's VM-sandboxed computer server (Lume on the Mac,
   Linux desktops on DaServer) as one possible Cowork computer-use shape; its host desktop
   driver, if ever, only as the highest-trust node capability. Telemetry off.
   ([spec §5](spec-agent-execution.md))

**Other**
8. Known-good settings per model and hardware.
9. Wider model evidence: accuracy, reasoning budgets, MTP, multi-GPU. *Idea to explore:* running larger
   MoE models on DaServer by keeping experts in system memory or mmap'd from disk with llama.cpp's
   own options (verify flags against the pinned build), measured on this GPU — the idea behind
   flash-moe/Swiftlet, whose Metal-only code doesn't apply here.
10. Backend portability (llama.cpp vs vLLM).
11. Headscale vs NetBird to replace a slow Tailscale.
12. AIO-style master container managing the stack.

**References (added 2026-09-17; reviewed in [research-references.md](research-references.md): borrow ideas only, no dependencies)**

- [Ramps](https://www.ramps.studio/) — free tool that generates perceptually even OKLCH colour
  scales and WCAG-checked semantic tokens from one brand colour. Question: could it inform or
  replace how noevia's palettes and `tests/theme-contrast` tokens are derived?
- [zoxilsi studio](https://studio.zoxilsi.cc/) ([source](https://github.com/zoxilsi/studio),
  MIT; Next.js, Three.js, GLSL) — WebGL mesh-gradient editor with image/video/code export.
  Question: a reference for the glass light field (`public/glass.js`) and banding-free
  gradients, not a dependency.
- [appllama-skills](https://github.com/Appllama/appllama-skills) (MIT; name/logo trademarked) —
  agent skills for building native-quality mobile apps from top-app design patterns, using the
  Appllama MCP design library and Expo simulator checks. Question: useful for the future Mac/iOS
  client or as a pattern for agent-driven UI QA.
- [Unsloth](https://github.com/unslothai/unsloth) (Apache-2.0 core) — fine-tuning and RL
  library for local models, and a major publisher of GGUF quantizations (dynamic quants).
  Questions: are its GGUFs the preferred source for Discover/known-good settings (R8), and is
  local fine-tuning (for example a Diary-style or tool-calling adapter) worth a later spike on
  this hardware?

**Later:** Mac execution node and richer desktop capabilities; Auto architect/harness routing
once evidence exists.

Research tied to a build item stays with it: task-conditional tool loading (E) and deep
research mode (I) are measure-first, then build.

## Order

0. **Shipped.** Compaction correctness: protected-input preflight and validate-before-commit
   ([spec §3–4](spec-context-projection.md)). Placed first because it is a verified bug —
   a compaction that shrinks but doesn't fit is saved before the fit check — and it is small.
1. **Shipped.** Live stats, settings ✕.
2. **Shipped.** Deleted model state, safe defaults after download.
3. **Shipped.** Full-page model manager with Easy/Advanced and the parity audit.
4. **Shipped.** Mobile drawer, search button, brightness and banding (on-device check pending).
5. **Shipped.** Live log tab, tool-call menu, settings sub-pages (first split).
6. **Shipped (D1).** Modes and projects; the shared context layer (D2) waits for a second mode.
7. **Shipped.** Diary latency, inheritance and WebDAV plugin; SMB cutover when the user is ready.
8. **Spec written / prepared.** Task-conditional tool loading (router + benchmark ready, not measured) and the deep research spec.
9. Research priorities in ranked order; context-efficiency logging can start alongside the
   build items.

## Current phase — decisions build (2026-09-17)

Build order from master-prompt.md § Current phase. Checked items are committed and pushed.

- [x] 1. **D1 preflight** — `deploy/preflight/check.php` `modelLoaderBoundary()` blocks a deploy when
  model-loader's `MODEL_LOADER_TOKEN` is unset/short, web lacks the same token, or diary shares a
  network (or host mode) with model-loader; `overlay-release.sh` rolls back if the running diary can
  resolve `model-loader`. PHP tests run on DaServer in a temp dir; the live resolved config is
  **blocked** by it today, as intended, until the operator steps are applied.
- [x] 2. **D5** — `server/features.cjs` registry (env `NOEVIA_FEATURE_*` is authoritative and locks the
  toggle; otherwise the admin setting in the auth DB `settings` table; default off), routes in
  `server/routes/features.cjs` (`GET /api/features` booleans for any user, admin list/PUT), UI in
  `src/components/features/` (Settings → Administration → Features; shared `.noevia-switch`).
  `previews` gates Scheduled/Plugins/Explore and the Code mode switch/workspace. Flags are cached
  per browser under `noevia:feature-flags` to avoid a layout shift. `qa/features.cjs` added.
  Deviation: the "Planned features" settings page stays visible — it is an honest roadmap list,
  not a dead-end surface.
- [x] 3. **D8** — `server/project-sweep.cjs`: after a delete is saved, `rmdir` (never recursive) the
  project's `project-uploads`/`project-documents`/`project-assets` dirs if empty and realpath-inside
  the tenant dir; remote WebDAV folder (directly under `PROJECT_ROOT_FOLDER`) and its empty
  Documents/Images/Text/Other subfolders go only when PROPFIND shows no children and DELETE with
  `If-Match` on the collection ETag succeeds (no ETag → no delete; S3 has no dirs). Logged as
  `project.sweep`. Deviation: no route file — it is a post-commit hook, not an endpoint.
- [x] 4. **D6** — Companion `workspace_ops.py` (`POST /api/workspace-ops`): DELETE = Trash capsules per
  file, MOVE/COPY in one SQLite transaction, If-Match (428/412), protected set + `AI Memory/**`
  (403), ≤500 entries/50 MiB (507), managed storage only (409), index outbox for old+new paths.
  Web `server/dav-ops.cjs` (tenant-bound Destination, tagged `If` for destination, 503 +
  Retry-After on unknown outcome), folder ETags in PROPFIND, `DAV: 1`, no LOCK. Tests:
  `tests/test_workspace_ops.py` (19), `server/dav-ops.test.cjs`. Interop matrix still to run.
- [x] 5. **D10** — Sidecar `POST /api/entries/append` (today only, `entryTime` must be now ±15 min,
  UUIDv4 `requestId` = xid so replays never duplicate, no headings/markers, ≤8000 chars) on
  `log_exchange`'s journal + guarded append. Web: `diary_append` tool in
  `mcp-internal-tools.cjs` only when `features.diaryMcpWrite`; not in `reads`, so approval is
  always required; audited `diary.append` (xid, length). Tests: `test_diary_append.py`,
  `mcp-internal-tools.test.cjs`, `qa/diary-append-http.cjs`.
- [x] 6. **D12** steps 4–5 — plan step (`research-plan.cjs`), service (`research-service.cjs`: budget
  12 web calls/10 min/5 sources, one active job per project, report + `.sources.json` saved via the
  upload path, artifacts on the job, cancel keeps finished sections, explicit partial save),
  admin-only routes (`routes/research.cjs`, 404 unless `features.deepResearch`), Research tab in
  the project (`src/components/research/`), `qa/research.cjs`. Deviation: files are named
  `Research <date> <slug>.md` in the project's Text upload folder, because uploads only manage the
  Documents/Images/Text/Other subfolders. The §8 measurement gate (real model) is still unrun —
  no model is served on DaServer. Fixed on the way: `jobs.recover()` ignored `kinds`; the shared
  close icon's second stroke was half length (skewed ×).
- [x] 7. **D7** — `server/offsite-backup.cjs` (AES-256-GCM, HMAC chunk ids, 4 MiB chunks, encrypted
  manifests, dedupe, restore into an empty dir with per-chunk and per-file verification, retention
  7 daily/4 weekly/6 monthly + prune, restore test), `offsite-s3.cjs` (SigV4, HTTPS-only except
  loopback, no credentials in URLs), `offsite-service.cjs` (env config, nightly at
  `OFFSITE_BACKUP_HOUR`, status file, consistent SQLite copies via the online backup API),
  `routes/offsite-backup.cjs`, Settings → Off-site backups. Operator env: `OFFSITE_BACKUP_S3_ENDPOINT`,
  `_BUCKET`, `_REGION`, `_ACCESS_KEY_ID`, `_SECRET_ACCESS_KEY`, `_PREFIX`, `OFFSITE_BACKUP_KEY_FILE`
  (64 hex chars, refused inside a backed-up path), `OFFSITE_BACKUP_PATHS` (default `UI_DATA_DIR`;
  add the Diary data mount to include the corpus). Deviation: Node AES-256-GCM instead of
  age/libsodium (no new dependency). Tests: `offsite-backup.test.cjs`, `offsite-service.test.cjs`,
  `qa/offsite-backup.cjs` (fake S3).
- [x] 8. **D9** — `server/kiwix.cjs` read-only built-in box `offline-wikipedia` (`wikipedia_search`,
  `wikipedia_read` with offset paging; only `/content/...` paths from this server; content labelled as
  reference) when `features.kiwix` and `KIWIX_URL` are set. Compose: `deploy/examples/kiwix.override.yml`
  (profile `kiwix`, `ghcr.io/kiwix/kiwix-serve:3.7.0`, read-only, cap_drop ALL, internal network,
  no ports). Verified 2026-09-17 against a real kiwix-serve 3.7.0 on DaServer with a 26 MB test ZIM
  in a temporary container (removed with its image and files). Not deployed.
- [x] 9. **D4** — Impeccable 4.1.0 (npm shim + its pinned `@impeccable/cli-darwin-arm64` binary) run once
  from a temp dir, removed afterwards; nothing added to the app or image. `detect --json src`: 9 findings.
  Triage: **real** side-tab accents on the approval card (`app.css`) and `.msg-warning` → uniform
  border/tint; **newly caught** dead `.diary-tab` rules (no component uses the class; removed from
  `diary-tab.css` and `noevia.css`); **noise** ×2 bounce-easing (`--ease-spring` is
  `cubic-bezier(0.16,1,0.3,1)`, no overshoot — flagged by name), blockquote rule, ×2 palette/theme
  swatch miniatures (thick left edge draws the sidebar; annotated). Kept locally as
  `npm run lint:design` (`scripts/lint-design.cjs`: side-tab, overshoot-ease, gradient-text; inline
  `design-lint: allow` with a reason), tested in `tests/lint-design.test.cjs`, which also keeps the
  stylesheets clean in `npm test`. Recommendation: keep the local script; re-run Impeccable
  occasionally on a URL scan of the local spin-up, not as a dependency. No post-edit hook: the
  script runs in <0.1 s inside `npm test` already.
- [x] 10. **D3** — preset diff and go-steps in `research-known-good-settings.md` § D3 (4B capped at
  24 576, 9B at 16 384, `spec-type` removed, gemma E2B out of the served set, nomic embed added).
  Found while preparing it: the live `models.ini` has three presets and the GGUFs are back on disk,
  so the "no models served" carry-over is stale; the engine runs `--models-max 1`, which would
  make embeddings evict the chat model. **Applied live 2026-09-17** with `--models-max 2`, caps
  verified (4B 22.7k tokens in 46 s, 9B 15.1k in 50 s) and stale Auto roles fixed.

### Bug hunt

Rotation order a→f (master-prompt § Bug hunt). Baseline 2026-09-17 before pass 1: npm test 587,
typecheck/build green, every `qa/*.cjs` green except `mobile-audit` (clicked the Chat/Code switch
that D5 hides — test fixed to use New chat), pytest diary 310 passed/3 skipped, model-manager 19,
deploy 5, experiments 5.

- 2026-09-17 · pass 1 (a, chat/approvals) · Stopping a reply while a write awaited approval saved the
  approval card as `pending`; the call showed Allow/Decline buttons that could only 404, and a
  `running` chip spun forever after reload · `settleToolCalls` marks unfinished calls "not run" when
  a reply ends and when history loads · `tests/tool-call-state.test.cjs`, `qa/stopped-approval.cjs`.
- 2026-09-17 · pass 1 (a) · Hardening, not a confirmed user bug: two sends dispatched in one task
  started two generations for one chat (render-state guard); real double Enter presses are separate
  discrete events that React flushes, so no human-reproducible path was found · ref guard ·
  `qa/duplicate-send.cjs`.
- 2026-09-17 · pass 1 (a) · Considered, not a bug: "Allow for this chat" keyed by `userId:-` when a
  request has no chatId — the browser always sends one and only the same user can omit it.
- 2026-09-17 · pass 2 (b, auth) · Password sign-in skipped Argon2 for unknown usernames (0.09 ms vs
  12.5 ms), so response time revealed which accounts exist; and the limiter keyed on address+username
  let one address spray passwords across any number of usernames · always verify against a lazily
  created dummy hash; add a 30-per-15-min per-address limit · `server/auth-enumeration.test.cjs`.
- 2026-09-17 · pass 2 (b) · Suspected, not fixed: passkey `authentication/options` returns the
  credential ids of a known username and an empty list for an unknown one (enumeration). Returning
  an empty list for everyone would break sign-in with non-discoverable passkeys
  (`residentKey: 'preferred'`); needs a product decision on discoverable-only passkeys.
- 2026-09-17 · pass 3 (c, Diary/storage) · The D10 append endpoint answered 200 "Added a note" when
  storage refused the write and the journal only queued it · 202 `queued: true` unless the document
  carries the new marker; the tool says the note is in the write queue ·
  `tests/test_diary_append.py::test_append_reports_queued_when_storage_refuses_the_write`,
  `mcp-internal-tools.test.cjs`.
- 2026-09-17 · pass 4 (d, model manager) · No confirmed bug: token middleware (exact health exemption,
  constant-time compare), admin-only proxy path checks, download tracker states and evidence
  derivation reviewed. Noted: MTP evidence appends on every ≥0.05 acceptance change, so
  `evidence.jsonl` grows slowly and is re-read per reply — watch, not fixed.
- 2026-09-17 · pass 5 (e, projects/uploads/research) · No confirmed bug: project config patch indexes
  a spread copy (only affects document indexing state, which that path never touches), upload caps,
  research budget and job scoping reviewed.
- 2026-09-17 · pass 6 (f, UI) · With the "inference unreachable" banner on short phones (375×553,
  568×320), a new chat opened with the composer's add/send row off-screen or under the stats footer;
  the header's settings button also wrapped below the title at ≤640 px · greeting shrinks before the
  composer, header stays one row, stats footer and banner compact on short viewports ·
  `qa/short-phone-composer.cjs`.
- 2026-09-17 · pass 6 (f) · Touch targets under 44 px on phones/tablets: composer add/send (32),
  chat settings (32), project tabs (32 tall), project card options (30×33), Settings back (30 tall)
  and close (32 wide), project filter (38), thinking-effort select (38), "open an empty chat" (17) ·
  `(pointer: coarse), (max-width: 640px)` minimums · `qa/touch-targets.cjs`.
- 2026-09-17 · pass 7 (a) · No new confirmed bug: client SSE reassembly, heartbeat during approval
  waits (5 s keep-alive vs Cloudflare's idle limit), retry/edit truncation reviewed.
- 2026-09-17 · pass 8 (b, admin/features) · Turning "Offline Wikipedia" or "Diary append tool" on in
  Settings saved and showed "on", but both are wired into tool catalogues at startup, so nothing
  changed until a restart (and turning them off left the tools live) · restart-wired features keep
  answering with the running value and the page says "Restart the server to apply" ·
  `features.test.cjs`, `qa/features.cjs`.
- 2026-09-17 · pass 9 (c) · No new confirmed bug: DAV move/delete enqueue old and new paths; the
  outbox marks them dirty and retrieval already refuses dirty documents until reindexed.
- 2026-09-17 · pass 10 (d, calibration) · When a calibration was interrupted or failed after
  `models.ini` changed, the original profile was (correctly) not overwritten, but nothing told the
  admin that the calibration's context size might still be in the profile · `restored: false` and an
  explicit error sentence in both paths · `llamacpp-calibration.test.cjs`.
- 2026-09-17 · pass 11 (e, research) · After the web-call budget ran out, later sub-questions were
  written as "No source had relevant information" — a false claim about questions never searched —
  and the report was not marked partial · "Not researched: the web-call budget was used up", partial
  flag and researched count · `research-runner.test.cjs`.
- 2026-09-17 · pass 13 (a, chat history) · **Data loss:** `POST /api/chats/:id/history` kept only the
  last 40 messages (the model replay cap), so every save of a chat longer than 20 exchanges deleted
  its oldest turns for good; saves over 1 MB (long reasoning or tool output) were refused with 413 and
  the client ignored the failure · stored transcript cap 5000 messages / 32 MB, separate from the
  40-message model replay; oversize answers with a readable message ·
  `server/chat-history-routes.test.cjs`. Suspected, not fixed: two devices saving the same chat
  overwrite each other (last writer wins; no version check) — needs a merge design.
- 2026-09-17 · pass 13 (a, context) · The chat handler cut the incoming history to the last 40
  messages before the context projection, so older turns of any chat past 20 exchanges vanished from
  the model's context with no summary (and the compaction prefix shifted every turn) · offer up to
  1000 messages to the projection (compaction's own bound) and raise `/api/chat` body limit to match ·
  `qa/chat-context.cjs` (long chat reaches the model).
- 2026-09-17 · pass 14 (b, auth) · One-time secrets were not single-use under concurrency: the
  invitation, first-run setup code and recovery link were checked before the asynchronous Argon2 hash
  and consumed after it without a guarded update, so two simultaneous submissions created two
  accounts from one invite (including admin invites), two administrators from one setup code, or
  two password resets from one link · consume inside the transaction with `… AND used_at IS NULL` /
  delete-if-matches and treat a lost race as used · `server/auth-races.test.cjs`.
- 2026-09-17 · pass 15 (c) · No new confirmed bug: remote backup restore (checksummed immutable
  manifest, tenant-scoped objects, new directory only, overlap checks) and DAV write guards reviewed.
- 2026-09-17 · pass 16 (d) · No new confirmed bug: download destinations come from base names/stems
  (no traversal), URL downloads reject slashes and `..`, all behind the model-loader token.
- 2026-09-17 · pass 17 (e) · No new confirmed bug: in-memory caches (vision descriptions ≤64, Nextcloud
  flows ≤100, approvals time out) are bounded; research stores are per workspace.
- 2026-09-17 · pass 18 (f) · No new confirmed bug: keyboard focus rings visible on the first 30 tab
  stops (375/1440, light/dark); no animation runs under `prefers-reduced-motion: reduce` in chat,
  settings, projects and Diary. The earlier Settings "double highlight" was the test pointer hovering.
- 2026-09-17 · pass 19 (a, chat lists) · Free-chat and project-chat lists were saved by replacing the
  whole list with the browser's copy, so a second tab/device — or the same tab sending in a new chat
  before the previous save refreshed its state — silently removed chats from the sidebar (their
  transcripts stayed on disk, unreachable) · server merges by id, deletions only via DELETE with
  tombstones so stale lists cannot resurrect them, list cap 200 → 1000 ·
  `server/chat-lists-routes.test.cjs`, `server/chat-lists.cjs`.
- 2026-09-17 · pass 20 (b) · No new confirmed bug: sessions, internal MCP token replay, DAV
  re-authorization after body reads, and new admin routes (features, backups, research) reviewed.
- 2026-09-17 · pass 21 (c) · No new confirmed bug: sidecar tenant state creation is serialized under
  `_tenant_lock` (one write lock per corpus).
- 2026-09-17 · pass 22 (d) · No new confirmed bug: calibration start takes the exclusive maintenance
  gate before any preset change.
- 2026-09-17 · pass 23 (e) · No new confirmed bug: research start and off-site backup runs check and
  claim within one event-loop turn; the D8 sweep cannot remove a folder a new project allocated.
- 2026-09-17 · pass 24 (f) · No new functional bug: Diary reading at 375/1440. Cosmetic: the Diary
  breadcrumb separators sit off-baseline at 375 px — folded into UI polish (A8).
- 2026-09-17 · pass 25 (a, privacy) · Deleting a chat while its reply was still streaming removed the
  transcript, then the reply's final save wrote it back to disk — a deleted conversation persisted
  (hidden from the sidebar) · history saves for tombstoned chats answer 410 ·
  `chat-lists-routes.test.cjs`.
- 2026-09-17 · pass 25 (a, privacy) · Same race for context state: a reply finishing after its chat was
  deleted re-saved the chat's context file (which can hold a conversation summary) · removed at the end
  of the request when the chat is tombstoned · `qa/chat-context.cjs`.
- 2026-09-17 · passes 26–30 (b–f) · No new confirmed bugs. Checked: per-user tombstones and context
  routes stay in the tenant's workspace (b); queued append retries dedupe by marker (c); evidence
  appends are whole-line (d); sidecar ZIP imports land only in `Imports/<new name>` with conflict
  checks (e); full suite re-run after rotation 5 — every `qa/*.cjs`, pytest diary/model-manager,
  deploy and experiments green (f and all).
- 2026-09-17 · pass 31 (a) · No new confirmed bug (reload mid-stream aborts server-side as designed).
- 2026-09-17 · pass 32–34 (b–d) · No new confirmed bugs (re-checked the pass-19/25 tombstone paths for
  cross-tenant access, queued append retries, evidence line atomicity).
- 2026-09-17 · pass 35 (e, research) · Running the same research question twice on one day overwrote
  the first report and its sources file · numbered names when either file exists ·
  `research-service.test.cjs`.
- 2026-09-17 · pass 36 (f) · No new confirmed bug.
- 2026-09-17 · rotation 7 (passes 37–42) · **No new confirmed bug in any area** — stop condition met.
  Checked with a different technique: randomized fuzzing of `dav-ops` destination/If parsing,
  chat-list merge, plan sanitizing, search-result parsing, report names and backup retention (20k +
  5k cases, no crash or invariant break); a property fuzz of sidecar `workspace_ops` (300 corpora ×
  25 random delete/move/copy steps, 1,634 successful operations) found no protected-file change, no
  mutation by a refused operation and no content lost outside Trash; CSRF ordering of the new admin
  routes; full-suite re-run green.

**Bug hunt summary (2026-09-17, 7 rotations, 42 passes).** Fixed per area — a (chat/approvals/history):
6 (stale approval cards after Stop, history truncated to 40 messages, >1 MB histories refused,
context dropped past 40 messages, stale chat lists erasing chats, deleted chats resurrected by late
saves ×2) plus one hardening (same-tick double send); b (auth/admin): 3 (sign-in username timing +
password spraying, one-time secrets reusable under races, restart-wired feature toggles pretending to
be live); c (Diary): 1 (append claimed success while only queued); d (calibration): 1 (unrestored
profile not reported); e (research/projects): 2 (budget-skipped questions reported as "no relevant
source", same-day reports overwritten); f (UI): 2 (short-phone composer hidden, sub-44 px touch
targets); plus `jobs.recover()` ignoring store kinds and the skewed close icon found during the
build. **Suspected, then fixed after the hunt:** passkey options revealed whether a username exists (now padded with stable decoy ids, `auth-enumeration.test.cjs`); two devices saving the same chat transcript were last-writer-wins (now revisioned saves with 409 + client merge, `chat-history-routes.test.cjs`, `tests/transcript-merge.test.cjs`, `qa/two-device-history.cjs`). The MTP evidence log growth is bounded too (compaction keeps the newest 50 records per model/category/identity past 1 MB, `evidence.test.cjs`). Nothing remains suspected. **Needs the user:** applying D1's operator steps before the next deploy
(the new preflight blocks the live config until then); D3 preset diff and `--models-max 2`; SMB pilot
and cutover; an off-site provider and budget; a live-credit research measurement.
- 2026-09-17 · follow-up to pass 2 (b) · Found while preparing the deploy: the per-address limit
  counted every sign-in, and behind the Cloudflare tunnel (TRUST_PROXY off) the whole household
  shares one socket address, so 30 ordinary sign-ins in 15 minutes would have locked everyone out ·
  only attempts on non-existent usernames count toward the address block; once blocked, all attempts
  from it get the same 429 (no enumeration signal) · `auth-enumeration.test.cjs` (8 members × 4
  sign-ins from one address).

- 2026-09-17 · after the hunt · Auto roles named two models no longer served, so every Auto
  message failed upstream · 409 naming the role before any engine call, settings alert · `auto-roles-check.test.cjs`, `qa/llamacpp-http.cjs` · 8e4dcd0
- 2026-09-17 · release tooling · a failed local build shipped an empty `dist/` into the image build
  (stopped before switching) · overlay script refuses a tarball without a built bundle · c14df66
- 2026-09-17 · f · message edit box used `--surface/--line/--muted-ink`, defined nowhere, so dark
  mode got light fallbacks · real tokens + `undefined-token` design-lint rule · 7248c4a
- 2026-09-17 · f · accepted glass study's pointer glint never ported (CSS read `--glass-x` nothing
  set) · `public/glass-highlight.js` · 7248c4a; a queued frame re-lit a control after the pointer
  left · `glass-highlight.test.cjs` · 52f982e
- 2026-09-17 · f · archiving a chat hid it everywhere with no way back · Data → Archived chats · 52f982e
- 2026-09-17 · e · data export would have included the internal Diary attachments project · filtered
  like `/api/workspace` · 0d269fa
- 2026-09-17 · e · delete-old-chats used a preview loaded before old chats arrived and deleted one
  without confirmation (caught by QA) · fresh count on choose, server refuses unconfirmed deletes
  (409) · `routes/account.test.cjs` · 25325ac
- 2026-09-17 · f · `qa/mtp.cjs` broke when stats became a collapsed pill · opens the pill first · d2adc66
- 2026-09-17 · f · phone Settings showed an empty bar holding a second close button under "Back to
  app"; Projects empty state had two identical primary buttons; "1 workspace" on the Projects page ·
  fixed with QA · 4aea5d3, 0d269fa
- 2026-09-17 · a · test sandbox for `handleChat` lacked new globals and hung the whole suite ·
  stubs added · 0e5ed34

## Testing rules

- Diary work uses a per-run **copy** of `AI frontend thing/diary-test/`. Never the folder
  itself, never the real Diary, never production.
- Every UI change is checked visually on a local spin-up, repeatedly: 375/768/1440, light
  and dark. Suites complement looking; they don't replace it.
- Every commit: `npm test`, `npm run typecheck`, `npm run build` in `apps/web`, plus the
  affected `qa/*.cjs` suites.

## Explicitly not doing

- Renaming `cowork` identifiers.
- A global "never ask" for write tools.
- Vendoring an agent framework, or adopting an external harness/browser framework as noevia's
  API; external projects are references and adapters, not the architecture.
- Resurrecting Diary insights.
- Exposing admin-only external-source mounts to members before tenant ownership exists.
