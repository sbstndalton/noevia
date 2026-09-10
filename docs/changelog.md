# Changelog

Newest first. Merged from `QA-2026-09-08.md` and `review-fixes.md`.

Dependency audits report known advisories; they are not a guarantee that software
is free of vulnerabilities. Keep dependencies, the host, and the inference services
updated.

---

## 2026-09-10 — Diary landing reflects its actual contents

Empty diaries show a first-entry composer without a fictitious month. Populated
diaries show memory files, recent entry dates and tenant Raw Sources Markdown,
with month navigation below. Loading/errors do not masquerade as empty diaries.
Operator-wide import paths remain administrator-only. 281 web / 171 diary tests
(3 skipped), typecheck/build, synthetic browser and manual layout checks pass.
Rollout pending.

## 2026-09-10 — first-entry folders survive interrupted writes

New corpora receive Entries, AI Memory and Raw Sources seed READMEs with their
first logged exchange. Create-only writes use the existing durable journal and
ETag recovery, preserving existing files and avoiding duplicate entries on retry.
Existing/imported entry corpora are not migrated. AI Memory files join direct
context reads without copying legacy memory. 171 diary tests (3 skipped), 281 web
tests, typecheck/build and synthetic manual verification pass. Deployed `b34c33f`.

## 2026-09-10 — older entries remain available without semantic matches

The companion now falls back to bounded direct tenant file reads when semantic
retrieval is missing, empty or fails. It reads two explicit past ISO dates plus
three preceding days by default, within shared context limits. References state
the limited scope; successful semantic matches avoid extra reads. Existing daily
and monthly layouts remain the single source of truth. No write path changed.
166 diary tests (3 skipped), 281 web tests, typecheck/build pass. Deployed `23ba691`.

## 2026-09-10 — landing Diary messages follow the selected day

Landing messages previously stayed in a hidden home conversation. Send now opens
the destination day first, preserving its existing history, local/streamed replies,
retry state and optional-tool approval scope. Past-day selection and timestamps
stay unchanged; cancellation never starts capture. 281 web tests, typecheck/build,
157 diary tests (3 skipped), synthetic browser regressions and manual review pass.
Deployed as `5b1ef12`.


## 2026-09-10 — resumable member onboarding and explicit Diary choices

Invitations inherited a completed-onboarding default, skipping setup entirely.
New invitees now start incomplete, and members get Diary/preferences/passkeys
without administrator setup or global model controls. Saved Diary choices hydrate
the wizard immediately; updates persist with visible failures and retained focus.
Back and sign-out/resume clarify navigation; the dead-end models step is removed.
Completion preserves existing consent and defaults missing rows off. The separate
legacy feature backfill no longer re-enables missing rows on each restart.

Verification: 278 web tests, typecheck/build, 157 diary tests (3 skipped, two
existing warnings), synthetic real-server browser regression and manual review.
Application **`baf38aa`** is deployed to all three services, replacing `66af1ad`.
All 234 server tests passed in an isolated production-host image; 42 scoped live
assertions passed, including synthetic invitation/resume/completion/role boundaries
and cleanup. Public UI served the final bundle without resetting the existing user
into onboarding. Five synthetic accounts were removed; no real diary prompts or
corpus changes. `.bak.before-baf38aa` config/Compose/override and the previous
release remain for rollback. Tailscale was restored to stopped.


## 2026-09-10 — shared composers and opt-in Diary context

Project landing pages and Diary lacked the composer controls, and free chats could
not retain their own attachments/tool selection. All functional chat composers now
share the + menu. Diary extras are opt-in for the current session and off on reload;
its normal retrieval/capture remains active. Preparation uses the existing MCP
approvals and tool loop, then supplies bounded reference to the diary companion.
Attachments stay outside the diary corpus. See the audit for test evidence and
behavioral boundaries.


## 2026-09-10 — composer files and tool controls

Tools and uploads were buried outside the conversation. A + control now opens
a compact menu above the chat composer: Files and photos, Tools grouped into
Built-in/Connectors, and Model and routing. Project tool selections use the
existing permission-checked configuration route; all three write approvals remain.
Uploads retain the existing file limits, organized Nextcloud storage, and progress.
No skills or plugin execution features are implied by this menu.


## 2026-09-10 — unified uploads and visible processing

Application release `48027ef` replaces `e3b29bb` in production. One Sources upload
control now accepts non-archive originals up to 25 MB, including DOCX. Connected
storage receives Documents/Images/Text/Other subfolders; the UI uses the same
groups. Opaque formats remain stored-only, with authenticated original downloads
and explicit model-context disclosure. Images retain a bounded local cache for
inference; the 8 MB image-input budget is separate from the storage limit.

Earlier local image uploads are copied to connected storage on refresh. Transfer
percentage and per-file elapsed time are distinct from saving/extraction stages;
image chat exposes preparation status before model processing. The obsolete 1 MB
background request cap and 40-file refresh cap were corrected. The project quota
remains 60 total sources, with regression coverage for a 41-file refresh.

Verification: 256 web tests, typecheck/build, and 155 diary tests passed (3 skipped,
two existing dependency warnings). Local browser checks covered mixed uploads and
mobile source rows. Authenticated production checks uploaded synthetic PNG, PDF,
and DOCX files through one chooser, confirmed Documents/Images storage paths,
OCR-ready PDF metadata, original links, timing details, and successful refresh.
Image preparation feedback appeared at 0.2 seconds in the synthetic chat check;
the model correctly identified the shapes, colors, and ZEBRA-73 heading in 21.9
seconds. The synthetic chat and project were archived after verification.
The diary corpus and private financial files were not used for testing.

Deployment used the existing Tailscale configuration because the LAN route was
unavailable. All three service images use `48027ef`; prior release and
`.env.bak.before-48027ef` / Compose backups are retained for rollback. Tailscale
was restored to its previous stopped state after deployment and verification.


## 2026-09-10 — bounded reliability, OCR and image rollout

Production now runs `e3b29bb` (previous `cd717b0` retained). This includes the
agent deployment contract, duplicate tool-call protection, page-aware PDF source
retention/status, binary source reads, isolated local OCR, and image handling fixes.
All changes were pushed to main after 247 web tests, typecheck/build, 155 diary
tests (3 skipped), and three real OCR container tests passed.

Lemonade 10.8.0's Qwen 9B registration now loads its matching mmproj. Synthetic
inference recovered an invoice, dated/signed amounts, and total; authenticated
production chat identified a blue circle, orange triangle, and ZEBRA-73 from a
separate image, then correctly cited the scanned second PDF page and its values.
A synthetic mixed PDF uploaded through Nextcloud and showed OCR-ready status and
an Original PDF link. No real diary prompts or financial-document tests were used.

The live Compose Manager file now includes the internal OCR network and service;
web can reach OCR health, diary is healthy, and all three images use `e3b29bb`.
Compose/env backups carry `.bak.before-e3b29bb`; the Lemonade registration backup
is `user_models.json.bak.noevia-vision-20260910`. OCR preserves original/native
text, labels its output, and enforces documented resource limits. Existing PDFs
need refresh/re-upload. OCR accuracy, complex tables, and handwriting still need
human checking; interrupted polling after a server restart requires retry.


## 2026-09-08 — development continuation and QA

Based on a clean `0f8a9c1` checkout. The older UI master prompt was treated as
design context; much of its implementation was already present.

### Environment and build

- Fresh startup creates the state directory before writing its encryption key.
- **Dev, build and type-check scripts now invoke Node directly**, fixing the
  long-standing "`npm run typecheck` is broken" workaround. Vite uses the runner
  config loader, avoiding temporary writes inside the external dependency symlink.

### Projects and sources

- New project folders include the project ID, preventing same-name projects from
  sharing a folder. Existing paths preserved.
- Uploading to an older project creates its missing storage folder on demand.
  Without remote storage, text/PDF uploads remain usable as local sources. S3 uses
  a prefix instead of an unsupported directory operation.
- Image/document request caps account for base64 expansion while keeping
  decoded-byte limits — a 7 MB image no longer fails the advertised 8 MB limit.
- Failed source reads preserve the previous source text. Successful empty listings
  and explicit detachment still remove old sources.
- A refresh preserves uploads and folder changes made while it was awaiting
  storage. Opening a project refreshes attached folders, throttled to once a minute
  for the same folder selection.
- Invalid project settings no longer partly mutate the live project.
- Debounced edits merge different changed fields instead of dropping all but the
  last patch. The edit dialog awaits saving and retains input on failure.
- Model/routing/toolbox save errors are displayed rather than silently ignored or
  becoming unhandled rejections.

### Vision

- Probes are scoped to endpoint, credentials and model, with expiring results.
  Missing projectors and availability failures now have **distinct, actionable
  explanations** shown in chat — previously a 500 ("maybe missing mmproj") was
  conflated with a 400 ("model cannot do this"), which is what led to
  "Qwen3.5-9B is blind" being asserted wrongly.
- Image-description cache keys include the user, provider endpoint and full
  question. Provider authorization runs before image requests; vision requests
  refuse redirects and respond to chat cancellation.

### Tools and approvals

- Repeated tool calls across inference rounds retain distinct chip identities.
- Pending approvals keep their full arguments and all three decision buttons.

### UI and accessibility

- Mobile chat breadcrumbs truncate long names without hiding Settings or the
  inspector. Project headings reserve inspector space. Tool results use a compact
  layout; approval arguments remain fully visible and wrap.
- Mobile Settings uses a category selector so forms get full width. Provider fields
  have accessible labels. The diary navigation-expand control is restored on phones.
- Project/model dialogs use native modality, Escape dismissal and focus restoration.
  Keyboard activation of a card's child controls no longer opens the project.
  Filter/archive empty states are explicit.
- Creation uses shared text-file validation rather than reading arbitrary selected
  binaries as text. Project initials use theme text contrast; the initial browser
  theme colour matches the dark canvas.
- `MarkdownPreview`: parenthesized links and tables now render.

### Verification

Web **161 passed** (11 new regressions); diary **145 passed, 3 skipped** (no diary
implementation changes); typecheck, build and `git diff --check` all passed.

Browser checks used an isolated authenticated instance at localhost:8022 with
disposable state and a local inference simulator — no production diary messages,
files or tool writes were created. Phone (375), tablet (768) and desktop (1440)
layouts in both themes, plus chat overflow at 320/640/641/1024 with no clipping or
horizontal overflow. Exercised onboarding, project creation, model selection,
failed-chat retry, two successive clock-tool rounds, Markdown tables/code/
parenthesized links, settings, diary home/calendar/error states, coding preview and
keyboard modal/card controls.

Docker was unavailable on the Mac; container builds and Compose validation were not
run locally. A live RAG/embedding smoke test remains necessary.

### Deployment note

Read-only SSH confirmed DaServer still ran `0f8a9c1` with a healthy diary
container. The patch introduced no required environment variables. Publishing and
deployment were subsequently approved; rollout is recorded in the DaServer
changelog. Existing projects that already share a folder are **not** automatically
split or moved.

---

## Earlier — diary conversation and reliability update

Diary questions now receive thoughtful replies directly in the diary conversation.
**The separate Insights screen, reflection endpoints and activity badge were
removed.** The logger still preserves the user's own words separately from
assistant commentary.

Clearer diary and chat composers, consistent focus states, better text contrast,
calmer cards, mobile layout adjustments, reduced-motion support. Setup completion is
acknowledged by the server before exiting, and unfinished onboarding resumes after
sign-in.

### Reliability and security

- Streaming errors use SSE after headers are sent. Split SSE lines are retained; all
  provider fetch paths refuse redirects and respect cancellation signals.
- Retry identifies the exact failed final message and preserves earlier history.
- Provider deletion updates the correct private/shared collection.
- Diary edits report pending writes honestly. Durable invalidation prevents stale
  retrieval after a crash, and pending operations replay in order.
- S3 storage enforces conditional writes; a disposable capability probe rejects
  unsupported servers before writing diary data. Bucket listings paginate.
- Members can connect only to operator-approved origins, avoiding DNS-rebinding
  exposure from member-controlled endpoints. Existing shared providers remain
  usable — see `SECURITY.md` for `MEMBER_OUTBOUND_ORIGINS`.
- External import folders require administrator access. Requests, import reads,
  session histories and pending Nextcloud login flows are bounded.
- Tenant UUID validation is strict; legacy migration applies only to the designated
  owner. Cache eviction no longer closes active requests' resources.
- Browser security headers protect against framing and MIME sniffing. Node runtime
  builds use the lockfile without falling back to an unlocked install.
- Auxiliary inference uses the documented endpoint/key fallback.
- The Python installer was upgraded past a known advisory.

### Verification

Node suite covers provider deletion, first-round model failures, split SSE, redirect
refusal, request limits and approved-origin checks. Diary tests cover failed-edit
acknowledgment, crash recovery, stale-retrieval exclusion, empty-document cleanup
and refusal of nonconforming S3 stores. The UI was exercised with an isolated local
fixture using synthetic responses.

---

## 2026-09-09 — deployed `f6832bf`

Three commits shipped to DaServer, replacing `8a78172`:

- `d8a6f2c` journal poison pill — one malformed entry no longer blocks every
  subsequent diary write.
- `def7c18` state directory permissions — parents of a nested state path took the
  umask rather than `0o700`.
- `f6832bf` docs consolidated from ten files to nine; the old
  `noevia-design-system.md` palette was stale and would have reintroduced the
  fire-engine red the UI overhaul removed.

Verified before push: 162 node, 147 python + 3 skipped, typecheck clean, on `main`
rather than on the feature branch. Verified after deploy: both containers on
`:f6832bf`, diary healthy, the poison-pill fix present *inside the running
container*, `localhost:8021` and `https://cowork.daserver.work` both 200, no
errors or tracebacks in either container log since restart.

**Not yet verified against real data** — these need an authenticated browser
session and were not done: a real diary write (the poison-pill fix is in exactly
that path), a Nextcloud upload, and one MCP write approval.

Rollback: `releases/8a78172` is on disk; repoint `current` and `COWORK_VERSION`,
then rebuild. Env backup at `config/.env.bak.20260909203405`.

### Incident during this deploy

The working tree's entire `docs/` directory disappeared mid-session — all nine
files at once, after they were committed and pushed. This is the same Nextcloud
eviction that previously ate `dist/assets` and `node_modules`. Nothing was lost
(`git checkout -- docs/` restored it, and `origin/main` was never affected), but
it is a reminder that this checkout lives on a sync client that removes files
underneath you. Commit early; do not treat the working tree as durable storage.

## 2026-09-09 — aux model 404, found while verifying the deploy

`LLM_AUX_MODEL` was the literal string `default` on the live deployment, because
`DIARY_AUX_MODEL` was never set and every compose file fell back to that
placeholder. No backend serves a model by that name, so **every** summariser,
skip-classifier and index-maintenance call had been 404ing — for at least five
days before it was noticed.

It hid because the pipeline degrades gracefully: `summarizer failed (...);
logging verbatim assistant reply`. Entries kept being written correctly and only
lost their `— Topic` headers. September 5–9 have 0 topics across 75 time headers.

Fixed in three places, because a fix in only one of them leaves the trap armed
for the next deployment:

- **Live `.env`**: `DIARY_AUX_MODEL=gemma-4-E2B-it-GGUF-UD-Q4_K_XL`. Verified the
  aux model now returns 200 on the exact call that was failing.
- **compose.yaml, deploy/examples/unraid-compose-manager.yml, and the live
  compose-manager copy**: `${DIARY_AUX_MODEL:-${DIARY_CHAT_MODEL:-default}}`.
  This mirrors what line 36/37 already did for `llm.aux.base_url` and
  `api_key` — the aux *model* was simply never given the same fallback.
  All three interpolation cases verified against real `docker compose config`.
- **services/diary/agent/config.py**: `_resolve_aux_model()` treats an empty or
  placeholder aux model as "reuse the chat model" and logs a warning naming
  `DIARY_AUX_MODEL`. This catches every deployment path, not just compose. Four
  tests, including that an explicit aux model is never overridden and that a
  wholly unconfigured pair is left alone rather than guessed at.

Historic entries were **not** backfilled. `/api/relog` looks like the tool for it
and is not: it re-logs an exchange from the *current in-memory session* at
`now=datetime.now()`, with an empty `sub_header`. Pointed at old entries it would
append duplicates stamped today rather than repair anything.

Tests: 151 python (+4), 162 node.

Synthetic source refresh also passed through the browser's background polling
path. The QA project and chat were archived (recoverable); their invented fixtures
remain available for review. The temporary OCR test container and host fixtures
were removed. Production remains on the tested application release `e3b29bb`.

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


Shared-composer rollout: application `12ba04f` replaces `3320fc3`. All three
production images use the new tag. `.bak.before-12ba04f` environment/Compose
backups and the previous release are retained; no environment/schema additions
were needed. Diary health passed and web-to-OCR health returned 200. The live
authenticated browser confirmed the new Diary + menu and extras OFF by default.
No production diary prompts were sent, nor were extras enabled against the real
corpus. Execution/approval tests used isolated synthetic inference, MCP, and diary
fixtures; the earlier real MCP integration test remains recorded above. Temporary
QA servers/tabs were closed, viewport reset, and Tailscale returned to stopped.

Live reliability audit rollout: `4ec8269` is now deployed to all three services,
following `cfc3a05` and `12ba04f`. Fixed repeat legacy migration into new admin
accounts, stale image input after oversized replacement, and administrator
deletion blocked by issued invitation/recovery tokens. Deletion also preserves
the last active admin when other admins are disabled. All three fixes passed
live rechecks; 266 web tests, typecheck/build, 157 diary tests (3 skipped), and
222 server tests inside the built image passed. Real Nextcloud approvals, OCR,
vector retrieval and isolated diary capture were exercised. Synthetic accounts,
corpora and the QA Nextcloud folder were removed. No real diary prompts/corpus
changes. Backups `.bak.before-cfc3a05` and `.bak.before-4ec8269` and previous
releases retained. [Coverage and remaining concerns](live-audit-2026-09-10.md).

Composer model placement: `dc325d5` deployed to all services, replacing `4ec8269`.
Removed the chat-header model selector and placed it beside Send inside the text
composer, keeping the existing picker/routing behavior. Long labels truncate on
mobile. 266 web tests, typecheck/build and 157 diary tests (3 skipped) passed;
synthetic browser layout/switch/send checks and the live picker check passed.
Thinking-effort options are a future follow-up. `.bak.before-dc325d5` backups and
the prior release are retained; no environment/Compose changes were needed.

Shared composer controls: `66af1ad` deployed, replacing `dc325d5`. Project landing
and Diary home/day composers now share the model-button component and placement
used in free/project chats. Diary shows its fixed companion until extras are
enabled; the enabled picker configures optional context only. Thinking options
remain planned. Tests: 266 web, typecheck/build, 157 diary (3 skipped). Synthetic
mobile/desktop and light/dark checks, scoped picker checks, live project/Diary
checks and service health passed. No real diary prompts or corpus edits.
