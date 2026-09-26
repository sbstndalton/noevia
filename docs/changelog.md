## Format

From 2026-09-24 each release entry starts with a `### Services` list with one line per service:
Web, Diary, Model manager, Code sandbox, OCR, Docling, Deploy/infra. Each line names the PRs
that touched that service and the image tag deployed for it (for example `cowork-web:958022b`),
"merged, not yet deployed" when the code is on main but the running image predates it, or
"no change". Sidecar image tags are pinned separately from `COWORK_VERSION`, so a web-only
release leaves the other services on their previous tags. The prose, deploy evidence and rollback
notes follow as before. Entries before release 7b6942c keep their original free-form layout.

## Release web 584bdba — 2026-09-26 (spacing rhythm: #417)

### Services

- **Web:** [#417](https://github.com/sbstndalton/noevia/pull/417) closes #371–#381 (Apple HIG spacing scale restored across Settings and panes — CSS tokens/families/`noevia.css`/`app.css`/`phone.css`, `SettingsShell` focus-on-deep-link one-liner, density rows, new `qa/spacing-rhythm.cjs`, a `design-lint` rule) — deployed as `cowork-web:584bdba`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-584bdba`, live `docker-compose.yml`/`docker-compose.override.yml` backups `*.bak.before-584bdba`.

PR #417 (head `627f216`) was draft with CI green against an earlier `origin/main`. Main had since
advanced to `6c7fafb` (#412, #416 plus their changelogs); merged `origin/main` into the branch in a
worktree (`ort` auto-merge, no conflicts — including `Sidebar.tsx`, which kept both #416's row-actions
focus fix and this PR's phone touch-target/spacing rules) to `95463ac`. From `apps/web`: `npm test`
2295/2295, `typecheck`, `build`, `lint:design` all clean; CI green (7/7 checks); `qa/spacing-rhythm.cjs`
(180 screenshots, flush=0 clipped=0 small=0 zoom=0 overflow=0 nav-error=0 probe-error=0 — 9 unrelated
`pageerror`s only in the Editorial family, pre-existing and not part of this script's flush/overflow
gate), `qa/sidebar-focus-undo.cjs` (4/4) and `qa/settings-focus-deep-links.cjs` (all scenarios) each
**PASS** against the built `dist` with `PLAYWRIGHT_MODULE`. Marked ready, squash-merged to `584bdba`
(final `main` SHA); `git diff` against `origin/main` is empty, confirming tree invariance. The worktree
and both local+remote copies of `fix/spacing-apple-rhythm` were deleted after merge.

Built `cowork-web:584bdba` on DaServer from `releases/584bdba` (git archive of `main`@`584bdba`, scp'd —
no git creds on the box); the in-image build ran all 622 tests before `npm run build`, and
`stamp-icons` reported `version=584bdba`. The candidate image's `version.json` reported `584bdba` and
`dist/assets` contained the expected hashed `index-*.js`/`index-*.css` bundles before cutover. `current`
symlink and `COWORK_VERSION` updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`,
`OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`,
`CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Deployed with the guarded `tools/preflight/up.sh --env-file
config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/`
**200**; `/api/profile` **401**; served `index-B_EOWjkW.css` / `index-CPLXOJtR.js` match the image's
`dist/assets`. Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id`
and `State.StartedAt` (model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix).
`cowork-embed-1` remains in its pre-existing crash loop (#336, unrelated, untouched — same container
`Id`, `RestartCount` rose 786→788 from its own ongoing restarts, not recreated). No chat sends, model
tunes, or Diary access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn /mnt/docker/appdata/cowork/releases/3cf7233 /mnt/docker/appdata/cowork/current &&
cp /mnt/docker/appdata/cowork/config/.env.bak.before-584bdba /mnt/docker/appdata/cowork/config/.env &&
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env
-- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 3cf7233 — 2026-09-26 (two reviewed fixes: #412, #416)

### Services

- **Web:** [#412](https://github.com/sbstndalton/noevia/pull/412) fix #410 (`server/routes/plugin-directory.cjs` gives MCP starter servers distinct, readable titles instead of a shared fallback; test), [#416](https://github.com/sbstndalton/noevia/pull/416) fix #355 #362 #406 (`Sidebar.tsx` restores focus into hover-hidden row actions after search Escape and inline rename Escape/Enter, and fires a `workspace-changed` event after archive/Undo so other mounted readers refresh; `server/spa-routes.cjs` serves the SPA shell for `/c`, `/c/`, `/p`, `/p/` instead of a raw 404; new `qa/sidebar-focus-undo.cjs`, extended `qa/url-history.cjs`; tests) — deployed as `cowork-web:3cf7233`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-3cf7233`, live `docker-compose.yml`/`docker-compose.override.yml` backups `*.bak.before-3cf7233`.

Both PRs were draft with CI green against `origin/main` at `2c7488d` at the start of this release.
#412 (`c70ce3d`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0639102`; `npm test`
2291/2291, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `4b38263`. #416
(`faa6b1c`) then merged `origin/main` (the merge had been started against `2c7488d`, before #412 landed)
cleanly — `ort` auto-merge, no conflicts, only `docs/changelog.md` — to `39ee9a6`; `npm test` 2289/2289,
`typecheck`, `build`, `lint:design` clean; `qa/sidebar-focus-undo.cjs` (4/4) and `qa/url-history.cjs`
(11/11, including the `/c`, `/c/`, `/p`, `/p/` SPA-shell fallback) both **PASS** against the built `dist`
with `PLAYWRIGHT_MODULE`; CI green (including `offline-contract`); squash-merged to `3cf7233` (final
`main` SHA — this squash lands cleanly on top of #412's already-merged `plugin-directory.cjs` change,
which is why `git diff` against `origin/main` shows exactly that file). All worktrees and their
local+remote branches were deleted after merge. The pre-existing spacing branch (`fix/spacing-apple-rhythm`)
was left untouched, as scoped.

Built `cowork-web:3cf7233` on DaServer from `releases/3cf7233` (git archive of `main`@`3cf7233`, scp'd —
no git creds on the box). A disposable, network-isolated candidate container confirmed `/` **200**,
`/api/profile` **401**, `/c` and `/p/` **200** `text/html`, `/api/nope` JSON, and that the image's
`dist/assets` contains the exact `index-CfeaRzvk.js` / `index-CW-35hg6.css` referenced by `index.html`
and `version.json` reporting `3cf7233`, before cutover. `current` symlink and `COWORK_VERSION` updated;
every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/c` and `/p/` **200** `text/html`; `/api/nope` JSON. Served
`index-CfeaRzvk.js` / `index-CW-35hg6.css` match both the public page and the image's `dist/assets`.
Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and
`State.StartedAt` (model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1`
remains in its pre-existing crash loop (#336, unrelated, untouched — same container `Id`, `RestartCount`
rose 762→776 from its own ongoing restarts, not recreated). No chat sends, model tunes, or Diary access
were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/0a8cc31 current`, restore `.env.bak.before-3cf7233` (`COWORK_VERSION=0a8cc31`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 0a8cc31 — 2026-09-26 (three reviewed fixes: #407, #411, #408)

### Services

- **Web:** [#407](https://github.com/sbstndalton/noevia/pull/407) fix #399 (repair remaining stale `qa/` account-popover locators, no app code), [#411](https://github.com/sbstndalton/noevia/pull/411) fix #409 (`ModelPopup`/`ModelsSettings` filter out non-chat models, `routes/projects.cjs` rejects a non-chat model with 400, `chat.cjs` returns 409 for a stale non-chat manual project model via `chat-model-kind.cjs`, `index.cjs` wiring, tests), [#408](https://github.com/sbstndalton/noevia/pull/408) fix #401 #403 #404 #405 (`settings-focus.ts` + `SettingsShell`/`AccountMenu`/`Sidebar`/`App.tsx` return focus to whatever opened Settings, `routes.ts` gives every section its own `/settings/<id>` alias, truthful status dots, `auth.cjs` `listSessions` now takes the caller's own `session.id_hash` and marks that row `current`, one date formatter shared across Settings/models components, i18n, `qa/settings-focus-deep-links.cjs`) — deployed as `cowork-web:0a8cc31`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-0a8cc31`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-0a8cc31`.

All three PRs were draft with CI green against `origin/main` at `2c0d59c` at the start of this release.
#407 (`511f8a7`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `0b59fdd`; `npm test`
2262/2262, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `aead398`. #411
(`db447ce`) then merged `origin/main` (now carrying #407): clean `ort` auto-merge, no conflicts, to
`e563658`; `npm test` 2273/2273, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `637f003`. #408 (`2472e3e`) then merged `origin/main` (now carrying
#411's `chat.cjs`/`ModelsSettings` changes): the anticipated conflicts in `ModelsSettings.tsx`,
`App.tsx` and `Sidebar.tsx` did not materialize — `ort` auto-merged cleanly, both sides kept, to
`bb4a63c`; `npm test` 2289/2289, `typecheck`, `build`, `lint:design` clean, and
`qa/settings-focus-deep-links.cjs` (run against the built `dist` with `PLAYWRIGHT_MODULE`) **PASS**; CI
green; squash-merged to `0a8cc31` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. All three worktrees and their local+remote branches were deleted
after merge. The pre-existing spacing branch and #410 were left untouched, as scoped.

Built `cowork-web:0a8cc31` on DaServer from `releases/0a8cc31` (git archive of `main`@`0a8cc31`, scp'd —
no git creds on the box). Candidate image confirmed to contain the served `dist/assets/index-*.js`/
`index-*.css` bundle before cutover. `current` symlink and `COWORK_VERSION` updated; every other
`*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/settings/account` **200** `text/html`. Served `index-kKb03zeT.js` /
`index-CW-35hg6.css` match both the public page and the image's `dist/assets`. Every other `cowork-*`
container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — same container `Id`, `RestartCount` rose 755→756 from its own ongoing
restarts, not recreated). No chat sends, model tunes, or Diary access were performed; no other container
was rebuilt or recreated.

Rollback: `ln -sfn releases/592c4d3 current`, restore `.env.bak.before-0a8cc31` (`COWORK_VERSION=592c4d3`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release web 592c4d3 — 2026-09-26 (three reviewed fixes: #400, #395, #402)

### Services

- **Web:** [#400](https://github.com/sbstndalton/noevia/pull/400) fix #392 (repair stale `qa/` phone/sidebar/workspace scripts only, no app code), [#395](https://github.com/sbstndalton/noevia/pull/395) fix #393 (per-chat composer drafts via `chat-drafts.ts`, `ChatView.tsx`, tests), [#402](https://github.com/sbstndalton/noevia/pull/402) fix #396 #397 #398 (`EditProjectModal` focus restore, `ProjectView` delete-chat confirm, project name length shared by `server/project-limits.json` and the client, `ProjectsView`, `noevia.css`, i18n) — deployed as `cowork-web:592c4d3`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-592c4d3`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-592c4d3`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-592c4d3`.

All three PRs were draft with CI green against `origin/main` at `ff0d4ea` at the start of this release.
#400 (`74bb630`) merged `origin/main` cleanly (`ort` auto-merge, no conflicts) to `e67370e`; `npm test`
2221/2221, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `edcf18d`. #395 (`9cab4ca`)
then merged `origin/main` (now carrying #400): the expected `ChatView.tsx` conflict materialized as a
two-line import-order conflict against #394's already-merged `edit-focus.ts` import — resolved by keeping
both import lines (`chat-drafts.ts` and `edit-focus.ts`), no logic conflict, to `10d6f8a`; `npm test`
2240/2240, `typecheck`, `build`, `lint:design` clean; CI green; squash-merged to `fff2a02`. #402 (`c284a4d`)
then merged `origin/main` (now carrying #395's `chat-drafts.ts`): clean `ort` auto-merge, no conflicts, to
`e37d7d8`; `npm test` 2262/2262, `typecheck`, `build`, `lint:design` clean; CI green (including
`offline-contract`); squash-merged to `592c4d3` (final `main` SHA). `git diff --quiet <head> origin/main`
confirmed tree-identical after each squash. All three worktrees and their local+remote branches were
deleted after merge. The pre-existing spacing branch and the #399 QA PR were left untouched, as scoped.

Built `cowork-web:592c4d3` on DaServer from `releases/592c4d3` (git archive of `main`@`592c4d3`, scp'd — no
git creds on the box). Candidate image confirmed to contain `server/project-limits.json` and the served
`dist/assets/index-*.js`/`index-*.css` bundle before cutover. `current` symlink and `COWORK_VERSION`
updated; every other `*_VERSION` left untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`,
`MODEL_MANAGER_VERSION=1c87ab0`, `DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`).
Deployed with the guarded `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`; `/api/profile` **401**; `/c/abc123` **200** `text/html`. Served `index-C2mIAJXk.js` /
`index-CW-35hg6.css` match both the public page and the image's `dist/assets`. Every other `cowork-*`
container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — same container `Id`, `RestartCount` rose 700→701 from its own ongoing
restarts, not recreated). No chat sends, model tunes, or Diary access were performed; no other container
was rebuilt or recreated.

Rollback: `ln -sfn releases/f70e969 current`, restore `.env.bak.before-592c4d3` (`COWORK_VERSION=f70e969`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web f70e969 — 2026-09-26 (two reviewed fixes: #394, #391)

### Services

- **Web:** [#394](https://github.com/sbstndalton/noevia/pull/394) fix #387 #388 #389 #390 #355 (`useChatScroll` follow guard + "Jump to latest" while streaming; Markdown h2–h6/blockquote grouping and remote images rendered as new-tab links via `markdown-image.ts`; edit-cancel focus restore via `edit-focus.ts`; `ChatView.tsx`, `DiaryModal.tsx`, `app.css`, `diary-tab.css`, i18n), [#391](https://github.com/sbstndalton/noevia/pull/391) feat #359 shareable chat/project/Settings URLs with working Back/Forward (`routes.ts`, `server/spa-routes.cjs` static fallback, `AuthGate` `safeReturnPath` sign-in return, `App.tsx`, `SettingsShell`, `ProjectView`, `PluginsView`, i18n, `qa/url-history.cjs`) — deployed as `cowork-web:f70e969`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-f70e969`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-f70e969`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-f70e969`.

Both PRs were draft with CI green and `MERGEABLE` against `origin/main` at `d805cfd` at the start of this
release. #394 (`fa0f63f`) already had `d805cfd` as an ancestor, so `git merge origin/main` was a no-op and no
new merge commit was needed; squash-merged directly to `532b049` (`npm test` 2208/2208, `typecheck`, `build`,
`lint:design` clean; GitHub Actions CI green). #391 (`5a00528`) then merged `origin/main` (now at `532b049`,
carrying #394) — the expected `App.tsx`/`ChatView`-adjacent conflict did not materialize; the `ort` merge
strategy auto-merged `ChatView.tsx`, `DiaryModal.tsx`, `useChatScroll.ts`, i18n and the new `edit-focus.ts`/
`markdown-image.ts` files cleanly, keeping both PRs' changes intact, producing `704d569`. `npm test`
(2221/2221), `typecheck`, `build`, `lint:design` all clean on the merged worktree; GitHub Actions CI green
on the pushed head. `qa/url-history.cjs` ran against the built dist with a real Chromium
(`PLAYWRIGHT_MODULE` pointed at the codex-runtime `playwright` package, synthetic `page.route` API mocks,
no inference/storage/Diary/network) — all 10 scenarios passed, including the sign-in-returns-to-deep-link
case. Squash-merged #391 → `f70e969` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

Built `cowork-web:f70e969` on DaServer from `releases/f70e969` (git archive of `main`@`f70e969`, scp'd — no
git creds on the box). `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`; confirmed the `.env` diff before/after
is exactly the one `COWORK_VERSION` line). Deployed with the guarded
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**
`text/html`, `/api/profile` **401** `application/json`; served `index-CtQ_CHX0.js`/`index-CeaH-H3n.css` match
the image's `dist/assets` (confirmed from the public page and inside the running container). New SPA fallback
checked directly: `/c/abc123` and `/settings/appearance` both **200** `text/html`; `/api/nope` **401**
`application/json` (never HTML); `/definitely-not-a-route` **404** `application/json` (never HTML). Every
other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt`
(model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 663→671 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or Diary
access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/5430d25 current`, restore `.env.bak.before-f70e969` (`COWORK_VERSION=5430d25`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web 5430d25 — 2026-09-26 (two reviewed fixes: #384, #365/#356)

### Services

- **Web:** [#386](https://github.com/sbstndalton/noevia/pull/386) fix #384 [P1] (`ModelPopup.tsx` sends `{model, routing:'manual'}`; `routes/projects.cjs` model-only PATCH now pins `routing:'manual'` and sets `routingChosen`, so picking a model from the popup atomically pins it instead of leaving it on Auto), [#385](https://github.com/sbstndalton/noevia/pull/385) fix #365 + feat #356 (StatsBar scoped to chat views only via `statsbar-visibility.ts`; Regenerate + Copy reply added to `ChatView` message actions via `regenerate.ts`, `App.tsx` wiring, i18n) — deployed as `cowork-web:5430d25`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** no change — `cowork-model-loader:1c87ab0`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-5430d25`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-5430d25`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-5430d25`.

Both PRs were draft with CI green and `MERGEABLE` at the start of this release (`origin/main` unmoved at
`16ba52d` since the orchestrator's review). #386 (`f599869`) already had `16ba52d` as an ancestor, so no
merge commit was needed; #385 (`1bc6756`) merged `origin/main` cleanly (auto-merge, no conflicts) to pick
up #386's `ModelPopup.tsx`/`routes/projects.cjs` changes, producing `e9c5c53`. `npm test`
(2162→2181 passing), `npm run typecheck` and `npm run build`/`lint:design` were green on both worktrees;
GitHub Actions CI was green on both heads and re-verified after #385's merge commit was pushed. Squash-merged
in order: #386→`443396d`, #385→`5430d25` (final `main` SHA). `git diff --quiet <head> origin/main` confirmed
tree-identical after each squash. Both worktrees and their local+remote branches were deleted after merge.

Built `cowork-web:5430d25` on DaServer from `releases/5430d25` (git archive of `main`@`5430d25`, scp'd — no
git creds on the box). Candidate verified before cutover: `version.json` reports `5430d25`; the built
`dist/assets/*.js` contain the new `msg.regenerate` i18n key; `server/routes/projects.cjs` in the image
contains `routingChosen`. `current` symlink and `COWORK_VERSION` updated; every other `*_VERSION` left
untouched (`DIARY_VERSION=f6444b4`, `OCR_VERSION=5004b50`, `MODEL_MANAGER_VERSION=1c87ab0`,
`DOCLING_VERSION=2026-09-21`, `CODE_SANDBOX_VERSION=pi-0.87.0-9b532a8`). Deployed with the guarded
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-N4RSCO_q.js`/`index-Bj6_HXWs.css` match the image's `dist/assets`
(confirmed both from the public page and inside the running container). In-container check: the built
bundle contains `msg.regenerate` and the live `server/routes/projects.cjs` contains `routingChosen`. Every
other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and `State.StartedAt`
(model-loader, diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 611→617 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or Diary
access were performed; no other container was rebuilt or recreated.

Rollback: `ln -sfn releases/1c87ab0 current`, restore `.env.bak.before-5430d25` (`COWORK_VERSION=1c87ab0`),
re-run `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release web + model-loader 1c87ab0 — 2026-09-26 (five reviewed a11y/UX fixes: #345 #346 #352–#363 #366–#368, and deploying #347/#348)

### Services

- **Web:** [#351](https://github.com/sbstndalton/noevia/pull/351) fix #345 #346 (AccountMenu/ToolCatalogue menu semantics, onBlur + mousedown keep-focus, `menu-nav.ts`, scrim tokens, lint rule), [#370](https://github.com/sbstndalton/noevia/pull/370) fix #353 #355 #358 #360 #362 #363 (ToolCatalogue placement via `placeCatalogue()`, Sidebar focus/rename/undo toast, ChatView edit buttons + focus, `useModalDialog` initial focus), [#369](https://github.com/sbstndalton/noevia/pull/369) fix #352 #354 #357 (projects routing heal, selectedToolboxIds, toolbox summaries with connected connectors, ModelPopup/ComposerActions, reply-telemetry fallback, ChatView label), [#364](https://github.com/sbstndalton/noevia/pull/364) fix #361 (Diary active flag; App.tsx `Diary.View` active prop), [#382](https://github.com/sbstndalton/noevia/pull/382) fix #366 #367 #368 (mcp-status directory flag, Sidebar MCP label via `mcp-summary.ts`, PluginsView empty state, CodingWorkspace project picker, App.tsx wiring, i18n) — deployed as `cowork-web:1c87ab0`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#347](https://github.com/sbstndalton/noevia/pull/347) fix #342 (discover.py stops offering imatrix files as models) and [#348](https://github.com/sbstndalton/noevia/pull/348) model-loader half — fix #341 (services.py/config.py: probe llama on its real port, honest unknown-model state), both already on `main` since `7a72713` but undeployed — deployed now as `cowork-model-loader:1c87ab0` (built on the box from `releases/1c87ab0/services/model-manager`).
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION` and `MODEL_MANAGER_VERSION`; `.env` backup `.env.bak.before-1c87ab0`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-1c87ab0`, live `docker-compose.override.yml` backup `docker-compose.override.yml.bak.before-1c87ab0`.

All five PRs merged one at a time into `main` from base `31973d5`, each re-merged with the moving
`origin/main` tip and re-verified before squash-merge: #351→`74436e1`, #370→`b13250f` (conflict in
`ToolCatalogue.tsx` — kept #351's no-dialog-role/keepFocusOnMouseDown behaviour together with #370's
inline `placeCatalogue()` layout style), #369→`0b0b88e` (ChatView.tsx auto-merged both edit-action and
reply-telemetry/label changes cleanly), #364→`98641b0`, #382→`1c87ab0` (final `main` SHA; auto-merged
cleanly). Node/TS/build/lint:design green on every merge (2105→2155 tests passing as files were added);
`npm run typecheck` and `npm run lint:design` clean on every merge. GitHub Actions CI green on every
head before merge and again on every re-merged commit before squash.

Built `cowork-web:1c87ab0` and `cowork-model-loader:1c87ab0` on DaServer from `releases/1c87ab0` (git
archive of `main`@`1c87ab0`, scp'd — no git creds on the box). Candidates verified before cutover:
web — `isSidecarModel('nomic-embed-text-v1')` is `true` with `--env-file config/.env`, `routes/health.cjs`
loads; model-loader — `app.api`/`app.main`/`app.services`/`app.discover` import cleanly and the router
exposes `/api/v1/models-ini`, `/api/v1/backends`, `/api/v1/search/repo`. `current` symlink and
`COWORK_VERSION`/`MODEL_MANAGER_VERSION` updated; every other `*_VERSION` left untouched. Deployed with
the guarded `tools/preflight/up.sh --no-build --no-deps --wait`, model-loader first per docs/deployment.md
("models.ini writer"), then web.

Verification: `cowork-model-loader-1` recreated, healthy, `RestartCount=0`; from inside `cowork-web-1`
(the `models` network), `GET /api/v1/backends` reports `cowork-llama-1` `loaded_model:
"gemma-4-E2B_q4_0-it"`; `GET /api/v1/search/repo?repo=bartowski/Qwen_Qwen3.5-4B-GGUF` returned 26 groups,
none an imatrix file; an unauthenticated `PUT /api/v1/models-ini` returned **401** (single-writer endpoint
intact). `cowork-web-1` recreated, healthy, `RestartCount=0`; `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-ADr6npT9.js`/`index-zUZs3-6Q.css` match the image's `dist/assets`.
Every other `cowork-*` container and `CloudflaredTunnel` kept identical container `Id` and
`State.StartedAt` (diary, code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its
pre-existing crash loop (#336, unrelated, untouched — `RestartCount` rose 584→587 across the deploy window
from its own ongoing restarts, same container `Id`, not recreated). No chat sends, model tunes, or model
operations were performed; no other container was rebuilt or recreated.

Rollback (web): `ln -sfn releases/7a72713 current`, restore `.env.bak.before-1c87ab0`
(`COWORK_VERSION=7a72713`, `MODEL_MANAGER_VERSION=f6444b4`), re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
Rollback (model-loader only): restore `.env.bak.before-1c87ab0`'s `MODEL_MANAGER_VERSION=f6444b4` line and
re-run the same `up.sh ... model-loader`.

---

## Release web 7a72713 — 2026-09-26 (five reviewed fixes: #339–#343)

### Services

- **Web:** [#344](https://github.com/sbstndalton/noevia/pull/344) fix #339 (models-ini-writer.cjs, llamacpp-manager.cjs), [#349](https://github.com/sbstndalton/noevia/pull/349) fix #340 (rag.cjs, routes/health.cjs, GeneralSettings/SettingsView, i18n settings, css), [#350](https://github.com/sbstndalton/noevia/pull/350) fix #343 + #336 guard (routes/models.cjs, models.cjs, model-system.cjs, LibraryTab.tsx, i18n models), [#348](https://github.com/sbstndalton/noevia/pull/348) web half — fix #341 (HardwareTab.tsx, i18n models) — deployed as `cowork-web:7a72713`.
- **Diary:** no change — `cowork-diary:f6444b4`.
- **Model manager:** [#347](https://github.com/sbstndalton/noevia/pull/347) fix #342 (discover.py stops offering imatrix files as models) and [#348](https://github.com/sbstndalton/noevia/pull/348) model-loader half — fix #341 (services.py/config.py: probe llama on its real port, honest unknown-model state) — merged, not yet deployed; still `cowork-model-loader:f6444b4`. A model-loader release needs the owner's go.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no compose/env changes beyond `COWORK_VERSION`; `.env` backup `.env.bak.before-7a72713`, live `docker-compose.yml` backup `docker-compose.yml.bak.before-7a72713`.

All five PRs merged one at a time into `main` from base `cfe2fae`, each re-merged with the moving
`origin/main` tip and re-verified before squash-merge: #344→`a2cfb16`, #349→`3a10074`, #350→`9908192`,
#348→`791a17d`, #347→`7a72713` (final `main` SHA). Node/TS/build/lint:design green on every merge
(2052→2091 tests passing as files were added); model-manager pytest green on #348 (91 passed) and #347
(102 passed). Clean i18n-model-file and `noevia.css`/`app.css` auto-merges across #348/#350/#347, no
conflict markers. One local-only false alarm: `apps/web` `npm test` hung/failed intermittently on
`rag.test.cjs` in the #347 worktree due to a concurrent unrelated agent process contending for the
same Mac (a `noevia-fix-366` test run observed live); isolated GitHub Actions CI for #347 (unaffected by
local contention) passed clean, including the actually-changed Model manager suite, and was treated as
authoritative.

Built `cowork-web:7a72713` on DaServer from `releases/7a72713` (git archive of `main`@`7a72713`, scp'd —
no git creds on the box). Candidate verified before cutover with a synthetic read-only check
(`docker run --env-file config/.env cowork-web:7a72713`): `model-system.cjs`'s
`isSidecarModel('nomic-embed-text-v1')` is `true` and `routes/health.cjs` loads. `current` symlink and
`COWORK_VERSION` updated; every other `*_VERSION` left untouched. Deployed with the guarded
`tools/preflight/up.sh --no-build --no-deps --wait web` (web only).

Verification: `cowork-web-1` recreated, healthy, `RestartCount=0`; every other `cowork-*` container and
`CloudflaredTunnel` kept identical container `Id` and `State.StartedAt` (model-loader, diary,
code-sandbox, laya, ocr, docling, llama, kiwix). `cowork-embed-1` remains in its pre-existing crash loop
(#336, unrelated, untouched — `RestartCount` rose from 560→562 across the deploy window from its own
ongoing restarts, same container `Id`, not recreated). `https://noevia.daserver.work/` **200**,
`/api/profile` **401**; served `index-Cg--Likw.js`/`index-CbJQZWX2.css` match the image's `dist/assets`.
Re-ran the same `isSidecarModel`/`routes/health.cjs` check inside the live `cowork-web-1` container:
same result. No chat sends, model tunes, or model operations were performed.

Rollback if needed: `ln -sfn releases/f6444b4 current`, restore `.env.bak.before-7a72713`
(`COWORK_VERSION=f6444b4`), re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release model-loader f6444b4 — 2026-09-25 (M3: model-loader is the single writer of models.ini)

### Services

- **Web:** no code change — `cowork-web:f6444b4` recreated once with `MODELS_INI_WRITER=model-loader` ([#319](https://github.com/sbstndalton/noevia/pull/319) web side now active: preset saves, calibration and autotune go through model-loader's CAS endpoint).
- **Diary:** no change — `cowork-diary:f6444b4` (M2, earlier today).
- **Model manager:** [#319](https://github.com/sbstndalton/noevia/pull/319) `PUT /api/v1/models-ini` compare-and-swap endpoint, WRITE_LOCK, immutable `models.ini.noevia-backup-<rev>`, dir fsync (closes #295) — deployed as `cowork-model-loader:f6444b4` (built on the box from `releases/f6444b4/services/model-manager`).
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** `MODEL_MANAGER_VERSION=f6444b4` and `MODELS_INI_WRITER=model-loader` in `config/.env` (backup `.env.bak.before-m3`); the live Compose Manager override gained `MODELS_INI_WRITER: ${MODELS_INI_WRITER:-web}` on the `web` service (it was not passed through before; backup `docker-compose.override.yml.bak.before-m3`). Web's `/llamacpp-config` mount is still read-write; the `:ro` follow-up PR is pending.

Order per docs/deployment.md "models.ini writer": model-loader recreated first (healthy, `RestartCount=0`;
from the web container an unauthenticated `PUT /api/v1/models-ini` returned **401**, proving the endpoint
exists and is token-gated; the previous `5b6d9b6` image had no such route), then the flag added and `web`
recreated (healthy; `MODELS_INI_WRITER=model-loader` confirmed inside the container). Every other `cowork-*`
container and Cloudflared kept identical container IDs; public `/` 200. `cowork-embed-1` stays in its
pre-existing restart loop (#336, untouched).

Not verified here (needs an authenticated session): a preset save through the UI and the resulting
`models.ini.noevia-backup-<rev>` file. No calibration or autotune run was started.

Rollback: set `MODELS_INI_WRITER=web` (or delete the line) in `config/.env` and recreate `web`; to return the
sidecar, restore `.env.bak.before-m3` and recreate `model-loader` with `tools/preflight/up.sh ... model-loader`.

---

## Release diary f6444b4 — 2026-09-25 (M2: Diary tenant assertion + month-file protection)

### Services

- **Web:** no code change — `cowork-web:f6444b4` recreated once so it holds `DIARY_TENANT_KEY` ([#321](https://github.com/sbstndalton/noevia/pull/321) web side now active).
- **Diary:** [#321](https://github.com/sbstndalton/noevia/pull/321) per-request tenant assertion + scoped storage credentials (M2, closes #291 #292), [#326](https://github.com/sbstndalton/noevia/pull/326) month-file protection fix (closes #324) — deployed as `cowork-diary:f6444b4` via `deploy/examples/diary-overlay.sh f6444b4` (agent/ overlay on the running image; `requirements.txt` and `Dockerfile` unchanged since `9b532a8`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose Manager `docker-compose.yml` gained `DIARY_TENANT_KEY: ${DIARY_TENANT_KEY:-}` on both the `diary` and `web` services; `DIARY_TENANT_KEY` (32 random bytes, hex, generated on the host, never printed) added to `config/.env`. Backups: `.env.bak.before-m2`, `.env.bak.before-m2-key`, `.env.bak.before-diary-f6444b4`, `docker-compose.yml.bak.before-m2`, `docker-compose.override.yml.bak.before-m2`; image `cowork-diary:rollback-before-diary-overlay`.

Order followed per docs/deployment.md "Diary tenant key (M2)": (1) compose wiring added, `compose config` clean
with the key empty; (2) diary overlay to `f6444b4` with the key unset (appdata backup
`ab_20260925_170701` verified first; diary logged "DIARY_TENANT_KEY is unset: accepting tenant requests
without X-Cowork-Tenant-Assertion"; health via web 200); (3) key generated into `.env`, `web` recreated
(healthy, `RestartCount=0`, env contains the key, no tenant warning); (4) `diary` recreated with the key.

Verification after step 4: `cowork-diary-1` healthy, `RestartCount=0`; an unsigned tenant request from the
web container (`GET /api/diary/status` with only the bearer + `X-Cowork-User-ID`) returned **401** and diary
logged "tenant assertion rejected: missing or malformed assertion"; `/api/health` via web 200; every other
`cowork-*` container and Cloudflared kept identical container IDs; public `/` 200, `/api/profile` 401.
Not verified here (needs an authenticated browser session, `LEGACY_AUTH_COMPAT=false`): a real Diary tab
read/write through the signed path, covered by the unit suites (diary pytest 415, web
`diary-tenant-assertion.test.cjs`). Direct sidecar clients using `DIARY_LEGACY_USER_ID` stop working now that
the key is set.

Rollback, in this order only: remove `DIARY_TENANT_KEY` from `config/.env` (or restore
`.env.bak.before-m2-key`) and recreate `diary` with `tools/preflight/up.sh ... diary`; then recreate `web` the
same way. Never roll the diary image back to `9b532a8` while web still holds the key; once the key is gone,
`.env.bak.before-diary-f6444b4` + `up.sh ... diary` returns the previous image.

---

## Release f6444b4 — 2026-09-25 (web-only: fix boot crash from 0d602d6 retry)

### Services

- **Web:** [#338](https://github.com/sbstndalton/noevia/pull/338) copies `/app/package.json` into the runtime image and adds a CI boot smoke test; also carries [#322](https://github.com/sbstndalton/noevia/pull/322) `/api/ready` + independent auth tokens + egress bind, [#325](https://github.com/sbstndalton/noevia/pull/325) Docling header-safe names, [#319](https://github.com/sbstndalton/noevia/pull/319) `MODELS_INI_WRITER` at default, [#321](https://github.com/sbstndalton/noevia/pull/321) inert without `DIARY_TENANT_KEY`, [#320](https://github.com/sbstndalton/noevia/pull/320) docs, i18n [#288](https://github.com/sbstndalton/noevia/pull/288)/[#289](https://github.com/sbstndalton/noevia/pull/289)/[#299](https://github.com/sbstndalton/noevia/pull/299)/[#300](https://github.com/sbstndalton/noevia/pull/300), QA [#332](https://github.com/sbstndalton/noevia/pull/332)/[#334](https://github.com/sbstndalton/noevia/pull/334) — deployed as `cowork-web:f6444b4`.
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-f6444b4`; compose files backed up as `docker-compose.yml.bak.before-f6444b4` / `docker-compose.override.yml.bak.before-f6444b4`.

This is a retry of an earlier same-day attempt to deploy `0d602d6`, which crash-looped on a missing
`/app/package.json` in the built image and was rolled back to `2037ffd`; `f6444b4` fixes that build
regression and CI now boots the image before merge.

Source shipped via `git archive` of `origin/main` at `f6444b4` (full:
`f6444b42538d362336b78da0d77d385bb097095a`) to `releases/f6444b4`. Only `cowork-web:f6444b4` was
built; no other image was touched. Candidate verification: `docker run --rm --entrypoint ls
cowork-web:f6444b4 /app/package.json` returned the file (the exact defect that broke `0d602d6`).

Cutover used the installed host preflight: `current` repointed at `releases/f6444b4`, `COWORK_VERSION`
set to `f6444b4`, then `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait
--wait-timeout 180 web`. Only `cowork-web-1` was recreated (image `2037ffd` → `f6444b4`, healthy,
`RestartCount=0`); every other `cowork-*` container and all unrelated containers (Nextcloud AIO, arr
stack, Jellyfin, Cloudflared, etc.) kept identical container ID and `StartedAt` in a before/after
`docker ps`/`inspect` diff. `cowork-embed-1` remained in its pre-existing restart loop (known, issue
#336, untouched).

Verification: internal `GET /api/ready` on the container's `UI_PORT` (8021) returned `200
{"ready":true,"version":"0.2.0"}`; logs since deploy showed `egress.listening` on `172.28.0.4:8040`
and the expected `DIARY_TENANT_KEY` warning, no auth-token warnings; `https://noevia.daserver.work/`
returned 200 and `/api/profile` returned 401; the served `index-pLXervss.js` / `index-CY0nLBZh.css`
matched the hashes in `cowork-web:f6444b4`'s `/app/dist/assets`.

Rollback (not needed — deploy succeeded): restore `current` to `releases/2037ffd`, restore
`config/.env` from `.env.bak.before-f6444b4`, restore the two compose file backups, then re-run
`tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

---

## Release 2037ffd — 2026-09-25 (web-only: theme families + cursor-pull hover)

### Services

- **Web:** [#315](https://github.com/sbstndalton/noevia/pull/315) Three distinct theme families — Material 3 Contemporary, Liquid Glass, ruled Editorial — plus cursor-pull hover, all frontend-only (`apps/web/src`) — deployed as `cowork-web:2037ffd` (full build FROM release source; `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-2037ffd`.

No open PRs against `sbstndalton/noevia` were merged for this release (PR #315 was merged as part of this deploy; `gh pr list --state open` after merge showed only other unrelated work). `origin/main` was confirmed at `2037ffd` (full: `2037ffdbe211990d436b95a12b3927951b57be87`) with no trailing non-docs commits, and `git diff --stat 2037ffd origin/main -- apps/` was empty. CI on that SHA (`2037ffdbe211990d436b95a12b3927951b57be87`, workflow `CI`) completed success, including "Docker images build" (2m25s) and "Node tests, typecheck, frontend build" (1m31s).

Source shipped via `git archive` of `2037ffdbe211990d436b95a12b3927951b57be87` to `releases/2037ffd`. Only `apps/web/src` changed, so a full web build was required; it produced `index-Ck6gpNmS.js` / `index-CY0nLBZh.css`.

Candidate release was archived to `releases/2037ffd`, `.env` backed up to `.env.bak.before-2037ffd`, and `cowork-web:2037ffd` was built with `COWORK_VERSION=2037ffd`. Candidate verification used a synthetic in-image check: `docker run --rm --entrypoint cat cowork-web:2037ffd /app/dist/version.json` returned `{"version":"2037ffd"}` before cutover. The served `index.html` referenced `/assets/index-Ck6gpNmS.js` and `/assets/index-CY0nLBZh.css`, matching the hashes baked into `cowork-web:2037ffd`'s `/app/dist/assets`. An in-container grep confirmed the served CSS contained 335 occurrences of `data-family`, including `contemporary`, `editorial` and `glass` family selectors.

Cutover used the installed host preflight: `current` repointed at `releases/2037ffd`, then `tools/preflight/up.sh --env-file config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`, followed by `tools/sidecar-restart-alert.sh --ack`. Only `cowork-web-1` was recreated (image `58b340c` → `2037ffd`); every other `cowork-*` container and all unrelated containers (Nextcloud AIO, arr stack, Jellyfin, etc.) kept their prior image, identity and start time in a before/after `docker ps`/`inspect` diff.

Post-cutover verification: `cowork-web-1` healthy, 0 restarts; `https://noevia.daserver.work/` returned 200 on 3/3 requests; `/api/profile` returned 401; `/version.json` returned `{"version":"2037ffd"}`; the served `index.html` referenced `/assets/index-Ck6gpNmS.js` and `/assets/index-CY0nLBZh.css`, matching the built dist; `docker logs cowork-web-1` showed only normal startup lines (MCP discovery, UI listening), no errors.

Rollback (not needed — verification passed): restore `.env.bak.before-2037ffd`, `ln -sfn releases/58b340c current`, then rerun the same `up.sh … --no-build --no-deps --wait web` command.



## Release 58b340c — 2026-09-25 (favicon/app-shell cache-busting, stamp-test fix)

### Services

- **Web:** [#314](https://github.com/sbstndalton/noevia/pull/314) Favicon/app-shell cache-busting (`STAMP_VERSION`), stale-shell guard, `no-store` on `index.html`, and a mark in Appearance previews (#311, #312); [#318](https://github.com/sbstndalton/noevia/pull/318) fix stamp-icons tests to be independent of ambient `STAMP_VERSION` (#317) — deployed as `cowork-web:58b340c` (full build FROM release source; `apps/web/Dockerfile` and `compose.yaml` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** the live Compose file (`/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml`) lacked `web.build.args.COWORK_VERSION`, which the Dockerfile needs to bake `STAMP_VERSION` into the image. It was backed up as `docker-compose.yml.bak.before-58b340c` and patched to add `args: COWORK_VERSION: ${COWORK_VERSION:-dev}` under `web.build`, keeping the existing `context:`. This is now required for every web release; it stays in place going forward (see the "compose-copies" note in `docs/deployment.md`). `.env` backed up as `.env.bak.before-58b340c`.

Preflight: `gh pr list --repo sbstndalton/noevia --state open` showed only #315 (theme families work, not part of this release) — nothing was merged. `origin/main` was confirmed at `58b340c` (full: `58b340c1553fd42ec40a14bc9c1a6728b7f7a370`) with no trailing non-docs commits ahead of it for `apps/`, `compose.yaml`, `.github/` (`git diff --stat` empty against the prior release SHA `20a24c2`... verified against 58b340c as tip). CI on `58b340c1553fd42ec40a14bc9c1a6728b7f7a370` (workflow `CI`, run 36112669958) completed success, including "Docker images build" (2m19s) and "Node tests, typecheck, frontend build" (1m24s), plus Diary test suite, Docling extraction contract and Model manager test suite.

Source shipped via `git archive` of `58b340c1553fd42ec40a14bc9c1a6728b7f7a370` to `releases/58b340c` (the stale `releases/29d2d1d` directory, left over from an aborted attempt that failed the Dockerfile's test stage — fixed by #318 — was removed first). The compose build-arg patch above was required for the `STAMP_VERSION` build arg to resolve; `docker compose ... config` was used to confirm `args: COWORK_VERSION: 20a24c2` resolved correctly before the version bump, and `COWORK_VERSION: 58b340c` after. Building `cowork-web:58b340c` with `COWORK_VERSION=58b340c` completed cleanly, with `stamp-icons: version=58b340c stamped=index.html, manifest.webmanifest wrote version.json` in the build log.

Candidate verification used a synthetic in-image check: `docker run --rm --entrypoint cat cowork-web:58b340c /app/dist/version.json` returned `{"version":"58b340c"}` (not `0.2.0` or `dev`) before cutover. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `https://noevia.daserver.work/` returned 200 three times, `/api/profile` returned 401, `curl .../version.json` returned `{"version":"58b340c"}`, response headers carried `cache-control: no-store`, and the served `index.html` referenced `icon.svg?v=58b340c` / `icon.png?v=58b340c`. Served container asset filenames under `dist/assets` matched the built image's assets exactly. Logs since start were clean. Before/after `docker ps`/`docker inspect` snapshots of every container on the host showed only `cowork-web-1` changed (new container id, new `StartedAt`, restart count unchanged at 0); every other `cowork-*` sidecar (Laya, llama, embed, ocr, docling, kiwix, model-loader, diary, code-sandbox) and unrelated container (Nextcloud AIO stack, media stack) kept its identity and start time. Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-58b340c`, point `current` at `releases/20a24c2`, then rerun the same guarded no-build `web`-only `up.sh` command. The compose build-arg patch is left in place (harmless, and required going forward).

## Release 20a24c2 — 2026-09-25 (new leaf logo)

### Services

- **Web:** [#310](https://github.com/sbstndalton/noevia/pull/310) New noevia mark: three leaves emerging at the tip of a bare twig (#306) — deployed as `cowork-web:20a24c2` (full build FROM release source; `apps/web/src` and public icons changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-20a24c2`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `20a24c2` (full: `20a24c28b34865480aa83e7075c122f9abdcc3ff`) with no trailing non-docs commits, and `git diff --stat 20a24c2 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`) completed success, including "Docker images build" and "Node tests, typecheck, frontend build".

Source shipped via `git archive` of `20a24c28b34865480aa83e7075c122f9abdcc3ff` to `releases/20a24c2`. `apps/web/src` and the public icon assets changed, so a full web build was required; it produced `index-3BnUMor0.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access: the candidate image was run standalone on a scratch port and checked directly — `/` returned 200, `/icon.svg` had 12 `<path>` elements, `/icon-512.png` was 41,683 bytes (old icon was 4,725 bytes), and `/api/profile` returned 401 — before it was removed. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `https://noevia.daserver.work/` returned 200 three times, `/api/profile` returned 401, `/icon.svg` had 12 `<path>` elements, `/icon-512.png` was 41,683 bytes with `Content-Length` matching, the served `index.html` asset references (`index-3BnUMor0.js` / `index-DqhxSEgr.css`) matched the built dist inside the container, and logs since start were clean. Before/after `docker ps`/`docker inspect` snapshot of all 43 containers on the host showed only `cowork-web-1` changed (new container id, new `StartedAt`, restart count unchanged at 0); every other `cowork-*` sidecar and unrelated container (Laya, llama, embed, ocr, docling, kiwix, model-loader, diary, code-sandbox, Nextcloud AIO, media stack) kept its identity and start time. Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-20a24c2`, point `current` at `releases/2ab7c99`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 2ab7c99 — 2026-09-25 (Settings back/close loop fix, new chats default to Auto)

### Services

- **Web:** [#307](https://github.com/sbstndalton/noevia/pull/307) Fix Settings back/close loop through Models & routing; new chats default to Auto when roles are configured; Back-to-app removed (#304, #305) — deployed as `cowork-web:2ab7c99` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-2ab7c99`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `2ab7c99` (full: `2ab7c991d81e4b52d8bc724bdbbb5e434e2f2e6c`) with no trailing docs-only commits, and `git diff --stat 2ab7c99 origin/main -- apps/` was empty. CI on that SHA ("Fix Settings back/close loop through Models & routing; new chats default to Auto (#307)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

Source shipped via `git archive` of `2ab7c991d81e4b52d8bc724bdbbb5e434e2f2e6c` to `releases/2ab7c99`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-Bwxxo8tc.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access: an in-container grep confirmed the built image's `server/chat.cjs` contains `project ? project.routing === 'auto' : true`. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary` and `ocr` (spot-checked; other sidecars unchanged) kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect`/`docker ps` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-2ab7c99`, point `current` at `releases/4e19d28`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 4e19d28 — 2026-09-25 (model delete now unloads, clears auto-router roles)

### Services

- **Web:** [#303](https://github.com/sbstndalton/noevia/pull/303) Fix: deleting a model now unloads it, clears auto-router roles, invalidates caches, and removes the card (#302) — deployed as `cowork-web:4e19d28` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-4e19d28`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `4e19d28` (full: `4e19d2850f49a6671f472a0b2d24ea02aebddff4`) with no trailing docs-only commits, and `git diff --stat 4e19d28 origin/main -- apps/` was empty. CI on that SHA (workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the "Node tests, typecheck, frontend build" job.

Source shipped via `git archive` of `4e19d2850f49a6671f472a0b2d24ea02aebddff4` to `releases/4e19d28`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-C3C3OjXI.js` / `index-DqhxSEgr.css`.

Candidate verification used synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and an in-container grep confirmed `server/models.cjs` contains `clearRoleReferences`. Logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-4e19d28`, point `current` at `releases/cfdb5b3`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release cfdb5b3 — 2026-09-25 (Laya tool gate, experimental, off by default)

### Services

- **Web:** [#301](https://github.com/sbstndalton/noevia/pull/301) Tool gate: make small models use tools when the prompt needs them (experimental, off) — deployed as `cowork-web:cfdb5b3` (full build FROM release source, both `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-cfdb5b3`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `cfdb5b3` (full: `cfdb5b30c483cfe39596cd80ccd8e7b43bd2231f`) with no trailing docs-only commits, and `git diff --stat cfdb5b3 origin/main -- apps/` was empty. CI on that SHA ("Tool gate: make small models use tools when the prompt needs them (experimental, off) (#301)", workflow `CI`, plus "Offline skills MCP contract") completed success, including "Docker images build" and the Node tests/typecheck/frontend-build job.

Source shipped via `git archive` of `cfdb5b30c483cfe39596cd80ccd8e7b43bd2231f` to `releases/cfdb5b3`. Both `apps/web/server` and `apps/web/src` changed, so a full web build was required; it produced `index-C8b5Zts7.js` / `index-DqhxSEgr.css` (unchanged locale chunks).

Candidate verification ran the built image standalone: an in-container listing confirmed `server/tool-gate.cjs` was present, and `server/features.cjs` showed the `toolGate` feature flag defaults to `enabled: false` (`NOEVIA_FEATURE_TOOL_GATE` was left unset in `.env`) — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. `NOEVIA_FEATURE_TOOL_GATE` was not set — the tool gate stays off. No real tune, private Diary access, new harness installation, broader exposure or other production action was part of this release.

Rollback (untaken): restore `.env.bak.before-cfdb5b3`, point `current` at `releases/8454694`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 8454694 — 2026-09-25 (i18n catalogues, QA scripts, docs)

### Services

- **Web:** [#287](https://github.com/sbstndalton/noevia/pull/287) live browser-service Chromium QA run and dark-mode task banner check, [#288](https://github.com/sbstndalton/noevia/pull/288) i18n Settings catalogue chunk and remaining Settings screens, [#289](https://github.com/sbstndalton/noevia/pull/289) i18n translate account menu, Projects and Diary screens, [#290](https://github.com/sbstndalton/noevia/pull/290) docs: versioned service boundaries and migration contracts, [#299](https://github.com/sbstndalton/noevia/pull/299) i18n Customise segment, chat-shell footer, Thinking control and view loading names, [#300](https://github.com/sbstndalton/noevia/pull/300) i18n model manager segment, Diary & storage and Service status — deployed as `cowork-web:8454694` (full build FROM release source, `apps/web/src` changed; no `apps/web/server` or sidecar changes).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-8454694`.

No open PRs against `sbstndalton/noevia` were merged for this release (`gh pr list --state open` was empty at preflight). `origin/main` was confirmed at `8454694` (full: `84546946e4b3460e95e1f608ab5d75c77b117549`). CI on that SHA (`i18n: model manager segment, Diary & storage and Service status (#300)`, workflow `CI`) completed success.

Source shipped via `git archive origin/main` to `releases/8454694`. Only `apps/web/src` changed, so a full web build was required (no server changes); it produced `index-C5ea3Cp-.js` plus refreshed locale chunks (e.g. `de-DE-CJsuIpcy.js`).

Candidate verification ran the built image standalone: `dist/index.html` referenced the freshly built `index-C5ea3Cp-.js`, an in-container listing confirmed the de-DE locale chunks were present, and every pinned sidecar tag (`cowork-diary:9b532a8`, `cowork-ocr:5004b50`, `cowork-model-loader:5b6d9b6`, `cowork-code-sandbox:pi-0.87.0-9b532a8`, `cowork-docling:2026-09-21`) already existed locally — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the served `index.html` asset reference matched the built dist, a locale chunk (`de-DE-CJsuIpcy.js`) served 200, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (before/after `docker ps`/`inspect` snapshot diff showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-8454694`, point `current` at `releases/5a47942`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 5a47942 — 2026-09-24 (Projects/Cowork task status, connector permissions, usage drilldown, Customise UI; MCP custom-server preview)

### Services

- **Web:** [#282](https://github.com/sbstndalton/noevia/pull/282) integrate UI inspiration work for [#256](https://github.com/sbstndalton/noevia/issues/256)–[#260](https://github.com/sbstndalton/noevia/issues/260) (task status, connector permissions, usage drilldown, Customise UI) with review fixes, plus server routes `GET /api/code/active` and the MCP custom-server preview step — deployed as `cowork-web:5a47942` (full build FROM release source, `apps/web/src` and `apps/web/server` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-5a47942`.

No open PRs against `sbstndalton/noevia` were merged for this release (a PR touching #283 was open but explicitly out of scope). `origin/main` was confirmed at `5a47942` followed only by docs-only changelog commits (`037cc23`, `b247bfa`), and `git diff --stat 5a47942 origin/main -- apps/` was empty. CI on `5a47942` (Detect changed areas, Docker images build, Diary test suite, Model manager test suite, Docling extraction contract, Node tests/typecheck/frontend build, CI required) was all green before release.

Source shipped via `git archive 5a47942` to `releases/5a47942`. Both `apps/web/src` and `apps/web/server` changed, so a full web build was required; it produced `index-BHPy9b1M.js` / `index-Cf_aeTgD.css` plus the unchanged locale chunks.

Candidate verification ran the built image standalone: `dist/index.html` referenced the freshly built `index-BHPy9b1M.js`/`index-Cf_aeTgD.css`, and an in-container `grep` confirmed `server/routes/mcp-directory.cjs` contains the `custom/preview` route — synthetic checks only, no live inference or real Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, `/api/code/active` returned 401 unauthenticated, the served `index.html` asset references matched the built dist, and logs since start were clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-5a47942`, point `current` at `releases/9a8f29e`, then rerun the same guarded no-build `web`-only `up.sh` command.

## Release 9a8f29e — 2026-09-24 (i18n interface translations)

### Services

- **Web:** [#281](https://github.com/sbstndalton/noevia/pull/281) translate the interface: i18n layer and nine catalogues (closes [#231](https://github.com/sbstndalton/noevia/issues/231)) — deployed as `cowork-web:9a8f29e` (full build FROM release source, `apps/web/src` changed heavily).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-9a8f29e`.

`origin/main` was confirmed at `9a8f29e` followed only by a docs-only changelog commit (`b247bfa`,
`git diff --stat 9a8f29e origin/main -- apps/` empty) and no open PRs were merged. CI on `9a8f29e`
(Detect changed areas, Docling extraction contract, Node tests/typecheck/frontend build, Model
manager test suite, Diary test suite, Docker images build, CI required) was all green before release.
Source shipped via `git archive 9a8f29e` to `releases/9a8f29e`. `apps/web/src` changed heavily, so a
full web build was required; it produced `index-DLVIslzU.js` / `index-hZUNMXvd.css` plus separate
locale chunks for all nine catalogues (`de-DE-Cv76COWg.js`, `fr-FR-CVCTYCXG.js`, `es-ES-k7TGcfPb.js`,
`it-IT-Cr3AnigY.js`, `nl-NL-DRkttd5-.js`, `pt-BR-5roZJfo7.js`, `sv-SE-CkBFoZrU.js`,
`nb-NO-pn-W27bk.js`).

Candidate verification ran the built image standalone: `/` served index.html, `/api/profile` returned
401, and `dist/assets` contained the locale chunks — synthetic checks only, no live inference or real
Diary access. Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It
recreated with zero restarts and reported healthy. Public `/` returned 200 three times, `/api/profile`
returned 401, the served `index.html` matched the container's `dist/index.html` byte-for-byte, the
served `index-*.js/css` names matched the built dist, and `de-DE-Cv76COWg.js` / `fr-FR-CVCTYCXG.js`
both returned 200 from the public URL. Logs since start were clean. `diary`, `code-sandbox`,
`model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids,
`StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed).
Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader
exposure were part of this release.

Rollback (untaken): restore `.env.bak.before-9a8f29e`, point `current` at `releases/e35ab29`, then
rerun the same guarded no-build `web`-only `up.sh` command.

## Release e35ab29 — 2026-09-24 (browser executor wired into managed jobs)

### Services

- **Web:** [#280](https://github.com/sbstndalton/noevia/pull/280) wire the browser executor into managed jobs and approval cards (closes [#274](https://github.com/sbstndalton/noevia/issues/274)) — deployed as `cowork-web:e35ab29` (full build FROM release source, `apps/web/server` and `apps/web/src` changed). `NOEVIA_FEATURE_BROWSER_EXECUTOR` was left unset, so the feature stays off by default.
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-e35ab29`.

`origin/main` was confirmed at `e35ab29` (only #281, unrelated, open against it) and every check-run
on that commit (CI: Detect changed areas, Model manager test suite, Diary test suite, Docker images
build, Node tests/typecheck/frontend build, Docling extraction contract, CI required; plus Offline
skills MCP contract) was completed/success before release. `apps/web/server` and `apps/web/src` both
changed since the live `c09ee38`, so a full web build was required. Source shipped via
`git archive e35ab29` to `releases/e35ab29`. The in-image test suite ran as part of the build
(334/334 passing) and produced `index-ClOM-B3G.js` / `index-hZUNMXvd.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401, the
served `index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename,
`server/browser-service.cjs` and `server/routes/browser.cjs` were confirmed present in the container,
and logs since start were clean (no `[egress]` or `[browser]` errors). `diary`, `code-sandbox`,
`model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids,
`StartedAt` and zero restarts (snapshot diff before/after showed only `cowork-web-1` changed).
Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation or broader
exposure were part of this release; only synthetic candidate checks were used.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-e35ab29 config/.env`, `ln -sfn releases/c09ee38 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release c09ee38 — 2026-09-24 (model evidence import)

### Services

- **Web:** [#279](https://github.com/sbstndalton/noevia/pull/279) import attributable model evidence alongside downloads (closes [#266](https://github.com/sbstndalton/noevia/issues/266)) — deployed as `cowork-web:c09ee38` (full build FROM release source, `apps/web/server` and `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env` backed up as `.env.bak.before-c09ee38`.

`origin/main` was confirmed at `c09ee38` (no PRs open against it besides unrelated #280) and every
check-run on that commit (CI: Detect changed areas, Model manager test suite, Docker images build,
Diary test suite, Node tests/typecheck/frontend build, Docling extraction contract, CI required;
plus Offline skills MCP contract) was completed/success before release. `apps/web/server` and
`apps/web/src` both changed since the live `d5cf1ea`, so a full web build was required. Source
shipped via `git archive c09ee38` to `releases/c09ee38`. The in-image test suite ran as part of the
build (334/334 passing) and produced `index-CNbsCH0G.js` / `index-hZUNMXvd.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200 three times, `/api/profile` returned 401,
the served `index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename,
`server/model-evidence-import.cjs` was confirmed present in the container, and logs since start were
clean. `diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and
`kiwix` kept identical container ids, `StartedAt` and zero restarts (snapshot diff before/after
showed only `cowork-web-1` changed). Restart-alert baseline re-acked. No model runs, real Diary
data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-c09ee38 config/.env`, `ln -sfn releases/d5cf1ea current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release d5cf1ea — 2026-09-24 (theme families, visual and motion system batch J)

### Services

- **Web:** [#278](https://github.com/sbstndalton/noevia/pull/278) theme families Editorial/Contemporary/Glass replace materials with migration, unified elevation/radius/type tokens, motion system with reduced-motion support (closes [#245](https://github.com/sbstndalton/noevia/issues/245), [#247](https://github.com/sbstndalton/noevia/issues/247), [#249](https://github.com/sbstndalton/noevia/issues/249)) — deployed as `cowork-web:d5cf1ea` (full build FROM release source, `apps/web/src` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-d5cf1ea`.

`origin/main` was confirmed at `d5cf1ea` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
Diary test suite, Detect changed areas, CI required) was completed/success before release.
Only `apps/web/src` changed since the live `c7f7999`. Source shipped via `git archive d5cf1ea`
to `releases/d5cf1ea`. Web required a full build (frontend changed); the in-image test suite ran
as part of the build and passed, producing `index-DNSqOhiT.js` / `index-CsqE8JA1.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename, and the
served `/theme.js` contained `data-family`. `diary`, `code-sandbox`, `model-loader`, `ocr`,
`docling`, `laya`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero
restarts. Restart-alert baseline re-acked. No model runs, real Diary data, new harness installation
or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-d5cf1ea config/.env`, `ln -sfn releases/c7f7999 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release c7f7999 — 2026-09-24 (settings reorganisation, notifications, memory, response style, keyboard, archived chats, Customise, home recents)

### Services

- **Web:** [#277](https://github.com/sbstndalton/noevia/pull/277) batch G settings split, notifications, memory, response style, keyboard, language, archived chats, Customise, home recents (closes [#226](https://github.com/sbstndalton/noevia/issues/226), [#227](https://github.com/sbstndalton/noevia/issues/227), [#228](https://github.com/sbstndalton/noevia/issues/228), [#229](https://github.com/sbstndalton/noevia/issues/229), [#230](https://github.com/sbstndalton/noevia/issues/230), [#232](https://github.com/sbstndalton/noevia/issues/232), [#238](https://github.com/sbstndalton/noevia/issues/238), [#239](https://github.com/sbstndalton/noevia/issues/239); [#231](https://github.com/sbstndalton/noevia/issues/231) partial) — deployed as `cowork-web:c7f7999` (full build FROM release source, `apps/web` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-c7f7999`.

`origin/main` was confirmed at `c7f7999` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
Diary test suite, offline-contract, Detect changed areas, CI required) was completed/success before
release. Only `apps/web` changed since the live `89142c0`. Source shipped via `git archive c7f7999`
to `releases/c7f7999`. Web required a full build (frontend changed); server/Dockerfile/package files
unchanged in scope but the build ran end to end, producing `index-BjjnjAwL.js` / `index-7jjrR2RA.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, and the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename.
`diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept
identical container ids, `StartedAt` and zero restarts. Restart-alert baseline re-acked. No model
runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-c7f7999 config/.env`, `ln -sfn releases/89142c0 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 89142c0 — 2026-09-24 (composer Chat/Cowork toggle, tool catalogue)

### Services

- **Web:** [#276](https://github.com/sbstndalton/noevia/pull/276) composer Chat/Cowork toggle and permitted tool catalogue (closes [#236](https://github.com/sbstndalton/noevia/issues/236), [#237](https://github.com/sbstndalton/noevia/issues/237)) — deployed as `cowork-web:89142c0` (full build FROM release source, `apps/web` changed).
- **Diary:** no change — `cowork-diary:9b532a8`.
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-9b532a8`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-89142c0`.

`origin/main` was confirmed at `89142c0` and every check-run on that commit (Docling extraction
contract, Docker images build, Node tests/typecheck/frontend build, Model manager test suite,
offline-contract, Detect changed areas) was completed/success before release. Only `apps/web`
changed since the live `9b532a8`. Source shipped via `git archive 89142c0` to `releases/89142c0`.
Web required a full build (frontend changed); server/Dockerfile/package files unchanged in scope
but the build ran end to end, producing `index-DKpCIBTO.js` / `index-DghX1G7f.css`.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web` only. It recreated with zero
restarts and reported healthy. Public `/` returned 200, `/api/profile` returned 401, and the served
`index-*.js/css` names matched the web image's `dist/assets` byte-for-byte by filename.
`diary`, `code-sandbox`, `model-loader`, `ocr`, `docling`, `laya`, `llama`, `embed` and `kiwix` kept
identical container ids, `StartedAt` and zero restarts. Restart-alert baseline re-acked. No model
runs, real Diary data, new harness installation or broader exposure were part of this release.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-89142c0 config/.env`, `ln -sfn releases/9b532a8 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 9b532a8 — 2026-09-24 (model manager guided tuning, secrets rotation, Diary tombstone/quarantine, upload/RAG/MCP hardening, code-sandbox batch A)

### Services

- **Web:** [#240](https://github.com/sbstndalton/noevia/pull/240) model manager filters/phone routing/calibration guard/settings headings, [#241](https://github.com/sbstndalton/noevia/pull/241) secrets key rotation UI, [#242](https://github.com/sbstndalton/noevia/pull/242) (web side) Diary tombstone/quarantine/status polling, [#243](https://github.com/sbstndalton/noevia/pull/243) uploads/offsite/pdf-reduce caps + RAG version filter + source lock + job ids, [#244](https://github.com/sbstndalton/noevia/pull/244) untrusted-prompt framing/replay/MCP hardening, [#246](https://github.com/sbstndalton/noevia/pull/246) Q5 KV-cache floor + task-aware sampling presets, [#248](https://github.com/sbstndalton/noevia/pull/248) (web side) code-sandbox batch A hardening, [#251](https://github.com/sbstndalton/noevia/pull/251) guided estimate/tuning pre-flight/Quality and Recover — deployed as `cowork-web:9b532a8` (full build FROM release source, `apps/web/src` changed).
- **Diary:** [#242](https://github.com/sbstndalton/noevia/pull/242) tombstone, quarantine cascade, status polling, backup perf — deployed as `cowork-diary:9b532a8` (`diary-overlay.sh 9b532a8`, `agent/` only, FROM `cowork-diary:d264606`).
- **Model manager:** merged, not yet deployed — stays `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** [#248](https://github.com/sbstndalton/noevia/pull/248) batch A hardening (harness, egress, sandbox) — deployed as `cowork-code-sandbox:pi-0.87.0-9b532a8` (`pi-acp-bridge.cjs` + `supervisor.cjs` overlay, FROM `cowork-code-sandbox:pi-0.87.0-dda50c2`).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** no change to live Compose files; `.env`/Compose backed up as `*.bak.before-9b532a8`.

Source shipped via `git archive 9b532a8` to `releases/9b532a8`. Web required a full build (frontend
changed across `apps/web/src`); server/Dockerfile/package files unchanged in scope but the build ran
end to end, producing `index-BJqPT_o9.js` / `index-BrNEIg3U.css`. Diary and code-sandbox diffs against
`d264606`/`pi-0.87.0-dda50c2` were confirmed limited to `services/diary/agent` and
`services/code-sandbox/{pi-acp-bridge.cjs,supervisor.cjs}` respectively (Dockerfiles/requirements
identical), so both are overlays with no dependency install.

Cutover used the guarded `up.sh --no-build --no-deps --wait` for `web`, `diary-overlay.sh 9b532a8` for
Diary (appdata backup `ab_20260924_173346` verified, `gzip -t` passed), and `up.sh --profile code
--no-build --no-deps --wait` for `code-sandbox`. All three recreated with zero restarts and reported
healthy/running. Public `/` returned 200, `/api/profile` returned 401, and the served `index-*.js/css`
names matched the web image's `dist/assets` byte-for-byte by filename. `model-loader`, `laya`, `ocr`,
`docling`, `llama`, `embed` and `kiwix` kept identical container ids, `StartedAt` and zero restarts.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-9b532a8 config/.env`, `ln -sfn releases/d264606 current`, then
  `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=d264606/' config/.env` (or restore
  `config/.env.bak.before-diary-9b532a8`), then `up.sh --env-file … -- -d --no-build --no-deps --wait
  --wait-timeout 180 diary`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-dda50c2/'
  config/.env` (or restore `config/.env.bak.before-code-sandbox-9b532a8`), then `up.sh --env-file …
  --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.

## Release d264606 — 2026-09-24 (code-actions publish/network gating, fetchJson body cap, Diary corpus_store NameError and queued-edit races)

### Services

- **Web:** [#233](https://github.com/sbstndalton/noevia/pull/233), [#235](https://github.com/sbstndalton/noevia/pull/235) (web side) — deployed as `cowork-web:d264606` (server/ overlay FROM `cowork-web:b5941e4`).
- **Diary:** [#235](https://github.com/sbstndalton/noevia/pull/235) (`corpus_store.py`, `journal.py`) — deployed as `cowork-diary:d264606` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:b5941e4`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-d264606`).

Source shipped via `git archive d264606` to `releases/d264606`. All of `apps/web` outside `server/` is identical to b5941e4
(only `code-actions.cjs`, `http.cjs` and their tests changed), so the web image is `FROM cowork-web:b5941e4` with `/app/server`
replaced (candidate `sha256:fa337d92…`). With no network, the in-image `code-actions.cjs`/`http.cjs` SHA-256 hashes match the
release, `node --check` passes and the two changed test files pass 30 of 30. Dist still serves `index-BsftJ7Co.js` /
`index-CV0N4hHI.css`. The Diary diff vs b5941e4 was `agent/corpus_store.py`, `agent/journal.py` and one test (requirements.txt
and Dockerfile identical). The overlay took appdata backup `ab_20260924_151049` (gzip verified), then recreated Diary as image
`cb092351…`; Diary health via web returned 200. In-container `journal.py` contains `unapplied_exchange_edit` and
`corpus_store.py` contains `errors: Optional`.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay (its appdata backup restarted web
again). Web started at 19:11:03Z and Diary at 19:11:10Z. Both are healthy with zero restarts. All other cowork containers
(code-sandbox, model-loader, laya, ocr, docling, llama, embed, kiwix) kept identical ids and start times. Public `/` returned 200
on 3 of 3 requests, and `/api/profile` returned 401. Web logs had zero error markers over 60 s. No Diary data was read.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-d264606 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/b5941e4 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=b5941e4/' config/.env` (or restore `config/.env.bak.before-diary-d264606`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release b5941e4 — 2026-09-24 (routing/menu fixes, stale loaded summary, chat-only prompt suite, Diary polling and journal replay order, admin-gated warm-up, backup-worker backoff)

### Services

- **Web:** [#207](https://github.com/sbstndalton/noevia/pull/207), [#208](https://github.com/sbstndalton/noevia/pull/208) (web side), [#209](https://github.com/sbstndalton/noevia/pull/209), [#213](https://github.com/sbstndalton/noevia/pull/213) — deployed as `cowork-web:b5941e4` (full `compose build web` from the release context; frontend changed).
- **Diary:** [#208](https://github.com/sbstndalton/noevia/pull/208) (journal replay order, `ORDER BY rowid`) — deployed as `cowork-diary:b5941e4` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:11617a3`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-b5941e4`).

Source shipped via `git archive b5941e4` to `releases/b5941e4`. `apps/web/src` changed vs 11617a3 (lockfile and
Dockerfile identical), so web was built on DaServer (`cowork-web:b5941e4`, image `752c3966e0ca`). Candidate checks were run
with no network. `isChatGenerationModel` (chat-model-kind.cjs) and `MAX_BACKOFF_MS` (diary-backup-worker.cjs) are present.
Dist serves `index-BsftJ7Co.js` / `index-CV0N4hHI.css`. The `installedSummary` / `notifyModelsChanged` grep can't match
minified output because both are renamed identifiers. The bundle and SettingsShell chunk hashes changed from 11617a3.
The Diary diff vs 11617a3 was `agent/journal.py` plus one test (requirements.txt and Dockerfile identical). The overlay took
appdata backup `ab_20260924_144722` (gzip verified). It then recreated Diary as image `aedb9cef…`, and Diary health via web
returned 200. The in-container `/app/agent/journal.py` contains `ORDER BY rowid`.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay. Web started at 18:47:36Z and
Diary at 18:47:43Z. Both are healthy with zero restarts. All other cowork containers (code-sandbox, model-loader, laya, ocr,
docling, llama, embed, kiwix) kept identical ids and start times. Public `/` returned 200 on 3 of 3 requests, and
`/api/profile` returned 401. Web logs had zero error markers over 60 s. No Diary data was read. Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-b5941e4 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/11617a3 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=11617a3/' config/.env` (or restore `config/.env.bak.before-diary-b5941e4`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release 11617a3 — 2026-09-24 (round-13 fixes: harness approval bypasses, MCP discovery TTL, Diary storage-outage handling, UI fixes)

### Services

- **Web:** [#166](https://github.com/sbstndalton/noevia/pull/166), [#167](https://github.com/sbstndalton/noevia/pull/167), [#168](https://github.com/sbstndalton/noevia/pull/168) (web side), [#169](https://github.com/sbstndalton/noevia/pull/169) (web side), [#171](https://github.com/sbstndalton/noevia/pull/171), [#172](https://github.com/sbstndalton/noevia/pull/172), [#187](https://github.com/sbstndalton/noevia/pull/187), [#188](https://github.com/sbstndalton/noevia/pull/188), [#189](https://github.com/sbstndalton/noevia/pull/189) (web side) — deployed as `cowork-web:11617a3` (full `compose build web` from the release context; frontend changed).
- **Diary:** Diary parts of [#134](https://github.com/sbstndalton/noevia/pull/134), [#168](https://github.com/sbstndalton/noevia/pull/168), [#169](https://github.com/sbstndalton/noevia/pull/169), [#189](https://github.com/sbstndalton/noevia/pull/189) — deployed as `cowork-diary:11617a3` (`diary-overlay.sh`, `agent/` only, FROM `cowork-diary:5b6d9b6`).
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** no change — `cowork-code-sandbox:pi-0.87.0-dda50c2`.
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** live Compose files unchanged (backed up as `*.bak.before-11617a3`).

Source shipped via `git archive 11617a3` to `releases/11617a3`. `apps/web/src` changed vs dda50c2
(lockfile and Dockerfile identical), so web was built on DaServer with `docker compose build web`
(`cowork-web:11617a3`, image `23fd3187b3cb`). Candidate checks, run with no network: the in-image `code-harness.cjs` and
`mcp-wiring.cjs` SHA-256 hashes match the release; `pinnedParent` and `discoveryFailTtlMs` are present; dist serves
`index-CzWzWYqN.js` / `index-CV0N4hHI.css`. Diary diff vs 5b6d9b6 was `agent/` plus tests only (requirements.txt and
Dockerfile identical). The overlay took appdata backup `ab_20260924_140932` (gzip verified), which restarted web at
18:09:47Z (same container id). It then recreated Diary as image `96dc142c…`, and Diary health via web returned 200.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then the Diary overlay. Web and Diary are healthy
with zero restarts. All other cowork containers (code-sandbox, model-loader, laya, ocr, docling, llama, embed, kiwix)
kept identical ids and start times. Public `/` returned 200 on 3 of 3 requests, and `/api/profile` returned 401. The served assets exist in
the image, and web logs had no error markers over 60 s. The Diary import check passed; no Diary data was read. Restart-alert
baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-11617a3 config/.env` (also reverts DIARY_VERSION), `ln -sfn releases/dda50c2 current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=5b6d9b6/' config/.env` (or restore `config/.env.bak.before-diary-11617a3`), then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 diary`.

## Release dda50c2 — 2026-09-24 (harness containment, RAG/prompt budget, round-12 hardening, pi bridge timeouts)

### Services

- **Web:** [#132](https://github.com/sbstndalton/noevia/pull/132), [#133](https://github.com/sbstndalton/noevia/pull/133) (web side), [#134](https://github.com/sbstndalton/noevia/pull/134), [#135](https://github.com/sbstndalton/noevia/pull/135) — deployed as `cowork-web:dda50c2` (server/ overlay FROM `cowork-web:958022b`).
- **Diary:** no image change — stays `cowork-diary:5b6d9b6`; the #134 Diary `agent/` changes are merged, not yet deployed.
- **Model manager:** no change — `cowork-model-loader:5b6d9b6`.
- **Code sandbox:** [#133](https://github.com/sbstndalton/noevia/pull/133) — deployed as `cowork-code-sandbox:pi-0.87.0-dda50c2` (pi-acp-bridge.cjs overlay).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** repo-side changes only; live Compose files unchanged (backed up as `*.bak.before-dda50c2`).

Source shipped via `git archive dda50c2` to `releases/dda50c2`. Web lockfiles and all of `apps/web`
outside `server/` are identical to 958022b, so the web image is `FROM cowork-web:958022b` with
`/app/server` replaced (node_modules kept) and the existing dist reused (`index-BaEAos9j.js`,
`index-CVYcHCIL.css`). Candidate `sha256:e6544d4d…`: server `.cjs` hashes match the release; the in-image
server tests pass 1144 of 1152. The 958022b image fails the same 8 tests the same way (repo files that
are not in the image). With no network, `/api/setup/status` returned 200. Sandbox `sha256:2ecb13d6…`:
the diff against 5b6d9b6 was only the bridge and its test; `node --check` passes; bridge tests 5/5;
the in-container bridge SHA-256 `5ce4f3db…` matches the release.

Cutover used guarded `up.sh … --no-build --no-deps --wait` for `web`, then `--profile code` for
`code-sandbox`. Both were recreated with zero restarts. Web is healthy and the sandbox is running. All other cowork containers
(diary, model-loader, laya, ocr, docling, llama, embed, kiwix) kept identical ids and start times.
Public `/` returned 200 on 3 of 3 requests, and `/api/profile` returned 401. The served assets exist in the image. Web logs had no error markers over 60 s.
Restart-alert baseline re-acked.

Rollback (from the Compose Manager project directory):
- Web: `cp -p config/.env.bak.before-dda50c2 config/.env` (also reverts the sandbox tag), `ln -sfn releases/958022b current`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 web`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-5b6d9b6/' config/.env`, then `up.sh --env-file … --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.

## Release 5b6d9b6 — 2026-09-24 (Diary hardening, model manager + code sandbox hardening, per-service tags; sidecars only)

### Services

- **Web:** no change — stays `cowork-web:958022b` (`current` and `COWORK_VERSION` untouched).
- **Diary:** [#77](https://github.com/sbstndalton/noevia/pull/77), [#84](https://github.com/sbstndalton/noevia/pull/84), [#87](https://github.com/sbstndalton/noevia/pull/87), [#93](https://github.com/sbstndalton/noevia/pull/93), [#94](https://github.com/sbstndalton/noevia/pull/94), [#99](https://github.com/sbstndalton/noevia/pull/99) — deployed as `cowork-diary:5b6d9b6` (agent/ overlay).
- **Model manager:** [#79](https://github.com/sbstndalton/noevia/pull/79) — deployed as `cowork-model-loader:5b6d9b6` (app/ overlay).
- **Code sandbox:** [#79](https://github.com/sbstndalton/noevia/pull/79) — deployed as `cowork-code-sandbox:pi-0.87.0-5b6d9b6` (supervisor.cjs overlay).
- **OCR:** no change — `cowork-ocr:5004b50`.
- **Docling:** no change — `cowork-docling:2026-09-21`.
- **Deploy/infra:** [#104](https://github.com/sbstndalton/noevia/pull/104), [#106](https://github.com/sbstndalton/noevia/pull/106) merged; live `.env` and Compose Manager files migrated to `DIARY_VERSION`/`OCR_VERSION`/`MODEL_MANAGER_VERSION`.

Source shipped via `git archive 5b6d9b6` to `releases/5b6d9b6`. Before building, diffs against the
running sources were confirmed limited to Diary `agent/` (+ tests, README), model manager `app/*.py`
(+ tests) and code sandbox `supervisor.cjs`; Dockerfiles and requirements identical, so every image
is an overlay `FROM` the running one with no pip/npm step.

1. Per-service tags: backed up `docker-compose.yml`, `docker-compose.override.yml` and `.env` as
   `*.bak.before-per-service-tags`; diary/ocr/model-loader image lines switched to the required
   variables, pinned to the running tags (5004b50/5004b50/a1ededd). `compose config` resolved every
   cowork image to its running tag and a dry-run `up` recreated nothing; no container changed.
2. Model manager `sha256:869beb3f…`: recreated `model-loader` only (guarded `up.sh`), healthy,
   `/api/v1/health` 200 from web; api.py in the container matches the release (shardBase guard).
3. Code sandbox `sha256:ba39f7fc…`: recreated `code-sandbox` only (`up.sh --env-file … --profile code --`),
   running with zero restarts, supervisor.cjs SHA-256 matches the release, TCP reachable from web.
4. Diary `sha256:ab519fdf…`: `diary-overlay.sh 5b6d9b6` took appdata backup
   `ab_20260924_130511` (verified; it stops/starts web and diary, so web kept its container id
   but has a new start time), recreated diary only, healthy, health via web 200.

All other cowork containers (laya, llama, embed, ocr, docling, kiwix) kept identical ids and start
times. Public `/` 200, `/api/profile` 401.

Rollback (from the Compose Manager project directory; old images untouched):
- Model manager: `sed -i 's/^MODEL_MANAGER_VERSION=.*/MODEL_MANAGER_VERSION=a1ededd/' config/.env`, then `up.sh --env-file … -- -d --no-build --no-deps --wait --wait-timeout 180 model-loader`.
- Code sandbox: `sed -i 's/^CODE_SANDBOX_VERSION=.*/CODE_SANDBOX_VERSION=pi-0.87.0-99be0a2/' config/.env`, then `up.sh --env-file … --profile code -- -d --no-build --no-deps --wait --wait-timeout 180 code-sandbox`.
- Diary: `sed -i 's/^DIARY_VERSION=.*/DIARY_VERSION=5004b50/' config/.env` (or restore `config/.env.bak.before-diary-5b6d9b6`), then `up.sh … diary`.
- Per-service-tag migration: restore the three `*.bak.before-per-service-tags` files.

## Release 958022b — 2026-09-24 (job start controller leak, phone preview Settings, web-only)

### Services

- **Web:** [#102](https://github.com/sbstndalton/noevia/pull/102) — deployed as `cowork-web:958022b`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#102](https://github.com/sbstndalton/noevia/pull/102) starting a background job no
longer leaks a controller when the journal write fails; the phone preview on desktop collapses
Settings panes like a real phone.

CI green on `958022b`. Deployed via `git archive 958022b` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/958022b`, built as
`cowork-web:958022b`
(`sha256:ee934d3dc820296cd3f567ed17686ada0a07aaad6c2897295d0a805ca362e9fd`). Config and the
live Compose Manager file were backed up as `*.bak.before-958022b`; `current`/`COWORK_VERSION`
were repointed at `958022b`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:c3a03c7`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-BaEAos9j.js` and `index-CVYcHCIL.css` are present in the image's `dist/assets`;
no error/unreadable lines in the startup log.

Rollback: `config/.env.bak.before-958022b` and the Compose Manager
`docker-compose.yml.bak.before-958022b` restore `current` to `releases/c3a03c7`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release c3a03c7 — 2026-09-24 (account cleanup, job journals, research saves, code harness hardening, web-only)

### Services

- **Web:** [#98](https://github.com/sbstndalton/noevia/pull/98), [#99](https://github.com/sbstndalton/noevia/pull/99), [#100](https://github.com/sbstndalton/noevia/pull/100), [#101](https://github.com/sbstndalton/noevia/pull/101) — deployed as `cowork-web:c3a03c7`.
- **Diary:** [#99](https://github.com/sbstndalton/noevia/pull/99) (Diary part) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#98](https://github.com/sbstndalton/noevia/pull/98) deleting a user removes their MCP
sign-ins and directory keys; disabled admin credentials are no longer used for discovery; WebDAV
hrefs decode HTML entities; `$` in key templates is handled literally;
[#99](https://github.com/sbstndalton/noevia/pull/99) one unreadable job journal no longer blocks other background
jobs; [#100](https://github.com/sbstndalton/noevia/pull/100) research reports save to the current project by id,
the phone preview honours `data-layout` in JS checks, and the approval card re-enables after a
decision; [#101](https://github.com/sbstndalton/noevia/pull/101) code harness config writes refuse symlinks,
approvals are answered by id, the engine key is never committed (tracked config is refused and
pinned files are removed before auto-commit), and grants are released once. Diary changes in #99
are merged but not deployed by this web-only release.

CI green on `c3a03c7`. Deployed via `git archive c3a03c7` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/c3a03c7`, built as
`cowork-web:c3a03c7`
(`sha256:57bccee21803427c2c8ee3a28a0c187798f887d4652071def4a52fa94de0c275`). Config and the
live Compose Manager file were backed up as `*.bak.before-c3a03c7`; `current`/`COWORK_VERSION`
were repointed at `c3a03c7`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 34 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:852ef76`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-DTEDzgUo.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`cwdPinPaths` is a function in the running container; no error/unreadable lines in the startup log.

Rollback: `config/.env.bak.before-c3a03c7` and the Compose Manager
`docker-compose.yml.bak.before-c3a03c7` restore `current` to `releases/852ef76`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 852ef76 — 2026-09-24 (S3 region, storage secret v2, replay history, web-only)

### Services

- **Web:** [#96](https://github.com/sbstndalton/noevia/pull/96), [#97](https://github.com/sbstndalton/noevia/pull/97) — deployed as `cowork-web:852ef76`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#96](https://github.com/sbstndalton/noevia/pull/96) S3 connections store and sign with a
region (new `storage_connections.region` column, default `us-east-1`, migrated at startup); storage
secrets are always encrypted and bound to the account (v2), and legacy v1 secrets are upgraded on
read; [#97](https://github.com/sbstndalton/noevia/pull/97) model replay merges adjacent same-role turns and never
starts with an assistant turn; WebDAV MOVE/COPY default `Overwrite` to `T` per RFC 4918.

CI green on `852ef76`. Deployed via `git archive 852ef76` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/852ef76`, built as
`cowork-web:852ef76`
(`sha256:25a1b70c5f1dfea627f34bb06a6abbdea4e7512c0562ceb9ca6f48f576ac0c79`). Config and the
live Compose Manager file were backed up as `*.bak.before-852ef76`; `current`/`COWORK_VERSION`
were repointed at `852ef76`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:0c2be32`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-SGaWTEhw.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`normalizeReplayHistory` is a function in the running container; no error/migration lines in
the startup log.

Rollback: `config/.env.bak.before-852ef76` and the Compose Manager
`docker-compose.yml.bak.before-852ef76` restore `current` to `releases/0c2be32`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 0c2be32 — 2026-09-24 (routing model, Diary edit proxy and offsite backup hardening, web-only)

### Services

- **Web:** [#90](https://github.com/sbstndalton/noevia/pull/90), [#91](https://github.com/sbstndalton/noevia/pull/91), [#92](https://github.com/sbstndalton/noevia/pull/92), [#95](https://github.com/sbstndalton/noevia/pull/95) — deployed as `cowork-web:0c2be32`.
- **Diary:** [#93](https://github.com/sbstndalton/noevia/pull/93), [#94](https://github.com/sbstndalton/noevia/pull/94) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#90](https://github.com/sbstndalton/noevia/pull/90) Details/Configure hide tuning and calibration for the system
routing model, and the Settings routing summary wraps at narrow widths; [#91](https://github.com/sbstndalton/noevia/pull/91) the Diary
edit proxy forwards `base_hash` and relays 409 conflicts; [#92](https://github.com/sbstndalton/noevia/pull/92) fixes offsite S3 listing
with a "/" prefix and adds a Drive-copy busy-lock guard; [#95](https://github.com/sbstndalton/noevia/pull/95) the Drive mirror never
prunes a foreign backup store (store id, sibling folder, 25% guard, serialized runs), caps
storage reads/listings, and fixes SigV4 canonical path encoding. [#93](https://github.com/sbstndalton/noevia/pull/93) (Diary trash long
names) and [#94](https://github.com/sbstndalton/noevia/pull/94) (Diary tenant delete race, fixed 502 text) are merged but NOT deployed by
this web-only release.

CI green on `0c2be32`. Deployed via `git archive 0c2be32` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/0c2be32`, built as
`cowork-web:0c2be32`
(`sha256:ecb14d6ef8aafcb22d72e6282eaaf672375c8690afae11691bafb8a0123ee257`). Config and the
live Compose Manager file were backed up as `*.bak.before-0c2be32`; `current`/`COWORK_VERSION`
were repointed at `0c2be32`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7e8ce3a`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-94Ntc5E5.js` and `index-C7qt3UiI.css` are present in the image's `dist/assets`;
`/app/server/offsite-s3.cjs` loads in the running container.

Rollback: `config/.env.bak.before-0c2be32` and the Compose Manager
`docker-compose.yml.bak.before-0c2be32` restore `current` to `releases/7e8ce3a`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7e8ce3a — 2026-09-24 (code-workspace and Drive hardening, web-only)

### Services

- **Web:** [#86](https://github.com/sbstndalton/noevia/pull/86), [#88](https://github.com/sbstndalton/noevia/pull/88) — deployed as `cowork-web:7e8ce3a`.
- **Diary:** [#87](https://github.com/sbstndalton/noevia/pull/87) — merged, not yet deployed.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#86](https://github.com/sbstndalton/noevia/pull/86) the code-workspace
release refuses harness-planted git hooks, filters and fsmonitor, and runs git with them
disabled; [#88](https://github.com/sbstndalton/noevia/pull/88) caps Drive reads (Range request
plus a streamed cap), makes autoconfig suggest only calibrator-verified context sizes, and adds
InstructionSkills guards. [#87](https://github.com/sbstndalton/noevia/pull/87) (Diary
index_update validation and quarantine) is merged but NOT deployed by this web-only release.

CI green on `7e8ce3a`. Deployed via `git archive 7e8ce3a` (no local checkout modified; archive
SHA-256 matched after upload) to `/mnt/docker/appdata/cowork/releases/7e8ce3a`, built as
`cowork-web:7e8ce3a`
(`sha256:e0400c5f93df8e60b598934c74080fb344f94736578a4a07ae5d50c870ca99e7`). Config and the
live Compose Manager file were backed up as `*.bak.before-7e8ce3a`; `current`/`COWORK_VERSION`
were repointed at `7e8ce3a`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only, from the Compose Manager project directory. All 42 non-web
container IDs and start times were identical before and after.
`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7ce2213`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-B6Wdf04v.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`;
`/app/server/code-workspace.cjs` loads in the running container.

Rollback: `config/.env.bak.before-7e8ce3a` and the Compose Manager
`docker-compose.yml.bak.before-7e8ce3a` restore `current` to `releases/7ce2213`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7ce2213 — 2026-09-24 (hardening batch, web-only)

### Services

- **Web:** [#76](https://github.com/sbstndalton/noevia/pull/76), [#80](https://github.com/sbstndalton/noevia/pull/80), [#81](https://github.com/sbstndalton/noevia/pull/81), [#82](https://github.com/sbstndalton/noevia/pull/82), [#83](https://github.com/sbstndalton/noevia/pull/83), [#85](https://github.com/sbstndalton/noevia/pull/85) — deployed as `cowork-web:7ce2213`.
- **Diary:** [#77](https://github.com/sbstndalton/noevia/pull/77), [#84](https://github.com/sbstndalton/noevia/pull/84) — merged, not yet deployed.
- **Model manager:** [#79](https://github.com/sbstndalton/noevia/pull/79) — merged, not yet deployed.
- **Code sandbox:** [#79](https://github.com/sbstndalton/noevia/pull/79) — merged, not yet deployed.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

Web changes deployed: [#76](https://github.com/sbstndalton/noevia/pull/76) server error
bodies no longer leak raw errors, JSON bodies are checked, chat ids are sanitized and
approvals are scoped; [#80](https://github.com/sbstndalton/noevia/pull/80) and
[#83](https://github.com/sbstndalton/noevia/pull/83) guard the system model (Laya) from
delete, calibration, preset apply and section delete/rename, and gate research maintenance;
[#81](https://github.com/sbstndalton/noevia/pull/81) hides system-model rename/delete in the
Configure tab, merges racing history loads and orders stats updates;
[#82](https://github.com/sbstndalton/noevia/pull/82) caps and aborts MCP responses and makes
the diary stream and tool arguments robust; [#85](https://github.com/sbstndalton/noevia/pull/85)
makes chat delete stop the reply and block saves, resets the project view on switch, and keeps
merged roles alternating. [#77](https://github.com/sbstndalton/noevia/pull/77),
[#79](https://github.com/sbstndalton/noevia/pull/79) and [#84](https://github.com/sbstndalton/noevia/pull/84)
(Diary service, model-manager, code-sandbox) are merged but NOT deployed by this web-only release.

CI green on `7ce2213`. Deployed via `git archive 7ce2213` (no local checkout modified) to
`/mnt/docker/appdata/cowork/releases/7ce2213`, built as `cowork-web:7ce2213`
(`sha256:e3605b2deabbd04561cfe1312c0b47e131540563f97a599f7b9153a1575b6c0a`). Config and the
live Compose Manager file were backed up as `*.bak.before-7ce2213`; `current`/`COWORK_VERSION`
were repointed at `7ce2213`. Cutover used the guarded preflight `--no-build --no-deps --wait
--wait-timeout 180 web` only (it must run from the Compose Manager project directory; the first
attempt from another cwd was blocked before any change). All 42 non-web container IDs and start
times were identical before and after.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:7b6942c`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-DoBtRaex.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`;
`errorResponse` from #76 is exported in the running container.

Rollback: `config/.env.bak.before-7ce2213` and the Compose Manager
`docker-compose.yml.bak.before-7ce2213` restore `current` to `releases/7b6942c`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`
from the Compose Manager project directory.

## Release 7b6942c — 2026-09-24 (chat save races)

### Services

- **Web:** [#75](https://github.com/sbstndalton/noevia/pull/75) — deployed as `cowork-web:7b6942c`.
- **Diary:** no change.
- **Model manager:** no change.
- **Code sandbox:** no change.
- **OCR:** no change.
- **Docling:** no change.
- **Deploy/infra:** no change.

[PR #75](https://github.com/sbstndalton/noevia/pull/75) fixes chat save races while replies
stream. The chat list no longer drops a chat when two sends overlap; a save conflict during
a streaming reply no longer replaces the transcript or loses the reply; and persisting was
moved out of the React state updater. Deployed web-only via `git archive 7b6942c` (no local
checkout modified) to `/mnt/docker/appdata/cowork/releases/7b6942c`, built as
`cowork-web:7b6942c` (`sha256:da15caf99d8e8d3b40bbf177ea9feaf40a6a297ce6bfd5e262592b3e17ad542a`).
Config and the live Compose Manager file were backed up as `*.bak.before-7b6942c`;
`current`/`COWORK_VERSION` were repointed at `7b6942c`. Cutover used the guarded preflight
`--no-build --no-deps --wait --wait-timeout 180 web` only; all 42 non-web container IDs and
start times were identical before and after.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:9ee7bb0`).
Public checks: `/` returned 200 and `/api/profile` returned 401 (3/3 tries); the served
`index-RdBcm5Rx.js` and `index-B1OLP7Ag.css` are present in the image's `dist/assets`.
Later PRs merged to main after 7b6942c are not part of this release.

Rollback: `config/.env.bak.before-7b6942c` and the Compose Manager
`docker-compose.yml.bak.before-7b6942c` restore `current` to `releases/9ee7bb0`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 9ee7bb0 — 2026-09-23 (Laya excluded from auto-tuner)

[PR #74](https://github.com/sbstndalton/noevia/pull/74) blocks the auto-tuner from
selecting or deleting `laya_multilingual_f16`. Deployed web-only via `git archive
9ee7bb0` (no local checkout modified) to `/mnt/docker/appdata/cowork/releases/9ee7bb0`,
built as `cowork-web:9ee7bb0` (`sha256:b0c2f0ef69c671465864ad80ed4df9456fac647aacbf5dfd33802eceb2d98ced`).
Config and the live Compose Manager file were backed up as `*.bak.before-9ee7bb0`;
`current`/`COWORK_VERSION` were repointed at `9ee7bb0`. Cutover used the guarded
preflight `--no-build --no-deps --wait --wait-timeout 180 web` only; no other
service was rebuilt or restarted.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:6b59118`).
Read-only, without starting a tune, `require('/app/server/model-system.cjs')` inside
the running container confirmed `isSystemModel('laya_multilingual_f16')` returns
`true` (reason: "System routing model — not tuned"/"not deleted"), while an ordinary
model ID returns `false`. Locally the container answered its root path with the
expected unauthenticated 302 redirect and the built `dist/assets` matched the served
bundle name pattern from prior releases.

**Public HTTPS verification did not complete.** `https://noevia.daserver.work/` and
`/api/profile` both returned Cloudflare edge error 530 at cutover and on retries; the
`CloudflaredTunnel` container logs show persistent QUIC dial timeouts to Cloudflare's
edge starting around the same time, while `ping 1.1.1.1` from the host showed 0%
loss, indicating an outbound tunnel/edge problem rather than home WAN loss or a web
regression. `CloudflaredTunnel` was left untouched (out of scope for a web-only
release) and was not restarted. Laya (`cowork-laya:0.3.5-recovery-2ffd153`), Diary,
OCR, code-sandbox, model-loader, docling and the native llama engine kept identical
container IDs and `StartedAt` timestamps before and after cutover. Web was not
rolled back because the failure is isolated to the tunnel, reproducible without any
version dependency, and the container itself is verified healthy locally; the public
200/401 checks remain outstanding and must be reconfirmed once the tunnel recovers. Reconfirmed after the tunnel recovered without restarting it: `/` returned 200 and `/api/profile` returned 401 (3/3 tries), and the served `index-C1P7G4yr.js` and `index-B1OLP7Ag.css` are present in the `cowork-web:9ee7bb0` image.

Rollback (only needed if the web image itself is found to be at fault):
`config/.env.bak.before-9ee7bb0` and the Compose Manager
`docker-compose.yml.bak.before-9ee7bb0` restore `current` to `releases/6b59118`,
then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 6b59118 — 2026-09-23 (Auto routing label in inference stats and saved replies)

[PR #69](https://github.com/sbstndalton/noevia/pull/69) shows the Auto routing decision
alongside inference stats and in saved replies. Deployed web-only, staged via
`git archive 6b59118` (no local checkout modified) to
`/mnt/docker/appdata/cowork/releases/6b59118`, built as `cowork-web:6b59118`
(`sha256:ddf73b888f317e70c2e894ecb1b856bca104704f3aebbc746252882b9ecffa22`). Config and
the live Compose Manager file were backed up as `*.bak.before-6b59118`; `current` and
`COWORK_VERSION` were repointed at `6b59118`. Cutover used the installed guarded preflight
`--no-build --no-deps --wait --wait-timeout 180 web`; no other service was rebuilt,
restarted or touched.

`cowork-web-1` came up healthy with zero restarts (previous image `cowork-web:6b1621c`).
`https://noevia.daserver.work/` returned 200 and `/api/profile` returned 401 unauthenticated.
Served `index.html` referenced `index-CU_LuO7r.js` and `index-B1OLP7Ag.css`, both present
byte-identically in the built image's `dist/assets`. Laya (`cowork-laya:0.3.5-recovery-2ffd153`),
Diary, OCR, code-sandbox, model-loader, docling and the native llama engine kept identical
container IDs and `StartedAt` timestamps before and after cutover; only synthetic checks were
used, no real tune or Diary access.

Rollback: restore `config/.env.bak.before-6b59118` and the Compose Manager
`docker-compose.yml.bak.before-6b59118`, repoint `current` at
`releases/6b1621c`, then rerun
`bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --no-deps --wait --wait-timeout 180 web`.

## Release 6b1621c — 2026-09-23 (auto-tune recovery and compact progress)

Auto-tune now waits until the router reports every model unloaded before saving the
next candidate profile. This prevents the immediate 409 that could follow a rejected
quality probe while the previous model was still unloading. A bounded timeout names
the blocking model and state; cancellation still restores the current phase. Failed
quality probes report the check and failure type without storing generated answers.
The Auto Tune panel puts status, progress and Resume above compact queued details.

[Issue #72](https://github.com/sbstndalton/noevia/issues/72) was fixed by
[PR #73](https://github.com/sbstndalton/noevia/pull/73), merged as `6b1621c`.
All 1,354 web tests, typecheck, build and design lint passed; the candidate web image
passed 32 isolated tuner/calibration tests. A web-only guarded overlay from `5004b50`
completed with the web container healthy. Public CSS and model-manager JavaScript
match the validated build; protected routes return 401 without authentication.
Brave review confirmed the deployed layout and recovery controls without resuming a
real tune. Diary, OCR, llama and the Laya recovery image retained their container
IDs and start times. Configuration and Compose backups named `.bak.before-6b1621c`
are retained for web-only rollback to `5004b50`; no full appdata backup was run
because it would restart unrelated services. Historical state cannot explain why
the initial f16 quality probe failed.

## Release 827932b — 2026-09-22 (three-material refinement)

Removed the redundant Glassmorphism mode from preferences, pre-paint initialization,
settings, CSS and reference samples; old saved values fall back to Soft. Soft is matte
with restrained depth and visible switch boundaries. Liquid Glass is limited to functional
controls, with readable content, restrained highlights, no label refraction or pointer tilt,
and reduced-preference handling. Material 3 uses paired color roles, tonal selection,
correct pressed/disabled states and native-checkbox switch contrast. Shared geometry stays
stable. General now correctly distinguishes synced theme/accent from browser-local preferences.

`ui/material-refinement` (`7663b40`, `827932b`) was pushed, then fast-forwarded into main
from `9cf92b3` after a fresh fetch. No remote changes conflicted; no force push or branch
deletion. The original `ui-polish-update` checkout is unchanged and clean.

Validation: 1,247 unit tests, typecheck, build and design lint pass. Fourteen distinct
synthetic browser suites pass, including Code, approvals and onboarding in all three
materials. The broad inventory covers 468 states; the final focused confirmation covers
198 states, with zero detected overflow, matte-mode blur leaks or page errors. Both themes,
375/768/1440 widths, smaller approval/drawer viewports, keyboard focus and accessibility
preferences are covered. All 12 rendered switch on/off/mode/theme pairs meet 3:1 contrast.
The Impeccable detector's five dimension-animation findings were fixed. See the full
[material audit and iteration log](material-audit-2026-09-22.md) for evidence and scope limits.
No real Diary corpus, live model inference or user data was used for testing.

Backup `ab_20260922_143433` completed successfully; web, Diary and extra-file archives
independently passed `gzip -t`. Local/remote SHA-256 matched for source
`0731f040149d450e122841bd69443f7bb6475a1f50389c16125b933cde0c7d01` and app
`9b7232a1d68dbf4b6fb211de415f91d77b795eae39d437b1bf802c3c739b269d` archives.
Guarded overlay `04780e6` → `827932b` passed mount/env/tenant-isolation preflights and
reported `RELEASE_827932b_COMPLETE` at 14:46 EDT. Web, Diary and OCR are healthy with zero
restarts. Native engine, embeddings, pi sandbox and Laya IDs/start times are unchanged.
Laya remains pre-existing unhealthy. Existing volume/swap-limit warnings are unchanged.

Public index serves `index-U2SHbFp3.js` / `index-Dtub7VGn.css`; both and `theme.js`, `lens.js`,
`glass-highlight.js` match the local build byte-for-byte. Unauthenticated profile/admin-users
requests return 401; web logs contain zero error markers since cutover. A Python HTTP client
received 403; ordinary curl returned 200 and verified every public asset without changing any
edge/security configuration.

Rollback: restore `config/.env.bak.before-827932b`, point `current` at `releases/04780e6`,
then run the guarded no-build startup for web/diary/ocr. Old images, branches and backups
are retained. The subsequent main commit records rollout evidence only; deployed application
source is `827932b`.

## Release 04780e6 — 2026-09-22 (development branches integrated)

Integrated `ui-polish-update` (`7014b69`) and local
`codex/harness-hardening-claude-pi` (`c729379`) from `origin/main` (`506f0f8`).
The tuning commit already existed as a patch-equivalent change; no duplicate feature
or stale alternative was applied. Only documentation conflicted. See
[integration evidence](integration-2026-09-22.md).

1,245 unit tests, typecheck, build, design lint and 15 synthetic browser/HTTP suites
pass. Real pi 0.87.0 and Claude ACP 0.79.0 pass local scripted-model approval checks,
including hostile Claude repository resources. The Linux pi candidate passes the same
allow/decline fixture with no network or production volumes. The web image passes 80
isolated harness/approval/tuning tests. No real Diary corpus or live inference was used.

Backup `ab_20260922_135257` completed successfully; web, Diary and extra-file archives
independently passed `gzip -t`. Source/app archive checksums matched before deployment.
Guarded overlay `5a88558` → `04780e6` passed all preflights and reported
`RELEASE_04780e6_COMPLETE`. Web, Diary and OCR are healthy, zero restarts. The pi
sandbox was rebuilt from its Dockerfile with pi 0.87.0 and lifecycle scripts disabled,
then activated as `cowork-code-sandbox:pi-0.87.0-99be0a2`; its deployed bridge SHA-256
matches source, version is 0.87.0, and the container runs with zero restarts.

The first candidate package accidentally included a dependency symlink; Docker refused
it before cutover. The corrected archive excludes dependencies/state. The initial sandbox
activation put the profile flag after the wrapper separator; Compose refused it, the env
was restored, and the corrected preflight invocation succeeded. Neither failed attempt
ran an unvalidated candidate.

Public index serves `index-B5Qudv_W.js` / `index-3Twk2Xqu.css`; JavaScript SHA-256 matches
the local build. Unauthenticated model-tuning access returns 401, and web logs contain
zero error markers since cutover. Native llama, embeddings and Laya IDs/start times
are unchanged. Laya's pre-existing unhealthy status remains outside this release.
The existing unmanaged-volume and kernel swap-limit warnings remain unchanged.

Rollback: restore `config/.env.bak.before-04780e6` (including the old pi tag), point
`current` at `releases/5a88558`, then use the guarded preflight no-build startup for
web/diary/ocr and `--profile code -- -d --no-build --no-deps code-sandbox` for the
sandbox. The old release, pi image and backups are retained. The subsequent record
commit is documentation only; deployed application source is `04780e6`.

## 2026-09-22 — Complete automatic model tuning (release `5a88558`)

Models → Your models now has **Tune untuned models** beside **Check for updates**. One
confirmed maintenance window runs a sequential queue of configured chat models without a
current tune. It measures f16/q8/q4 KV cache, long-context recall, three existing-MTP-head draft
settings, n-gram and batch sizes. Three deterministic quality probes screen each setting; the
fastest passing complete profile is rechecked and applied automatically. 60–70% draft acceptance
is guidance, not a cutoff. No model/head downloads; no production benchmarks were started.

Changed artifacts, presets/defaults or engine builds invalidate a tune. Cancellation, failures
and interrupted runs restore the active model's original settings when safe, without overwriting
external edits. Earlier successful queue entries remain tuned. The probes are smoke tests, not
general quality certification. 1,242 tests, typecheck/build/design lint and both affected browser
suites pass; six responsive/theme layouts inspected. The deployed image passes all 10 synthetic
full-tuning tests. Native engine, embeddings and pi sandbox remain unchanged.

## 2026-09-22 — Claude Code and pi pins hardened (source only)

Claude Code now receives the full noevia-owned permission/model configuration inline, exposes a
fixed core tool set, and loads no settings, context, hooks, skills/commands or MCP servers from the
checked-out repository. Its own sandbox can no
longer auto-approve Bash, and both automatic and manual self-update paths are off. pi starts with
only noevia's approval gate and a fixed tool set, never loads project resources or context, makes no startup
network checks, saves no session, and waits for the true whole-turn completion event. Its package
install can no longer run lifecycle scripts. Codex remains refused because it cannot meet the
per-command approval rule. Verified with fake ACP/pi processes; no CLI was installed, no model was
run, and this source change is not deployed.

## 2026-09-22 — Code mode now runs pi

The coding agent in Code mode is now **pi**, the minimal agent many forks start from. It runs in
the same locked-down sandbox. Because pi normally never asks before acting, noevia adds its own
gate: every edit and command shows up on your approval card first, with the exact command or
file. Tested live twice on the throwaway `scratch` repository: it fixed the bug and the tests
pass. OpenCode is still installed and one setting away.

## 2026-09-22 — Diary service updated

The Diary service now keeps the previous version in Trash when a WebDAV client overwrites a
file, and reports each file's last-modified time so sync apps like Obsidian can tell what
changed. Nothing else in the Diary changed, and no Diary data was touched. File sharing (WebDAV)
remains off until you turn it on.

## 2026-09-22 — A local graph for Diary notes

Open a note in the Diary editor and expand **Local graph** to see the notes it links to and the
notes that link back, as a small diagram and a list you can click. Links you have just typed show
straight away. Two-way links are drawn heavier, incoming links dashed. It only reads: nothing is
indexed or changed, and it says so when the backlink scan could not cover every file.

## 2026-09-22 — Claude Code and pi can be pinned; Codex refused (releases `59249d9`, `d59d1a0`, `2577e16`)

Nothing changes in Code mode today; it still runs OpenCode. noevia now knows how to lock down
more coding agents the way it locks OpenCode: every edit, command and web access asks you,
the agent's own "skip permissions" modes are off, it talks only to your local engine, and it does
not update itself or send telemetry. For pi, which has no permission prompts of its own, noevia
installs a gate that asks for every non-read action and blocks if it cannot ask. Installing any
of them in the sandbox is your call. Tested with the real Claude Code and pi against a scripted
fake model: approvals reach you, Decline blocks, and a repository's own settings can't skip the
question. Codex was tested the same way and is **refused**: its commands ran without asking.

## 2026-09-22 — Step supervision stops pausing ordinary chats (release `b055571`)

With Step supervision on, Laya sometimes stopped a harmless chat for review (for example after a
plain project list) and added needless "double-check" rounds. New wording, measured on synthetic
cases: 16/17 on a fresh set with no needless pauses or extra rounds, and every synthetic
dangerous case (hidden instructions, credential requests, destructive commands) still stops.

## 2026-09-22 — System-One decisions show up in the web log (release `e19119d`)

Each routing and supervision decision writes one line — chosen role or action, margin, time
and whether it fell back — and never the message. This is how the next tuning step gets real
evidence instead of synthetic cases.

## 2026-09-22 — System-One routing picks Smart and Code when it should (release `6c3cde0`)

Laya was routing most reasoning and code questions to the Fast model. Probing it with the exact
requests production sends, on synthetic messages, showed the abstract role descriptions were the
cause: 23 of 40 held-out decisions right. Concrete descriptions ("greetings, thanks, or a
one-line factual answer" / "explaining, comparing, planning…" / "anything involving programming
code…") score 36 of 40; the rest are near-ties. Step supervision was checked the same way (8/9)
and left alone. Fallbacks, manual model choice and approvals are unchanged.
[Evidence](research/system-one/19-routing-labels.md).

## 2026-09-22 — Request-local live inference readouts (source `80d116f`, deployed in `e7b59d6`)

The inference footer now follows the visible chat's own event stream instead of treating the
engine-wide `/api/stats` poll as reply telemetry. It shows the routed model and generating state
immediately, records server-observed first output as it arrives, and applies provider-reported
tokens, rate and MTP acceptance without waiting for the next poll. Tool-loop rounds are
cumulative and use a weighted provider rate. Missing measurements remain explicitly unavailable;
they are never guessed from chunks or text. Engine totals/hardware stay separately labelled, so
another chat or a stale poll cannot replace the visible reply's facts.

Verification: 39 focused telemetry/tool-loop tests and 1,111 socket-free tests pass; typecheck,
production build (195 modules), design lint and diff whitespace checks pass. The full suite could
not complete in this task sandbox: 34 listener-based tests were refused with `listen EPERM`, while
1,143 tests passed and no assertion failure was observed. A fully synthetic, port-free browser QA
was added, but Chromium launch and visual inspection were blocked by the task's browser sandbox.
No inference, benchmark, paid endpoint, personal source or Diary data was used. Production remains
on `3d2521d` until the pushed source is deployed and checked on DaServer.

## 2026-09-22 — Compact context inside tool continuations

The chat loop now rechecks and, when necessary, compacts its model-facing projection before
every continuation after tool execution. The saved transcript and cross-turn summary remain
unchanged. The current user turn, assistant tool calls and their matching results stay
byte-identical and atomic; invalid or oversized protected groups stop with a readable error
without deleting messages, fabricating results or replaying tools. Continuation summaries use
the existing provider-neutral compaction call and conservative context estimate, in bounded
rolling batches. The context meter and opt-in context log report the compacted continuation.

Verification: 1,196 web tests, typecheck, production build, design lint and diff whitespace
checks pass. Focused coverage forces the real handler over budget between tool rounds and
confirms the next request receives a summary plus the intact current tool group. No model
inference, paid endpoint, personal source or Diary data was used.

Deployed as `3d2521d` after verified backup `ab_20260922_020935`; release preflights,
application/Laya health, public HTTP and clean-log checks passed. Native inference, embedding
and Laya container identities/start times remained unchanged.

### 2026-09-21 — Material 3 shares component geometry

## 2026-09-22 — Configure and enable Laya routing in Experimental

Added shared decision-service setup with editable URL/deadline, installed-Laya shortcut,
health-only connection test and persistent admin Save. Routing now uses the configured
Laya service for Fast/Smart/Code instead of requiring the old option-logit endpoint.
Settings apply to subsequent routing and supervision decisions without restart.
1192 tests, typecheck, build and design lint pass; scoped light/dark responsive UI verified.
See [configuration and verification](research/system-one/18-decision-service-settings.md).

## 2026-09-21 — Laya endpoint for model-independent step supervision

Connected the experimental checkpoint seam to a private typed-decision service.
Laya uses a separate CPU-only, offline serving container; the selected answering
provider (including OpenRouter/OpenAI-compatible endpoints) remains unchanged.
Validated bounded responses, no redirects or shared answering credentials, and
existing fallback/approval limits. Pinned model/runtime and optional Compose profile.
One authorized synthetic Laya inference passed on DaServer; no benchmarks.
See [service scope and setup](../services/laya/README.md).

## 2026-09-21 — Experimental step supervision

Added a separate unavailable-by-default Experimental entry and a provider-neutral chat
checkpoint seam. Mocked decisions can continue, request a bounded verification round,
or pause for review. Failed decisions preserve existing behavior; durable escalation
uses the existing checkpoint store and blocks automatic restoration. No Jev/Laya calls,
model switching or replay. 1181 web tests, typecheck, build and design lint pass.
See [scope and verification](research/system-one/17-step-supervision.md).

Material 3 now inherits the shared dimensions, padding, font metrics and layout borders
instead of replacing them. Tonal colors, radii, shadows and inset outlines retain the
Material appearance. Removed the width-changing selected checkmark and matched segment
font weights; rounded selection fills stay within wrapped tracks. Sidebar spacing also
uses the common tokens. Regression test rejects Material-only geometry overrides.

Verification: 1171 unit tests, typecheck/build/design lint and diff whitespace checks pass.
Synthetic browser comparison: 43 settings/navigation boxes match exactly across Soft,
Liquid glass, Glassmorphism and Material 3 at 375 and 1440 CSS px, plus the normal desktop
viewport. Visually inspected the corrected selection fills. No model or personal-data tests.

### 2026-09-21 — Descriptions above settings controls at every width

Corrected the requested layout: shared settings descriptions occupy their own full-width
row above buttons/selectors even on wide desktops. Compact on/off switches retain their
inline label. Wrapped segmented choices remain visible. This supersedes the prior
width-dependent placement in 126637e.

### 2026-09-21 — Release 126637e deployed

User authorized automatic deployment. Live now includes the shared responsive-control fixes,
Experimental settings and prior bounded continuation source changes. Backup and preflight
passed; all checked services healthy, public HTTP 200. Live Material text/options visually
verified. System-One remains off/unconfigured, durable chat inactive, native engine unchanged.
See [deployment verification and rollback](deployment.md#release-126637e--2026-09-21-shared-responsive-controls-and-experimental-routing).

### 2026-09-21 — Shared settings and segmented-control wrapping (local, undeployed)

Fixed the shared flex-row cause of one-word-per-line descriptions and clipped controls.
Settings rows now wrap by their available content width, including narrow desktop panels;
text retains a readable minimum width and control/value groups stay within the card.
Segmented controls throughout the app wrap instead of hiding options in a horizontal
scroller. Their selection highlight now tracks both axes and the selected button height,
including Material 3. Coding composer action groups also wrap within their available width.

Verification: 1170 unit tests passed; typecheck, build, design lint and diff whitespace
checks passed. Synthetic browser checks reproduced the original narrow desktop General
settings and confirmed readable descriptions and all Material choices visible. Checked
Material/Density/Motion/Layout at 375, approximately 768 (767 due to browser zoom rounding),
and 1440 CSS pixels: no document or segment overflow. Verified second-row Material 3
selection/highlight alignment, light/dark styling, capability label/value rows and the
Experimental switch page. Desktop screenshots were inspected; viewport override screenshots
still suffer the in-app browser's tiled-capture issue. A complete every-view/two-theme sweep
and physical-device testing were not run. No live preferences or data changed; no deployment.

### 2026-09-21 — Experimental System-One routing switch (local, undeployed)

Settings → Experimental now exposes an administrator-only System-One routing switch,
using the existing persisted/audited feature registry. On selects the option-logit
comparison baseline for new Auto role decisions; off restores the existing classifier.
Failures and deadlines fall back to that classifier. Requires an explicitly configured
private decision endpoint; no model is loaded, downloaded or selected automatically.
1170 unit tests, typecheck, build and design lint passed. Synthetic browser checks covered
save/reload, keyboard rollback and mobile/desktop presentation. See
[implementation and verification](research/system-one/16-experimental-routing.md).
No deployment or real inference. Dedicated System-One model selection remains open.

### 2026-09-21 — Default model mode setting (release c53713b, deployed)

### 2026-09-21 — Broader continuation verification (local, undeployed)

Added separate-process SIGKILL tests for durable generation and ambiguous tool execution.
Verified 1164 web tests, 64 decision/experiment tests, four synthetic real-HTTP suites,
typecheck/build/design lint, and targeted browser tool/approval/responsive checks.
Read-only live checks found Diary disabled for the account and a Nextcloud viewer registration
console error; no file-preview failure reproduced. See [exact scope and results](verification-2026-09-21-continuation.md).
No production changes, model inference or personal data operations.

### 2026-09-21 — First durable-chat slice (local, disabled, undeployed)

Added an optional chat recorder using the existing tenant job journal, with fsynced hash chains,
canonical tool results separate from context projections, stable turn identity, approval history
and persisted retry limits. Mocked replacement generation preserves completed tool results;
ambiguous execution requires review and cannot replay. No production wiring or switching.
See [implementation scope and exact verification](research/system-one/15-durable-chat-slice.md).
Focused durability/regression tests: 45 passed. Final web suite: 1162 passed; typecheck, build
and design lint passed. No live provider, Diary, engine, downloads or deployment involved.

### 2026-09-21 — Adapter cutoff and conditional bounds (local, undeployed)

Applied the reviewed continuation patch at its exact d6e7081 base. Independent run budget
covers version/startup/requests; cleanup is bounded and recorded separately. Partial option
scores now carry normalized conditional bounds and reject malformed distributions.
Current-repository verification: focused tests 28/28; existing decision/experiment tests 36/36;
web unit suite 1138/1138; typecheck, build and design lint pass with installed dependencies.
Only synthetic Node workers ran. No inference, downloads, live checks or deployment.

Models → Routing has a new "Default model mode" panel with an Auto/Manual choice for new projects. It is stored per workspace in `preferences.json` and replaces the browser-local setup-wizard flag; the wizard now writes this setting. "Switch existing projects to <mode>" rewrites that user's projects only. `GET/PUT /api/routing-default` takes `{ routing, applyToExisting }`. At the user's request, all 205 Manual projects in the `sebastian` workspace were switched to Auto, making 224/224 Auto; the member workspace (Ernestpov, 1 project) was switched too, at the user's request. 1,117/1,117 unit tests; `qa/models-settings` extended and green.

### 2026-09-21 — Auto routing is the default (release f9dc5df, deployed)

At the user's request, new projects are created with Auto (Fast/Smart) routing unless Manual is asked for. This replaces the step-12 Manual default. The setup wizard's Auto box starts ticked, and unticking it stores `manual`. Existing projects keep their setting. Auto with no Fast/Smart roles configured now uses the project's model instead of refusing the message. Also in this release: the multi-hop rerun on the fixed corpus. Rerank 12→6 got 3/4 against 2/4 for the baseline, and 24→3 got 1/4, which supports keeping 6. 1,116/1,116 unit tests; typecheck clean.

### 2026-09-21 — RAG rerank in chat (release 67f336e, deployed)

Project retrieval now takes a cosine pool (`RAG_RERANK_POOL`, default 12, max 24) and lets Qwen3-Reranker-0.6B pick the chunks kept (`RAG_RERANK_KEEP`, default 6) through the decision layer (`decisions.rank()`, `llama-rerank` backend). A down, malformed or slow reranker (`RAG_RERANK_DEADLINE_MS`, default 3000) falls back to the cosine top-6 used before, so chat never waits past the deadline. The whole feature is behind `NOEVIA_FEATURE_RAG_RERANK` + `RERANK_BASE_URL`. The engine's model manager keeps `RERANK_MODEL` loaded beside the chat model, the way it keeps the embedding model. Placement (the user's choice): the reranker is the router's second resident, `reranking = true` / `pooling = rank` in `models.ini`. Embeddings stay on the CPU `embed` container. DaServer GPU timing, warm: 12 chunks ~1.95 s, 24 ~3.9 s (CPU was ~21 s). The prototype scored 12→6 at 89%, 24→6 at 86% and 24→3 at 91%; keep stays at 6 because at 3 one exact-number demotion loses the answer. 1,115/1,115 unit tests.

### 2026-09-21 — Curated plugin starters (release 067ac1d, deployed)

`server/plugin-starters.json` is noevia's starter list: five first-party hosted MCP servers (Exa, Notion, Linear, Hugging Face, Cloudflare docs) and six Anthropic skills, each with a one-line reason. `GET /api/plugins/directory?starters=1` resolves them against the live registry and skills repository (cached an hour), keeps their order and drops any that vanished. The Plugins page shows them as "Recommended by noevia" above each directory until you search. Verified from DaServer: 5 servers, 6 skills. 1,103/1,103 unit tests; `qa/shared-sidebar` extended and green.

### 2026-09-21 — Ordinary WebDAV clients can write (release 42540fb, web only)

rclone, Finder, Explorer and Obsidian sync send no `If-Match`, so every DAV write was refused (428). Per the user's decision, DELETE and MOVE without `If-Match` use the version read at request time (both reversible); an untagged `Overwrite: T` reads the destination's version (the replaced file goes to Trash); a PUT over an existing file first keeps its bytes in Trash through the companion's new `preserve` op — restorable beside the file as `<name> (replaced <UTC time>).md` — then writes against the version just read. Protected files still require `If-Match`. New `qa/dav-interop.cjs` runs rclone against the real web server and the real companion on a throwaway tenant: 18/18. Web released; the Diary image is not rebuilt (the live Diary stays untouched), and DAV sharing remains off live (`COWORK_DAV_PORT=0`).

### 2026-09-21 — Shared context across a project's Chat and Code modes (release dbfbd92, deployed)

`shared-context.cjs`: `project.sharedContext = { chat, code }`, both off by default, validated on the project config route. Sharing into Code prepends the project's goal, instructions, memories and up to eight recent chat titles to the agent's prompt (not to the task label); sharing into Chat adds up to six recent Code tasks (prompt, status, branch, error) to the system prompt. Both blocks are capped at 6,000 characters and framed as reference data. Edit project shows the toggles only when Chat and Code are both on. 1,101/1,101 unit tests; `qa/project-modes` extended and green at 375/1440 light/dark.

### 2026-09-21 — Code mode can reach granted domains (release 9611580, deployed)

The egress proxy (`code-egress.cjs`, D15) now runs inside web on `CODE_EGRESS_PORT` (8040), reached by the sandbox as `egress` on the internal code network. A Code task approved for network or installs, with named domains, gets a per-task token that allows only those domains on 80/443 and is revoked when the task ends; unset, the capabilities stay unavailable. A granted task now keeps the engine host in `NO_PROXY` — empty, its model calls would have gone through the proxy and been refused as a private address. Live compose: web joins `code` with alias `egress` and gets `CODE_EGRESS_PORT`/`CODE_EGRESS_HOST` (`.bak.before-egress` backups of the override and `.env`).

### 2026-09-21 — index.cjs is wiring (branch `wip/index-split`, release 2ce73df, deployed)

Everything `handleRequestScoped` still carried inline moved into its own module with injected
dependencies and a `routes/` file: the project, source and upload routes (`projects.cjs`), the
provider registry (`providers.cjs`), the models routes (`models.cjs`), the Diary routes and the
connector endpoint (`diary.cjs`), then sign-in/profile/admin, the storage connection, tool
approvals, the chat lists and transcripts, reasoning settings, health, and the HTTP helpers
(`http.cjs`). The member-origin policy shared by providers, storage and the Diary corpus is now
`createEndpointApproved` in `ssrf.cjs`. Each move is verbatim behind one sentinel and mounted in
its original order, so every status code, message, the session and CSRF gate and the three
approval actions answer as before; `index.cjs` is 2,787 → 752 lines and holds only config,
construction, the router and server start. 68 new tests, none booting the server;
`documents.test.cjs` now calls the modules instead of slicing `index.cjs` as text. The Claude
Diary plugin README's revocation section points at Settings → Diary & storage → Connected apps
instead of a deleted script.


### 2026-09-21 — index.cjs in pieces, and a measurement instead of a port (release a4e0178, deployed)

The server's toolboxes and built-in tools, its MCP wiring and its chat loop each moved out of
`index.cjs` into a module with injected dependencies (`toolboxes.cjs`, `mcp-wiring.cjs`,
`chat.cjs`) and a `routes/` file, with tests that never boot the server; the tests that used
to slice `index.cjs` as text now call the modules. Behaviour is unchanged: the approval gate,
the per-user MCP credentials and the project a tool call acts for all travel exactly as
before. `index.cjs` is 4,241 → 2,787 lines.

Removed because nothing called them: the Hugging Face model search and the variants listing
(server routes, front-end wrappers and their types), six helpers in `index.cjs`, a finished
Docling handoff document. Every spec is now linked from the docs index, and the Claude Diary
plugin README no longer points at a script that was deleted.

Measured, with synthetic data: Node spends about 10 µs of CPU per streamed token; the engine
spends 25–90 ms. Nothing is worth porting. The one slow Node path — fitting a long tool
result to the model's budget re-rendered every surviving record on every step — is now
linear: a 500-record listing reduces in 0.5 ms instead of 53, byte-identical. Study and
numbers: `docs/research-language-consolidation.md`; rerun with
`apps/web/scripts/profile-hot-paths.cjs`.


### 2026-09-21 — The Code tab, full height and honest about the network (2d7ba8f)

The chat composer no longer sits under the Code tab, which left the task form half the height
with an unrelated send button below it. And because this server runs no egress proxy, "Reach the
network" and "Install dependencies" are shown unavailable with the reason — and the server no
longer grants them — instead of being accepted and then quietly never happening.


### 2026-09-21 — "Thought for 12s" (bbae129)

A reasoning reply now says how long the model thought — from its first thought to the first word
of the answer, or to the tool it decided to use — measured as it streamed and kept with the chat.
Older chats, and ones streamed on another device, fall back to the length of the thinking.


### 2026-09-21 — A quieter chat footer (5ae8d7f)

The context meter no longer takes a row above the composer to say "Calculated when you send":
a short chat that has not been measured shows nothing, a measured one shows a single quiet line
aligned with the composer, and a long unmeasured chat still offers compaction. It is read when
a chat opens and when a reply finishes, instead of every three seconds for every open chat.
"Thought for 312 words" now reads "Thought · 312 words".


### 2026-09-21 — Templates for new Diary files (a1ededd)

A `Templates` folder at the Diary's root — Obsidian's convention — is offered when a new file is
still empty. `{{title}}`, `{{date}}` and `{{time}}` are filled in (with optional formats, as in
Obsidian); anything else in braces stays as written. Nothing is saved until you save.


### 2026-09-21 — Unlinked mentions (780b8c7)

"Find links to this file" also lists the notes that name it in prose without linking it — whole
words, case-insensitive, never inside code or properties. They are shown, not rewritten: turning
a mention into a link is an edit to someone's note, and edits here are explicit.


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
# 2026-09-22 (cloud material state correction; deployed as `72ae258`)

Corrected wrapped Material 3 segmented boundaries and role-paired hover/pressed
states for the mode switch, menus, outlined and destructive buttons. Liquid primary
actions retain legible primary colors during interaction, including in dialogs.
No geometry or application behavior changed. The cloud browser binary was unavailable;
rendered review remains pending. See [audit continuation](material-audit-2026-09-22.md).

The test runner now isolates state and restricts outbound sockets to disposable
fixture ports. The SSRF and egress disconnect tests no longer target arbitrary
host-local ports. All 1,247 guarded tests pass, along with typecheck, build and
design lint; the cloud browser blocks the local fixture, so visual QA is pending.

Local recovery: both cloud commits were recovered through their exact combined diff.
All 1,247 guarded tests and required static checks pass locally; the 468-state
synthetic view sweep, accessibility preferences, Code mode and mobile approvals pass.
Fixed two remaining nested/collapsed hover/press cascade conflicts and added a
rendered interaction regression. See the audit and deployment record for final status.

Release `72ae258` is live after verified backup `ab_20260922_201853` and guarded
overlay from `827932b`. All application services healthy, zero restarts; public assets
match the local build, protected endpoints return 401, no web error markers. Model
services and pi sandbox unchanged. Full rollback evidence is in docs/deployment.md.
