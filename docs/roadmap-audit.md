# Roadmap audit — 2026-09-10

## Current handoff status — reconciled 2026-09-10

The status table and priority order below are current; dated follow-ups retain
evidence from earlier stages. Application **`baf38aa`** is deployed to all three
services, replacing `66af1ad`. Fresh verification: **278 web tests**, typecheck/build;
**157 diary tests passed, 3 skipped** (two existing dependency warnings). All
**234 server tests** passed in a disposable production-host container with networking
disabled and read-only repository fixtures. Synthetic browser regression, manual
UI review and scoped production checks passed; see the onboarding rollout below.

Reliability, PDF/OCR/image support, unified uploads, shared composer actions,
and composer model controls, and onboarding correctness have shipped. Diary extras remain OFF by default;
the companion pipeline remains active. Thinking controls are still planned.
Known limits include stored-only DOCX, model color errors, slow inference/tool
round trips, implausible throughput telemetry, and reasoning-only fallback text
reaching the final answer. See [live audit coverage](live-audit-2026-09-10.md);
passing checks do not imply exhaustive coverage or resolved model-quality issues.


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
| 2 / 5b: thinking modes | Not implemented | No reasoning-effort schema, override, badge, or verified-provider fallback in web code. `index.cjs` has `enable_thinking` suppression for a helper call, not the planned user-facing feature. Main streaming and non-streaming fallback bodies must both be considered. |
| 3: wizard restructure | Partial | Administrator flow is account → provider → diary → prefs → passkey; members start at diary. The dead-end models step is removed. Full diary-first/storage redesign remains deferred. |
| 3.5: invite onboarding | Complete and deployed (`baf38aa`) | New invitees explicitly start incomplete. Members receive Diary → preferences → passkey, with no bootstrap/provider/global-model step. Authenticated session state supplies the saved Diary choice before rendering. |
| 3.6: markOnboarded | Complete and deployed (`baf38aa`) | Existing choices are preserved atomically; missing rows mean no recorded consent and stay off. Reproduced a separate repeated legacy backfill enabling missing rows on restart; it now runs only once. Existing onboarded accounts are unchanged. |
| 4a: diary scaffolding | Not implemented as specified | No first-entry scaffold for Entries, AI Memory, and Raw Sources in diary agent code. Existing storage lazily creates paths. |
| 4b: diary zero state | Not implemented as specified | `DiaryView.tsx` still has the shared landing; month discovery adds the current month even when there are no entries. No dedicated first-entry composer / three-panel populated split. |
| 4c: landing-to-day navigation | Implemented; rollout pending | Send pins the browser-local date and routes history, streamed/local replies, errors and optional-tool scope to that day before preparation begins. Synthetic browser-local/server-backed regressions pass. |
| 4d: diary visual/refactor work | Partial / defer cosmetics | Broad visual updates shipped, but the specified component split and new panel behavior have not. UI is now accepted; implement necessary behavior without restarting cosmetic work. |
| 5a: duplicate tool-call guard | Complete and deployed | `tool-exchange.cjs` is instantiated inside `handleChat`; canonical arguments, exchange-only result reuse, read invalidation on attempted writes, and handler-level mocked streaming/fallback regression coverage. See Workstream 5a for denial/failure/validation semantics. |
| 5: deferred tool disclosure; 5c: planner/executor | Research only | Static toolbox cap/budget resolution and message-level Fast/Smart routing remain. No dynamic find_tools or phase-based planner/executor implementation found. |
| 5d: offline Wikipedia | Not implemented; optional | No Wikipedia toolbox found. Requires a selected available service; it is not a prerequisite for OCR, skills, or correctness fixes. |
| 5e: harness framing | Partial | Already explained in `docs/agent-brief.md`; root agent entry points now link the brief. |
| 6a: timezone | Complete, including production | Both Compose definitions, `.env.example`, wizard timezone helper, and timezone regression tests exist. Live read-only check: TZ=America/New_York, EDT -0400. The old statement that the live copy remains unapplied is stale. |
| 6b: direct diary context | Partial; original claim too broad | `agent/context.py` directly reads the current day, standing sections, and memory files. Older entries still use retrieval; a bounded older-entry fallback is the remaining design question. The browser-local path also supplies local reference material. |
| 6c / 6d: memory ownership/privacy | Architectural constraints | Disk-backed diary memory already feeds context. Keep the single-store and no-cross-profile diary-content boundaries; these are not standalone missing UI features. |
| 7a: Unraid state default | Original example hazard addressed | `deploy/examples/unraid-compose-manager.yml` requires COWORK_STATE_DIR explicitly. Generic `compose.yaml` and the manifest still use ./state. No named-volume default or explicit /boot-path rejection exists; those are separate remaining decisions. |
| 7b / 7c: local storage UX | Partial | Storage clients and browser-local folder access exist, but they do not expose server-held files to other devices. The two-choice appliance setup flow is absent. |
| 7d / 7e / 7h / 7i: served storage | Not implemented | No noevia WebDAV server or noevia-issued app-password lifecycle found. Outbound PROPFIND/MKCOL and saved Nextcloud credentials are client functions, not these features. No managed corpus volume default / Off-LAN-Public sharing wizard. |
| 7f / 7g: endpoint and proxy notes | Design/reference material | These describe requirements and prior experiments, not shipped endpoint features. The roadmap repeats 7g/7h sections; reconcile before implementing storage. |
| 8: PDFs/OCR/images | Implemented and deployed | Original retention, native pages, isolated OCR, asynchronous status, bounded binary reads, image projector configuration, unified categorized uploads and progress are shipped. DOCX remains stored-only; OCR/vision accuracy and inference latency remain limitations. See the follow-ups and live audit report. |
| 9: skills | Planning only | No selected skills format, execution model, or lifecycle. Coordinate with existing instructions/toolboxes rather than adding a parallel framework. |

## Corrected priority order

Completed prerequisites: Workstreams 1 and 5a, PDF/OCR/image support, shared
composers/model controls, and onboarding correctness (3.5/3.6) are deployed.

1. **Diary navigation:** Workstream 4c, using synthetic exchanges. Preserve the
   write path, timestamps, history, cancellation, and optional-tool approval scope.
   Scaffolding/zero state (4a/4b) is a separate follow-up requiring data-model review.
2. **Thinking modes:** Workstreams 2 / 5b. Put eventual controls beside the shared
   composer model selector; verify budgets, model capabilities, streaming/fallback
   behavior, and Diary companion versus extras scope first.
3. **Document/model follow-ups:** Scope DOCX readers, OCR/vision accuracy,
   latency, telemetry and reasoning-only fallback separately using the live audit.
4. **Storage architecture:** Workstream 7 needs a scoped spec; app passwords must
   precede exposing DAV. Existing outbound Nextcloud support is not a DAV server.
5. **Skills and tool research:** Workstream 9 and relevant parts of 5. Defer
   optional Wikipedia and planner/executor experiments until concretely needed.

The 2026-09-10 continuation request now authorizes continuing the full roadmap,
with testing and a Git push after each implemented item. Keep each change bounded
and reviewable; prior production rollout authorization remains in force. Preserve the accepted sidebar and current composer behavior.

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
