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

- Live release **`a48a8c4`** on DaServer (`https://cowork.daserver.work`), five containers
  healthy, native llama.cpp (`cowork-llama-1`) as the only inference backend.
- **No models are served.** `models.ini` was emptied and the GGUF weights removed from
  `/mnt/user/ai-models`; only `Ornith-1.5-9B-Q5_K_M` remains, without an entry. Earlier
  notes record the entry deletion as the user's choice. Re-downloading is the user's call;
  `nomic-embed-text-v1` is what project retrieval needs.
- The live Compose Manager file lacks the six MCP keys, so startup logs `mcp: disabled`.
  The user edits that file; the preflight drift check names the missing keys.
- `a48a8c4` was deployed without the pre-deploy appdata backup the runbook calls for and
  is not yet recorded in `deployment.md` or the DaServer changelog. Do both next deploy.
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
- **Open** — The settings ✕ differs from every other close control; use one component.
- **Open** — Short-height populated sidebar reachability (carried from the backlog).
- **Open** — Mobile checks for Settings, Projects, Code and the setup wizard, and software
  keyboard behaviour (Freebuff covered Chat and Diary only).
- **Decision** — Scheduled, Plugins, Explore and Coding are preview surfaces: keep them as
  labelled previews, or hide them until built.

### B. Settings structure
- **Open** — More side-panel sub-pages (Profile, Personalization, Appearance, Data…), one
  concern per page, ChatGPT-level depth with Claude-level polish. References:
  `ui mockups/inspiration/`, [spec-ui-direction.md](spec-ui-direction.md),
  [ui-reference-review.md](ui-reference-review.md).
- **Open** — The model manager opens as its own full page with a back button; the settings
  dialog keeps a simple summary.

### C. Model management
- **Open** — Easy mode by default (auto-tune context against real VRAM, MTP type, KV-cache
  quant) with an Advanced toggle for every `models.ini` field.
- **Open** — Parity audit against Model Loader, run with its own UI still up; port gaps.
- **Open** — After a download, write safe defaults automatically: 8k context, MTP when the
  model ships a draft head, the model's own template and sampling defaults.
- **Open** — A deleted model leaves projects and chats pointing at it; show "No model
  selected".
- **Open** — Choose where downloads go (Unraid shares such as `ai-models`).
- **Open** — Routing clarity: plain labels, what Auto does, per-project view.
- **Open** — Hugging Face cache files can surface as hex identifiers; unconfirmed (the scanner
  already skips `blobs/`), needs a real HF-cache fixture.
- **Research** — Known-good settings per model and hardware.
- **Research** — Wider model evidence: accuracy, reasoning budgets, MTP, multi-GPU; and
  applying the qualified Gemma 131k / Qwen 262k profiles beyond their exact configuration.
- **Research** — Backend portability (llama.cpp vs vLLM), measured, no silent migration
  ([spec](spec-backend-portability.md)).

### D. Modes, projects and harnesses
- **Open** — Chat, Cowork and Code modes; projects enabled per mode (C++ → Code, Random
  questions → Chat, HomeLab → all).
- **Open** — Optional shared context layer across the modes a project is enabled in.
- **Research** — Code-mode harness switcher (Hermes, opencode, DeepSeek…).

### E. Tools
- **Open** — Tool-call menu under the thinking box in every mode, including Diary.
- **Open, measure first** — Task-conditional tool loading: a pre-turn embedding router picks
  toolboxes for the task from the manifest, loads them for the session, and adds no
  discovery round. A tool-search/unlock variant was already measured slower on these
  models (12.91 s vs 8.64 s median). Adopt only if the `experiments/tool-routing` runner
  shows equal-or-better completion without higher latency.
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
- **Open** — Tokens/s and stats in the footer don't update live during generation.
- **Open** — Admin-only tab streaming the llama.cpp log live.

### I. Deep research mode
- **Research, then build** — Gemini Deep Research / NotebookLM-style cited reports as a
  background job, grounded in selected sources.

### H. Platform
- **Research** — Headscale vs NetBird to replace a slow Tailscale.
- **Research** — AIO-style master container managing the stack.
- **Later** — Mac-native app.

## Research priorities

Ranked. Each ends in a written recommendation in `docs/`, with measurements from this
deployment's models.

1. **Context efficiency: scripts before tokens.** Cut how much context tool calls use by
   moving mechanical work into code. Measure first: log tokens per tool call and per tool
   result over real use, then (a) trim results in code before the model sees them,
   (b) replace repeated multi-step tool sequences with one task-shaped scripted tool,
   (c) answer purely mechanical requests without the model, and (d) summarise old tool
   results instead of carrying them forward. Script only sequences the logs show repeating.
2. Known-good settings per model and hardware.
3. Wider model evidence: accuracy, reasoning budgets, MTP, multi-GPU.
4. Backend portability (llama.cpp vs vLLM).
5. Code-mode harness switcher (Hermes, opencode, DeepSeek…).
6. Headscale vs NetBird to replace a slow Tailscale.
7. AIO-style master container managing the stack.

Research tied to a build item stays with it: task-conditional tool loading (E) and deep
research mode (I) are both measure-first, then build.

## Order

1. Live stats, settings ✕.
2. Deleted model state, safe defaults after download.
3. Full-page model manager with Easy/Advanced and the parity audit.
4. Mobile drawer, search button, brightness and banding.
5. Live log tab, tool-call menu, settings sub-pages.
6. Modes and projects.
7. Diary latency, inheritance and WebDAV plugin; SMB cutover when the user is ready.
8. Task-conditional tool loading (measured) and the deep research spec.
9. Research priorities, starting with context efficiency. It can run alongside
   the build items above, since it begins with logging.

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
- Vendoring an agent framework.
- Resurrecting Diary insights.
- Exposing admin-only external-source mounts to members before tenant ownership exists.
