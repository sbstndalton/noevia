### 2026-09-21 — Auto-tune says what it is doing, as it does it (f66ecd2)

A run is 5–15 minutes of a progress bar that can sit still for a minute while the engine
loads, and a still screen reads as nothing happening. Auto-tune now keeps a timed, line-by-line
account: each test and the exact settings it writes, "still loading · 25s" while the engine
loads, every workload's speed and draft acceptance, why a candidate was rejected, what it chose
and why, and whether the original settings were put back after a cancel. It follows the newest
line while running, and folds away once the run is done. The panel now refreshes every second.


### 2026-09-21 — A note's properties, and the tags a vault really uses (5b0e531)

A leading YAML block is shown as the properties it is rather than as three dashes and a list of
keys pretending to be prose; a line the reader cannot parse is shown as written rather than
dropped. The tag filter now also reads the `tags:` property, which is where a diary written in
Obsidian keeps its tags — excluding it meant the filter quietly missed most of them.


### 2026-09-21 — Documents in folders could not be read (c237480)

The Docling sidecar refuses a name that could be a path, and noevia's names are paths, so every
document inside a folder failed with "Document extraction unavailable (HTTP 400)" while a file
at the root worked. noevia now sends the file name. A 400 is also named for what it is — noevia
sending the document wrongly — and stays retryable, so the documents it broke read again on the
next sync rather than keeping a cached failure. Rollback 71f1ab0.


### 2026-09-21 — Typing [[ offers the files you could mean (71f1ab0)

The Markdown editor suggests the files in the folder as soon as you type `[[`, inserts the
shortest name that is unambiguous and closes the brackets for you. Arrow keys choose, Enter or
click inserts, Escape leaves what you typed alone. It stays a textarea throughout — the
suggestions are an offer beside it, not a form control.


### 2026-09-21 — The Docling sidecar is deployed

Document extraction now uses the sidecar that was verified in September and then sat unused:
reading order, table structure, and the Office, OpenDocument, HTML and image formats that were
previously stored whole and unread. CPU-only, so it never contends with the engine for VRAM.


### 2026-09-21 — Obsidian-style [[links]] in the Diary (f72c2a6)

A vault written in Obsidian is full of `[[wiki links]]`, and noevia rendered every one as
literal text and found none of them when asked what links to a file. They now render as links,
open the file, and count as backlinks alongside relative Markdown links. Aliases, heading and
block anchors and the `![[embed]]` form are all recognised; a link to a file that is not there
is shown as the writer wrote it rather than as a button that opens nothing. Nothing is
rewritten: the vault stays exactly as its owner left it.


### 2026-09-21 — Connect an app to the Diary in Settings (6eb1698)

Connected apps is a section of Settings → Diary & storage: name it, copy the credential once,
revoke it in one click. It replaces `diary-connector-admin.cjs`, a script an administrator had
to run on the server. Also removed: two components nothing rendered, and the CSS of two
interfaces that no longer exist (the old Code sidebar and the old Diary landing).


### 2026-09-21 — Code mode runs, and is on (f57dd21)

noevia writes the coding harness's own configuration file — every action class asking, one model
endpoint, no self-update — and refuses a harness whose configuration it cannot pin. A repository
owned by the harness user is used instead of being reported as "Not a git repository". The
sandbox is deployed on an internal network whose only other member is the engine, and a real
task fixed the scratch fixture end to end. Rollback 39b0970.


### 2026-09-21 — Usage: peak hour, favourite model, tool calls (b126eb6)

The usage file gained two counters: replies by hour of the local clock, and one count per tool
call recorded where the call runs. Usage shows a peak hour on a readable clock, the busiest
model and a per-tool list. Older files read as empty rather than needing a migration, and an
account with nothing recorded says so. Rollback 05cc153.


### 2026-09-21 — The project screen (05cc153)

Header actions, context chips above the composer, an Outputs row for the documents noevia made
in the project, labelled recent chats, and a context panel with Context and a Scheduled row
marked not yet available. Covered by `qa/project-screen.cjs` at 1440 light and 390 dark.
Rollback 5379771.


### 2026-09-21 — Nextcloud is a connector of its own (5379771)

Plugins → Connected lists Nextcloud beside Google Drive. It reuses the connection set under
Settings → Diary & storage, says plainly when that connection is missing, not configured on
this server, or at an address outside `MCP_NEXTCLOUD_ORIGINS`, lists the toolboxes it offers,
and carries the same per-tool permissions as Drive — writes can never be “Always allow”.
Rollback 76865e1.


### 2026-09-21 — Routing split; Projects tab (76865e1)

Routing keeps the Auto roles; thinking effort is its own panel; per-project routing is its own
tab. Rollback a73a72d.


### 2026-09-20 — Models page: one tab bar (a73a72d)

Routing, Hardware, Benchmarks and Prompts are tabs instead of sections stacked under the model
list. Rollback d99c066.


### 2026-09-20 — README, icon set, last Cowork prose (d99c066)

The logo's two squares now read as depth in light mode; adds a favicon, Apple touch icon,
maskable icons and a web manifest (none existed). README describes what noevia does today.
Rollback 06f5aa4.


### 2026-09-20 — Add an MCP server by URL (06f5aa4)

Admins can add a server that is not in the registry, with an optional sign-in header (shared
or per account) or OAuth. Same checks as a directory server. Rollback 8b458e9.


### 2026-09-20 — Routing panel spacing and width (8b458e9)

The four Auto role pickers sit two to a row; Default thinking effort is separated from the
save button; disclosure rows and panels share one spacing scale. Rollback b8d78a9.


### 2026-09-20 — The UI and MCP branch is merged into main (b8d78a9)

An overnight deploy of main had replaced the 2026-09-19 UI and MCP work, which was only on
`claude/blissful-brown-v86y3o`. Merged (two conflicts: appended tool-routing tests and
release notes, both kept) and deployed together with Docling and tool-result compaction.
823 server tests, 74 QA suites. Rollback aad6216.


### 2026-09-19 — Models page: faster, cards side by side, one toolbar (06f9402)

The list shows at once while file details load; the folder scan is cached server-side.
Cards up to three per row; tabs, search and filters on one line. Rollback d459867.


### 2026-09-19 — Diary from Code; model and tools panel reworked (d459867)

Diary opens from Code mode. The model panel spreads model and tools side by side on wide
screens, with a segmented Auto/Manual switch, one-line model rows, compact tools and a budget
meter, on an opaque surface. Rollback da5dfa9.


### 2026-09-19 — Per-account API keys for directory MCP servers (da5dfa9)

Admins choose 'Each person uses their own key' or 'Everyone uses this key'; each account adds
its own key in Plugins → Connected and only then gets the server's tools. Rollback 3f3ff1e.


### 2026-09-19 — Hand-registered apps for MCP sign-in (3f3ff1e)

Sign-in services without self-registration: the admin registers an app with the shown return
address and enters its client ID (and secret). Stored encrypted; replacing it signs everyone
out. Rollback c173952.


### 2026-09-19 — Per-account OAuth sign-in for directory MCP servers (c173952)

Servers that ask for OAuth are added through a sign-in tab; each account signs in for itself
from Plugins → Connected and only then is offered the server's tools. PKCE, resource
indicator, refresh; tokens encrypted per account. Rollback e4fc0d3.


### 2026-09-19 — Sign-in keys for directory MCP servers (e4fc0d3)

Hosted servers that need a key can be added: checked before saving, stored encrypted, never
returned, sent only to that server in its declared headers; changeable; admins only. Rollback
6330ea8.


### 2026-09-19 — Skills auto-load; skills and MCP servers from the directory; long model names (6330ea8)

A message matching one enabled skill gets its reviewed instructions. Plugins → Skills adds a
published SKILL.md to a project (arrives needing review). Admins can add hosted MCP servers
from the registry: own toolbox, no credentials, every tool asks, removable. Model names keep
their start and quantization ending; the model list filters. Nine QA suites updated; all 74
pass. Rollback a163543.


### 2026-09-19 — Settings no longer reopens on a quick reload (a163543)

Closing Settings forgets it as the reload target at once. qa/mtp and qa/google-drive pass again.
Rollback 957e972.


### 2026-09-19 — Model picker Tune button back to 44px (957e972)

A later generic button rule had shrunk it to 30px. Rollback ba95afa.


### 2026-09-19 — Engine holds the embedding model beside the chat model (ba95afa)

llama `--models-max 2` (live override edited, backup kept); before a chat model is used, other
chat models are unloaded and the embedding model stays. Tool routing (already on via
NOEVIA_FEATURE_TOOL_ROUTER=true) no longer evicts the chat model. Rollback 41cb2aa.


### 2026-09-19 — Tool routing: "Using:" line and ask-for-more (41cb2aa)

When routing narrows a message's toolboxes the reply says which, and the model can ask once for
the rest of the project's tools. Routing stays off: the live engine holds one model
(`--models-max 1`), so the embedding model would evict the chat model on every message.
Rollback 363171c.


### 2026-09-19 — Re-fit after zoom (363171c)

The page re-stretches after zooming in and back out on iOS. Rollback c71a30d.


### 2026-09-19 — Tall screens: full layout from 520px, pages grow, greeting centred (c71a30d)

A zoomed-out phone keeps the sidebar from 520px wide; short pages grow up to 125% on phones and
tablets; the empty chat greeting sits mid-height. Rollback 70631b0.


### 2026-09-19 — Shrink-to-fit for slightly-too-tall pages and menus (70631b0)

Pages and menus that overflow by a little are scaled just enough to fit (never below 82%);
long lists keep their size and scroll. Rollback f87b157.


### 2026-09-19 — One sidebar for Chat and Code; Plugins page (f87b157)

Code mode reuses the chat sidebar (current look, switch in the header, aligned rail, shared
collapse). Closing Settings keeps you in Code. New chat floats over the list; the collapsed
rail names items on hover; Chat/Code eases in. Google Drive moved from Settings to Plugins,
which also browses the MCP registry and Anthropic's skills. Rollback 027bd00.


### 2026-09-18 — iOS keyboard fix; web image flattened (027bd00)

The keyboard no longer pushes the page up on iOS. The web image had hit Docker's 127-layer
limit; overlay-release.sh now flattens it automatically past 100 layers. Rollback d995cd9.


### 2026-09-18 — Composer focus, iOS keyboard, phone Settings (d995cd9)

No square focus ring in the composer; the app follows the iOS keyboard; legacy narrow phone
Settings rules removed. Rollback 7326ac0.


### 2026-09-18 — Visual pass (7326ac0)

Legibility sweep across sizes, materials and themes with real device user agents; fixed the
phone composer row, phone Settings width, sidebar row alignment. Rollback 4c151be.


### 2026-09-18 — Sidebar header and phone drawer like Claude's (4c151be)

Small Chat/Code switch beside the logo; full-width phone drawer with search on top; the
drawer closes when you switch mode. Rollback 5cd033b.


### 2026-09-18 — Diary in the bottom bar, sliding Chat/Code, project colours (5cd033b)

Diary beside Search; liquid-glass Chat/Code thumb; phone Code drawer works; project colours
everywhere. Rollback 5a0e026.


### 2026-09-18 — Icon centring scoped; row options beside the title (5a0e026)

Only icon-only buttons centre their icon; sidebar row options no longer cover the title.
Rollback 350050e.


### 2026-09-18 — Composer like Claude's, SVG icons (350050e)

Centred SVG + with a files-and-tools menu (no duplicate model entry), Thinking as a menu of
levels, Code keeps a closed sidebar, every icon an SVG and centred. Rollback 91a89ba.


### 2026-09-18 — Account menu and Search like Claude (91a89ba)

Light/dark in the account menu, Search beside the account, account menu unclipped from
the rail, clean rail Chat/Code, no blank page entering Code. Rollback 94909d3.


### 2026-09-18 — Collapsed sidebar like ChatGPT's (94909d3)

Icon-only rail with the avatar at the bottom, remembered per device, expands from its
empty space. Rollback 4152d15.


### 2026-09-18 — Settings and sidebar organised like ChatGPT (4152d15)

Sidebar order Pinned, Projects, Recent chats. Settings is one flat list: General, …,
Security and login, Account; renamed pages, same content. Rollback 95eacd6.


### 2026-09-18 — Sidebar as one scrolling plane (4ea3282, 95eacd6)

Like ChatGPT: one scrolling rail, Diary and Plugins with the top destinations, flat
Projects/Pinned/Recent lists, only the account pinned, every chat listed. Rollback 4ea3282.


### 2026-09-18 — Material 3 and phone fixes (265c650, 6930549)

The Material material is now Material 3 component by component; touch fields are 16px
everywhere; narrow Appearance controls fit; Projects counts active projects; sidebar lists
never collapse to their heading. Two guarded overlays after verified backups; five
services healthy. Rollback 265c650.


### 2026-09-18 — Phone review fixes (3d20de0, a2a1c8e, e777259)

Three guarded web-only overlays over d11cfac, each after a verified appdata backup.
The phone drawer is whole from any view, Diary/Plugins are never under the footer,
row menus are no longer clipped, theme previews and the selected ring are correct,
Settings rows align, the strip no longer reports a false outage at start, and desktop
list headings stay in view. Five services healthy after each. Rollback a2a1c8e.


### 2026-09-18 — UI overhaul release 3 and phone-review fixes

Deployed d11cfac over ab2720a as a web-only overlay (no dependency changes). 861 web tests,
typecheck, design lint and a fresh build passed first; appdata backup ab_20260918_112354.
Five services healthy, zero restarts, native engine untouched. Live browser QA was partial
(write-approval card, phone width, themes and accents still owed). No real Diary corpus used.
Rollback ab2720a with .env.bak.before-d11cfac; see deployment.md.


## 2026-09-14 — Qualified direct native inference in production

### 2026-09-14 — Markdown date/tag filters

Deployed 48432fe: bounded stored-file search supports inclusive filename dates and
whole hashtags, alone or combined with text. 426 web tests, 343 Linux image tests,
CI and synthetic six-size/two-theme editor checks passed. Production health and
ordinary-chat smoke test passed; no real Diary corpus used.


### 2026-09-14 — native model UI and mobile approvals

Deployed 02495a7: embedding/reranking excluded from chat selection, accurate native
MTP guidance, 44-pixel approval targets. Full arguments and three decisions verified
in six viewports/both themes. 424 web tests, 343 exact-image server tests and CI
passed. Production synthetic chat and all four service health checks passed.


Switched the existing 2570a02 app release to pinned native llama.cpp with guarded
GPU and isolated app/client workload tests. Preserved existing model IDs, shared
provider settings and rollback backups; retained Lemonade stopped for recovery.
Verified live phone chat, 32k context and actual MTP counters; archived synthetic
verification chat. Added repeatable native and populated mobile QA. No real Diary
corpus testing, migration or reindex. See deployment.md for exact rollback.

# Changelog

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


Newest first. Merged from `QA-2026-09-08.md` and `review-fixes.md`.

Dependency audits report known advisories; they are not a guarantee that software
is free of vulnerabilities. Keep dependencies, the host, and the inference services
updated.

---

## Calendar landing rollout — 2026-09-14

All three services run **5894266**, replacing a6d15c3. Diary opens on the current
month with Calendar selected, a List toggle above, and the composer below.
404 local web tests, typecheck/build and synthetic responsive/draft recovery
checks pass; the candidate passes 324 serial Linux server tests. Diary/OCR image
IDs are identical to the prior release's verified images (199/13 tests).
Mount preflight passed; all services healthy, zero restarts/OOM; web and OCR
health return 200. Public JS/CSS hashes match index-CdTrv7d0.js and
index-Bm_DWXB9.css. Authenticated production Diary opens with Calendar selected
and date markers loaded. No prompts sent or corpus edits. Retain a6d15c3 and
.bak.before-5894266 configuration backups for rollback. This record is
documentation only; deployed application source remains 5894266.

## Diary workspace, model guidance and context rails — 2026-09-14

Production now runs **a6d15c3** on web, Diary and OCR, replacing fca1f19.
Includes guarded Markdown editing/recovery/navigation, explicit hardware and
memory guidance, and continuous context rails that move below narrow content.
GitHub main includes all five application commits.

Validation: 404 local web tests, typecheck/build and synthetic responsive editor
checks pass. Exact candidate images pass 324 serial Linux server tests, 199 Diary
tests (two existing dependency warnings), and all 13 OCR tests with fixtures.
The installed writable-mount preflight passed. All three services are healthy
with zero restarts/OOM; web setup-status and internal OCR return HTTP 200.
Public JS/CSS hashes match the tested build (index-CXIpF5Wf.js and
index-DGAF1v_V.css). Authenticated production reload succeeds, and the project
view has one transparent context rail. No real Diary prompts or corpus edits.

Retain fca1f19 and config/Compose backups .bak.before-a6d15c3 for rollback.
No environment schema, mounts or model configuration changes. This documentation
commit records the rollout; deployed application source remains a6d15c3.

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

## 2026-09-10 — shared Diary server connector and Nextcloud push repair

Deployed `12a1646`: dedicated revocable Diary credentials and live version-checked
Markdown tools. Stale saves conflict rather than overwriting newer files. Private
Claude plugin prepared; import and a real Claude round trip remain outstanding.
The plugin identifies itself as `noevia-diary/1.0` because production rejects the
default Python client identifier. Synthetic tests pass; no corpus edits performed.
Nextcloud push now uses its internal Apache callback; six self-tests pass before
and after restart. Rerun the repair after AIO recreates the push container.

## 2026-09-10 — oversized PDFs and native local-Qwen thinking

Deployed `ddbe852` (including `2408c32`). PDFs up to 60 MB receive asynchronous
native-text extraction and image compression before the 25 MB storage limit is
applied. Validated compressed PDFs and labelled text-only fallbacks use distinct
filenames; originals remain on the user's computer. Invalid, encrypted and
unrecoverable inputs fail without replacing existing sources. Local Qwen Low/High
now uses the actual thinking-template switch rather than a hint. Default remains
provider default. The exact installed 9B GGUF lacks MTP weights; support in the
original architecture does not make this file MTP-capable.

329 web tests, typecheck/build, synthetic browser checks, 281 Linux server and
13 real worker tests passed. Health/public assets verified. Shared Diary editing
is designed around version-checked server access; the Claude adapter is not yet
configured. Nextcloud's push self-test found a reverse-proxy trust failure, while
Mac upload-queue health remains unverified. See `spec-diary-shared-editing.md`.
No real Diary writes, corpus reconciliation or model changes were performed.

## 2026-09-10 — MTP controls, acceptance and fixed inference footer

Deployed `cac1778`, including `df8a486` (New chat launch) and `8eb7b99` (native
MTP Yes/No load controls and permanent inference footer). Chat and Diary show
actual acceptance: cumulative backend counters when available, otherwise the
current user's last response timings, labelled accordingly. Installed llama.cpp
b9632 uses the latter and updates at completion. Unsupported models explain why
MTP cannot be enabled; existing GPU/cache/context settings survive changes.

325 web tests, 178 Diary tests (3 skipped), typecheck/build, synthetic browser
checks, 277 isolated Linux server tests and eight worker tests pass. The Diary
wheel-scroll regression timed out during concurrent browser runs and passed on
its isolated rerun. All three services run `cac1778` with zero restarts/OOM;
Diary healthy, web/OCR 200, public assets match. No production model loads or
real Diary corpus tests. Multi-GPU benchmarking and compatible external draft
models remain experiments. Broader roadmap testing pause continues.

## 2026-09-10 — live Diary progress and long-request connection

Deployed `3ef0501`. Diary now streams real provider thinking/answer output while
retrieval and capture stages report their progress with an elapsed timer. Optional
tool traces stay on their turn. Immediate response headers and keep-alives prevent
silent long-running exchanges from waiting for capture before responding. Proxy
HTML is sanitized, interrupted saves are explicitly unconfirmed, and there is no
automatic resend. Switching app views keeps the mounted exchange; full page reload
recovery remains open. 319 web tests, typecheck/build, 177 Diary tests (3 skips),
synthetic browser regressions, 271 Linux server and eight worker tests passed.
All services healthy; public build assets match. Broader roadmap remains paused.

## 2026-09-10 — Diary reading and reasoning feedback

Deployed `ecaaa73`: saved summaries are a separate disclosure during the active
conversation; the day composer stays outside scrolling content. Diary and normal
chat stop following output when the reader scrolls up. Provider reasoning reaches
the Diary thinking disclosure separately from journal text and follow-up history.
Diary reasoning arrives at completion, only when the provider supplies it; live
Diary streaming and durable full conversation history remain open.
315 web tests, typecheck/build, 172 Diary tests (3 skips), synthetic browser checks,
267 candidate Linux server tests and eight worker tests passed. All three services
run the release, public assets match, zero restarts/OOM. Broader roadmap paused.

## 2026-09-10 — skill metadata names the file to load

The existing skill index now supplies exact filenames, escapes metadata as JSON,
and bounds catalogue size. Tool permissions and source loading remain unchanged.
314 web tests, typecheck/build and 171 Diary tests (3 skipped) pass, including a
real-handler prompt assertion. Full instruction-skill lifecycle remains planned.
Deployed `79cd24f` after 267 Linux server and eight worker tests. Wizard and
limited default-off DAV shipped in `9e2bfbb`.

## 2026-09-10 — explicit Diary and storage choices during setup

Fresh setup asks Diary/chat before account creation. Storage offers server-held
or existing external service choices; skipping and failed saves preserve the
configuration. The picker waits for saved settings before editing or saving.
Admin preferences include the existing thinking default. 310 web tests,
typecheck/build, 171 Diary tests (3 skipped) and expanded synthetic browser checks
pass. Existing completed users remain completed. Rollout pending.

## 2026-09-10 — optional bounded Diary file sharing

Added a separate, default-off listener and per-user sharing controls. Supported
Markdown reads/property lists/conditional writes use the existing tenant file API.
App-password scope and configured transport are enforced. No port is published by
default. Full DAV/file-manager compatibility remains open. 310 web / 171 diary
(3 skipped), typecheck/build and synthetic real-app browser checks pass. Rollout
pending; production sharing will remain off.

## 2026-09-10 — revocable device app passwords

Per-user name/scope/date metadata, shown-once random secrets, Argon2id hashes and
individual revocation are available in Profile & security. Credentials do not
permit account login or chat. Sharing remains unavailable; no new listener opens.
304 web / 171 diary tests (3 skipped), typecheck/build and synthetic real-app
browser checks pass. 257 Linux server and eight worker tests passed; deployed `2525de5`.

## 2026-09-10 — DOCX main-body text and tables

Unified uploads and connected-folder refresh retain originals and extract bounded
DOCX body/table text in the private worker, with explicit partial-coverage labels.
Malformed replacements clear stale text and remain downloadable; no dependencies
or corpus changes. 301 web / 171 diary tests (3 skipped), typecheck/build, six
local worker tests and synthetic real-worker browser QA pass. 254 candidate Linux server and eight worker tests passed; deployed `e18f1de`. See the roadmap audit for parser limits.

## 2026-09-10 — engine throughput omits unstable short samples

The display labels the engine rate as reported and omits invalid or sub-second
count/rate samples instead of displaying timer-dominated spikes. Valid longer
samples remain untouched; missing values stay unavailable. 297 web / 171 diary
tests (3 skipped), typecheck/build, live read-only sample and manual UI check pass.
This is sample filtering, not a repaired upstream benchmark. Deployed `3b1e256`.

## 2026-09-10 — reasoning-only output is no longer presented as an answer

The final-answer channel now reports that no final answer was returned instead of
copying internal narration. Per-round tracking covers tool continuations, retaining
tool results and separate reasoning. No extra inference/tool retries. 295 web /
171 diary tests (3 skipped), typecheck/build and synthetic real-server browser
verification pass. Model output quality remains a separate limitation. Deployed `34df7c2`.

## 2026-09-10 — thinking effort reports what the provider receives

Added admin defaults, project/free-chat overrides and optional Diary extras effort
controls beside model selection. Documented GPT-5.4 on OpenAI receives a parameter;
other pairs get labelled hints. High hints request an explicit 8,192-token budget,
with field-rejection fallback. Default leaves the request unchanged. The companion
and approval gate remain unchanged. 292 web / 171 diary tests (3 skipped),
typecheck/build, synthetic real-server/browser checks and local inference pass.
Uncapped budgets and wider provider verification remain out of scope for this v1.
Deployed `6570c51`.

## 2026-09-10 — Diary components are easier to maintain

Landing, calendar and context sidebar are extracted from dense inline JSX.
Existing navigation, storage and composer behavior remains; Up honors busy like
other file navigation. 281 web / 171 diary tests (3 skipped), typecheck/build,
both synthetic browser suites and manual calendar review pass. Deployed `7a34a0a`.

## 2026-09-10 — Diary landing reflects its actual contents

Empty diaries show a first-entry composer without a fictitious month. Populated
diaries show memory files, recent entry dates and tenant Raw Sources Markdown,
with month navigation below. Loading/errors do not masquerade as empty diaries.
Operator-wide import paths remain administrator-only. 281 web / 171 diary tests
(3 skipped), typecheck/build, synthetic browser and manual layout checks pass.
Deployed `8edacf7`.

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
releases retained. [Coverage and remaining concerns](roadmap.md).

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

## Model manager: settings-native styling, layout mode, working search — 2026-09-17

Settings → Models & routing now draws on the same surfaces, radii, type scale and control
sizes as the rest of the settings pane; see design-system.md. No class names or tab
structure changed.

Hugging Face search no longer asks the hub for `full=true`. That parameter existed only to
fill in a per-repo GGUF file count, and it made the hub serialize every sibling file of
every hit — against the client's 20s timeout an ordinary browse of the top 30 GGUF repos
could time out and surface as "Network error" with an empty list. The count is now shown
only when the hub volunteers it. A named search that the `gguf` tag filter answers with
nothing is retried once without the filter and narrowed to repos that look like GGUF, so a
repo the hub has not tagged is still findable; browse mode (no query) is not retried, since
an untagged top-30 is not a GGUF browse. Failures are reported with the reason — a 401/403
points at the saved token, a 429 explains that a token raises the rate limit — instead of a
bare status code, and owner avatars, which noevia's Download tab never renders, can no
longer fail the search. Changing Sort by re-runs the search, and the empty state
distinguishes "nothing matched your search" from "the browse list came back empty".

New: a Layout control (Automatic / Phone / Desktop) backed by `public/layout-mode.js` and
user-agent detection. It sits in Settings → Appearance.

Verified locally: `npm run typecheck` and `npm run build` clean; web tests unchanged from
this checkout's baseline (274 pass, 45 pre-existing environment failures, identical before
and after); model-manager Python tests 19 passed, including 8 new ones covering the search
query, both fallbacks and the error messages. The hub itself was not reachable from the
development environment, so the search changes are verified against a mocked hub only.

## Merged main (PR #1) into the model-tuning branch — 2026-09-17

Four files conflicted, all of them touched by both PR #1 and Discover. Decisions:

- **`noevia.css`** — PR #1's surfaces win: `--bg-surface` on `--border-subtle`,
  `--radius-panel` for panels, 14px for rows, tiles, results and tables,
  `--radius-control` for fields, and the shared glass block with its reduced-transparency
  fallback. Its pixel sizes are re-expressed as this branch's type-scale roles, which is
  the same value in every rule the two sides both set, and the 550 weights it carried over
  are normalised to 600 — both are `lint:design` rules rather than a look. Each side's
  appended block is kept whole; PR #1's shared material goes last, as its comment assumes.
- **`api.py`** — Discover's endpoint wins, with one correction. It caught
  `httpx.HTTPStatusError`/`httpx.HTTPError`, which `search_models` no longer raises; taken
  verbatim, every rate-limited or unreachable hub would have become an unhandled 500
  instead of a readable error, and silently, because the types simply stop lining up. It
  now catches `hf.HfSearchError`, and the avatar lookup is guarded again. Both are pinned
  by new tests in `test_api.py`; the first fails against the unmerged endpoint.
- **`DownloadTab.tsx`** — Discover wins outright. Its header search box, sort control and
  filters supersede PR #1's local ones, and its `[sort]` effect already re-runs the search,
  so that fix is retired. Carried across: the query is trimmed, a new search collapses an
  expanded repository (the sort and filter paths did this, pressing Enter did not), a
  malformed body can no longer crash the list, the caption reads the term the results were
  actually fetched for rather than the 400ms-behind search box, and a hub error offers a
  retry.
- **`SettingsShell.tsx`** — this branch's settings restructure wins; the `general` section
  PR #1 mounted the layout control in no longer exists. `LayoutModeControl` is now
  `LayoutModeChoice`, a Layout row in `AppearanceSettings` next to chat font and density.

`hf.py` never conflicted — this branch does not touch it, so PR #1's search fix applies to
Discover unchanged. Dropping `full=true` costs Discover nothing either: it already fetches
repo trees itself, because the hub's search response carries no file sizes.

Verified: typecheck, build and `lint:design` clean; web tests 473 pass / 57 fail, identical
to this branch's head before the merge (the failures are this environment's missing native
dependencies); model-manager pytest 48 passed, up from 38 + PR #1's 8, plus the 2 new ones
above.
