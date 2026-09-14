# Freebuff implementation report — 2026-09-14

Implementer: Buffy (Codebuff). Reviewer: as assigned. Nothing was deployed; no
pushes; no real Diary content touched; no servers, models or deployments started.

**Branch-structure deviation, stated up front:** task 1 is on its own branch as
required. Tasks 2 and 3 ended up as two separate commits on the *same* branch
`freebuff/markdown-fidelity`, because the working session was interrupted
mid-task-2 and the mobile fixes landed on that branch's checkout. I did not
rewrite history to split them (hard rule 1 forbids it). Each commit is
self-contained and either or both can be cherry-picked by the reviewer.

---

## Task 1 — Parallel test flake (`secrets.key` EEXIST)

- **Branch / commit:** `freebuff/test-isolation` / `3d441bf`
- **Root cause:** eight server test files require `index.cjs` at module scope
  without setting `UI_DATA_DIR`, so every test process fell back to the default
  `server/ui-data/` directory. `createSecretStore()` writes `secrets.key` with
  `flag: 'wx'`, so two processes starting at once intermittently threw EEXIST.
  Affected files: `auto-router`, `chat-meta-sanitize`, `mcp`, `mcp-servers`,
  `prefill`, `tool-permissions`, `toolbox`, `usage` (all `.test.cjs`).
- **Change:** each of those eight files now sets
  `process.env.UI_DATA_DIR = fs.mkdtempSync(...)` immediately before the first
  `require('./index.cjs')`. Test setup only; `secrets.cjs` behaviour untouched.
- **Verification:** `npm test` — 429 passing, 0 failing, in parallel. Also ran
  `npm run typecheck` and `npm run build` — both pass.
- **Not done / notes:** I did not add a global test helper; each file carries two
  small lines. A shared `tests/setup` seam would be cleaner but changes more
  files. Build initially failed with a vite ENOENT for `apps/web/dist` because
  the `/tmp/noevia-qa-dist` symlink target did not exist on this machine;
  `mkdir -p /tmp/noevia-qa-dist` resolved it (environment issue, not a code one).

---

## Task 3 — Markdown fidelity (done before task 2; see deviation note)

- **Branch / commit:** `freebuff/markdown-fidelity` / `6f724cd`
- **What I found:** the hand-rolled renderer in `DiaryModal.tsx`
  (`MarkdownPreview`) already handles headings (h2/h3/h4), bold/italic/inline
  code, safe external links, tenant-internal `.md` links, ordered/bulleted lists
  with indent levels, GFM tables, whole fenced code blocks with language bar and
  copy button, blockquotes, hr, HTML-comment stripping, and never executes raw
  HTML. Verified true with a synthetic browser run; no rendering rewrite was
  needed or made for those.
- **Bug fixed:** task lists — `- [ ] open` / `- [x] done` rendered as plain
  bullets with literal `[ ]` text. They now render as bordered checkbox
  indicators (`.md-task-box`), struck/pale when done. Preview-only: the source
  text is never rewritten, so round-trip stays verbatim (asserted: saved bytes
  equal loaded source exactly).
- **New QA script:** `apps/web/qa/markdown-fidelity.cjs` — drives headless
  Chrome over the DevTools protocol using Node 26's built-in WebSocket, against
  a fully synthetic local fixture server (no model calls, no real Diary storage;
  `fixture.requests.length === 0` asserted). Covers every construct above plus
  save round-trip, `javascript:`-link neutralisation, no-alert safety, and no
  horizontal overflow at 375px in both themes. Output: `PASS markdown
  fidelity: headings, inline, nested lists, table, code, quote, safety,
  round-trip, responsive`. Screenshots in `/tmp/noevia-md-fidelity-375-*.png`.
- **Why no Playwright:** no Playwright module or browser cache exists anywhere
  on this machine (checked `~/.noevia-deps`, global npm, Spotlight). Installing
  it would have been a new dependency purely for QA; CDP-over-WebSocket
  achieved the same result with zero additions to `package.json`.
- **Verification:** `npm test` 429 pass / 0 fail; typecheck; build — all pass.
- **Not tested / guessed:** rendering of streamed partial tables (table cells
  complete one row at a time) was not exercised; nested blockquotes and
  frontmatter-in-preview were out of scope (frontmatter is preserved verbatim
  by design). The `md-task-box` styling uses existing semantic tokens; I
  reviewed both themes only via the automated overflow/screenshot pass, not a
  manual pixel review — the reviewer should eyeball the two screenshots.

---

## Task 2 — Mobile UI polish (committed second on the same branch)

- **Branch / commit:** `freebuff/markdown-fidelity` / `836399e`
- **Real bug found and fixed — Diary composer unreachable at 320×568:** the
  Diary column rendered 789px inside a 568px viewport with zero scrollable
  ancestors (`.app` has `overflow:hidden`; `.app-stack` could not shrink below
  content height; `.diary-layout`'s `overflow-y:auto` never engaged). The
  composer sat 155px below the fold; at 375×667 it was 15px clipped. Fix:
  `min-height:0` on `.app-stack` (and its `.app-main`/`.diary-mount` children)
  plus, at ≤1100px, a `max-height:40dvh` cap on `.diary-calendar-section` so
  the calendar scrolls internally instead of pushing the composer dock off
  canvas. Measured before/after with a DOM probe: composer bottom 723px → 492px
  against a 568px viewport. The `min-height:65dvh` on `.diary-primary` became
  `auto` as part of this; I did not observe any regression at desktop sizes in
  the audit screenshots, but this is the change most worth the reviewer's
  scrutiny since that rule was presumably added deliberately for the
  "landing fills the screen" look.
- **Tap targets:** raised sub-44px targets at mobile widths (≤1024px sidebar,
  ≤900px content): breadcrumb Diary home link, `.popup-tab`, `.btn`,
  composer model pill (`.composer-model` / `.model-pill`, including the
  disabled "Diary companion" pill which needed an explicit
  `.chat-composer-inner > .composer-model` override of a 32px `min-height`
  set at line 510 of `noevia.css`), app-mode switch, sidebar nav rows and
  section toggles.
- **New QA script:** `apps/web/qa/mobile-audit.cjs` — CDP-driven, synthetic
  fixture, audits Chat and Diary at exactly 320×568, 375×667, 390×844,
  768×1024 in light and dark for horizontal overflow, tap targets <40px, and
  Diary-composer visibility; screenshots at every size/theme into
  `/tmp/noevia-mobile-*.png`. Final output: `PASS mobile audit: no overflow
  or sub-40px targets found at the audited views/sizes`. Two throwaway
  diagnostics (`composer-probe.cjs`, `chain-probe.cjs`) are committed so the
  reviewer can reproduce the composer measurements.
- **Verification:** `npm test` 429 pass / 0 fail; typecheck; build — all pass.
- **Not tested / half-done:** I did not test the Settings, Projects, Code or
  setup-wizard views on mobile (the brief's own manual-verification section
  asks for those; my synthetic fixture covers Chat/Diary/workspace only).
  Keyboard-visible-viewport behaviour was not simulated (CDP device metrics do
  not emulate a software keyboard); the fix targets layout height, and the
  existing `viewport.js` keyboard handling was left alone. No real-device or
  touchscreen testing happened — this is headless-Chrome-only evidence.

---

## Task 4 — Next small backlog items

Not started. The session budget went to tasks 1–3 and, in my judgement, the
remaining genuinely-UI-only backlog entries ("optional empty-folder cleanup",
"explicit Docker healthchecks") are not actually UI-only or belong to the
reviewer's guarded areas (storage contract / deploy), so I stopped rather than
force one. Remaining scoped work per `docs/backlog.md` — short-height sidebar
reachability follow-ups, Claude-bridge verification, native workload
reliability — all sit outside what I can safely touch under rule 4.

## Rule 4 stops

No code in the guarded areas was read or modified. The mobile fix touches
`.diary-composer-dock` layout CSS only; the composer save path, pending-write
handling and version checks were not opened. The Markdown round-trip check
exercises the guarded save route through its public API but changes nothing in
it.

## Exact test outputs

- `npm test`: `tests 429 / pass 429 / fail 0 / cancelled 0 / skipped 0`
- `npm run typecheck`: clean exit (no output beyond the command banner)
- `npm run build`: `✓ built in 556ms`, assets `index-CweV_f7p.css` /
  `index-Y7vvKlTM.js`
- One transient environment failure worth knowing about: `npm run build` fails
  with `ENOENT ... mkdir .../apps/web/dist` if `/tmp/noevia-qa-dist` is absent
  (the symlink target is volatile). Recreate with `mkdir -p /tmp/noevia-qa-dist`.
