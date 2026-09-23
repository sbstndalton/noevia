# noevia roadmap

The one planning document: what is live, what is done, and what comes next **in order**. The
executable brief is [master-prompt.md](master-prompt.md); every release is in
[changelog.md](changelog.md) and [deployment.md](deployment.md); designs are in the `spec-*.md`
files; outside sources are in [sources.md](sources.md). The reasoning behind earlier decisions,
session logs and superseded plans are in [roadmap-history.md](roadmap-history.md) — read it for
*why*, not for status.

Status words: **Done** = deployed and verified · **Next** = to build, in the order listed ·
**Needs the user** = waiting on a decision, a device, or a maintenance window.

## Where things stand — 2026-09-22 (updated 14:48)

- **Live:** release **`827932b`** on DaServer at **https://noevia.daserver.work**, built from
  `main` (GitHub `sbstndalton/noevia`). `cowork.daserver.work` stays routed for passkeys.
- **Stack (ten containers):** web, diary, ocr, llama (native llama.cpp Vulkan), embed (CPU
  embeddings), kiwix, model-loader, **code-sandbox**, **docling**, and CPU-only **Laya**.
  Sidecar image tags are pinned in `.env` (`DOCLING_VERSION`, `CODE_SANDBOX_VERSION`), not
  tied to the app release.
- **Features on:** previews, Diary MCP append, tool router, Kiwix, off-site backup, **Code mode**
  (harness: **pi 0.87.0** since 2026-09-22; OpenCode one `.env` change away),
  **System-One routing** and **Step supervision**. The two experiments share the saved Laya endpoint.
  **Off:** deep research.
- **Tests:** 1,247 server and front-end unit tests pass locally (none touches production). The three-material refinement passes 14 distinct synthetic browser suites, a 468-state sweep and a 198-state final confirmation. Models/settings and full-auto-tune browser suites also pass. The last full browser QA sweep, on 2026-09-22 against `e19119d`,
  was **77 of 77 green** (after fixing three stale test fixtures). `diary-reading` has been timing-flaky under a full sweep before and
  passes on its own.
- **Deploy:** `deploy/examples/overlay-release.sh OLD NEW` after a verified appdata backup; it now
  keeps the sidecars running itself. Runbook: [deployment.md](deployment.md).

## Done

### 2026-09-22 — Cloud CSS state correction (release `72ae258`)
- Material 3 segmented, mode switch, menu and button state layers were corrected;
  Liquid primary actions keep their paired foreground/background on hover and press.
  Local Chromium validation now covers the complete 17-destination inventory and
  targeted interaction states. Native Apple/Safari parity remains open; see the audit.
- The unit suite now runs behind a test-only outbound guard and passes all 1,247
  cases with isolated state and disposable loopback fixtures. Guarded deployment is
  verified healthy; public assets match the validated build.

### 2026-09-22 — Three materials refined (release `827932b`)
- Removed Glassmorphism; older saved values fall back to Soft. Soft stays matte, Liquid
  controls use restrained highlights without label distortion, Material 3 uses tonal roles
  and correct state colors. Native-checkbox switches now meet 3:1 knob/track contrast.
- Keyboard focus, reduced preferences, approval decisions and account isolation verified.
  1,247 tests and all required checks pass. [Audit and iteration log](material-audit-2026-09-22.md).
- Deployed after verified backup; public assets match, services healthy, engine/embeddings/pi
  unchanged. Full evidence and rollback are in [deployment.md](deployment.md).

### 2026-09-22 — Outstanding branches integrated (release `04780e6`)
- Settings and project-library polish plus Claude/pi harness hardening merged into main.
  Existing model tuning retained without duplication; no outstanding branch excluded.
- 1,245 tests, typecheck/build/design lint, 15 synthetic browser/HTTP suites, real pi/Claude
  scripted-model checks, and 80 isolated Linux image tests pass. All three approval actions
  and tenant isolation preserved. No real Diary corpus used.
- Web deployed; pi sandbox rebuilt as `pi-0.87.0-99be0a2` and activated. Engine/embeddings
  unchanged; Laya remains pre-existing unhealthy. [Evidence](integration-2026-09-22.md).

### 2026-09-22 — Complete model auto-tuning (release `5a88558`)
- User-prioritized: **Tune untuned models**, beside Check for updates, detects missing/stale
  tunes and runs a sequential queue under one confirmed maintenance window. Context, KV cache,
  three MTP draft profiles, n-gram and batch settings are measured and quality-screened, then
  the fastest complete passing profile is applied. 60–70% acceptance is guidance, not a gate.
- Three deterministic probes plus long-context recall are smoke tests, not broad accuracy
  certification. Uses existing MTP heads only; no downloads. Rollback on cancellation/failure,
  restart recovery and external-edit protection tested. No production inference run started.
- App-only deployment; pi sandbox unchanged. Laya was already unhealthy at preflight and was
  left untouched (routing-health diagnosis is separate work).

### 2026-09-22 — Code mode runs pi (your go)
- The sandbox runs pi 0.87.0 through noevia's own ACP bridge; every non-read action reaches the
  approval card with its real command or path. Two live `scratch` tasks on the loaded model fixed
  `median()` (test `ok`, only `median.js` changed). OpenCode remains one `.env` change away.

### 2026-09-22 — Diary image overlay (your go)
- The Diary companion now runs the Trash-on-overwrite (`preserve`) and file-time (`modified`)
  fixes. Built `FROM` the running image with only `agent/` replaced (no dependency changes);
  backup, preflights, health and D1 isolation checked; rollback tag kept.

### 2026-09-22 — Diary local graph (release `080a91d`, deployed)
- Diary editor → Local graph: the open note, what it links to (Markdown and `[[wiki]]` links,
  including ones typed but not saved) and what links back (the existing bounded backlink scan),
  drawn as a small graph with clickable, keyboard-focusable nodes and a grouped list of names.
  Read-only; no index; says when the scan was partial. `qa/diary-local-graph.cjs`.

### 2026-09-22 — Pinned configs for Claude Code, Codex and pi (release `59249d9`, deployed)
- Claude Code and pi get noevia-written config (everything but reads asks, local engine only, no
  updates/telemetry; pi a fail-closed gate plus noevia's own ACP bridge). Both proven with the
  real CLIs against scripted fake models. Codex refused: measured, its commands ran unasked.
  Live remains OpenCode.

### 2026-09-22 — Routing labels and live footer (releases `e7b59d6`, `6c3cde0`, deployed)
- The footer follows the visible chat's own stream (generating, first output, exact usage and
  MTP across tool rounds), separate from engine polling. `qa/live-stats.cjs` passes; 375/768/1440
  light/dark inspected; stray wrapped-line separators fixed.
- System-One routing: Laya was sending most reasoning/code to Fast (23/40 held out). Concrete
  role labels: 36/40, verified through the deployed module with zero fallbacks at ~0.5 s.
  Second fresh set: 45/50.
- Step supervision (release `b055571`): the old wording paused a benign chat and added needless
  verify rounds; new wording 16/17 fresh, no needless pauses, every dangerous case stops.
  Laya chat smoke passes on the loaded model. [Evidence](research/system-one/19-routing-labels.md).

### 2026-09-22 — Context compaction inside tool continuations (release `3d2521d`, deployed)
- Every provider continuation after tool execution is re-budgeted. When tool results push the
  transient projection over its threshold, older context is summarized before the next request.
  The current user turn and complete assistant-call/result groups remain byte-identical; no
  transcript rewrite, fabricated result, blind truncation or tool replay. 1,196 tests pass.

### 2026-09-21 — Curated plugin starters (release `067ac1d`, deployed)
- Plugins → MCP servers and Skills open with "Recommended by noevia": Exa, Notion, Linear,
  Hugging Face and Cloudflare docs (first-party, hosted, all addable), and the pdf, docx, xlsx,
  doc-coauthoring, frontend-design and skill-creator skills, each with a line on why. Resolved
  against the live directories (5 and 6 found from DaServer); a vanished pick drops out.

### 2026-09-21 — Ordinary WebDAV clients can write (release `42540fb`, web only)
- Your decision: relax If-Match, keeping a version. DELETE/MOVE use the current version; a PUT
  over a file first keeps its bytes in Trash (restores beside it). Protected files still need
  If-Match. `qa/dav-interop.cjs`: rclone 18/18 against the real companion on a throwaway tenant.
  DAV sharing stays off live; the Diary image is not rebuilt (`preserve` ships with it later).

### 2026-09-21 — Shared context across Chat and Code (release `dbfbd92`, deployed)
- Project settings → Shared context, shown when a project is in both Chat and Code; both off by
  default. "Code tasks see this project" starts a task with the goal, instructions, memories and
  recent chat titles (ahead of the task, never in its label). "Chats see recent Code tasks" tells
  a project chat what was asked and how it ended. Same user's workspace only; framed as data.

### 2026-09-21 — Code mode can reach the network (release `9611580`, deployed)
- The egress proxy runs inside web on port 8040; the sandbox reaches it as `egress` on the
  internal code network, and it is the sandbox's only way out. A task reaches only the
  domains its approved grant names, on 80/443, until the task ends. "Reach the network" and
  "Install dependencies" are offered again. Verified live: direct internet from the sandbox
  unreachable; no or forged token 407; a synthetic grant for `pypi.org` connects while
  `github.com`, a lookalike, `llama` and port 22 are 403, and revoking it gives 407. Fixed on
  the way: `NO_PROXY` was empty, so a granted task's own model calls would have been refused.

### 2026-09-21 — `index.cjs` is wiring (release `2ce73df`, deployed; QA sweep 77/77)
- **`index.cjs` is wiring.** The project, source and upload routes (`projects.cjs`,
  `routes/projects.cjs`), the provider registry (`providers.cjs`, `routes/providers.cjs`), the
  models routes (`models.cjs`, `routes/models.cjs`), the Diary routes with the connector
  endpoint (`diary.cjs`, `routes/diary.cjs`), sign-in/profile/admin (`routes/auth.cjs`), the
  storage connection (`routes/storage.cjs`), tool approvals, chat lists and history, reasoning
  settings, health and the HTTP helpers (`http.cjs`) each moved out with injected
  dependencies and a test with fakes; the member-origin policy is `createEndpointApproved` in
  `ssrf.cjs`. Every moved block is verbatim behind a sentinel, mounted in its original
  order; status codes, messages, the auth and CSRF gate and the approval actions are
  unchanged. 2,787 → 752 lines; `documents.test.cjs` no longer slices `index.cjs` as text.
  1,092 tests pass. The Claude Diary plugin README now points at Settings → Diary & storage →
  Connected apps for revocation.

### 2026-09-21
- **Code mode works and is on.** noevia pins the harness's own config (every action asks, one
  model endpoint, no self-update) and refuses a harness it cannot pin; registered repositories
  owned by the harness user are trusted instead of reported as "Not a git repository". The
  sandbox runs on an internal network whose only other member is the engine. A real task fixed
  the `scratch` fixture end to end twice. The Code tab gets the full height, and network and
  installs are shown unavailable (and never granted) because no egress proxy runs yet.
- **Docling is the extraction backend** — reading order, tables, Office/ODF/HTML/image formats.
  Fixed the same day: it was sent storage paths as names and refused every document in a folder;
  a 400 is now named for what it is and stays retryable, so affected documents heal on next sync.
- **Obsidian compatibility in the Diary:** `[[wiki links]]` render, open and count as backlinks;
  typing `[[` suggests files; frontmatter shows as properties; the tag filter reads `tags:`;
  unlinked mentions sit beside backlinks; new files can start from a `Templates` folder.
- **Diary connectors** are made and revoked in Settings (the server script is gone).
- **Auto-tune narrates itself** line by line, with heartbeats during engine loads.
- **Chat:** "Thought for 12s"; the context meter is one quiet line and no longer polls.
- **Usage** from real data: peak hour, favourite model, per-tool call counts.
- **Project screen:** header actions, context chips, an Outputs row, Context and Scheduled
  panel sections. **Nextcloud** is a connector of its own.
- **Repo:** usage accounting and the auto router moved out of `index.cjs`; dead components, the
  old Code sidebar CSS and the old Diary landing removed; design lint clean.
- **`index.cjs` taken apart** (release `a4e0178`, deployed): toolboxes and
  the built-in tools (`toolboxes.cjs`), the MCP wiring (`mcp-wiring.cjs`), the chat loop
  (`chat.cjs`) and the approvals gate each live in their own module with injected dependencies,
  a `routes/` file and tests that never boot the server; 4,241 → 2,787 lines. The tests that used
  to slice `index.cjs` as text now call the modules. Dead code removed end to end (the unused
  Hugging Face model search and variants routes, six uncalled helpers); the finished Docling
  handoff doc removed; every spec is now linked from `docs/README.md`.
- **Measured, not ported.** [research-language-consolidation.md](research-language-consolidation.md):
  Node costs ~10 µs of CPU per streamed token against the engine's 25–90 ms — 0.6 % of a
  paced reply — so nothing is worth porting to Rust, C++ or Python. The one slow Node path
  (`reduceToolResult`, quadratic on long listings, 53 ms) was fixed in place with parity
  tests: 0.5 ms. Rerun with `apps/web/scripts/profile-hot-paths.cjs`.

### Before 2026-09-21 (see the history file for detail)
Reliability fixes · PDF originals, OCR, images, DOCX · unified uploads · shared composers ·
onboarding and invites · the Diary (landing, days, Markdown editing, calendar, recovery, trash,
import/export, filters, sharing) · thinking modes · tool-call guard · app passwords and Markdown
DAV · instruction skills · backups with verified restore and Google Drive off-site copies ·
native llama.cpp with the Model Loader · MCP multi-server with OAuth, per-user keys and a
directory · skills auto-loading · tool routing · the Models page (tabs, routing, tuning,
benchmarks) · UI overhaul releases 1–4 (materials, primitives, Plugins page) · web address
rename with passkey continuity · Kiwix offline Wikipedia.

## Local source work — not deployed

No production application change. The Skills/MCP offline contract experiment is implemented
in [draft PR #20](https://github.com/sbstndalton/noevia/pull/20); model quality and production
adoption remain pending. The first durable-chat slice (research/system-one/15) remains
an internal, default-off seam.

## Next — in order

Each builds on the one before or is ordered by value. Work top-down; record any reordering here.

**Architecture under review:** the local-first System-One design ([research/system-one/](research/system-one/README.md)). Nothing below that touches routing, RAG, providers or model lifecycle starts before the review; its first prototype, RAG rerank, shipped in 67f336e (pool 12 → keep 6). Multi-hop rerun done (12→6 3/4). Next: watch fallback rates in the web log (`[rag] rerank`).

1. **System-One next steps.** Remaining routing misses are near-ties; a margin gate is not
   justified on 4 cases. Every decision is recorded text-free (role, margin, latency, fallback) in
   `state/web/system-one-decisions.jsonl` (bounded, rotated; docker logs are lost at each deploy).
   After a week of real use: `docker exec cowork-web-1 node /app/server/decision-log.cjs
   /app/server/ui-data` prints the summary; tune only from that. Rerun `scripts/system-one-probe.cjs` after
   any Laya or label change.
2. **Confirm the tax-folder documents re-read under Docling** the next time that project is
   opened (docling logs, no 400s). Proves the 2026-09-21 fix on real files.
3. **DAV client interoperability, remaining clients** — rclone passes 18/18 (docs/dav.md, run 2);
   Obsidian sync's client passes 17/17 after a modification-time fix (2026-09-22).
   Still to run: Finder (an agent-side `mount_webdav` is refused locally by macOS; see dav.md, 2026-09-22 — needs the user), Windows Explorer/WinSCP, iOS Files, Obsidian WebDAV sync. DAV sharing is
   off live (`COWORK_DAV_PORT=0`), and the Diary image now carries `preserve` and `modified`
   (overlay 2026-09-22), so turning it on is your call alone.
4. **Deep research** — measure on a sandbox model (D12), then turn on for admins.
5. **Other harnesses** — pi is live (2026-09-22); Claude Code pinned and proven with the real
   CLI; **Qwen Code pinned and proven with the real CLI**; Codex refused on measurement. Next: run
   the DeepSeek harness (`dsh --profile acp`, read at source: fail-closed approvals forwarded over
   ACP) against a fake model like the others, then pin it
   (spec-agent-execution, "Other harnesses: pinned configuration"). pi's approvals are bridged to
   noevia's cards (`services/code-sandbox/pi-acp-bridge.cjs`), proven with real pi 0.87.0 and a scripted fake
   model (`qa/pi-bridge-e2e.cjs`). Next, with your go: install Claude Code (+ ACP adapter) or the
   next measured harness in the sandbox image and run the `scratch` fixture. No `Auto` harness
   until there is evidence.
6. **Skills portability and bounded skill/toolbox selection — offline prototype in draft review.**
   The default-off contract and measurement harness for [issue #19](https://github.com/sbstndalton/noevia/issues/19) is implemented. Next, collect authorized held-out model evidence before deciding whether a production experiment is justified. Keep script execution and each MCP candidate behind separate qualification gates. See [the research plan](research-skills-mcp-loading.md).
7. **Later:** a whole-Diary graph (needs an index the Diary deliberately does not keep; the
   one-hop **local graph** shipped 2026-09-22) · a
   browser executor (spec-agent-execution §6; its policy module, `browser-policy.cjs`, is built and
   tested, 2026-09-22; the executor itself needs a node with a browser) · the Mac app with an offline Diary replica (D22).

## Needs the user — in order

1. **Look at the live footer once** while a reply streams (phone and desktop): the session had
   no signed-in browser, so only the synthetic QA and bundle identity were verified.
2. **Which repositories Code mode may open.** Only the throwaway `scratch` fixture is
   registered (`CODE_REPOS`); nothing real is reachable until you choose.
3. **One model or two in the engine** — partly settled 2026-09-21: the second router slot is
   the RAG reranker (the user's choice); embeddings run on the CPU `embed` container. The idle
   `nomic-embed-text-v1` router preset can go once nothing else needs it.
4. **`Ornith-1.5-9B-Q5_K_M`** was removed from `models.ini` at 00:08 on 2026-09-21 (backup
   `models.ini.bak-20260921-040852`); a restart dropped it from the served list. Restore or not.
5. **First Connect Google Drive** on the live site, then retire the host rclone cron.
6. **A maintenance window** (D2) for: the Tasks-box hints, the Prompt Architect benchmark, and the
   known-good settings measurements.
7. **An engine API key** shared by noevia and the Nextcloud Assistant.
8. **Real-device checks:** phone polish judgement, the glass banding check (D13), and a Finder
   Connect to Server with an app password once DAV sharing is on (docs/dav.md, 2026-09-22).
9. **`--fit on --fit-target 1024`** for the engine, now that the syslog mirror is on.
10. **Deep research live run** approval (D12).
11. **Claude Code in the sandbox** — pinned and proven locally; installing it is your call (it
    needs llama.cpp's Anthropic endpoint to work with your model, and your sign-in if ever pointed
    beyond the local engine).

## Lessons worth keeping

- Test with the real shape of the input: the Docling bug passed a synthetic check because it used
  a bare filename, not a storage path.
- `state/web/` is the live web state; `ui-data/` on the host is abandoned.
- Sidecars are tagged by what they contain; tying them to `COWORK_VERSION` breaks the next deploy.
- The live Compose files are separate from the repo's; edit them locally and copy them back (no
  python on the host), with a `.bak.before-<reason>` first.
- Measure before porting: the only slow Node path was a quadratic loop, fixed in JavaScript in
  twenty lines. A tsc `--checkJs` pass catches free identifiers when a block moves modules.
