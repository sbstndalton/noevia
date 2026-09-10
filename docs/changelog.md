# Changelog

Newest first. Merged from `QA-2026-09-08.md` and `review-fixes.md`.

Dependency audits report known advisories; they are not a guarantee that software
is free of vulnerabilities. Keep dependencies, the host, and the inference services
updated.

---

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
