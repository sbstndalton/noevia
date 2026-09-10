# Roadmap audit — 2026-09-10

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
| UI/sidebar | Accepted, complete for now | Deployed `cd717b0`; see `ui-reference-review.md`. Do not reopen the visual redesign. |
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
