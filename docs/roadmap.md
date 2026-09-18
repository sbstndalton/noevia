# noevia roadmap

The one planning document. Consolidated 2026-09-16 from the previous roadmap, the
roadmap audit, the backlog, the continuation checkpoint, both Codex handoffs, the live
and settings audits, the UI-overhaul plan, the Freebuff report and every master prompt.
Their dated evidence is in git history and [changelog.md](changelog.md); design detail
stays in the `spec-*.md` files linked below. The executable brief is
[master-prompt.md](master-prompt.md).

Status words: **Shipped** = deployed and verified · **Open** = to build ·
**Research** = ends in a written recommendation · **Decision** = waiting on the user · **Decided** = settled 2026-09-17 by delegation (table in master-prompt.md § Decisions).

## Where things stand — 2026-09-18, morning

`main` (GitHub `sbstndalton/noevia`), release **`f0ea80b`** live on DaServer at
**`https://noevia.daserver.work`** (cowork.daserver.work stays routed: it serves
`/.well-known/webauthn` so passkeys made under that name keep working). See `deployment.md`.

**New on 2026-09-18 (all live in `f0ea80b`):** Settings regrouped (Account, Preferences,
Connections, Server, Coming later); Settings → Web address (rename with a reachability check,
earlier addresses stay valid for sign-in, passkeys via WebAuthn related origins); Google Drive
backups done by noevia's backend (device sign-in, one button in the wizard and Settings →
Backups, auto-opened Google tab, recovery-key download); public `/about` and `/privacy`; Google
Cloud app `noevia` **in production** (drive.file, non-sensitive); wizard palette sits with
light/dark and no longer flips light to dark. **Pending:** the admin's first Connect on the live
site, then retire the host rclone cron (`/boot/config/plugins/dynamix/noevia-offsite.cron`).

### Live and verified in production
- Services: web, Diary, OCR, model-loader (D1), native llama.cpp (`--models-max 1`), the CPU
  embedding server `cowork-embed-1`, Kiwix. KoboldCpp was tested and removed (slower generation on
  every model, no router; findings §12).
- Tool routing is on and backed by `cowork-embed-1`; auto-tune, model folder sync and the
  server-judged Discover panel are live (release `ca5d2f6`).
- Models change over time at the user's discretion; don't treat a new or missing preset as a finding.
- MCP: Nextcloud (160 tools), Tavily, in-app server (10 tools).
- Features on through env: previews, Diary append tool, offline Wikipedia. **Deep research is off**
  (gate failed, parked until the user returns to it).
- **Nextcloud AIO repaired** (apache/talk crash-loop after the nightly update; this broke Diary
  storage with a 502) and **Nextcloud Assistant runs on the native engine** (`integration_openai` →
  `http://noevia-llama:8080/v1`, verified with a text task).

### Measured, and now deployed
Everything below was measured on the branch during 2026-09-17 and went live with `ca5d2f6`.

- **APU memory (step 1):** GTT is kernel-capped at 14.85 GiB (half of RAM) plus 2 GiB VRAM. 4B = 3.1
  GiB GTT + 1.9 GiB VRAM; embedding 0.3 GiB. Proposal: keep the cap, add `--fit on --fit-target 1024`
  after the syslog mirror. [research-known-good-settings.md](research-known-good-settings.md)
- **Retrieval swap (step 2):** a RAG turn under `--models-max 1` cost ~4.6 s of swapping and dropped
  the prompt cache; a CPU nomic answers in ~30 ms. `cowork-embed-1` now serves embeddings and web
  points at it through `EMBEDDING_BASE_URL`.
- **Tool router (step 4):** best-first ordering reaches the needed box 26/26 (was 8/26), right first
  call 21/26, 10.8 s vs 14.3 s median, on the real Nextcloud boxes. Live.
  [experiments/tool-routing/README.md](../experiments/tool-routing/README.md)
- **Auto-tune:** MTP gave +66 % on the 4B and +82 % on the 9B; micro-batch 512 beat 1024 and 2048.
  Contexts are now verified by calibration (49 152 / 32 768 / 49 152 / 49 152) instead of the
  unverified 131K–262K the old Easy mode saved.
- **Discover:** results are judged against this machine — real file sizes and quants from the repo
  tree, shards folded, companions excluded, publisher trust, fit against the 12.5 GB budget, ranked
  fit → trust → popularity with a 90-day half-life. Verified live after deploy (`gpt-oss` 6 shown of
  30; `gemma` 7 of 30).
- **Deep research gate (step 3):** failed on the 9B (citation validity 0.65–0.68 vs ≥ 0.95). Feature
  off, parked. [spec-deep-research.md §8](spec-deep-research.md)
- **KoboldCpp vs llama.cpp:** feature parity, but 8–53 % slower at generation on every model tested.
  Rejected and removed with its downloads. vLLM stays a possible future test under the §8 gates.
- **Prompt preparation (step 6, 4B run 2):** P0 raw 16/18, P1 template 15/18, P2 4B-as-architect 0/18
  (list fields returned as strings). Direct stays default; next 3 repeats and a 9B architect.
- **CodeHarness spike (step 9, D14):** OpenCode over ACP solved a synthetic bug on the 4B (165 s) and
  9B (265 s) in a read-only, capability-less container with only the engine reachable; escape probes
  all blocked. `experiments/acp-spike`.
- **Context logging (step 5):** `CONTEXT_LOG=1` on in production since 11:20, counts only. Read
  `context-log.cjs report()` from about 2026-09-24 and write reducers for what repeats.

### Broken or risky right now
- **Outage cause unknown** (2026-09-17, 04:15–08:24). Mover 03:40 and the appdata backup 04:10
  precede it. **The syslog mirror is now on** (2026-09-17 night): the box's own syslog is written
  to `/boot/logs/syslog`, bounded at 10 MB × 4, so a repeat leaves evidence. Note that "Local
  syslog server: Enabled" did *not* do this — that only receives syslog from other devices. The
  original outage's log is still gone; `/var/log/syslog` starts at the reboot that ended it. Leading guess moved from
  engine GTT to RAM-backed paths during the ZIM download or backup staging (the engine alone cannot
  exceed ~16.9 GiB). Unproven — keep `--models-max 1`.
- **FIXED 2026-09-17 night — Auto routing was pointing at models the engine does not serve.**
  Live `auto-roles.json` named `gemma-4-E2B-it-GGUF-UD-Q4_K_XL` / `Gemma-4-E4B-it-GGUF`; the engine
  serves `gemma-4-E2B_q4_0-it` / `gemma-4-E4B-it-qat-UD-Q4_K_XL` and four others. **Every
  Auto-routed message would have failed.** It showed no errors only because nobody had chatted
  that day. Cause: the D3 session edited `/mnt/docker/appdata/cowork/ui-data/auto-roles.json`,
  which **is mounted into nothing** — the live path is
  `/mnt/docker/appdata/cowork/state/web/auto-roles.json`. That dead directory's
  `.bak.before-d3` still holds the stale values, which is how it was traced. Repaired to
  Qwen3.5-4B (fast, vision) and Ornith-1.5-9B (smart), both confirmed served, web restarted
  because roles are cached at workspace load, and a real completion verified.
  **Lesson for the next session: `state/web/` is live; `ui-data/` is abandoned.** Check the mount
  before believing an edit landed.
- **The Nextcloud Assistant shares the single llama.cpp slot** with noevia chats and can evict the
  loaded model mid-conversation. Its thinking is disabled (2.9 s answers). **Much reduced
  2026-09-17 night:** the Assistant asks for `Qwen3.5-4B-Q5_K_M`, and noevia's fast and vision
  roles are now that same model, so the common path no longer evicts anything. Only a `smart`
  (9B) message still swaps. The engine has no API key on the `nextcloud-aio` network.
- **Deployed but only exercised by me — all three now addressed in code, none yet confirmed live.**
  The 4B not calling the Tasks box: every tool in it is named `nc_calendar_*` and described in
  calendar words, so `tool-hints.cjs` adds a plain-language sentence per tool and the box leads with
  "Tasks, to-dos, reminders" (`a9a3ff4`) — a hypothesis with a mechanism; confirming it needs a
  model run in a D2 window. Discover showing nothing for a one-word query: the empty state now
  offers "Show all publishers (N)" instead of only explaining itself (`03658d3`). Auto-tune's
  resumable state: an expired partial silently restarted from scratch; the job reports `resumed`
  and expired partials are deleted (`241af38`).
- Previously: **release `877947c`** (2026-09-18 night): off-site backups to an encrypted local
  store, restore-tested with the Diary included, mirrored by host rclone (D23, being retired).
- **Shipped (2026-09-18, D24 replaces D23)** — Google Drive backups run entirely in noevia's
  backend: one **Connect Google Drive** button (setup wizard and Settings → Backups) starts
  Google's device sign-in, the backend polls for approval and uploads the encrypted store to a
  `noevia-offsite` folder itself (`server/gdrive.cjs`), with the rclone script's safety rules
  (refuse a wiped store, upload then prune, 500-delete cap, size mismatch = corruption). Refresh
  token sealed with a key derived from the backup key; never reaches the browser; Disconnect
  revokes. Recovery key downloads from the page. Uses `GOOGLE_OAUTH_CLIENT_ID/SECRET` (a
  "TVs and Limited Input devices" OAuth client in Google Cloud project `noevia`, scope
  `drive.file`, published). Host rclone + cron retire once the new path has copied live.
  Settings regrouped: Account, Preferences, Connections, Server, Coming later. QA:
  `qa/google-drive.cjs`, `qa/wizard-backup.cjs`, `server/gdrive.test.cjs` (fake Google).
- **Next (user, 2026-09-18) — UI overhaul.** Brief: [ui-overhaul-master-prompt.md](ui-overhaul-master-prompt.md)
  (the user's prompt, plus one added line: *the current noevia visual design is not a
  reference; preserve functionality, data flows and tests, replace the visual language
  entirely*). Architecture from `ui mockups/inspiration/` (merged descriptions + screenshots);
  look from Apple HIG, Material 3 roles with Ramps Studio character, Aero/UniFi structural panes,
  selective Liquid Glass, Impeccable as skill and final critique. **Release 1 deployed 2026-09-18 as `35ed364`** (Soft default, four materials in Settings → Appearance, `SegmentedControl`): palette generator `apps/web/scripts/palette.cjs`, M3 role tokens, `materials.css`, `public/lens.js` (replaces `glass.js`), palette picker removed, Impeccable installed at `.claude/skills/impeccable` with `PRODUCT.md`; samples in `docs/ui-samples/`. Release 2 deployed as `ab2720a`. Planned releases,
  each deployed and click-tested:
  1. **Foundation** — one noevia palette (light/dark) on M3 roles, spacing/radius/type/motion/
     elevation/surface tokens; `public/glass.js` replaced; the whole app switches at once. Two or
     three sample screens (settings, a project, connectors) shown to the user before rollout.
  2. **Shell + Primitives + Connectors** (merged at the user's request after testing release 1,
     2026-09-18; deployed 2026-09-18 as `ab2720a`) — the samples as the app: sidebar and workspace as framed
     panes; Settings slides in and replaces the workspace (phone: list → page, rising sheet);
     floating phone drawer; context panel as a surface; composer pane with glass send/model;
     one look for every button, field, select, switch and row (`styles/primitives.css`,
     `styles/shell-v2.css`). **Connectors** (Settings → Customize): Google Drive per account
     with seven chat tools (`gdrive-tools.cjs`, `gdrive-files.cjs`, `drive-accounts.cjs`) and
     per-tool Allow / Ask / Block (`tool-policy.cjs`, enforced in the chat gate; blocked tools are
     not offered; writes can never be Allow). The admin's backup connection doubles as their
     Drive, with an Offsite backups switch on the page. Nextcloud and custom MCP by URL are listed
     as coming later. QA: `qa/connectors.cjs`, `qa/drive-tools-live.cjs`.
  **Phase 2 (from 2026-09-18, brief: [ui-overhaul-phase2-prompt.md](ui-overhaul-phase2-prompt.md)):**
  **User review of `ab2720a` — folded in, not yet deployed.** Eleven items from a desktop and
  phone pass. Fields are 16px on touch devices so iOS stops zooming on focus (`styles/phone.css`);
  a reload returns to where you were, Settings page included (`src/last-view.ts`, per device,
  guarded by account id); the phone chat pins the composer to the bottom edge and greets you at
  the top instead of centring the column; the inference strip is one tappable line on a phone and
  one always-open horizontal row on a desktop (`StatsBar`); the sidebar is a fixed top group,
  three independently scrolling lists (Projects first, then Pinned, then Recent chats) and a fixed
  pane holding Diary — on a phone the whole rail scrolls with Diary and the account row stuck to
  the bottom edge; Customize and Explore left the sidebar (Customize is Settings → Customize),
  Plugins stayed; Settings goes single-pane below 820px rather than 700px, because Safari widens
  the layout viewport when anything overflows and their phone was sitting just above the old
  breakpoint; the five accent palettes are back (Iris, Warm, Cool, Neutral, Sage) generated from
  `scripts/palette.cjs`, applied before paint, with the contrast suite now measuring all five in
  both modes; and Auto routing gained an optional **Code** role that the classifier can choose
  (a fenced block or a diff skips straight to it), falling back to Smart when no code model is
  set. This reverses the earlier "one palette" decision at the user's request. Then:
  3. **Primitives beyond Settings** — menus, context menus, modals as aero overlays (phone:
     bottom sheets), confirm dialogs, cards, banners, empty states, chat bubbles and tool-call
     list (approval card restyled, never simplified). **Built, not yet deployed**:
     `styles/overlays.css` (loads after `primitives.css`, before `materials.css`) carries the
     whole release; components only gained classes (`overlay` on the context menu, account
     popover and composer panel; `aero dialog-sheet` on every `<dialog>` or its panel;
     `surface` on project, month and model cards). Phone dialogs are bottom sheets with a
     grabber that follow the *visible* viewport, so the software keyboard shortens them
     instead of hiding their lower half. Context menus gained a complete symbol column, and
     the sort menu's `✓ ` label prefix became a checked `menuitemradio`; the tool-call list's
     `✓`/`⃠` became drawn Lucide icons (`arrow-down` added to the vendored subset). The
     approval card is restyled on the warning role with 44px decisions on every device, its
     three actions and its full unclamped arguments unchanged.
  4. **Customize backends** — Nextcloud connector, custom MCP server by URL (per account, same
     Allow / Ask / Block page), then Skills, then the Plugins marketplace.
  5. **Projects and chats** — the sample's project screen: header, composer context chips,
     outputs, recent chats, context panel sections.
  6. **Activity/usage** — only from real usage data.
  7. **Impeccable critique pass and phone polish pass.**
  **Decided 2026-09-18** (recorded at the top of the brief): plugins are bundles of skills,
  connectors and commands; marketplace sources are Claude-compatible repos, any GitHub repo
  added by URL, own/imported skills, and a curated noevia list; desktop first with a phone
  polish pass after; skip Billing, Browser/Computer use, Desktop app/Extensions/Reveal in
  Finder; Voice shown as not yet available; one palette to start.
- Previously: **release `1fe3f1b`** (deployed 2026-09-17 night from `ca5d2f6`, web-only overlay,
  appdata backup `ab_20260917_192134` first). All five services healthy, engine untouched, public
  bundle byte-identical to the local build. Code mode ships **off** with no `CODE_*` environment
  set. D1 needed no operator steps — it was already applied in `657d21b`, and the preflight passes
  live; the earlier "blocked until the operator steps are applied" note was stale.
- Glass banding on real devices: the user's check (D13). `llama-vulkan-test` is stopped, kept.

### Needs the user
a maintenance window to confirm the Tasks-box hints and finish the Prompt Architect
repeats (the user will say when) · a real end-to-end CodeHarness run against OpenCode before
`features.codeHarness` goes on · `--fit on --fit-target 1024` after the syslog mirror · an engine
API key shared by noevia and the Nextcloud Assistant · the first live Connect Google Drive · the
Customize/UI overhaul brief · deep research when they return to it · Talk's `changed-users` waits on an upstream
AIO image · the glass banding check on real devices (D13).

Deploying, spending, model weights on DaServer and live Compose/preset edits stay the user's call.

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
- **Not applied live, contrary to the D3 note** — the box runs `--models-max 1` with the 4B at
  ctx 49152 and the 9B at 32768, not the planned 24576/16384. The roadmap's "Applied live
  2026-09-17 with `--models-max 2`, caps verified" is at best half true: `--models-max` went back
  to 1 in the outage response, and the preset caps are not what D3 proposed. Verify against the
  engine's own `/v1/models` args before acting on that entry.
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
- **Built 2026-09-17 (on `main`, not deployed; `features.codeHarness`, off)** — `CodeHarness`, nine
  modules, spec §3's "next" list complete **and its `_meta`/selector gaps closed**: `code-actions.cjs` (ACP tool call → noevia's action classes,
  fail-closed, compound commands take their worst part, refusals never downgrade to an allow),
  `code-workspace.cjs` (per-task git worktree, one writer per repository+branch, realpath
  containment including for files that do not exist yet), `code-egress.cjs` (D15: per-task domain
  allowlist at the proxy, check-then-connect to the same address, 80/443 only, credentials stripped),
  `code-harness.cjs` (the session: approvals, "allow for this task" scoped to one action class and
  never to a delete or push, containment re-checked at write time, job events), `code-acp.cjs`
  (hand-written JSON-RPC over stdio, no SDK, cancellation wired before the handshake, process-group
  kill), `code-service.cjs` + `routes/code.cjs` (admin-only, `CODE_REPOS` is the only way a
  repository becomes reachable, one task per project), and the Code tab UI
  (`src/components/code/`, `qa/code-mode.cjs`). Added the same day: `code-sandbox` — the harness
  runs in its own container reached over an internal socket, never as a child of the web process
  and never through the Docker socket (`services/code-sandbox/`,
  `deploy/examples/code-sandbox.override.yml`); `code-meta.cjs` — token usage, harness version,
  exit codes and the §1 identity tuple, read defensively and **naming what the harness did not
  report** rather than defaulting it; and the Harness / Prompt-preparation selectors, with no
  `Auto` (§2 permits one only after evidence) and the unavailable modes carrying their measured
  reason. **Staged on DaServer 2026-09-17 with the flag off** (`deploy/examples/code-mode-staging.md`,
  and a copy at `/mnt/docker/appdata/cowork/tools/CODE-MODE-READY.md`): sandbox image built and
  probed, `cowork_code-workspaces` volume with a deliberately buggy `scratch` fixture repo, the
  override staged but *not* wired into the Compose Manager project. Staging found three real gaps,
  now fixed — worktrees must sit on the shared volume at an identical path, a workspace must be
  handed to the harness uid, and a handed-over worktree **cannot commit**, so a separate harness
  user now gets `git clone --shared` with the branch fetched back on release. **Contract v1 complete, 2026-09-18: the whole loop works.** Ornith-1.5-9B fixed the fixture in
  46 s — two approvals, the edit through noevia's file API, only the intended file changed, and the
  repository's own test passing on the task branch. Getting there found that **noevia's approvals
  never reached the harness at all**: ACP nests the permission outcome and noevia sent it
  unwrapped, so OpenCode read every approval as "the user rejected permission". Fail-safe, and
  invisible because the fake agent shared the same wrong assumption. Three more: uncommitted work
  was deleted with the clone, `HOME` inside the workspace got the harness's cache and database
  committed onto the branch, and the shared state directory was created unenterable. All fixed and
  covered. Earlier note, kept for the record: **first pass against real OpenCode 1.18.31 on 2026-09-17** (spec §3 "Contract v1"): the
  mapping holds — classification, the approval card with a real diff, containment, `test.js`
  untouched — and four defects surfaced that only a real harness could show, the worst being that
  git's "dubious ownership" check made `release()` strand **every task's work** in its clone. All
  four fixed. Still to do: `Auto` harness once evidence exists, the adapter owning the harness
  config file, and runs against Claude Code and Codex. Original item: noevia-owned contract that external harnesses
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
- **Retired 2026-09-18 (D22)** — Mac SMB pilot and the Diary cutover. The user decided plain
  files on a Mac share are not the move; the Diary stays app-owned on the server. (The SMB spec
  itself had already said so on 2026-09-14; this entry had not caught up.) What replaces it is an
  offline Diary replica in the Mac app — see H.
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
- **Live 2026-09-18 (D7, D23: Google Drive).** Encrypted, content-addressed snapshots written
  nightly to a folder (`offsite-dir.cjs`) and mirrored to Drive by the host's rclone
  (`deploy/offsite/`), so the Google credential never enters noevia. First snapshot restored in
  full with the Diary, all 12 databases passing `integrity_check`. **Google Drive connected
  2026-09-18:** 124/124 objects on Drive, `rclone check` 0 differences; the key is in the user's
  password manager.
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
  **Requirement (D22, 2026-09-18): an offline Diary.** The app pulls the latest Diary from the
  server, keeps working with no connection — read, write, and a local model with local tools and
  MCP servers — and syncs back on reconnect. Built with the Mac app, not before.
  ([spec §5](spec-agent-execution.md), "Offline Diary")

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
8b. **Built 2026-09-17.** CodeHarness (spec §3): worktrees, egress proxy, ACP client, job events,
   Code mode UI, the sandbox container, `_meta`/evidence identity and the harness selectors — all
   behind `features.codeHarness`, off, not deployed.
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
- 2026-09-17 (afternoon) · baseline before the next rotation: npm test 661, Diary pytest 310, model
  manager 27, deploy 4, experiments OK; 59 QA suites, 57 pass. `qa/features.cjs` and
  `qa/offsite-backup.cjs` still clicked "Close settings" on phones, which 0d269fa hid; test-only fix.
- 2026-09-17 · a (self-review) · the new Tune button showed for members, whose model manager is
  admin-only · shown only with `modelManagement` · qa/native-model-picker covers admin and member
- 2026-09-17 · d · Easy "Use and save" wrote Qwen3.5's native 262K context live (memory-only
  estimate) · capped by calibration / measured prompt speed / 32K · 18c1349, ba10351
- 2026-09-17 · d · any file with an "-mtp-" token counted as a draft head: multi-GB MTP model builds
  were hidden, refused by safe defaults and could draft for themselves · size check · 18c1349
- 2026-09-17 · e · tool router returned boxes in selection order, so a large earlier box used the
  token budget before the best match · best first · c36eee5 (needed box 16/26 → 26/26 live)
- 2026-09-17 · f · ConfigureTab crashed (blank page) on a sections response without arrays, now
  reachable from chat through Tune · validated · ba10351

#### Session of 2026-09-17 (night) — CodeHarness build

- 2026-09-17 · d/f · **The QA baseline was not green on the live release.** `qa/models-settings.cjs`
  fails at `ca5d2f6`, verified in a worktree at that commit: the model manager's `.mm-root` rule
  keeps its tab row on a phone instead of switching to a select, so tabs and buttons shipped at 38px
  at every width · floor raised to 40px, and 44px on touch screens, for `.mm-tabs-row button`,
  `.mm-select select`, `.modal-btn`, `.popup-tab` · `qa/models-settings.cjs` · 241af38
- 2026-09-17 · d · Auto-tune's "resume" silently restarted from scratch once the saved partial passed
  its 7-day TTL, and expired partials were left in the state file forever · the job reports `resumed`,
  the page says everything is being measured again, expired partials are deleted ·
  `llamacpp-autotune.test.cjs` · 241af38
- 2026-09-17 · self-review · A waiting approval's id was derived from the map size and the clock, so
  two raised in the same millisecond collided and the overwritten one hung until its timeout with
  nobody able to answer it · random id · `code-service.test.cjs` · 99fa187
- 2026-09-17 · found by their own tests during the build, fixed before shipping: a `stuck` worktree
  stopped blocking new claims on its branch (`code-workspace.cjs`); the ACP client wired cancellation
  *after* the handshake, so an agent that never answered `initialize` could not be stopped
  (`code-acp.cjs`); the harness's file handlers checked containment and then returned without reading
  or writing anything (`code-harness.cjs`); `qa/code-mode.cjs` photographed the composer six times
  because the cards sit in the project's own scroll area.
- 2026-09-17 · baseline (corrected) · After the `models-settings` fix, **all 59 QA suites pass**
  (`managed-diary` and `restore-http` print a JSON result whose `"result":"PASS"` a naive
  `grep '^PASS'` misreads — worth knowing before calling them failures). npm test 795, typecheck,
  build, lint:design green.
- 2026-09-17 · pass A (new code, self-review) · **A failed task could keep its egress token and its
  branch for good.** `createSession` and the first checkpoint sat outside the `try`, and that
  checkpoint writes to disk, so an ordinary failure (full volume, read-only mount) skipped the
  `finally`: the proxy grant stayed live and every later task on that branch was refused as
  "already writes" · whole body inside the try · `code-harness.test.cjs` · 46f179f
- 2026-09-17 · pass A (egress) · **A client hanging up mid-check crashed the web process.** The
  egress verdict does a DNS lookup, and nothing listened for `error` on the client socket during
  it; an `error` with no listener is an uncaught exception, and the proxy runs inside the web
  process. Killing a task's container — which is what cancelling does — sends a reset. Handlers
  are attached before anything awaits · `code-egress.test.cjs` · 46f179f. Note: a clean
  `destroy()` did not reproduce it; only `resetAndDestroy()` did.
- 2026-09-17 · pass B (fuzzing) · 25,000 randomized cases through the CodeHarness parsers and
  policy, asserting invariants (no unknown action, nothing but a read waved through, a refusal
  never answered with an allow) · one crash: `summarize({ agent: null })`, because a parameter
  default only fills in `undefined` · every field coerced · `code-meta.test.cjs` · 073f1f9
- 2026-09-17 · pass B (MCP) · No bug, but a gap: the loop binding curated boxes to what servers
  offer had no direct test, and it carries the property that **a box binds only its own server's
  tools**. Extracted to `mcp-boxes.cjs` and covered against a fixture where a second server offers
  the same tool name · 476e11d
- 2026-09-17 · noted, not a bug · The Nextcloud sync client evicted 86 tracked files mid-session
  (whole `src/components/icons/`, `models/`, `server/routes/` directories). Restored with
  `git checkout`. This is the documented hazard behind the `node_modules`/`dist` symlinks; worth
  knowing that it hits tracked source too, and that a sudden wave of "cannot find module" errors
  means eviction, not a code change.

