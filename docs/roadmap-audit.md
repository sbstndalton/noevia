# Roadmap audit — 2026-09-10

## Managed Trash release — 2026-09-14

Production **724cd34** replaces ee86c24 (candidate details below). Exact Linux
web image: first parallel run had one failure from concurrent tests racing on a
shared `ui-data/secrets.key` (EEXIST, harness only); serial rerun
`node --test --test-concurrency=1 server/*.test.cjs` with the three read-only
config fixtures passed all 345. Diary image suite 275 passed.

Backup ab_20260914_112117 (web and Diary archives present). Guarded app-only
rollout with automatic rollback to ee86c24 passed; native llama container
unchanged. All four services healthy, zero restarts/OOM. Public assets match
index-ByZk1SN-.js / index-2LTQHseZ.css; `/api/diary/workspace-trash` returns 401
unauthenticated and the Diary image imports `agent.workspace_trash`.
**Not yet done:** authenticated synthetic production Trash/restore browser check
at a phone viewport. No real Diary access.

Rollback: `current` + `COWORK_VERSION=ee86c24`, `.bak.before-724cd34` config/Compose
backups, then app-only preflight/up.sh --no-build --no-deps --wait web diary ocr.

Remaining roadmap, in order:
1. Authenticated synthetic production verification of Trash/restore (mobile sizes).
2. Remaining Markdown fidelity work and scoped Claude client verification.
3. Continue docs/backlog.md and spec-diary-markdown-workspace.md items.
Still unapproved/not enabled: automatic purge, 50-revision/90-day retention,
offsite/paid backup destination, Wikipedia service, legacy WebDAV migration.


## Managed Trash candidate — 2026-09-14

Adds reversible single-file Trash/restore for app-managed Markdown, with saved
buffer guards, capture/index protection, SHA compare-and-swap, occupied-path
refusal and idempotent operation receipts. Source, recovery capsule, backup
schedule and index invalidation commit atomically. Pending capture writes block
mutations; endpoints perform no inference. No legacy migration or purge policy.

Hidden recovery capsules retain exact bytes inside both ZIP and immutable remote
backups, including after restore. Imported capsules remain inside their new
Imports folder for isolated operator extraction; this is stated in the UI and
workspace specification. Existing archive bounds count recovery content.

429 web tests, typecheck/build; 272 local Diary tests with three existing skips.
Synthetic real web/Diary HTTP recovery verifies auth/method guards, no-inference
mutations, uncertain retry, ZIP capsule inclusion and restored source. Six-size,
two-theme UI covers dirty drafts, lost responses, collision retry, reload with
an empty active folder, 44px center hits, reduced motion and enlarged text.
Existing seven-size mobile and editor save/conflict/reconciliation suites pass.
Light and dark screenshots reviewed. No real Diary access. Production remains
ee86c24 pending Linux image qualification and rollout.


## Short-screen sidebar release — 2026-09-14

Production **ee86c24** replaces e9358ab. Short-height/keyboard navigation scrolls
without collapsing history; touch Options targets remain 44px, and menus fit the
visible viewport. Expanded phone rail is opaque; section overlap caps removed.

429 local web tests, typecheck/build; seven populated viewport/keyboard cases in
both themes with scroll/hit/menu Rename/Escape checks and reviewed screenshots.
Existing mobile and Diary editor suites pass. Exact Linux web image: 345 server
tests pass. Initial image run lacked repository config fixtures; mounting the
three read-only config fixtures resolved its sole ENOENT failure. Diary/OCR image
identities match the previously verified release. CI 34826626504 all jobs passed.

Backup ab_20260914_051311 verified both archives; completed 05:13:27 EDT.
Preflight and app-only rollout passed, native container unchanged. All four
services healthy, zero restarts/OOM; OCR HTTP 200. Public assets match
index-B4SS5Cq1.js / index-kRE51da1.css. Production 375×360 synthetic ordinary chat
returned SIDEBAR_RELEASE_OK (5.0 s, 516 input/103 output, 26.4 tok/s, 32768 context,
MTP61.2%, no tools). Actual sidebar scrolling exposed its recent row; coordinate
Options click opened a fully visible menu and Archive removed the synthetic row
at the same viewport. Normal viewport/New chat restored. No real Diary access.

Rollback e9358ab and .bak.before-ee86c24 configuration/Compose backups retained;
app-only preflight/up.sh with --no-build --no-deps --wait web diary ocr.
Next: reversible managed trash/recovery; no retention/purge policy enabled.


## Short-screen navigation candidate — 2026-09-14

Reproduced populated history collapsing to zero at 320×360. Short-height and
keyboard-height rails now scroll as a whole; section height caps no longer
cause overlapping rows. Touch chat rows retain one stable 44px Options control,
with Pin/Archive available in its menu. Expanded phone navigation is opaque.
Context menus use the visible keyboard viewport and reposition on resize.

429 web tests, typecheck/build, seven viewport/keyboard cases in both themes,
real scrolling/center-hit/menu-selection/focus checks and screenshot review pass.
Existing seven-size mobile and Diary editor recovery suites pass. All data is
synthetic; no inference/corpus calls. Production remains e9358ab pending image
qualification and rollout. Reversible managed trash remains the next roadmap work.


## Previewed managed workspace import release — 2026-09-14

Production application **e9358ab** replaces 11155df. ZIP preview and explicit Apply
into a new managed Imports folder are deployed, including transactional source /
empty-folder / backup / retry-receipt / index-outbox handling. Preview recognizes
a completed import after reload. Existing data/settings are preserved; legacy
storage is not migrated. Browser upload cap is 32 MiB. No retention policy added.

429 local web tests, typecheck/build; 258 local Diary tests (three skipped, two
existing warnings). Exact Linux images passed 346 web/proxy and 261 Diary tests.
CI 34825276184 passed all three jobs. Synthetic six-size/two-theme import UI,
editor save/conflict regressions and seven-size/two-theme mobile suite passed.
The real synthetic HTTP recovery workflow verifies ZIP export/import/retry/readback.

Backup ab_20260914_045459 verified both archives and completed at 04:55:15.
Installed preflight and app-only deployment passed; native container unchanged.
All four services healthy, zero restarts/OOM; OCR HTTP 200 at its configured 8030
port. An initial manual probe used the wrong 8090 port; corrected probe succeeded.
Public assets match index-CrOIZ7n1.js / index-D-NOzdGs.css. Production 375×360
ordinary-chat smoke returned IMPORT_RELEASE_OK in 3.7 s, 516 input/68 output tokens, 26.9 tok/s,
32,768 context, MTP 60.0%, no tool calls. Synthetic chat archived; normal viewport
and New chat restored. Real Diary was never opened/read/imported/reindexed.

Production mobile follow-up discovered: expanded sidebar at 375×360 leaves no
visible recent-chat list (header/footer consume available height). AX/locator
menu clicks had no effect until normal viewport was restored, where menu/archive
worked. This is a pending populated-sidebar reachability regression to fix next;
existing mobile suite did not catch it. Do not call mobile QA complete.

Retain 11155df and .bak.before-e9358ab env/Compose backups for app-only rollback.
The two added managed SQLite tables are additive; no live data was imported.
Next: short-height populated sidebar fix, then reversible managed trash/recovery,
Markdown fidelity and scoped Claude client verification. No subagents authorized.


## Previewed managed workspace import candidate — 2026-09-14

Adds noevia ZIP preview and explicit Apply into a new `Imports/<name>` folder,
with conflict checks and identical-content information. Browser uploads are capped
at 32 MiB; expanded archives retain the existing 5,000 file / 256 MiB limits.
Legacy/browser storage stays on isolated operator restore. Active layout settings,
existing raw capture and source bytes remain unchanged; this is not a corpus cutover.

Source, empty folders, backup generation/deadline, retry receipt and indexing outbox
commit in one SQLite transaction. Same archive/destination retries return the
receipt without overwriting later edits. A fresh preview recognizes the same receipt
after a browser reload, so an uncertain success is not mistaken for a conflict. Journal failure retains the outbox;
normal recovery indexes afterward. Preview/Apply do not call inference. Pending
capture writes block import. ZIP validation now rejects directory payloads, entry
mode/path disagreement and malformed manifests; export enforces its transport cap.

429 web tests, typecheck/build; 258 Diary tests (three skipped, two existing warnings).
Synthetic six-size/two-theme UI covers conflicts, changed-name invalidation, uncertain
retry and retained drafts; phone screenshots reviewed. Real synthetic web/Diary
HTTP export/import/retry/readback and backup/restore workflow passes. Full-suite
compatibility failure in an early indexing hook was fixed before this candidate.
Production remains 11155df pending exact-image qualification and deployment.


## Portable workspace export release — 2026-09-14

Production application **11155df** replaces 48432fe. Stored-workspace ZIP export
and verified isolated operator restore are deployed. Raw Markdown/binary bytes,
empty folders and checksums round-trip; no corpus migration or retention policy
was introduced. Phone export controls remain clear of the telemetry row.

427 local web tests, typecheck/build; 233 local Diary tests (three skipped),
344 exact-image web/proxy tests and 236 exact-image Diary tests pass. Two existing
Python dependency warnings remain. GitHub CI 34823510937 passed all three jobs.
Six-size/two-theme ZIP failure/retry/download/draft and center hit checks passed;
seven-size/two-theme viewport/composer/settings checks and editor conflict/rebase
regressions also passed. The real synthetic web/Diary recovery workflow now
verifies authenticated binary export, unauthenticated/method rejection, archive
preview and exact restoration to a new folder.

Backup ab_20260914_043757 verified both state archives and completed at 04:38:12.
Installed mount preflight passed. All four services healthy, zero restarts/OOM;
native container unchanged, OCR HTTP 200. Public assets match index-m33txJ5p.js
and index-KAGKyq4l.css. Production 375×360 ordinary-chat smoke returned
EXPORT_RELEASE_OK in 3.0 s (514 input/49 output, 26.2 tok/s), 32,768 context and
MTP59.2%, with no tool calls. Exact synthetic chat archived through its menu,
viewport reset and New chat restored. No real Diary corpus access/export.

Retain 48432fe and .bak.before-11155df config/Compose backups for app-only rollback.
Next: in-app import preview/conflict handling and reversible recovery; operator
ZIP restore is new-directory-only and does not activate or merge a live corpus.


## Portable workspace export candidate — 2026-09-14

Added authenticated stored-workspace ZIP download with original Markdown/binary
bytes, empty folders and checksum manifest; isolated operator recovery previews
and verifies before restoring to a new directory only. Export defers cold-tenant
replay/indexing and refuses pending writes. Managed reads are one SQLite snapshot;
legacy export requires two matching bounded snapshots. In-app import and reversible
trash are still pending. Browser-folder export remains a file-manager copy.

427 web tests, typecheck/build and 233 Diary tests (three skipped, two existing
warnings) pass, plus synthetic download/failure/retry/draft checks at six sizes in
both themes and existing server/local editor conflict/save/reconciliation QA.
A screenshot-detected telemetry overlap is fixed with workspace scroll clearance
and verified center hit testing. Production remains 48432fe pending qualification.


## Markdown filters release — 2026-09-14

Production application **48432fe** replaces 02495a7, adding bounded dated-filename
and hashtag filters to stored Markdown search. The UI explains the supported
syntax; no corpus migration, model call or persistent search index was introduced.
426 web tests, typecheck/build, six-size/two-theme filter QA and the existing
server/local editor save/conflict/reconciliation checks passed. The exact Linux
web image passed 343 server tests. Diary/OCR image IDs remain identical to the
previous qualified release. GitHub CI 34822124225 passed all three jobs.

Fresh backup ab_20260914_042006 verified both state archives. Installed mount
preflight passed; native router container unchanged. All four services healthy,
zero restarts/OOM, internal OCR HTTP 200. Public assets match index-DiUxf1Ea.js
and index-CyMgPvGj.css. Production keyboard-height UI reviewed at 375×360. Final
synthetic ordinary chat returned FILTER_RELEASE_OK in 7.7 s (622 input/44 output
on final call, 30.4 tok/s), with 32,768 context and live MTP58.7%. It made one
safe built-in get_current_time call despite the prompt requesting no tools; no
external write or Diary access occurred. Both synthetic release chats archived;
viewport reset and New chat restored. Filter functionality itself was tested
against synthetic stored files, not the real production Diary corpus.

Retain 02495a7 and .bak.before-48432fe env/Compose backups for app-only rollback
using the preflight wrapper with --no-build --no-deps --wait web diary ocr.
The pinned native backend/provider configuration remains in place.


## Markdown date/tag filter candidate — 2026-09-14

Added inclusive dated-filename and whole-hashtag filters to the existing bounded
stored-source search. Filters combine with text or work alone; changed inputs
clear stale results. No index, model call or persistent copy is added. Syntax and
limits are explicit in the UI and Markdown workspace spec. 426 web tests,
typecheck/build, editor server/local conflict regressions and six-size/two-theme
filter browser checks pass. Candidate image qualification/deployment remains.
Next: portable workspace export with attachments/manifest and reversible recovery,
reusing managed-storage snapshot/restore contracts where possible.


## Native model UI release — 2026-09-14

Production application **02495a7** replaces 2570a02. The pinned native router
container is unchanged. Chat choices and auto roles exclude embedding/reranking
models; Manage retains them. Legacy MTP controls are capability-gated, with native
profile guidance. All approval actions have 44-pixel minimum height and retain
full argument disclosure.

424 local web tests, typecheck/build and synthetic model/approval browser checks
passed. The exact Linux web image passed 343 server tests; Diary/OCR image IDs
match the previously verified release. GitHub CI 34821414694 passed all three
jobs. Scheduled backup ab_20260914_041001 verified web/Diary archives immediately
before release. Env and both Compose backups use .bak.before-02495a7.

Installed mount preflight passed; all four services healthy, zero restarts/OOM.
Public assets match index-DPDvw100.js and index-BdQJWaar.css; OCR health returns
200. Authenticated 390×844/375×360 production checks confirmed the corrected chat
picker, preserved embedding in Manage and fitting dialog. A synthetic ordinary
chat returned UI_RELEASE_OK in 5.0 s (524 input / 95 output, 24.3 tok/s), with
32,768 context and native MTP acceptance 56.5%. The exact test chat was archived;
viewport reset and browser left on New chat. No real Diary prompt/corpus access.

App-only rollback: set current and COWORK_VERSION to 2570a02, then invoke the
preflight wrapper from the live Compose folder with --no-build --no-deps --wait
for web diary ocr. Preserve the current native override/provider configuration;
do not use the separate backend rollback merely to revert this application.


## Native model selection and mobile approvals — 2026-09-14

Candidate fixes normalize native effective embedding/reranking flags for loaded
and unloaded models, exclude those capabilities from chat and auto-role choices,
and prevent an embedding-only loaded model becoming the default chat model.
Manage retains those models and their native identities. Switch model now gates
legacy MTP controls by runtime capability and explains native profile management.
Approval buttons have 44-pixel minimum height; full arguments remain untruncated.

Verified: 424 web tests, typecheck/build; synthetic real-HTTP default/cold/auto model
regressions; native picker and Manage at 375/768/1440 widths in both themes;
full approval text, all three decisions, failure/retry and touch reachability at
320×568, 375×667, 390×360, 667×375, 768×1024 and 1440×900 in both themes.
No real Diary traffic, writes or model configuration changes. Production rollout
is pending candidate image qualification. Continue Markdown date/tag filters and
portable workspace recovery after this release.


## Native GPU qualification and production cutover — 2026-09-14

Production now uses direct llama.cpp **b10920-eafe15a5e**, pinned Vulkan image,
with one loaded model process at a time. Web/Diary/OCR application images remain
**2570a02**; this is a qualified backend/configuration cutover, not another app
image deployment. All four services are healthy, zero restarts/OOM. Lemonade,
Model Loader UI and the old GPU experiment are stopped with restart disabled.
All 11 existing model identities are retained as presets; no tenant selections
were rewritten. The saved shared default-provider endpoint was updated alongside
the environment because it otherwise retained the old Lemonade URL.

Real GPU tests passed chat, structured tools, cancellation, a 28,671-token input
with 2,048 output tokens reserved, embedding/auxiliary/chat eviction and reload,
Gemma vision and Qwen 9B vision at 262,144 context. Minimum available host memory
was 8.67 GiB. Separate isolated application tests passed the actual Diary LLMClient
and all three tool approvals, including reapproval in a different chat. No real
Diary prompt, corpus access/import or reindex. Eighteen synthetic embedding vectors
and eight retrieval pairs verified new queries against old vectors as well as a
new synthetic index; arithmetic differs slightly across backend builds.

Authenticated production phone testing returned `NATIVE_PROD_OK` (8.6 s, 519 input /
89 output tokens, 23 tok/s), reported 32,768 per slot and live MTP acceptance.
375×360 composer/dialog hit checks passed; native profiles show the deployed
context/KV/MTP settings. The exact synthetic chat was archived. The native profile
editor was read only. Backup `ab_20260914_034204` verified both app state volumes.
The first cutover attempt rolled back on a missing operator heartbeat; corrected
launch and pre-start saved-provider updates passed the subsequent guarded rollout.
See [runbook](deployment.md) and [machine-readable evidence](evidence/native-cutover-2026-09-14.json).

Additional populated mobile QA passed source actions, long filenames/folders,
delete cancellation, and upload rejection/progress at six viewports in both themes.
423 web tests, typecheck/build pass; app assets remain unchanged.
Next concrete UI fixes: native embedding presets appear in the chat picker, and
the legacy MTP control says “No”/unverified despite active native MTP metrics.
Native management is through Manage → Native runtime profile. Continue the
remaining Markdown-workspace roadmap and extended mobile approval-card tests.


## Mobile viewport and native adapter release — 2026-09-14

Production web, Diary and OCR run **2570a02**, replacing 55b2767. Mobile composers
remain reachable at keyboard height; model/settings dialogs follow the visible
viewport and phone telemetry uses one scrollable row. Direct llama.cpp support
is included, while the active production inference backend remains Lemonade.
Native GPU workload qualification and cutover are still outstanding.

Verification: 423 local web tests, typecheck/build, seven viewport sizes in both
themes, keyboard/draft/zoom regressions, all personal settings categories, Diary
calendar/list and Markdown conflict/save checks, native profiles and model guidance.
The exact Linux candidate passed 342 server tests and 221 Diary tests (two existing
dependency warnings). OCR image matches the previously verified image. GitHub CI
passed. Backup `ab_20260914_031839` verified web/Diary state before the installed
mount preflight performed rollout. All three services are healthy with zero
restarts/OOM; web and internal OCR probes return 200. Public assets match
`index-DZyp8_tE.js` and `index-D7vxMZ0U.css`, with `/viewport.js` present.

Authenticated production checks reproduced and resolved the short-height composer
bug, verified populated model selection and administrator settings, and completed
a synthetic ordinary-chat inference returning `MOBILE_OK`. That test chat was
archived. No real Diary prompts, corpus edits/import or model configuration changes.
Retain 55b2767 and `.bak.before-2570a02` env/Compose backups for rollback.


## Mobile viewport correction — 2026-09-14

Reproduced an off-screen chat composer at keyboard-sized height and cramped
model dialogs in landscape. The shell follows the visual viewport while preserving
pinch zoom; short-height empty-chat decoration yields to the composer. Mobile
telemetry stays present in one horizontally scrollable row. Model/settings dialogs
respect visible height, and phone model forms use 16px text to avoid focus zoom.
Synthetic browser QA covers seven screen sizes in both themes, keyboard shrink/
restore, draft retention, model dialog controls, settings categories, and Diary
calendar/list composer reachability. Markdown save/conflict/reconciliation tests
also pass. 423 web tests, typecheck and build pass. No real Diary data was used.
The user authorized continued roadmap fixes and repeated GitHub/production cycles;
production remains `55b2767` until a separately verified release.

## Direct native llama.cpp implementation — 2026-09-14

Implemented native router lifecycle/readiness, public variant downloads and durable
status, guarded native INI profiles, per-slot context/build observations, metrics,
capability-aware UI and generic Compose overlay. No replacement router, Docker
socket, production backend switch or real Diary test traffic. See
[implementation and qualification boundary](spec-direct-llamacpp.md). Earlier
Lemonade-retention recommendations below are historical. Verified: 423 web tests,
218 Diary tests/3 skipped, typecheck/build, native HTTP/browser regressions and
pinned-image API contract. Production remains healthy on `55b2767`.


## App-owned Diary deployed — 2026-09-14

Implemented transactional tenant-local Diary storage and delayed immutable WebDAV
backup, explicit copy/verify import, portable restore and status UI. This supersedes
the pending SMB working-corpus direction. Deployed as `55b2767` after explicit authorization and verified backup/image
checks. The real Diary remains on its original WebDAV connection until explicit
import. Direct llama.cpp integration is now authorized as the next implementation. See
[design, limitations and restore runbook](spec-managed-diary.md).

## Roadmap resumed — 2026-09-12

The user explicitly resumed the remaining roadmap with “Just go”. The earlier
testing pause is superseded. Continue in tested, documented deployment increments:
reconcile stale backlog, ship the verified context fix, establish durable backups
and restore evidence, then complete instruction skills, Diary recovery and the
remaining scoped storage/tool experiments. Preserve all approval gates and tenant
isolation. Mac SMB authentication remains an independent pending client step.
No subagents or new Codex tasks were requested.

## Latest review — 2026-09-12

Dedicated Diary storage support and cold-load context resolution are deployed in `cc59e8f`.
The synthetic read-only `Diary-Pilot` share exists; real cutover is pending the
Mac SMB login and visibility check. All 80 Mac/server files match, with originals
and consistent journal backups preserved. Tests: 192 local/3 skipped, 195 Linux;
real-image synthetic bind/HTTP checks cover guarded saves, stale conflicts,
reader UID access, missing-volume failure and recovery. See
[the evidence and remaining steps](spec-diary-smb.md).

Model Loader staging results and the deployed cold-load context
fix are recorded in [the experiment report](../experiments/model-loader/README.md).
All three production services now run `8fa1112`, including reviewed instruction skills, selected-HF-artifact MTP checks, saved-storage Diary recovery and active-project source refresh. See deployment.md for validation. Dated observations
below retain their original scope; they do not imply these follow-ups are deployed.

## Chat context budgeting and compaction — 2026-09-10

Added ordinary/project-chat context meter above the composer with an expandable
breakdown of messages/summary, instructions/memory/sources, tools, generation
reserve, safety buffer and free space. Counts are conservative UTF-8 estimates,
not exact tokenizer or account totals; unknown limits use a labelled 8k fallback.
Lemonade uses the loaded model's configured ctx_size, not its architecture maximum.
The first prepared request establishes the meter; later visible output updates
its estimate. Existing chats can use Compact chat before sending another turn.

Manual and automatic compaction summarize older exchanges with the selected
provider, preserve two recent exchanges verbatim, and keep the full visible/saved
transcript. Summaries are private per-user/per-chat files and exact-prefix hashes
invalidate them after edits. Failed/unusable/truncated summaries retain previous
context; oversized sources/recent messages fail clearly rather than being dropped.
Compaction is lossy and may omit details. Diary's separate journal is unchanged.

Requests reserve up to 4,096 generation tokens and 15% estimation margin; automatic
compaction triggers when input exceeds the remainder (about 72% for 32k). High
effort cannot expand or discard this budget. Tool continuations are rechecked;
context errors inside SSE are surfaced, and heartbeat frames cover silent waits.
No automatic retry of tools or writes. Configured capacity is not a guarantee of
available shared-backend memory, and non-Lemonade model limits remain a fallback.

338 tests, typecheck/build, and synthetic browser QA pass: manual/automatic
compaction, transcript retention, cache reuse, failure handling, streamed errors,
375/768/1440 widths and both palettes. Deployed `ae39000`; all three services
healthy, public assets match, 290 Linux server and 13 worker tests passed. No private
financial data, Diary prompts, model reloads or live corpus changes used in QA.


## PDF reduction, local thinking and shared Diary assessment — 2026-09-10

User-authorized follow-up: `2408c32` makes configured local Qwen3/3.5 Low/High
use actual `chat_template_kwargs.enable_thinking` false/true. Default remains
provider default; other providers retain their documented parameter/hint behavior.
[Qwen’s model card](https://huggingface.co/Qwen/Qwen3.5-9B) documents the template switch; the installed template was also verified.
This controls ordinary/project chat (including optional Diary extras), not the
separately configured Diary companion's effort. Its provider reasoning still streams.
The exact installed Qwen3.5-9B UD-Q4_K_XL GGUF was inspected read-only: it uses
`enable_thinking` in its template but contains no MTP metadata/tensors. Its disabled
MTP control is correct; the upstream model's training capability is insufficient.
[Unsloth's separate MTP GGUF](https://huggingface.co/unsloth/Qwen3.5-9B-MTP-GGUF)
is a potential replacement to validate, not an automatically installed model.

`ddbe852` allows PDFs up to 60 MB into bounded asynchronous reduction. Native text
is extracted, images recompressed, and a PDF under 25 MB is saved with a distinct
`.compressed.pdf` name only after validation and matching page counts. If that
fails, a complete native-text extract within the text limit may be saved as
`.extracted.txt`, explicitly warning that images/scanned text/layout are omitted.
Encrypted, malformed, over-300-page and unreducible files fail clearly. Originals
remain on the user's computer; ordinary files retain the 25 MB limit. The private
worker adds Ghostscript; no cloud document processor is used. Verification:
329 web tests, typecheck/build, 13 real Linux worker tests and synthetic browser
checks covering notices, failures preserving sources, and responsive UI.

Shared Diary API deployed in `12a1646`: dedicated revocable credentials and
version-checked Markdown operations prevent stale replacements. The Claude plugin
is packaged privately but not installed; Claude UI automation became unavailable.
Nextcloud push callbacks are repaired and all six self-tests pass after restart.
Desktop sync timing and pending Mac/cloud differences remain unverified; no real
Diary data changed. See [shared-editing status](spec-diary-shared-editing.md).
The broader roadmap stays paused for user testing.


Rollout complete: `ddbe852` on all three services; 281 Linux server and 13 worker
tests passed before cutover. Health and public assets match; rollback retained.

## MTP controls and persistent inference footer — 2026-09-10

User-authorized follow-up: fresh launch/reload opens an unsaved New chat (separately
tested/pushed as `df8a486`). Model selection/Manage now offer native MTP Yes/No,
with an explicit Apply and load action for administrators because Lemonade model
loading is shared. Native support comes from Lemonade's GGUF-derived `mtp` label
and llamacpp recipe, never a model-name guess. Saved options are preserved,
including context/cache/GPU split arguments. A successful load precedes saving the
preference; a failed load leaves saved options unchanged. No automatic reload or
model download happens on opening the selector. Native MTP models keep Lemonade's
automatic default until explicitly overridden. Unsupported models show why Yes is
unavailable; arbitrary tiny draft models are not automatically paired/downloaded.

Inference details now stay open at the bottom, including Diary. Loaded MTP models
show an acceptance bar using accepted/proposed draft-token totals. Newer backends
can report cumulative counters. This server's llama.cpp b9632 instead reports
per-response `draft_n`/`draft_n_accepted`: Chat and Diary forward these actual
timings, labelled **last response**, updated at completion. These samples are
user/model scoped, bounded and expire after ten minutes. Missing/invalid telemetry
stays unavailable. Polls do not overlap; failed stats requests clear acceptance.

Runtime inspected: Lemonade 10.8.0 / llama.cpp Vulkan; installed Qwen 3.5 4B has an
MTP label, while the installed 9B/Gemma variants do not. No live model load/settings
were changed for testing. Multi-GPU on/off throughput/latency/acceptance benchmarks
and compatible external draft-model configuration remain explicit experiments;
MTP is not assumed to be a free speedup. Broader roadmap pause remains in effect.

Sources: [versioned load API](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/docs/api/lemonade.md#post-v1load),
[native defaults](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/server/backends/llamacpp_server.cpp),
[GGUF capabilities](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/include/lemon/gguf_capabilities.h),
and [backend metrics normalization](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/server/prometheus_metrics.cpp).

Validation: 325 web tests, 178 Diary tests (3 skipped), typecheck/build; isolated real-app/fake-Lemonade browser
checks cover Yes/No before load, option preservation, persistence after success,
failed-load safety, unsupported/member rejection, and acceptance footer visibility
at 375/768/1440 widths in Chat and Diary. New-chat landing and Diary scrolling
regressions pass. No real Diary prompts or corpus changes. Deployment recorded
separately.

Rollout complete: `cac1778` on all three services, replacing `3ef0501`; 277 Linux
server and eight worker tests passed before cutover. Health/public assets match.
No production model settings or Diary corpus changed for testing.


## Live Diary activity and timeout feedback — 2026-09-10

The user's follow-up explicitly requests live visibility and reports a 524 after
leaving an active Diary view. The earlier after-completion reasoning fix was not
sufficient. The noevia Diary path now streams immediate headers and 5-second
keep-alives through both proxy and companion, actual provider reasoning/answer
chunks, and actual retrieval/classification/summary/save/memory progress. The
answer is visible before capture finishes; saving is confirmed separately.
Optional tool calls remain attached to their conversation turn with unchanged
approval gates. An elapsed timer accompanies the active phase. No synthetic tool
calls or invented reasoning are shown. Providers that buffer or omit reasoning
still show the real pipeline phase. The external OpenAI JSON surface is unchanged;
noevia opts into its activity event protocol explicitly.

Switching app views keeps the mounted request and transcript alive, without a
second submission. Interrupted streams preserve the attempted message/partial
response and report unconfirmed saving; no automatic retry. Proxy HTML is never
shown as the error text. A full browser reload/close still does not provide durable
conversation/job recovery; the journaled server operation may finish after the
connection closes, so check the saved record before resending. Durable recovery
remains open. Browser-local saves still require the connected folder and browser.

Verification: 319 web tests, typecheck/build, 177 Diary tests passed (3 skipped,
2 existing warnings). Tests cover headers/heartbeats before slow upstream, frame
fragmentation, disconnect/no-retry, provider reasoning before answer, hidden log
markers, rejection of truncated generation, server tenant context and memory-only
local capture. Synthetic browser checks cover live thinking, leave/return while
running, save phases, retained optional tool traces, sanitized 524 and partial-stream
failure, plus prior scrolling/composer/navigation checks. No real Diary prompts or
corpus edits. Broader roadmap remains paused. Deployed application `3ef0501`; all three
services and public assets verified after 271 Linux server/eight worker tests.
The following rollout-record commit is documentation only.


## Diary reading feedback — 2026-09-10

The user authorized this focused fix during the broader testing pause. Other
roadmap implementation remains paused. The active conversation now shows the
original user message and complete companion answer, with the saved diary record
in a separate disclosure (collapsed when this session has conversation turns).
The day composer is outside the transcript scroll. Diary and ordinary chat follow
new output only at the bottom; scrolling up pauses following, and returning to the
bottom or sending resumes it. Ordinary chat's smooth auto-scroll was removed
because its intermediate scroll events incorrectly disabled following.

Provider-returned reasoning is carried separately through both server and local
Diary exchanges and displayed using the existing thinking disclosure. It is not
included in journal prose or follow-up history. The companion still uses a single
non-streaming request: reasoning arrives with completion, only when returned by
the provider. Live Diary token/reasoning streaming and durable full conversational
history remain future work; reopening after reload shows the saved diary record.

Verification: 315 web tests, typecheck/build, 172 Diary tests passed (3 skipped,
2 existing warnings). Synthetic Chrome checks cover server/local Diary reasoning,
retained previous thoughts, history filtering, navigation/errors/extras/cancel,
saved-summary disclosure, scroll pause/resume, stationary day composer, landing,
both themes and 375/768/1440 widths. Ordinary chat scroll is also tested against
an isolated real app server and synthetic streaming provider. No real Diary test
prompts or corpus changes. Deployed application `ecaaa73` across all three services after 267 Linux server
and eight worker tests; health and public build assets verified. The following
rollout-record commit changes documentation only.


## User testing pause — 2026-09-10

The user will test for a couple of days. Pause implementation and deployments
until feedback or an explicit resume request; do not resume automatically by date.
The current recorded application release is 79cd24f. The detailed clarification
and remaining-work summary are in [the roadmap](roadmap.md#user-testing-pause--2026-09-10).
The estimate of one third to one half remaining is informal and effort-based,
not measured completion. Shipped batches do not mean the full roadmap is complete.

Claude Diary workflow decisions were adapted, not Claude's device tools themselves.
Exact logging/wording/memory/conversation equivalence has not been tested. Add a
reference-prompt and synthetic-behavior comparison after user feedback; keep real
Diary corpus testing prohibited without specific authorization.

## Current handoff status — reconciled 2026-09-10

The status table below is current; dated follow-ups preserve earlier evidence.
Application **`79cd24f`** is deployed across all three services. Onboarding,
Diary navigation/scaffolding/landing, thinking effort v1, reasoning-only answer
handling and reported-rate sample guards have shipped. DOCX body extraction is deployed. App-password lifecycle is deployed; a limited, default-off DAV endpoint is
deployed with sharing disabled. Current
verification: **314 web tests**, typecheck/build and **171 diary tests passed,
3 skipped** (two existing warnings). Model accuracy, latency, uncapped local
thinking and storage architecture remain open. Diary extras stay OFF on reload;
the companion pipeline and all write approvals remain unchanged.


## OCR/image completion follow-up — 2026-09-10

The later request authorized implementation, Git push, and production deployment.
Local PDF OCR is implemented in a private, stateless Poppler/Tesseract container
(English/German). Native text and original bytes are preserved; OCR transcription
is separately labelled, including on mixed text/image pages. Failed/busy workers
remain incomplete and are retried on refresh. Upload/refresh polling avoids long
reverse-proxy requests; active operations/results are scoped to the authenticated
workspace and project. A server restart requires a refresh/re-upload retry.

Missing image files now produce a visible warning; truncated vision descriptions
fall back to direct vision; description caches include content and credentials,
expire after five minutes, and remain user/project scoped. The live Qwen 9B
registration lacked mmproj. Its matching projector is now configured and a real
synthetic image transcription passed (invoice ID, two dated rows, negative refund,
and total). No private financial or diary sources were used for testing.

The OCR container passed synthetic scanned, mixed-page, mixed-document, encrypted,
and malformed PDF checks. Limits: 25 MB input, 50 OCR pages, 3500-pixel longest
edge, one active worker job, 60 seconds per subprocess, ten minutes per document,
1 GiB memory and 512 MiB temporary storage. OCR does not guarantee financial table
semantics or handwriting accuracy; verify critical values against the original.
Native PDF parsing remains in the web process. Other onboarding/navigation and
roadmap work is not included in this follow-up.

Original audit (committed as `f0dd19e`) inspected `d726a63` on main, plus a
read-only production timezone check. That documentation-only audit made no
implementation changes or deployments; its baseline was 194 web tests and
155 diary tests (3 skipped).

Historical reliability batch verification, 2026-09-10: Workstreams 1 and 5a
were complete locally at this stage, before the later recorded production rollout.
No production access, diary prompts, or corpus changes were made. Verification:
`npm test` — 208 passing (14 new); `npm run typecheck` and `npm run build` —
passing; diary `.venv/bin/python -m pytest tests/ -q` — 155 passing, 3 skipped.
The diary suite emitted two dependency deprecation warnings. No runtime
dependencies, UI changes, or diary write-path changes were introduced.

Document/image investigation follow-up: synthetic fixtures and 15 additional tests
now reproduce the reported failure paths and related gaps. Verification: 223 web
tests, typecheck and build pass; diary 155 pass, 3 skip (two dependency warnings).
No runtime code, production configuration, or private sources were changed.

Source-completeness implementation follow-up: native page extraction/original
retention, stale/failed source state, page reads, and binary storage fixes are now
implemented locally. Verification: **238 web tests**, typecheck/build pass;
**155 diary tests pass, 3 skipped** (two dependency deprecation warnings).
Synthetic browser QA covered source rows and keyboard focus in light/dark modes
at responsive widths. No deployment or real diary/financial-source access.

## Status and evidence

| Item | Status | Evidence / remaining work |
| --- | --- | --- |
| UI/sidebar | Reopened by user; app-wide glass in progress | Preserve the Claude/ChatGPT layout. Local Study 03 received positive sidebar feedback; extend treatment across all views and Settings. See `spec-ui-direction.md` and `codex-handoff.md`. Not deployed. |
| 1: agent deploy contract | Complete and deployed | Root `AGENTS.md`/`CLAUDE.md` link the brief and distinguish generic `DEPLOY.md`/`cowork.setup.json` from the existing live Unraid runbook. Wizard wording matches the implemented account checkbox and models guidance. Included in `e3b29bb` and subsequent releases. |
| 2 / 5b: thinking modes | V1 deployed; uncapped budgets remain open | Admin default + project/free-chat/extras override; documented parameter support, labelled hints, rejection fallback and explicit high output budget. Uncapped local generation is not promised. |
| 3: wizard restructure | Deployed | Fresh setup starts Welcome → Diary/chat choice → account, then provider/storage/preferences/passkey. Explicit hosted/external storage choices preserve saved configuration on skip/failure. Admin thinking preference is available; members retain their restricted flow. Insights was removed from the product and is not resurrected. |
| 3.5: invite onboarding | Complete and deployed (`baf38aa`) | New invitees explicitly start incomplete. Members receive Diary → preferences → passkey, with no bootstrap/provider/global-model step. Authenticated session state supplies the saved Diary choice before rendering. |
| 3.6: markOnboarded | Complete and deployed (`baf38aa`) | Existing choices are preserved atomically; missing rows mean no recorded consent and stay off. Reproduced a separate repeated legacy backfill enabling missing rows on restart; it now runs only once. Existing onboarded accounts are unchanged. |
| 4a: diary scaffolding | Complete and deployed | First exchange in a new corpus journals create-only seed READMEs for Entries, AI Memory and Raw Sources. Existing journals/imported entry corpora are not migrated. |
| 4b: diary landing | Complete and deployed | Empty composer; populated Memory, recent Entries and Other sources panels. Operator-wide external import folders remain admin-only pending tenant ownership. |
| 4c: landing-to-day navigation | Complete and deployed | Send pins the browser-local date and routes history, streamed/local replies, errors and optional-tool scope to that day before preparation begins. Synthetic browser-local/server-backed regressions pass. |
| 4d: diary visual/refactor work | Complete and deployed | Landing, calendar and context sidebar are separate components. Existing tokens, responsive layout and shared composer behavior retained. |
| 5a: duplicate tool-call guard | Complete and deployed | `tool-exchange.cjs` is instantiated inside `handleChat`; canonical arguments, exchange-only result reuse, read invalidation on attempted writes, and handler-level mocked streaming/fallback regression coverage. See Workstream 5a for denial/failure/validation semantics. |
| 5: deferred tool disclosure; 5c: planner/executor | Research only | Scoped experiment plan in spec-tool-routing-research.md. Static toolbox budgets and message-level Fast/Smart routing remain; no speed/quality benefit is claimed without benchmarks. |
| 5d: offline Wikipedia | Not implemented; optional | No Wikipedia toolbox found. Requires a selected available service; it is not a prerequisite for OCR, skills, or correctness fixes. |
| 5e: harness framing | Partial | Already explained in `docs/agent-brief.md`; root agent entry points now link the brief. |
| 6a: timezone | Complete, including production | Both Compose definitions, `.env.example`, wizard timezone helper, and timezone regression tests exist. Live read-only check: TZ=America/New_York, EDT -0400. The old statement that the live copy remains unapplied is stale. |
| 6b: direct diary context | Complete and deployed | Missing/empty/failed semantic retrieval falls back to bounded tenant file reads: two explicit past ISO dates plus three previous days by default. This is not exhaustive diary search. |
| 6c / 6d: memory ownership/privacy | Architectural constraints | Disk-backed diary memory already feeds context. Keep the single-store and no-cross-profile diary-content boundaries; these are not standalone missing UI features. |
| 7a: Unraid state default | Original example hazard addressed | `deploy/examples/unraid-compose-manager.yml` requires COWORK_STATE_DIR explicitly. Generic `compose.yaml` and the manifest still use ./state. No named-volume default or explicit /boot-path rejection exists; those are separate remaining decisions. |
| 7b / 7c: local storage UX | Partial | Storage clients and browser-local folder access exist, but they do not expose server-held files to other devices. The two-choice setup flow is verified; broad device mounting remains open. |
| 7d / 7e / 7h / 7i: served storage | Partial | App-password lifecycle deployed; limited conditional Markdown DAV operations deployed. Broad file-manager compatibility remains open. Outbound PROPFIND/MKCOL and saved Nextcloud credentials are client functions, not these features. Sharing settings and hosted-storage wizard are deployed; managed-volume defaults remain open. |
| 7f / 7g: endpoint and proxy notes | Design/reference material | These describe requirements and prior experiments, not shipped endpoint features. The roadmap repeats 7g/7h sections; reconcile before implementing storage. |
| 8: PDFs/OCR/images | Implemented and deployed | Original retention, native pages, isolated OCR, asynchronous status, bounded binary reads, image projector configuration, unified categorized uploads and progress are shipped. DOCX body/table reader deployed; OCR/vision accuracy and inference latency remain limitations. See the follow-ups and live audit report. |
| 9: skills | Proposal complete; implementation planned | User selected reusable instructions using existing approved tools. See spec-instruction-skills.md for current code inventory, project-file lifecycle, context boundaries, representative weekly review and acceptance plan. No executable package framework. |

## Corrected priority order

Completed: reliability, PDF/OCR/images, composers/model controls, onboarding
correctness, Diary navigation/scaffolding/landing/refactor, thinking v1 and the
reasoning-only and short-sample telemetry fixes.

1. **Instruction skills:** implement the scoped project-file lifecycle, including
   explicit review and exclusion from every source/RAG path when disabled.
2. **Storage:** companion-backed namespace operations and real client compatibility;
   fresh-install volume defaults/Unraid path protection without existing-data migration.
3. **Thinking/model follow-ups:** verified provider budgets and synthetic performance
   evidence; current high hints are bounded, not uncapped.
4. **Tool research:** run the scoped experiments before adopting architectural changes;
   optional Wikipedia requires an operator-selected service.

The earlier 2026-09-10 continuation request authorized continuing the full roadmap,
with testing and a Git push after each implemented item. Keep each change bounded
and reviewable when work resumes. The later user testing pause takes precedence
over autonomous continuation and deployment. Preserve the accepted sidebar and
current composer behavior.

## Design cautions discovered during the audit

- Do not expose the admin-only external-source mount listing to members merely
  because Workstream 4 proposes it. Tenant ownership and filtering must be defined
  first; the current endpoints explicitly restrict server import folders.
- The old insights-badge proposal must be reconciled with the removal of diary
  insights from the product; do not resurrect it just to satisfy old checklist text.
- Scaffold names must be reconciled with the memory paths actually read today.
- A duplicate-call guard must normalize JSON object key order, preserve array
  order, avoid re-executing writes or re-requesting approval for the same call,
  and preserve tool-result/SSE pairing. Decide/document how denied or failed calls
  behave. Cache scope must be one exchange, never another turn or tenant.

Final pre-rollout verification for the OCR/image follow-up: **247 web tests
passing**, typecheck/build passing; **155 diary tests passing, 3 skipped** (two
existing dependency warnings); **3 OCR container tests passing**, including real
synthetic scans/mixed pages and malformed/encrypted failures. Qwen's loaded
llama-server command includes `--mmproj` and the synthetic image transcription
returned the exact invoice, dates, signed amounts, and total. Production rollout
and browser checks are recorded separately after completion.


Production follow-up: `e3b29bb` is pushed and deployed, including Workstreams 1
and 5a and this later OCR/image batch. Authenticated browser verification passed
synthetic mixed-PDF upload through Nextcloud, OCR-ready status, image perception
(blue circle, orange triangle, ZEBRA-73), and a correct answer citing scanned PDF
page 2 and its signed amounts. Web-to-worker health and diary container health
passed. Prior release/config backups remain available. Subsequent documentation
commits record this evidence without changing the deployed application image.


### Unified uploads follow-up — 2026-09-10

The Sources page now has one upload control for all non-archive files up to 25 MB.
New uploads use Documents/Images/Text/Other subfolders in connected storage, with
matching UI groups. DOCX and other opaque formats are retained as originals and
marked stored-only until a reader is implemented; Office containers are accepted
although internally ZIP-based. Images over the 8 MB model-input budget are kept
as originals with a resize explanation. No untrusted file is executed.

Earlier local image uploads are copied to the configured project folder during
refresh, with a stable ID suffix to avoid colliding with existing names. Local
image copies are durable caches, not ephemeral container storage. Managed category
folders are refreshed one level deep; unrelated reference trees are not traversed.
The existing PDF originals/page store and diary write path remain unchanged.

Upload progress now separates file reading, network transfer percentage, storage,
extraction/OCR, and completion, with per-file elapsed time. Completed details can
be expanded. Chat emits an image-processing status before waiting for inference.
The background wrapper's accidental 1 MB cap was corrected to the 25 MB file limit
plus base64 overhead. Verification: 256 web tests, typecheck/build pass; 155 diary
tests pass, 3 skipped. Synthetic local browser checks covered mixed uploads and
mobile source rows. The sidebar was not redesigned.


Unified-upload production follow-up: `48027ef` is deployed. Synthetic browser
uploads confirmed Nextcloud Documents/Images paths, original availability,
PDF OCR status, stored-only DOCX state, and preservation after refresh. Chat now
shows image preparation immediately, before waiting for model inference. The
synthetic image response correctly identified both shapes, colors, and heading;
QA chat/project were archived. See
`changelog.md` for the verification record and deployment rollback details.


### Composer actions — 2026-09-10

Project chats now expose a compact + menu for files/photos, grouped built-in and
connector toolboxes, and existing model/routing controls. Uploads use the same
organized storage API and show progress beside the draft; sending waits until
source processing and project refresh finish. Tool selections persist per project,
not per message, and do not bypass any write-approval action. Free chats explain
that sources and tools require a project. No skills/plugin runtime was added.

Verification: 256 web tests, typecheck/build, 155 diary tests (3 skipped). Synthetic
local browser checks covered mixed PNG/DOCX upload, persisted tool selection,
Escape dismissal, model shortcut, and light/dark desktop/mobile appearance.

Composer release `3320fc3` is deployed, replacing `48027ef`. All three service
images use the new tag; `.bak.before-3320fc3` config/Compose backups and the prior
release are retained. Diary health passed and web-to-OCR health returned 200.
The authenticated production browser verified a composer upload to Nextcloud and
enabled Nextcloud Files using the new menu. Qwen on the real Lemonade endpoint
then made exactly one `nc_webdav_list_directory` MCP call against the synthetic
project's Documents folder. The successful result named the synthetic DOCX; the
exchange took 23.7 seconds. This was a live integration test, not a locally
configured MCP endpoint. The QA chat/project were archived, local QA server and
tabs closed, viewport reset, and Tailscale restored to stopped. No real diary or
financial corpus was used.


### Shared composers and opt-in Diary extras — 2026-09-10

The + menu now covers project landing pages, project chats, free chats, and both
Diary landing/day composers. Free chats have tenant-owned, per-chat source/tool
configuration; internal context records are excluded from the normal project list.

Diary retrieval/capture is implemented in its companion pipeline, not a selectable
MCP toolbox. It remains active. Extra attachments & tools defaults OFF on reload;
turning it on enables separately stored attachments and selected MCP toolboxes for
the current mounted Diary session. Settings/files persist, activation does not.
Optional context is collected using the existing bounded tool loop and approval
cards, then passed as at most 12,000 characters of untrusted reference material to
the companion. It never replaces the raw user message or the existing diary write
path. The same optional reference path supports local-folder exchanges. Failed or
cancelled preparation does not start capture and restores the draft. Approval
allow-for-chat is scoped to the tenant, session, date, and Diary view conversation.
The extras model selector changes preparation only, not the companion model.

Verification: 261 web tests, typecheck/build; 157 diary tests with 3 skipped. Tests
cover default-off behavior, reference limits, tenant isolation, hidden contexts,
approval/result pairing, cancellation, and raw diary text/history preservation.
Synthetic browser checks covered project-front-page and free-chat uploads, free-chat
tool execution, Diary baseline/on/off/reload, all three write decisions, approval
scope separation, cancellation, and mobile popup placement. No real diary prompts
or corpus changes were used.


Shared-composer rollout: application `12ba04f` replaces `3320fc3`. All three
production images use the new tag. `.bak.before-12ba04f` environment/Compose
backups and the previous release are retained; no environment/schema additions
were needed. Diary health passed and web-to-OCR health returned 200. The live
authenticated browser confirmed the new Diary + menu and extras OFF by default.
No production diary prompts were sent, nor were extras enabled against the real
corpus. Execution/approval tests used isolated synthetic inference, MCP, and diary
fixtures; the earlier real MCP integration test remains recorded above. Temporary
QA servers/tabs were closed, viewport reset, and Tailscale returned to stopped.

### Live reliability audit follow-up — 2026-09-10

The broader authorized production audit found and fixed repeat legacy migration
into new administrator accounts and stale vision assets after stored-only image
replacement. Regression verification: 264 web tests, typecheck/build; 157 diary
tests, 3 skipped. Actual inference, Nextcloud read/write approvals, OCR, embeddings,
and synthetic tenant diary capture were exercised. See
[the coverage report](live-audit-2026-09-10.md) for evidence, latency observations,
model accuracy failures, and exclusions. No real diary test prompts or corpus edits.

Live cleanup also reproduced administrator deletion failing on issued invitation
foreign keys. Account deletion now revokes issued invitation/recovery tokens in
the same transaction, keeps audit history, and protects the last active admin even
when disabled admin accounts remain. Final regression count: 266 web tests;
typecheck/build and 157 diary tests (3 skipped) pass.

Final rollout `4ec8269` passed 222 server tests inside its image on the production
host, followed by live rechecks of all three fixes and cleanup of every synthetic
account, local corpus and the Nextcloud QA folder. The color-recognition assertion
remains a model-quality failure; measured latency and telemetry limitations are
recorded in the report. No broader roadmap implementation is implied.

### Onboarding correctness — 2026-09-10 (pre-rollout)

Workstreams 3.5/3.6 are implemented. New member and administrator invitations
explicitly set onboarded=0. AuthGate supplies the authenticated account and its
saved Diary choice before rendering, avoiding a late probe overwriting a choice.
Members start at Diary, then preferences and passkeys; administrators retain
optional personal-provider setup. Shared provider/model management stays role
protected. The non-actionable model-manager step is removed.

Both explicit Diary values persist at account creation and when changed in setup.
Back does not recreate accounts; sign-out/reload repeats optional steps with saved
account choices. Completion stops the wizard on subsequent sign-in/reload.
Theme/palette apply immediately in this browser, as explained; Auto routing saves
only on Use these preferences. Skipping preserves the previous browser setting.
Timezone guidance remains truthful about the deployment boundary. Hardware passkey
registration was not exercised; its optional skip/completion path was.

Tests confirm markOnboarded already preserves either existing choice atomically.
Its insert branch remains off: no feature row means no recorded consent. The
reproduced defect was the original legacy feature backfill running every restart
and enabling missing rows. Its migration marker now gates the backfill; original
legacy upgrades retain compatibility and completed users stay completed. No schema
addition or reset migration is needed.

Fresh checks: 278 web tests (12 new), typecheck/build pass; diary 157 passed,
3 skipped, two existing warnings. `apps/web/qa/onboarding.cjs` adds reproducible
browser regression against disposable real local servers using an existing
Playwright installation (PLAYWRIGHT_MODULE), with synthetic accounts. Coverage:
fresh admin and invited member/admin, Diary yes/no, failed saves, changes/reload,
Back, sign-out/resume, completion, role denial, account isolation, and
375/768/1440 light/dark layouts and focus. Manual browser review confirmed the
member boundary, saved opt-out, reload and completion; it caught and fixed toggle
focus loss during save. No real diary prompts/corpus changes, dependencies,
composer changes or write-path changes. Rollout pending. Next batch: Diary 4c.
Known model-quality, latency, telemetry and stored-only DOCX limits remain.


Onboarding rollout: **`baf38aa`** replaces `66af1ad` on all three services. Candidates
were built and 234 Linux server tests passed before cutover. The first candidate
image check lacked the deployment-config fixtures; mounting the repository's
`.env.example`, Compose and deploy examples read-only resolved that harness issue.
The final revision also corrects member guidance to Settings → Your connections.
Retain `.bak.before-baf38aa` environment/Compose/override backups and `66af1ad`.

42 scoped production assertions passed across preparation, verification and
cleanup: previous completion survives rollout, new member/admin invitation with
Diary yes/no, login/resume, choice changes, completion, cross-account isolation,
member administrator/shared-provider/model denials, empty new workspaces without
legacy migration, application/OCR health and synthetic cleanup. Five synthetic
accounts and their sessions/workspaces plus the exact bootstrap invitation were
removed; audit history remains. No diary prompts or corpus writes were performed.
The existing authenticated public browser opened Projects normally after reload,
with final bundle `index-DE1yxV8o.js`. All services run with zero restarts/OOM;
Diary health passes. Test tabs/local server were closed, viewport reset, and the
initially stopped client Tailscale state restored. This scoped follow-up does not
repeat the broad inference/MCP audit or resolve its documented model limits.


### Workstream 4c — day-scoped Diary navigation (2026-09-10)

Landing Send now selects the browser-local day before optional preparation or
capture, with that day owning history, streamed/local replies and retry rollback.
Returning home and sending again retains the same day's history and optional-tool
approval scope. Past-day selections remain explicit, timestamps stay browser-local,
and programmatic navigation does not invoke the unsent-draft discard prompt.
Failures/cancelled extras preserve the draft in the selected day; cancelled extras
never call capture. No diary writer or permission gate changed.

Verification: 281 web tests, typecheck/build; 157 diary passed, 3 skipped (two
existing warnings). Synthetic browser tests cover server-backed and simulated
browser-local folders, midnight/year boundaries, previous-day isolation, returning
home/history, failures, cancellation, extras scope and 375/768/1440 light/dark
layouts/focus. Manual fixture review confirmed navigation before reply arrival.
Reproduce with `qa/diary-navigation.cjs` after building, using PLAYWRIGHT_MODULE.
No real diary prompts/corpus changes. Rollout pending.


4c rollout: **`5b1ef12`** replaces `baf38aa` on all three services. Candidate
images built and 234 isolated Linux server tests passed before cutover. Retained
previous release and `.bak.before-5b1ef12` configuration backups. Diary health and
web-to-OCR health pass; all services have zero restarts/OOM. Authenticated public
Projects loads bundle `index-BZjK7Bdp.js`. No live diary prompts/corpus changes.

### Workstream 6b — bounded direct older-entry context (2026-09-10)

Semantic retrieval remains first choice. Missing, empty or failed retrieval now
reads up to two explicit past ISO dates in the message and three preceding dates
(default, configurable up to seven) through the tenant's existing CorpusStore.
References are labelled limited direct reads, not semantic matches or exhaustive
search. No arbitrary paths, second store, index prerequisite or writes are added.
The fallback shares the retrieval budget, defaults to 1,200 estimated tokens,
and has a hard 7,200-character cap and 2,400-character per-entry cap. Setting its
budget to zero disables it. Individual read failures leave other dates available.
Natural-language date interpretation and whole-corpus search remain out of scope.

Verification: 281 web tests, typecheck/build; 166 diary tests pass, 3 skipped,
two existing warnings. Nine new synthetic tests cover unavailable/failed/empty
retrieval, match precedence, explicit dates, budgets, read failures, isolation,
and actual daily/monthly CorpusStore reads with no writes or pending journal work.
No inference or production corpus was used. Rollout pending.


6b rollout: **`23ba691`** replaces `5b1ef12` on all three services, following
candidate builds and 234 isolated Linux server tests. Retained prior release and
`.bak.before-23ba691` configuration backups. Diary health and internal OCR health
pass, zero restarts/OOM. No production diary capture or corpus inspection used.

### Workstream 4a — first-entry folders (2026-09-10)

The first exchange in a new corpus creates one-line READMEs in Entries (or its
configured prefix), AI Memory and Raw Sources. Initialization is a flag on the
existing durable exchange intent, using ETag-guarded create-only writes. A partial
failure remains pending; restart replay deduplicates the raw exchange and fills
missing seeds. Existing/empty/custom README contents and concurrent user writes
are preserved. Subsequent exchanges do not recreate deleted seed files. Existing
journals and imported corpora with listed entry months are not migrated. Monthly
layouts remain monthly; Entries README describes the configured layout honestly.
Browser-local turns use the same CorpusStore and return changed files normally.
AI Memory is read directly as context alongside legacy aliases; no shadow store.

Verification: 171 diary tests pass, 3 skipped, two existing warnings; 281 web
tests, typecheck/build pass. New tests cover both layouts, existing files and
tenants, partial failure/restart, deletion, imported corpus and ETag races. Manual
in-memory first-entry exercise confirmed all three READMEs, the daily entry and
zero pending journal work. No production corpus touched. Rollout pending.


4a rollout: **`b34c33f`** replaces `23ba691` across all three services. Candidate
builds and 234 isolated Linux server tests passed before cutover; retained prior
release and `.bak.before-b34c33f` configuration backups. Diary/internal OCR health
pass, zero restarts/OOM. No production diary prompt/corpus inspection or mutation.

### Workstream 4b — state-dependent Diary landing (2026-09-10)

An empty loaded diary has a centered first-entry composer and folder explanation,
without the hero or invented current-month card. A populated diary shows Memory,
Entries (up to seven dates from the latest two available months), Other sources
(tenant Raw Sources Markdown), then month navigation. Canonical AI Memory and
legacy memory aliases appear; file buttons use the existing guarded editor.
Storage/file-browser controls remain accessible. Landing is a separate component.
Loading and failed listings are distinct from an empty diary; failures do not
promise an empty corpus or leave a perpetual loading indicator.

The historic suggestion to expose external-sources to members is intentionally
not applied: inspection confirms these are operator-wide paths, not tenant-owned.
Other sources shows the member's own corpus files. Per-user external imports need
a separate ownership model before sharing their metadata or content. Nested/raw
binary source browsing remains limited to the existing Markdown file API.

Verification: 281 web tests, typecheck/build, 171 diary tests (3 skipped, two
existing warnings). Existing landing/day/extras/local-folder browser regression
passes; new diary-landing.cjs covers empty/populated/error states, file/day links,
no member external-source request, focus and 375/768/1440 in both themes. Manual
synthetic browser and screenshot review confirmed layouts. No real diary access.
Rollout pending. Calendar/context component extraction remains Workstream 4d.


4b rollout: **`8edacf7`** replaces `b34c33f` on all services after candidate builds
and 234 isolated Linux server tests. Retained prior release/configuration backups
`.bak.before-8edacf7`. Diary/internal OCR health pass; zero restarts/OOM. No real
diary access. Bundle `index-BQXZ5gIA.js` contains the verified landing changes.

### Workstream 4d — readable Diary components (2026-09-10)

DiaryLanding, DiaryCalendar and DiaryContextPanel now own their respective views.
Calendar navigation/date labels/future-date guards and context file/storage actions
retain the existing state owner and callbacks. The file browser's Up button now
honors busy consistently with other navigation controls. No new state or layout
system, persistence change or write-approval change.

281 web tests, typecheck/build; 171 diary tests (3 skipped, two existing warnings)
pass. Both synthetic Diary browser suites pass, including local-folder selection,
history/extras/cancellation, file/day links, both themes and responsive widths.
Manual synthetic send/calendar review confirmed reply routing, month controls and
future-date restrictions. No real diary access. Rollout pending.


4d rollout: **`7a34a0a`** replaces `8edacf7` across all services. Initial parallel
image tests hit an existing disposable secrets.key creation race; no cutover
occurred on that failed check. All 234 server tests passed with test concurrency
one before release. Use serial isolated image tests in future releases. Retained
prior release/configuration backups `.bak.before-7a34a0a`. Diary/internal OCR health
pass; zero restarts/OOM. No real diary access.

### Workstream 2 / 5b — truthful thinking effort v1 (2026-09-10)

Admin-set `settings.reasoning_effort_default` plus nullable/removable project
override resolve project → global → default. Old projects inherit; explicit
default sends no hint/parameter/budget. Settings and project editor expose these
choices; compact selectors sit beside composer models in project/free chats and
optional Diary extras. Companion capture returns before this policy and remains
unchanged. Member global writes and cross-tenant project reads/writes are denied.

Only the documented GPT-5.4 / https://api.openai.com/v1 pair receives
reasoning_effort. Other models/endpoints use labelled best-effort hints. This
conservative allowlist is documentation-backed, not a claim that a live OpenAI
account was tested. Actual request mode appears with chat replies; Auto can pick
a different model from the pre-send estimate. Parameter-field rejection retries
once without it and demotes the credential/provider/model tuple for the process.
Provider URL/key/model changes naturally use a new tuple. All tool rounds and the
non-streaming fallback use the same policy; cancellation and fallback timeout
remain active. Default/off wire bodies stay unchanged.

High hints request an explicit 8,192-token output budget (max_completion_tokens
on OpenAI, max_tokens elsewhere). Budget-field rejection retries once with the
provider default and a warning, remembering that tuple. This is a bounded v1
budget, **not uncapped reasoning or a guaranteed increase over every provider's
implicit default**. Provider/context limits still apply. The historic claim that
Default equals Medium on all models is false; Default means omit the parameter.
No Anthropic wire format or vendor framework is introduced.

Primary capability references checked 2026-09-10:
[Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
and [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4).

Verification: 292 web tests, typecheck/build; 171 diary tests (3 skipped, two
existing warnings). Policy tests and real-handler tests cover resolution, unchanged
default bodies, supported origin/model constraints, retries, cache scope, output
fields, cancellation, streaming/fallback and tool continuation. Disposable real
server/browser verifies admin/member permissions, cross-tenant denial, overrides,
reload, actual high-hint chat/badge and 375/768/1440 both themes/focus. Existing
Diary suites pass; manual optional-extras selection and screenshot review pass.
Screenshot capture now completes theme transitions before taking evidence.

A synthetic direct Lemonade/Qwen3.5-9B request with the exact high hint and 8,192
budget returned HTTP 200 in 8,876 ms, 109 completion tokens, content present and
finish_reason=stop. No diary prompt or corpus access. No live OpenAI call; wider
model capability support and uncapped local budget policies remain unverified.
Rollout pending; documented model-quality/telemetry/reasoning-narration issues are
not resolved by these controls.


Thinking v1 rollout: **`6570c51`** replaces `7a34a0a` across all three services.
Candidate images and 245 serial isolated Linux server tests passed before cutover.
Retain prior release and `.bak.before-6570c51` configuration backups. Diary/internal
OCR health pass; zero restarts/OOM. No real diary access or production settings
changes. Existing projects inherit the absent global default (no wire changes).

### Live-audit follow-up — reasoning is not a final answer (2026-09-10)

The chat handler no longer copies reasoning-only output into the final-answer
channel. It emits a clear no-final-answer notice, keeping reasoning separate and
completed tool results intact. Final-answer tracking is per round, so earlier
content does not conceal a missing final tool continuation. No extra inference,
write, or automatic tool retry is introduced. This addresses the application's
promotion behavior, not model accuracy or the provider's tendency to omit content.

295 web tests, typecheck/build; 171 diary tests (3 skipped, two existing warnings)
pass. Real-handler tests cover stream/fallback and tool continuations. Disposable
real-server browser verifies the notice after an actual synthetic reasoning-only
completion; screenshot review confirms the final transcript. No production prompt
or corpus access. Rollout pending. Throughput telemetry, DOCX and model-quality
issues remain open.


Reasoning-only rollout: **`34df7c2`** replaces `6570c51` on all services after
candidate builds and 248 serial isolated Linux server tests. Retained prior
release and `.bak.before-34df7c2` configuration backups. Compose health passes.
No real diary access; this fixes final-channel promotion, not model inference quality.

### Live-audit follow-up — engine rate sample guard (2026-09-10)

The engine display labels throughput as provider-reported. Missing/non-finite or
nonpositive rates, invalid/fewer-than-two output counts and samples whose inferred
count/rate window is below one second display unavailable. No arbitrary maximum
speed is imposed and no replacement rate is fabricated. This suppresses tiny
samples that could produce the audit's million-token/s spike; it does not repair
upstream timing or claim an independently measured benchmark. Per-reply usage and
latency reporting are unchanged.

297 web tests, typecheck/build; 171 diary tests (3 skipped, two existing warnings)
pass. Tests cover malformed/tiny samples, the live 109-token/13.185 tok/s sample,
and valid high-throughput samples. A read-only live statistics query returned
that normal sample. Manual fixture review confirmed the reported label and dash
for unavailable statistics. No production prompt/corpus changes. Rollout pending.


Engine-rate rollout: **`3b1e256`** replaces `34df7c2` on all three services after
candidate builds and 250 serial isolated Linux server tests. Health checks pass,
zero restarts/OOM; previous release and configuration backups retained.

### DOCX body-text reader v1 — 2026-09-10

Unified uploads and connected-folder refresh now read DOCX main-body paragraphs
and tables through the existing private worker. Originals remain downloadable.
Extraction is always labelled partial: page layout, images, headers, footers,
comments and footnotes are not interpreted. Deleted tracked text and field
instructions are excluded. Failed replacements clear old readable/indexed text;
re-upload/refresh retries failures, while successful content-hash/version matches
reuse extraction. Existing stored DOCX requires re-upload or folder refresh; no
background migration or real-source scan is performed.

No dependencies or corpus paths added. ZIP files are never extracted to disk;
relationships/macros are never executed or fetched. Limits: 25 MiB request,
1,000 members, 2 MiB central directory, 64 MiB declared expanded total, 8 MiB main
XML, compression ratio 200 and 200,000 output characters. DTD/entities, encrypted
archives, duplicate members and unsupported encodings fail cleanly. Malformed or
unsupported files retain originals with a visible unavailable-text reason.

301 web tests, typecheck/build and 171 diary tests (3 skipped) pass. Six local
worker tests pass; two real PDF/OCR tests await candidate-image fixture execution.
Real worker + real app browser checks cover unified upload, byte-exact original
download, labelled extracted model context, malformed replacement and responsive
light/dark source rows. Only synthetic fixtures used. Rollout pending.


DOCX rollout: **`e18f1de`** replaces `3b1e256` on all services after 254 isolated
Linux server tests and all eight worker tests, including real synthetic PDF OCR.
Health passes, zero restarts/OOM; previous release/configuration backups retained.

### Workstream 7i — app-password lifecycle (2026-09-10)

Profile & security now creates/list/revokes tenant-owned device credentials with
immutable LAN/public scope, name and creation/last-used dates. Only the creation
response returns the generated secret. Argon2id hashes, transactional account/cap
checks, mint throttling, revoke/disable verification races and audit redaction are
covered. No DAV listener is opened and no normal auth route accepts these tokens.
The UI states sharing is not available yet. See spec-storage-appliance.md for the
reconciled storage batches and endpoint policy prerequisites.

304 web tests, typecheck/build and 171 diary tests (3 skipped) pass. Disposable
real-app browser verifies member creation, cross-tenant list/revoke isolation,
CSRF refusal, no Basic/Bearer/chat/password-login acceptance, shown-once state,
revocation and both themes at 375/768/1440. No production credentials or corpus
used. Candidate image checks and rollout pending.


App-password rollout: **`2525de5`** replaces `e18f1de` on all services after 257
isolated Linux server and eight worker tests. Compose health passes; previous
release/configuration backups retained. No production credentials minted.

### Workstream 7d/7h — bounded sharing endpoint (2026-09-10)

A separate optional listener and per-user sharing settings now support scoped
Basic app-password authentication, OPTIONS/HEAD/GET/PROPFIND and conditional PUT
through the existing companion file API. No direct volume access or new corpus
write path. Scope, opt-in, enabled Diary and local storage are required on every
request. Public/HTTPS proxy authentication uses a dedicated shared secret plus
exact authority/protocol, never caller-controlled forwarded headers alone. LAN
HTTP requires explicit acknowledgement. Default listener port is zero; Compose
publishes nothing new. No production exposure is enabled by rollout.

This v1 does not claim full DAV compliance or file-manager mounts: folder creation,
rename, delete, locks and other verbs remain unsupported. No DAV class header is
advertised. See docs/dav.md for supported requests, parser/resource limits and
operator setup. This is progress on 7d, not completion of the appliance roadmap.

310 web tests, typecheck/build and 171 diary tests (3 skipped) pass. Real HTTP tests
cover XML/property handling, path/scope/transport refusal, conditional writes,
limits and failures. Real web app/listener plus synthetic companion browser QA
covers actual credentials, opt-in/acknowledgement, tenant forwarding, revocation,
stale writes and responsive light/dark settings. No real corpus access. Candidate
image checks and rollout pending.


### Resumed wizard verification — 2026-09-10

Home-LAN SSH at 10.69.0.130 confirms production still at 2525de5; Tailscale was
unreachable. The saved wizard batch adds an explicit pre-account Diary/chat
choice, two storage paths with no preselection, and the existing administrator
thinking control in preferences. Existing completed accounts are not reset.

Focused browser checks now cover saved external connection loading, failed load
(disables editing/saving), selection/skip preservation, failed hosted save,
successful hosted save and sharing remaining off. Found and fixed the external
picker's initial local-state/save race: it initializes to an external kind and
waits for saved settings before enabling controls. No connection or corpus is
contacted by these tests. Existing onboarding role/reload/focus checks pass in
both themes at 375/768/1440; screenshot review passes. 310 web tests, typecheck,
build and 171 Diary tests (3 skipped, two existing warnings) pass. Rollout pending.


Wizard/DAV rollout: **`9e2bfbb`** replaces `2525de5` across all three services.
263 isolated Linux server and eight worker tests passed before cutover. Direct
home-LAN SSH verified health, zero restarts/OOM, and DAV port 0 (disabled). Prior
release and `.bak.before-9e2bfbb` backups retained. No production corpus accessed.

### Skills index correctness — 2026-09-10

Existing skill metadata now includes the exact project filename independently of
display name, so read_project_file has a usable argument. Metadata is JSON-escaped
and bounded to 32 entries/6,144 characters with an omission notice; names,
descriptions and versions have individual caps. Included filenames are never
truncated. Source/RAG behavior and tool permissions are unchanged. This does not
implement the proposed explicit skill selection UI or exclusive progressive
loading. 314 web tests (including the actual chat handler request), typecheck/build
and 171 Diary tests (3 skipped) pass. No new UI or production prompts. Rollout pending.


Skills-index rollout: **`79cd24f`** replaces `9e2bfbb` on all services after 267
serial isolated Linux server tests and eight worker tests. Compose health passes;
prior release and `.bak.before-79cd24f` backups retained. No corpus testing or
sharing exposure enabled. Frontend bundle is unchanged from the wizard release.

## Active project source refresh — 2026-09-13

Opening a project already refreshed attached folders. This follow-up adds return,
focus, online and visibility triggers with a one-minute cooldown, plus a one-minute
timer that refreshes after five minutes of staleness. Only the open project runs;
hidden/offline tabs and active project generation defer new automatic requests.
In-flight work is deduplicated across view changes; already-started server jobs
continue. Existing bounded source sync, stale-source error handling and instruction
skill re-review remain intact. No whole-drive polling or Diary corpus tests.

358 web tests, typecheck and build pass. Scheduler tests cover cooldowns, failures,
long overlapping requests, project isolation and disposed callbacks. Synthetic
real-HTTP skill review/exclusion regression passes; Sources guidance reviewed in
light/dark and 375/768/1440 layouts without horizontal overflow. Candidate rollout
is pending; production remains f7b9d95 until the deployment record confirms it.

## Source refresh rollout — 2026-09-13

All three services now run `8fa1112`, replacing `f7b9d95`. Candidate validation:
358 local web tests, typecheck/build and 308 isolated Linux server tests pass.
The installed boot-storage preflight wrapper passed and performed the rollout.
Diary reports Docker healthy; web setup-status and OCR health return HTTP 200.
Web/OCR have no Docker healthcheck configured, so Compose's Healthy output alone
is not application-health evidence. All three show zero restarts and no OOM.
Public assets match `index-DJTWu6Rf.js` and `index-CJPL3E7N.css`.

Rollback release `f7b9d95` and configuration backups `.bak.before-8fa1112` remain.
No storage mapping, production model setting or real Diary corpus was changed.
The earlier managed-volume installer/preflight commits are included; live host
bindings remain intact. This is a verified increment, not completion of the
remaining SMB authentication/cutover, context qualification or tool experiments.


## Candidate verification — 2026-09-13

All three candidate images `8bc4339` built successfully on DaServer. The exact
web image passes 318 isolated Linux server tests. Diary passes 199 Linux tests
(two existing dependency warnings); its production code is unchanged between
7628a4c and 8bc4339. Local validation passes 373 web tests, typecheck and build.
Real web/OCR image health probes pass both healthy and deliberate HTTP 503 cases.

The initial 7628a4c web run found a test-ordering assumption when preparation and
capture share a millisecond timestamp; the corrected assertion finds the capture
by ID. The full Linux suite then passed. This changed the test, not recovery logic.

Production still runs `8fa1112`; no current symlink, saved configuration, storage
mapping or live app container was changed for candidate verification. Browser QA
is incomplete because the synthetic localhost:31239 dialog blocks controls.
Required UI review remains a release gate. The Mac has no mounted SMB pilot yet,
and namespace rename/delete waits for the managed-path policy answer. Off-site
backup destination/budget remain undecided. The Qwen calibration has completed
and restored Gemma; no active GPU test remains.


## Latest user direction and handoff — 2026-09-13

The user now says the sidebar glass looks good and asks to carry the treatment
across the whole UI, top to bottom, explicitly including the untouched Settings
panel. Preserve the existing Claude/ChatGPT-inspired layout and mature artistic
character. This supersedes the earlier closed UI/sidebar status and earlier
rejections of the sidebar treatment; it is not approval of unreviewed screens.

Next work:
- Extend the accepted local material language through Chat, Projects, project
  details/sources, Diary, Code/preview surfaces, menus, dialogs, Settings and setup.
  Keep reading surfaces legible and material behavior consistent. Preserve the
  fixed account-menu stacking bug and all six theme/palette combinations.
- Audit every Settings category against actual component and server behavior.
  Distinguish working controls, missing wiring, explicitly unavailable previews,
  and decisions requiring user input. Begin implementing concrete missing settings
  with persistence, loading/error feedback and appropriate tests. The user did not
  specify which category first; choose from the audit rather than inventing a new
  feature set or enabling external services without configuration.
- Extend the synthetic fixture where needed to verify settings. Its default mock
  responses are not evidence of working production persistence.
- Complete all-view responsive, keyboard and theme QA before promoting the design.

At handoff, no changes implementing this latest app-wide request have been made.
The last implementation commit is `5dd573c`; the local preview is on port 31287.
Production remains last verified at `8fa1112`; functional candidate `8bc4339` is
built but not deployed. Recheck live state before rollout. Broader roadmap work
remains authorized, with outstanding user decisions preserved in the handoff.
See [the paste-ready continuation prompt](codex-handoff.md).

## Settings reliability and shared material — 2026-09-13 continuation

**Implemented locally:** [category audit](settings-audit.md), retryable validated
profile/connection loading, named action feedback and busy states, retained name
drafts, Diary preference failure feedback and accurate planned-feature labels.
Actual authenticated server routes already persisted names/preferences; new tests
exercise those paths rather than treating mock success as persistence evidence.
The malformed instruction-skills response that crashed Sources now fails visibly.

**Material implemented:** accepted Study 03 moved into real application assets;
shared treatment extends across Settings, headers, composers, cards, context rails,
menus, coding preview and modal/setup surfaces. Layout, approval cards, semantic
palette identifiers and the unfiltered sidebar ancestor are preserved. Preview
now uses the same application CSS rather than a competing injected stylesheet.

**Verified:** 376 web tests, typecheck and build. Browser Settings category/layout
matrix at measured 375/768/1440 in both themes; all six appearance combinations.
Name pending/success/reload, failed save retains draft, successful retry; Diary
preference on/off/reload and forced failure; connections load failure/retry/empty.
Representative desktop Settings/Projects/Sources/Diary and mobile Settings,
Projects/chat screenshots reviewed. Mobile account menu opens Settings above page;
composer draft editing, visible keyboard ring and files/tools popover checked.
Synthetic preview now explicitly returns valid settings/source data and rejects
unsupported settings mutations (501), instead of pretending they succeeded.

**Still unverified / not deployed:** full populated model manager, setup wizard,
security ceremonies, all destructive/user administration actions, real storage /
provider integrations, and exhaustive all-view/all-palette visual regression.
The 54 Settings category/theme/width checks are not 54 screenshot reviews.
Finish these release gates before deploying the redesign. No production connection,
model, corpus, storage mapping or sharing permission was changed. Existing
functional candidate `8bc4339` stays independently reviewable; production was last
verified at `8fa1112`, not rechecked during this local UI increment.

**Next bounded Settings work:** serialize StoragePicker actions and add direct
load retry; improve Users mutation and clipboard errors; expose reasoning-load
failure/retry and explicit model-list empty/loading states. App-password initial
load/retry and the stale disabled account-menu usage shortcut also remain.
SMB client/cutover, off-site backup destination/budget, managed DAV policy and
Claude-client workflow remain open with their prior safety constraints.

## Interactive glass controls follow-up — 2026-09-13

User review found remaining mismatched buttons/dropdowns, square Settings rows
and reflection limited to the sidebar switch. Implemented a shared pointer light
layer for enabled buttons, fields, project cards, composers and navigation controls.
It eases toward the pointer, fades on exit and stops scheduling frames when settled.
Touch/reduced-motion/transparency/contrast skip tracking; positioned controls keep
their original positioning, with no filtered/transforming menu ancestors.

Buttons now share padding, optical edges, pressed/hover feedback and rounded
corners. Settings rows stack name/description and align their action, with responsive
wrapping; stat/rate/preview surfaces use consistent corners. Native select semantics
remain: browsers supporting base-select get a rounded, blurred option panel with
an entry transition, rotating chevron and selected/focus states. Other browsers
retain native option panels. Mobile category chevron wrapping was reproduced and
fixed in this pass.

Verified locally: 378 web tests, typecheck/build. New motion tests check settling,
coordinate updates, exit cleanup, touch/reduced-motion and positioned-button
preservation. Browser verifies actual reflected coordinates/opacity on the Diary
button, open option panel, Down/Enter selecting Nextcloud then restoring local
without saving, and all Settings categories at measured 375/768/1440 light/dark
without dialog overflow. Representative mobile and desktop screenshots reviewed.
The original browser tab's zoom caused inconsistent captures; a clean verification
tab supplied the measured breakpoints. No production deployment or storage changes.

## Independent profile appearance — 2026-09-13

**Implemented:** Sage (mineral green) and Iris (ink violet) join Warm, Cool and
Neutral in both modes. Light and dark retain independent palettes. An authenticated
profile appearance endpoint validates and stores the pair plus mode in SQLite,
scoped exclusively to the session user. Browser keys supply the initial paint and
migrate to profile storage. Serialized writes preserve the latest choice, including
changes made during hydration; errors retain pending choices for an explicit retry.
General reports loading, saving, saved and retry states.

Glass now combines a narrow glint, opposing tinted reflection and pointer-dependent
angle instead of a single colored spotlight. Reduced-motion/transparency/contrast
and touch safeguards remain.

**Verified locally:** 389 web tests, typecheck and build. Tests cover all ten
mode/palette contrast combinations, startup cache, hydration races, ordered writes,
failed-save retry, endpoint validation/authentication, account isolation and SQLite
reopening. Browser review confirms Sage light/Iris dark independent selection and
restoration after reload in the synthetic preview; Settings palette layout reviewed.

**Deployment:** not deployed. Preview profile storage is deliberately process-memory
only; the production implementation uses SQLite. Existing release gates and safety
constraints remain unchanged. No real profile, corpus, provider or storage data used.

## Ambient light refinement — 2026-09-13

Implemented a low-contrast 36-second alternating background drift on the main
workspace and Settings. Reduced shared hover reflection opacity to 40% and the
mode-switch glint from .55 to .25. Reduced-motion/transparency and increased
contrast disable the ambient field. No layout, profile or data changes.
Verified locally: 389 tests, typecheck/build; browser confirms changing background
positions and computed button sheen opacity .4, with dark Settings visual review.
Not deployed; available in the synthetic local preview.

## Usage theme repair and inference island — 2026-09-13

Implemented: removed the angled hover gradient and its rotating coordinate entirely.
Ambient background now has one gradient; opening Settings pauses the workspace
animation beneath it. Inference telemetry has a darker rounded island with inset
spacing and wrapping. Usage's obsolete surface/line/muted/accent variables were
replaced with active theme tokens; cards, filters, text and heatmap now follow both
modes. Rounded cards, larger period controls and removal of the empty graph frame
complete this visual increment. Existing usage loading/error/retry remains intact.

Verified locally: 389 tests, typecheck/build. Browser reviewed Usage in light and
dark (white vs dark green card backgrounds with corresponding text), confirmed
background canvas paused while Settings runs, and reviewed telemetry island.
Preview has synthetic empty usage; populated aggregate/rates release QA remains
outstanding. Not deployed; no data or approval-policy changes.

## Shared live glass scene rewrite — 2026-09-13

Replaced pointer tracking (including opposite/mirrored highlights) with one WebGL
scene. Three diffuse light sources travel across the same field; rounded panel
edges refract that field. The single canvas moves into Settings when open and back
to the workspace on close. Surface transparency now exposes the moving field;
opaque composer wrapper removed. Text and private content are never rasterized.

References reviewed: dashersw/liquid-glass-js and ybouane/liquidglass. Adapted the
first project's MIT rounded-distance shader math (license shipped in public/).
The second project's live-scene/layered-compositing design informed the approach;
neither full DOM-capture wrapper is installed. This implementation refracts its
procedural light field, not screenshots of arbitrary page content. No remote
textures or rendering services. Max 900px scene dimension, approximately 30fps,
one context; visibility and accessibility preferences stop rendering, unavailable
or lost WebGL leaves the normal readable interface.

Verified: 390 tests, typecheck/build; lifecycle tests cover single canvas switching,
hidden/reduced-motion stop/resume and no-WebGL fallback. Browser reviewed light/dark
Settings and workspace, confirmed one canvas and no browser errors. Not deployed.

## Code glass parity and seam correction — 2026-09-13

Implemented: Code workspace now exposes the shared light scene; its composer is
one padded rounded glass surface with transparent draft input, consistent controls,
focus outline and explicit draft-only copy. Side panel is a rounded glass island,
overlaying rather than squeezing content below 1000px. Sidebar header and mobile
rail spacing corrected. Code composer/panel participate in the renderer's bounded
surface list. Shader edge distortion fades continuously at the boundary instead
of cutting off; ResizeObserver keeps sampled panel bounds aligned after resizing.

Verified: 390 tests, typecheck/build. Browser reviewed Code light/dark, mobile
composer and light side panel, desktop layout, and measured 375/768/1440 widths
without document overflow. Single scene retained. Code execution remains disabled;
no repository access, models or private data involved. Not deployed.

## Button highlight contour check — 2026-09-13

Inspector toggle and sidebar section toggles lacked a radius. They now share the
12px control radius with shell/header icon buttons and the Diary header link;
pseudo-element contours inherit their control shape. Browser inspected computed
radii and Settings buttons. 390 tests, typecheck/build pass. Local only, not deployed.

## Account shortcut and continuous chrome — 2026-09-14

Enabled the account-menu Usage & activity shortcut and passed an explicit initial
category through Chat/Code into Settings; ordinary Settings opens General. Removed
the stale Preview label. Popup glass now derives from active palette chrome rather
than fixed cool colors. Header and sidebar share a material with dividing borders
removed in Chat, Code and Settings.

Verified 390 tests, typecheck/build; browser clicked account shortcut through to
loaded token totals, and confirmed dark/light popup colors change. Synthetic empty
usage remains explicit. Not deployed; no data changes.

## Context layout consolidation and light/Sources polish — 2026-09-14

Removed top-right context drawer/toggle. Project overview retains its existing
Instructions/Memory/Sources rail; project chats show one persistent context rail.
Below 1100px both rails stack after the main content instead of overlaying it.
Unscoped chats no longer show an empty project-context drawer. Sources receives
consistent spaced file rows/storage panel and suppresses the unrelated chat composer.
Light scene is neutral and lower intensity; softer palette-derived rims replace
clashing colored edge shading.

Verified: 390 tests, typecheck/build. Browser reviewed populated synthetic Sources,
light surfaces and removal of the toggle. Persistent project-chat rail and breakpoint
rules implemented; broader project-chat responsive visual QA remains before release.
Not deployed. Source actions/data handling and write approvals unchanged.

## Diary product references and Markdown workspace — 2026-09-14

Added spec-diary-markdown-workspace.md after reviewing Moodiary documentation and
existing noevia Markdown editor/storage code. Prioritized editor ergonomics and
conflict resolution, revision history, Markdown links/backlinks, search/filtering,
and portable export/recovery. Existing guarded saves are the base; no second
content backend, automatic offline browser cache or corpus migration introduced.
Status: proposed, documentation only; not implemented, verified or deployed.

## Consolidated release deployed — 2026-09-14

Release fca1f19 / release-2026.09.14 is pushed and deployed to DaServer; supersedes
prior local-only status for implemented work through this record. All three services
healthy; see deployment.md for candidate tests, authenticated browser verification,
backup and rollback evidence. Populated Usage/pricing browser release checks pass.
Diary Markdown workspace remains proposed; Code execution, SMB cutover and off-site
backup decisions remain unfinished. This is one application release, not roadmap
completion. The deployment record commit is documentation only.


## Markdown editor first increment — 2026-09-14

Implemented locally: expanded workspace dialog with bounded folder browsing,
source/preview panes, explicit Cmd/Ctrl+S, dirty/save feedback and retained editor
on success. Server comparison retains the draft and offers explicit reviewed-base
acceptance or confirmed discard/reload. Existing guarded saves remain authoritative.
Local-folder pending saves/sync keep their existing recovery contract; comparison
is disabled there pending a separate reconciliation increment.

Verification: clean starting HEAD da237c6; preview 31287 responds. Production
rechecked on fca1f19 with all services healthy, zero restarts/OOM. 390 web tests,
typecheck/build and 21 Diary workspace tests pass (two existing dependency warnings).
Synthetic browser regression lives in apps/web/qa/diary-editor.cjs and covers
failure preservation, server conflict/reconciliation, keyboard save and responsive
light/dark panes. No real corpus or model calls; no deployment. See workspace spec
for the unfinished parts of increment 1 and subsequent decision-dependent work.


## Integrated Diary Markdown workspace — 2026-09-14 continuation

Implemented locally: integrated page editor, responsive persistent file rail,
source/preview/split, outline and loading/error/retry states. Server and local
conflicts retain source and offer explicit comparison/rebase or confirmed reload.
Local editor writes no longer share pending capture records; local save success
and remote sync failure are separate states. Later edits retain the original
pending remote base. Existing local-folder read-before-write limitations remain.

Added source-relative Markdown file links, bounded explicit text search and
backlinks, plus exact current-source Markdown download. Search is transient and
reports partial results; it does not implement a whole-corpus search index.
No source reformatting, raw-capture changes, new inference calls or browser cache.

Verified in the combined local set: 404 web tests, typecheck/build, 196 Diary
passed and three skipped (two existing warnings). Browser checks include
server/local conflict and failure recovery, save/sync separation, original sync
base preservation, discard protection, list retry, search/backlinks, safe links,
unsaved-source export and responsive light/dark workspace. Production remains
fca1f19. Revision retention is awaiting the requested user decision; full archive
export, trash/import and richer date/tag/dialect behavior remain unimplemented.

## Model guidance and inference hardware — 2026-09-14

Implemented locally following the CanIRun.ai product review: Models → Guidance
filters reported capabilities and assesses one explicit memory pool against model
file size and a configurable reserve. Unknown values remain unknown; no speed,
quality or runtime-compatibility guarantees. Download variants share the plan;
the first variant is no longer labelled a recommended quant without evidence.
Model-list loading/empty/error/retry and invalid-response handling were tightened.

Authenticated, GET-only hardware reading calls the configured Lemonade system-info
endpoint and returns only CPU/memory/GPU fields. Shared memory is separate from
VRAM and RAM. Applying a reported capacity is explicit. CanIRun code/catalogues
were not imported; its hosted API is not used. See spec-model-guidance.md.

Verified: 404 web tests, typecheck/build; actual synthetic HTTP auth, GET-only,
field allowlisting, failure/retry; browser capability/fit/unknown states,
read/apply hardware, download-plan continuity, retry and responsive light/dark.
All checks avoid inference/model changes. A read-only production upstream query
verified system-info availability; noevia's new route is local only. Production
rechecked on fca1f19, all services healthy with zero restarts/OOM. No rollout.

Keyboard follow-up: explicit editor save/compare restores the previously focused
control after its busy state, without stealing focus from a control the user has
moved to. File navigation focuses the workspace heading; editing a new path does
not move focus on each keystroke. Verified by browser keyboard-save focus assertion
and the full Diary/model browser regressions; 404 web tests, typecheck/build pass.

Context rail correction: project/chat/Diary rails now use the continuous back
canvas without independent tint, blur or shadow. Diary's Markdown navigation
is on the right; at 1100px and below both Diary contexts flow below content,
without the former 150px cap. The landing overview keeps entries while the
context browser owns files, eliminating repeated memory/source sections.
Synthetic browser assertions cover placement, one file browser, transparency,
overflow and retained editor recovery at phone/tablet/desktop widths; light/dark
screenshots reviewed. 404 web tests, typecheck and build pass. Local preview
updated; not deployed.

Diary calendar landing follow-up (local): home now loads the current month with
Calendar selected and an above-calendar List toggle. List uses the selected
month's entries in descending yyyy-mm-dd order; month arrows browse history.
Switching views preserves the capture draft. One transparent composer dock sits
below either view; phone layout remains in flow so calendar dates are unobscured.
Day-specific writing and Markdown context remain available. Synthetic preview
has sample dates. Browser checks verify date ordering, draft retention and editor
recovery; 404 web tests, typecheck/build pass. Not deployed.
