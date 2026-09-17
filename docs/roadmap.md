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
- **Open** — Sidebar collapses completely into a full-screen slide-out drawer the moment
  the viewport shrinks; one toggle; bigger targets; optimise for vertical space.
- **Open** — Search button is hidden under the top bar at small widths.
- **Open** — iPhone renders much brighter than Chrome on macOS; macOS shows banding.
- **Shipped** — One shared `CloseButton` for every dialog/popup close control (settings ✕ no longer differs).
- **Open** — Short-height populated sidebar reachability (carried from the backlog).
- **Open** — Mobile checks for Settings, Projects, Code and the setup wizard, and software
  keyboard behaviour (Freebuff covered Chat and Diary only).
- **Research** — Deterministic design-rule check: run Impeccable (`detect --json`, plain CSS
  supported) once against `apps/web/src`, triage findings against existing tests, mobile QA
  and screenshots, then adopt as a dev-only check, borrow selected rules, or reject. Also
  assess a lightweight post-edit scan for agent-driven UI work. Complements screenshot
  review; never replaces it. No app dependency.
- **Decision** — Scheduled, Plugins, Explore and Coding are preview surfaces: keep them as
  labelled previews, or hide them until built.

### B. Settings structure
- **Open** — More side-panel sub-pages (Profile, Personalization, Appearance, Data…), one
  concern per page, ChatGPT-level depth with Claude-level polish. References:
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
- **Open** — Parity audit against Model Loader, run with its own UI still up; port gaps.
- **Shipped** — A finished download registers itself once via model-manager
  `POST /sections/{name}/safe-defaults`: context capped at 8k, `draft-mtp` only with a draft
  head beside the file, `jinja` for the GGUF template, no sampler keys. Never overwrites an
  existing section; the preset reload never unloads, and a loaded model deferring it is shown.
- **Shipped** — A project or chat whose model is no longer installed shows "No model
  selected" (only when the local catalogue was read successfully; other providers exempt).
- **Open** — Choose where downloads go (Unraid shares such as `ai-models`).
- **Open** — Routing clarity: plain labels, what Auto does, per-project view.
- **Open** — Hugging Face cache files can surface as hex identifiers; unconfirmed (the scanner
  already skips `blobs/`), needs a real HF-cache fixture.
- **Open, design first** — Configuration-scoped qualification evidence: states (reported,
  unverified, verified for this configuration, failed, stale, unavailable) tied to an identity
  tuple (backend, model, artifact, projector, runtime, context, MTP profile, harness, prompt
  preparation, suite, date); changes mark evidence stale. No universal score. Today calibration
  history lacks artifact/preset identity and invalidation.
  ([spec §1](spec-agent-execution.md))
- **Research** — Known-good settings per model and hardware.
- **Research** — Wider model evidence: accuracy, reasoning budgets, MTP, multi-GPU; and
  applying the qualified Gemma 131k / Qwen 262k profiles beyond their exact configuration.
- **Research** — Backend portability (llama.cpp vs vLLM), measured, no silent migration
  ([spec](spec-backend-portability.md)).

### D. Modes, projects and harnesses
- **Open** — Chat, Cowork and Code modes; projects enabled per mode (C++ → Code, Random
  questions → Chat, HomeLab → all).
- **Open** — Optional shared context layer across the modes a project is enabled in.
- **Design before Code build** — `CodeHarness`: noevia-owned contract that external harnesses
  (Codex, Claude Code, DeepSeek Harness, OpenCode, Hermes) adapt to; Harness and Prompt
  preparation dropdowns beside Model; coding evidence scoped to model × harness × architect;
  every harness action classified through noevia's approval gate; one writer per workspace
  first. Evaluate ACP as the adapter protocol. ([spec §3](spec-agent-execution.md))
- **Research, benchmark first** — `PromptArchitect`: optional stronger model (local or cloud,
  provider-neutral, official auth only) writes a structured execution prompt for the local
  model. Modes Direct (default) / Local / Frontier; Auto only after paired fixtures prove a
  benefit. Outbound context allowlist enforced in code, disclosure shown, original request
  stays authoritative, no hidden reasoning stored. ([spec §2](spec-agent-execution.md))
- **Later** — Cowork browser capability through a noevia-owned `BrowserExecutor` on an
  execution node: isolated profiles, domain allowlists, secrets substituted outside model
  context, consequential actions through approvals, run as durable jobs. Browser Use is one
  candidate implementation. ([spec §6](spec-agent-execution.md))

### E. Tools
- **Open** — Tool-call menu under the thinking box in every mode, including Diary.
- **Open, measure first** — Task-conditional tool loading: a pre-turn embedding router picks
  toolboxes for the task from the manifest, loads them for the session, and adds no
  discovery round. A tool-search/unlock variant was already measured slower on these
  models (12.91 s vs 8.64 s median). Adopt only if the `experiments/tool-routing` runner
  shows equal-or-better completion without higher latency. Model-driven tool search (as in
  Row-Bot) stays rejected on that evidence. Add manifest fields only as this work needs them
  (example tasks, `autoLoad`, `requires`, `resultReducer`); one registry, policy never in the
  prompt, auto-loading never pre-approves a write.
- **Open** — Write access to the Diary from the in-app MCP server needs a sidecar append
  endpoint; the box is read-only by design until the user decides.
- **Decision** — Optional offline Wikipedia needs a chosen service.

### F. Diary and storage
- **Open** — Diary views inherit every main-interface change (shared components).
- **Open** — Entry load latency: serve the app-hosted copy first, then push to WebDAV.
- **Open** — WebDAV as a storage plugin, not Nextcloud-only.
- **Open** — Mac SMB authenticated pilot, then the real Diary cutover
  ([spec](spec-diary-smb.md)).
- **Open** — DAV rename/delete/locking and client interoperability need a storage contract
  first ([dav.md](dav.md), [spec-storage-appliance.md](spec-storage-appliance.md)).
- **Open** — Managed volume default for fresh installs and a resolved `/boot` path guard,
  without moving existing bindings.
- **Open** — Verify the scoped Claude Diary bridge with synthetic data; compare Diary
  logging behaviour with the Claude Cowork reference.
- **Open** — Include the Diary corpus in backups after migration.
- **Decision** — Off-site backup destination and budget.
- **Decision** — Empty-folder cleanup after project deletion (kept today to avoid racing
  uploads).

### G. Telemetry and logs
- **Shipped** — Footer tokens/s updates the moment each round's SSE `usage` event arrives instead of waiting on the 2.5s poll. A single long round still can't tick mid-generation: llama.cpp reports the rate only when a request finishes.
- **Open** — Admin-only tab streaming the llama.cpp log live.

### I. Deep research mode
- **Research, then build** — Gemini Deep Research / NotebookLM-style cited reports as a
  background job, grounded in selected sources.

### H. Platform
- **Research** — Headscale vs NetBird to replace a slow Tailscale.
- **Research** — AIO-style master container managing the stack.
- **Later** — Mac-native app as both client and optional trusted **execution node** (local
  files, terminal, repositories, browser, notifications): server orchestrates, node executes
  advertised capabilities after explicit pairing; never blanket control of the Mac. Idea: Swiftlet
  as an optional local runtime for that node.
  ([spec §5](spec-agent-execution.md))

## Research priorities

Ranked. Each ends in a written recommendation in `docs/` with measurements from this
deployment's models. Can run alongside the build order.

**Near-term**
1. **Context efficiency: scripts before tokens** ([spec](spec-context-projection.md)).
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
6. Shared durable-work primitive: append-only events, derived state, restart recovery,
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
3. Full-page model manager with Easy/Advanced and the parity audit.
4. Mobile drawer, search button, brightness and banding.
5. Live log tab, tool-call menu, settings sub-pages.
6. Modes and projects.
7. Diary latency, inheritance and WebDAV plugin; SMB cutover when the user is ready.
8. Task-conditional tool loading (measured) and the deep research spec.
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
