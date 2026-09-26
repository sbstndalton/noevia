# Page headers and list containers (#413, #414)

Decisions made while closing the two "decide, don't fix" items PR #417 filed. Synthetic
fixture only; no live Diary data was read.

## One page-header pattern

Settings and Customise already agreed on one pattern (per #417's own note): a display
title (`--text-title1`, 26px, weight 600) with a secondary intro paragraph, `--space-10`
(40px) below the page's own top edge. Two surfaces still differed:

- **Projects** used its own 52px hero (`.projects-hero`, `--text-hero`, -2.4px tracking) at
  a 76px top inset, with the "New project" button inline beside the title.
- **Diary** (and chat) use a thin top bar (`.chat-header`), not a page title.

**Decision: Projects adopts the shared page-title pattern; Diary keeps its compact bar.**

Projects is a list of things you open, the same shape as Settings' categories and
Customise's plugin/connector lists — it gets the same header, not a distinct brand
moment. Its title now uses the literal `.settings-title` class (primitives.css's
`.settings-title` rules, previously scoped to `.settings-stage`, now also match
`.settings-scroll .settings-title` — the container class Projects and the model manager
page already shared with Settings). The "New project" button moves out of the title row
(no page title anywhere in the app carries an inline control) to the tabs/search/sort row,
where `app.css`'s own `.projects-head .btn-primary { margin-left: auto }` already expected
it.

Diary is a deliberate full-bleed workspace: the composer and calendar want the vertical
space a page title would spend, and it already shares its top bar with chat (the same
`.chat-header` component) rather than inventing a Diary-specific header. That parity with
chat is worth more than parity with Settings' page title. Diary keeps the bar.

Measured (synthetic fixture, 1440×900, comfortable, Editorial, light):

| | top offset (px, viewport) | `h1` font-size |
|---|---|---|
| Settings → Appearance | 49 | 26px |
| Settings → Users | 49 | 26px |
| Customise → Skills | 49 | 26px |
| Projects | 49 | 26px |

At 390×844 (iPhone UA): Settings 68px, Customise 77px, Projects 60px — the three already
differed from each other by up to 9px before this change (a modal's own vertical centering
versus two full-bleed pages), so the tolerance in `qa/header-container-parity.cjs` reflects
that pre-existing spread rather than claiming pixel-for-pixel modal/page equality. Type
scale (26px) matches exactly at both widths on all three surfaces.

## Diary's left edge

Diary's compact bar is exempt from the shared title pattern, but its own left edge must
still track the diary content beneath it. It did not: `.chat-header`'s fixed 28px inset put
"Diary" at x≈309 while `.diary-compose`/`.diary-calendar-section` (their own responsive
gutter, `clamp(16px, 4vw, 64px)`) started at x≈339 — a 30px gap at 1440px, present at every
width above the phone breakpoint. Both now read one token, `--diary-gutter` (tokens.css),
so the header and the content column move together. On phones the floating nav-drawer
toggle still forces a fixed 60px inset on the header (avoiding an overlapping tap target);
the content column keeps its smaller gutter there, since nothing floats over it. That one
remaining phone-width difference is a legitimate exception to the alignment, not an
oversight.

Diary's own type scale (`.diary-home-link`, `--text-callout`/500) already matched chat's
`.header-title` — no change needed there.

## One list-container pattern

Users, Service status's "Connected services", Models summary, and the Diary & storage
page's Diary toggle moved from `.card-list` (background/border/shadow stripped inside
`.settings-detail`, each `.model-row` instead drawing its own bordered card) onto
`.set-rows` — the grouped surface Appearance, Data, and Notifications already use: one
bordered, shadowed card, hairline-divided rows. `.settings-detail .set-rows .model-row`
strips the per-row card look and takes the hairline instead; `.card-list` itself is
untouched, so every other current consumer (Security, AI providers, App passwords,
Storage picker, Diary connectors, MCP status's own small list, Usage) is unaffected.

**Left out of this pass, and why:** StoragePicker, DiaryConnectors and McpStatus each
render inside multiple, unrelated surfaces (onboarding, a project's Diary tab, a header
popover) as well as on these four settings pages. Converting their shared component would
change those other surfaces too — outside what #413/#414 asked for. The "Diary & storage"
and "Service status" pages therefore each still mix the new grouped surface (the Diary
toggle; "Connected services") with their own older sections (the storage form, MCP's own
list) — a known, intentionally scoped limitation, not a regression.

## Evidence

Measurements: `/tmp/noevia-fix-413-measure.cjs`, `/tmp/noevia-fix-413-measure-phone.cjs`,
`/tmp/noevia-fix-413-diary-check.cjs` (repo-external, synthetic APIs only). Screenshots:
`/tmp/noevia-fix-413-shots/settings-users.png`, `settings-status.png`, `settings-models.png`,
`settings-diary.png`. QA sweep: `qa/spacing-rhythm.cjs` (0 flush/clipped/small/zoom/overflow/
pageerror) and the new `qa/header-container-parity.cjs` (see PR description for counts).
