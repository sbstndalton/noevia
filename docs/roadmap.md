# noevia roadmap

The one planning document. Consolidated 2026-09-16 from the previous roadmap, the
roadmap audit, the backlog, the continuation checkpoint, both Codex handoffs, the live
and settings audits, the UI-overhaul plan, the Freebuff report and every master prompt.
Their dated evidence is in git history and [changelog.md](changelog.md); design detail
stays in the `spec-*.md` files linked below. The executable brief is
[master-prompt.md](master-prompt.md).

Status words: **Shipped** = deployed and verified · **Open** = to build ·
**Research** = ends in a written recommendation · **Decision** = waiting on the user.

## Where things stand — 2026-09-16

- Last recorded live release **`503b1c5`** on DaServer (`https://cowork.daserver.work`; see
  `deployment.md`, not re-verified since), five containers healthy, native llama.cpp
  (`cowork-llama-1`) as the only inference backend.
- **No models are served.** `models.ini` was emptied and the GGUF weights removed from
  `/mnt/user/ai-models`; only `Ornith-1.5-9B-Q5_K_M` remains, without an entry. Earlier
  notes record the entry deletion as the user's choice. Re-downloading is the user's call;
  `nomic-embed-text-v1` is what project retrieval needs.
- The live Compose Manager file lacks the six MCP keys, so startup logs `mcp: disabled`.
  The user edits that file; the preflight drift check names the missing keys.
- `a48a8c4` shipped without the pre-deploy backup; both it and `503b1c5` are recorded in
  `deployment.md`. The DaServer changelog in Nextcloud was not found locally.
- Empty the local build directory before building a release (a stale bundle shipped).

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
- **Research** — Deterministic design-rule check: run Impeccable (`detect --json`, plain CSS
  supported) once against `apps/web/src`, triage findings against existing tests, mobile QA
  and screenshots, then adopt as a dev-only check, borrow selected rules, or reject. Also
  assess a lightweight post-edit scan for agent-driven UI work. Complements screenshot
  review; never replaces it. No app dependency.
- **Decision** — Scheduled, Plugins, Explore and Coding are preview surfaces: keep them as
  labelled previews, or hide them until built.

### B. Settings structure
- **Shipped (first split)** — General held profile, preferences and capabilities, and profile
  identity was duplicated under "Profile & security". Personal settings are now Profile
  (identity), Security (passkeys, sessions, sign-out, app passwords), Appearance, Capabilities,
  Diary & storage, Your connections, Usage & activity, Planned features. Personalization,
  Notifications and Data stay under Planned until built. Still open: deeper pages at
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
- **First wave shipped 2026-09-17** — Configuration-scoped qualification evidence (design in [spec §1](spec-agent-execution.md)): `server/evidence.cjs` (identity hash, cheap artifact fingerprints, append-only store, derived states); the native manager computes live identity (build, endpoint hash, preset hash, model/projector/draft fingerprints, context, MTP); native calibration and the vision probe record evidence; `GET /api/models/evidence`; model details show verified/failed/stale/unverified/unavailable rows. MTP acceptance (from chat replies) and throughput (median of warm requests from a benchmark run of the saved preset, recorded when a run finished within 30 min is viewed) producers shipped 2026-09-17. Still to add: admin recheck endpoint: states (reported,
  unverified, verified for this configuration, failed, stale, unavailable) tied to an identity
  tuple (backend, model, artifact, projector, runtime, context, MTP profile, harness, prompt
  preparation, suite, date); changes mark evidence stale. No universal score. Today calibration
  history lacks artifact/preset identity and invalidation.
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
- **Prepared, not measured** — Task-conditional tool loading: a pre-turn embedding router picks
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
- **Open** — Write access to the Diary from the in-app MCP server needs a sidecar append
  endpoint; the box is read-only by design until the user decides.
- **Decision** — Optional offline Wikipedia needs a chosen service.

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
- **Contract written, build waits on a decision** — DAV rename/delete/copy/locks:
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
- **Decision** — Off-site backup destination and budget.
- **Decision** — Empty-folder cleanup after project deletion (kept today to avoid racing
  uploads).

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
- **Researched 2026-09-17** — AIO-style master container ([research-master-container.md](research-master-container.md)): don't build; keep Compose Manager. Found model-loader's socket-backed API reachable unauthenticated from the Diary container; repository fix adds `MODEL_LOADER_TOKEN` and a `models` network. **Operator action:** apply token and network changes to the live Compose Manager file.
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

**References to evaluate (added 2026-09-17, not yet reviewed)**

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
