# noevia roadmap

The one planning document: what is live, what is done, and what comes next **in order**. The
executable brief is [master-prompt.md](master-prompt.md); every release is in
[changelog.md](changelog.md) and [deployment.md](deployment.md); designs are in the `spec-*.md`
files; outside sources are in [sources.md](sources.md). The reasoning behind earlier decisions,
session logs and superseded plans are in [roadmap-history.md](roadmap-history.md) — read it for
*why*, not for status.

Status words: **Done** = deployed and verified · **Next** = to build, in the order listed ·
**Needs the user** = waiting on a decision, a device, or a maintenance window.

## Where things stand — 2026-09-22

- **Live:** release **`3d2521d`** on DaServer at **https://noevia.daserver.work**, built from
  `main` (GitHub `sbstndalton/noevia`). `cowork.daserver.work` stays routed for passkeys.
- **Pushed, awaiting deployment:** **`80d116f`** streams request-local reply telemetry to the
  footer. It does not change the live release until DaServer deployment and visual checks pass.
- **Stack (ten containers):** web, diary, ocr, llama (native llama.cpp Vulkan), embed (CPU
  embeddings), kiwix, model-loader, **code-sandbox**, **docling**, and CPU-only **Laya**.
  Sidecar image tags are pinned in `.env` (`DOCLING_VERSION`, `CODE_SANDBOX_VERSION`), not
  tied to the app release.
- **Features on:** previews, Diary MCP append, tool router, Kiwix, off-site backup, **Code mode**,
  **System-One routing** and **Step supervision**. The two experiments share the saved Laya endpoint.
  **Off:** deep research.
- **Tests:** 1,196 server and front-end unit tests pass locally (none touches production); the
  deployed decision-service release passed 1,192. The last full browser QA sweep, on 2026-09-21,
  was **73 of 73 green**. `diary-reading` has been timing-flaky under a full sweep before and
  passes on its own.
- **Deploy:** `deploy/examples/overlay-release.sh OLD NEW` after a verified appdata backup; it now
  keeps the sidecars running itself. Runbook: [deployment.md](deployment.md).

## Done

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

2026-09-22: `80d116f` is pushed to `origin/main`. The footer now separates current-chat SSE
telemetry from engine-wide polling, shows generating/first-output state immediately, and applies
exact provider usage across tool-loop rounds. 39 focused and 1,111 socket-free tests pass;
typecheck/build/design lint pass. Chromium and local listener execution were blocked by this task
sandbox, so the synthetic browser QA is authored but not run and no visual result is claimed.

2026-09-21: user-authorized continuation applied adapter cutoff/bounds fixes, then prioritized
the [first durable-chat slice](research/system-one/15-durable-chat-slice.md). It is an internal
dependency-injection seam, default off and unwired in production. No automatic model switching
or tool replay. The live release and System-One candidate decision remain unchanged.

## Next — in order

Each builds on the one before or is ordered by value. Work top-down; record any reordering here.

**Architecture under review:** the local-first System-One design ([research/system-one/](research/system-one/README.md)). Nothing below that touches routing, RAG, providers or model lifecycle starts before the review; its first prototype, RAG rerank, shipped in 67f336e (pool 12 → keep 6). Multi-hop rerun done (12→6 3/4). Next: watch fallback rates in the web log (`[rag] rerank`).

1. **Deploy and exercise `80d116f`, then iterate System-One routing.** Run the synthetic,
   non-personal footer QA on a browser-capable host and verify the live footer at phone/tablet/
   desktop widths. Then use bounded synthetic prompts to inspect Laya's actual Fast/Smart/Code
   and step-supervision decisions, adjust routing/fallback behavior where evidence warrants it,
   and repeat test → deploy → verify. Preserve approval gates, execution budgets and manual model
   choices; this is not authority for benchmarks, paid calls, personal sources, model downloads,
   training, engine changes or heavy compute.
2. **Confirm the tax-folder documents re-read under Docling** the next time that project is
   opened (docling logs, no 400s). Proves the 2026-09-21 fix on real files.
3. **DAV client interoperability, remaining clients** — rclone passes 18/18 (docs/dav.md, run 2).
   Still to run: Finder, Windows Explorer/WinSCP, iOS Files, Obsidian WebDAV sync. DAV sharing is
   off live (`COWORK_DAV_PORT=0`), and the Diary image still needs rebuilding for `preserve`
   before it is turned on.
4. **Deep research** — measure on a sandbox model (D12), then turn on for admins.
5. **Other harnesses** (Claude Code, Codex) — each needs its own pinned config before it runs;
   an `Auto` harness only once there is evidence to choose between them.
6. **Later:** a Diary graph (needs an index the Diary deliberately does not keep) · a
   browser executor (spec-agent-execution §6) · the Mac app with an offline Diary replica (D22).

## Needs the user — in order

1. **Which repositories Code mode may open.** Only the throwaway `scratch` fixture is
   registered (`CODE_REPOS`); nothing real is reachable until you choose.
2. **One model or two in the engine** — partly settled 2026-09-21: the second router slot is
   the RAG reranker (the user's choice); embeddings run on the CPU `embed` container. The idle
   `nomic-embed-text-v1` router preset can go once nothing else needs it.
3. **`Ornith-1.5-9B-Q5_K_M`** was removed from `models.ini` at 00:08 on 2026-09-21 (backup
   `models.ini.bak-20260921-040852`); a restart dropped it from the served list. Restore or not.
4. **First Connect Google Drive** on the live site, then retire the host rclone cron.
5. **A maintenance window** (D2) for: the Tasks-box hints, the Prompt Architect benchmark, and the
   known-good settings measurements.
6. **An engine API key** shared by noevia and the Nextcloud Assistant.
7. **Real-device checks:** phone polish judgement, and the glass banding check (D13).
8. **`--fit on --fit-target 1024`** for the engine, now that the syslog mirror is on.
5. **Deep research live run** approval (D12).

## Lessons worth keeping

- Test with the real shape of the input: the Docling bug passed a synthetic check because it used
  a bare filename, not a storage path.
- `state/web/` is the live web state; `ui-data/` on the host is abandoned.
- Sidecars are tagged by what they contain; tying them to `COWORK_VERSION` breaks the next deploy.
- The live Compose files are separate from the repo's; edit them locally and copy them back (no
  python on the host), with a `.bak.before-<reason>` first.
- Measure before porting: the only slow Node path was a quadratic loop, fixed in JavaScript in
  twenty lines. A tsc `--checkJs` pass catches free identifiers when a block moves modules.
