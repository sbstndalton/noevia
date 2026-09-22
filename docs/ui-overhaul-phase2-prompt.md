# noevia UI overhaul — phase 2 master prompt (2026-09-18)

> Hand-off for a fresh session. Written after releases 1 and 2 shipped. It continues
> [ui-overhaul-master-prompt.md](ui-overhaul-master-prompt.md), whose direction and noevia
> decisions still apply; read that brief's top section ("noevia decisions") before starting.

## Where things stand

- **Live on daserver:** `ab2720a` (release 2), deployed 2026-09-18 after backup
  `ab_20260918_092222`. Rollback target `35ed364` (release 1). The user is reviewing release 2 on
  desktop and phone; fold their feedback in before anything else.
- **Release 1 (Foundation):** one M3 palette (`apps/web/scripts/palette.cjs`), `tokens.css`,
  `materials.css` (Soft default, Liquid glass, Material 3), `public/lens.js`,
  `SegmentedControl`.
- **Release 2 (Shell + Primitives + Connectors):** framed sidebar and workspace panes
  (`styles/shell-v2.css`); Settings is an in-app region that slides over the workspace (phone:
  list → page); floating phone drawer; context panel surface; composer pane with glass controls;
  one look for buttons, fields, selects, switches and rows (`styles/primitives.css`);
  Settings → Customize → Connectors with Google Drive per account, seven chat tools and per-tool
  Allow / Ask / Block enforced on the server (`gdrive-tools.cjs`, `gdrive-files.cjs`,
  `drive-accounts.cjs`, `tool-policy.cjs`, `routes/connectors.cjs`).
- **Visual reference that the user approved:** `docs/ui-samples/foundation.html`
  (`?screen=settings|project|connectors|modal&theme=light|dark`). The samples are the target
  anatomy; the app must look like them, not like the pre-2026-09-18 app.

## What to build next (in this order, each one a deployable release)

1. **Release 3: Primitives beyond Settings.** Menus and context menus (`ContextMenu`,
   account popover, composer actions panel), modals and confirm dialogs (`EditProjectModal`,
   `ConfirmDialog`, `ModelPopup`, shortcuts dialog), cards (project cards, output cards, model
   cards), toasts/banners (`save-error`, route notes), empty states, and the chat surfaces
   (message bubbles, tool-call list, approval card restyled but never simplified). Modals become
   `aero` overlays with the `scrim`; on phones they become bottom sheets with a grabber.
2. **Release 4: Customize backends.** Nextcloud connector (reuse the existing Nextcloud MCP
   and app-password flow), custom MCP server added by URL (per account, with the same
   Allow / Ask / Block page), then Skills (own and imported `SKILL.md`), then the Plugins
   marketplace (Claude-compatible repos, any GitHub repo by URL, own imports, curated list).
3. **Release 5: Projects and chats** as in the sample's project screen: header with icon and
   actions, composer with context chips, outputs row, recent chats, context panel sections
   (Instructions, Memory, Context, Scheduled shown as not yet available).
4. **Release 6: Activity / usage** from real data only.
5. **Release 7: Impeccable critique pass and a dedicated phone polish pass.**

## How to work (the user's rules — follow exactly)

- Repo: `…/AI frontend thing/noevia-application` (the parent folder is not a git repo). Web app
  in `apps/web`. Read `AGENTS.md` and `docs/agent-brief.md` first.
- **Use the Impeccable skill** (`.claude/skills/impeccable`; run its launcher as
  `sh .claude/skills/impeccable/scripts/impeccable context` because Nextcloud drops exec bits).
  Read `reference/craft-floor.md` before UI edits; run `impeccable detect` on changed files.
- **Click-test every change yourself in Chrome** with Playwright
  (`PLAYWRIGHT_MODULE=~/noevia-local-test/node_modules/playwright-core`), desktop and phone,
  light and dark, all three materials where relevant. Test data and screenshots live in
  `~/noevia-local-test` (never inside the repo).
- **Before each commit:** `npm test`, `npm run typecheck`, `npm run build` (empty
  `/tmp/noevia-qa-dist/*` first), `npm run lint:design`, and the affected `qa/*.cjs` suites all
  pass. Known unrelated failure: `qa/notifications.cjs` fails on `35ed364` too.
- **Check `git status` for phantom deletions before committing**: Nextcloud has deleted tracked
  files from this checkout; restore with `git checkout -- <path>`.
- Commit and push after each step. **Deploy only when the user says**, appdata backup first,
  following `docs/deployment.md` and `deploy/examples/overlay-release.sh` (run `git archive`
  from the repo root).
- Never ask the user to paste commands. Collect questions and ask them together.
- Preserve: tenant isolation, all three write-approval actions (never a global "never ask"),
  `cowork` identifiers, and the "nothing fake" rule (unbuilt features look unavailable).

## Open threads

- User review of `ab2720a` (desktop + phone).
- Google Drive uses `drive.file`; whole-Drive search would need a restricted scope and Google
  verification. Not planned unless the user asks.
