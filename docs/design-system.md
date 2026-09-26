# noevia design system

Updated 2026-09-10. The reference images in `ui mockups/inspiration` are the
primary visual reference: Claude and ChatGPT's quiet navigation, generous reading
columns, compact menus, and clear separation of content from controls. The HTML
mockups supply structure, not a competing palette.

## Direction

Use a continuous workspace canvas with a subtly darker navigation surface. Avoid
an inset, rounded app inside the app, repeated card shadows, uppercase navigation
labels, emoji controls, and ornamental badges. Most content sits directly on the
canvas. Reserve panels for composers, dialogs, and things with distinct boundaries.

The existing Polymetal Day/Night theme identifiers and `cowork-theme` key remain.
Light/dark mode is independent of the palette: Warm uses cream and earth tones,
Cool preserves the slate and soft-white default, and Neutral uses grayscale.
Sage adds mineral green and Iris adds ink violet, each with light/dark tokens.
Choose in Settings → General. Each mode keeps its own palette, saved with the
authenticated profile. Existing browser keys remain as the before-paint cache;
`cowork-palette-light` and `cowork-palette-dark` preserve independent choices.
Loading, saving and retry feedback describe profile synchronization. Burgundy stays in the wordmark and focus/details;
primary actions use primary text color as their background with app-canvas text.
Destructive actions retain their own danger color.

## Source of truth

`apps/web/src/styles/tokens.css` owns the palette, spacing, radii, and aliases.
`noevia.css` loads last and owns shared visual rules and responsive refinements.
Component files keep their functional layout rules. Extend the existing semantic
names; extend shared palette tokens rather than hardcoding component colors.

UI text uses Inter with system fallbacks. Reserve monospace for code and detailed
technical output. Page titles use 25–32px, medium weight; navigation is 13px;
reading text is 15px with 1.8 line height. Avoid making every label bold.

## Layout and controls

- Sidebar: 248px at desktop, 220px on smaller screens, 60px rail on phones.
  The phone rail expands to reveal labels, search, projects, and theme controls.
  Project and recent-chat groups share one scrolling region.
- Chat: 800px reading column and 744px composer; an empty chat centers its
  invitation and composer. User messages align right; assistant text is unboxed.
- Projects: a centered 1000px library, simple folder icons, plain metadata,
  restrained card outlines, and a New project action beside the tab/search/sort
  row (#413: no page title carries an inline control — see
  `docs/design-notes/page-headers.md`).
- Settings: one dialog with category navigation, switching to a native category
  selector on phones. Dialog focus handling and Escape behavior are preserved.
- Diary: matching composer and typography, plain month links, and memory/storage
  in a side panel that moves below the writing area on smaller screens.
- Code remains explicitly a preview. Its empty activity dashboard is removed;
  the draft composer and existing preview navigation remain.
- Inference metrics are available through an expandable footer, not a permanent
  dashboard strip. This does not change polling or the values reported.

Buttons share a 36px minimum height, 9px radius, and medium-weight label. Send
buttons are circular with the same upward-arrow icon across chat/project/diary.
Use hairline separators and restrained shadows. No floating-card hover movement
or colored glow. Keyboard focus is a visible 2px ring.

## Contrast and theme startup

`tests/theme-contrast.test.cjs` checks all six mode/palette combinations against canvas, surface,
sidebar, app, and garnet tint: primary text at least 7:1; secondary/accent/success
text at least 4.5:1; focus rings and control boundaries at least 3:1. Keep checked
tokens as six-digit hex literals. Decorative borders may use transparency.

`public/theme.js` runs before React and stylesheet loading, restoring the saved
mode and palette preferences or defaulting to dark Cool. It also sets the browser chrome color.
App and setup changes update `data-theme`, `data-palette`, and that meta color without reloading.
Reduced-motion preferences disable transitions and animation.

## Functional boundaries

UI work does not alter authentication, tool approvals, diary dates, or storage.
The approval card always shows full arguments and all three decisions. Diary
browsing remains read-only; drafts are only submitted by explicit user action.
Use synthetic fixtures for visual verification, never a live diary prompt.

## Settings failure handling

Usage and Users validate API responses before rendering. Missing or malformed
fields show a retryable load error, while valid empty arrays render empty states.
A panel-level error boundary keeps category navigation and Close available if a
render fails. Local preview fixtures must implement both `/api/usage` and
`/api/admin/users`; a blanket HTTP 200 with `{}` is not a valid empty response.

## Project identity and navigation

Projects use a curated outline SVG from `server/project-icons.json` and an optional
hex color. This shared allowlist feeds the picker and server validation. Existing
projects default to the folder icon and theme text color. New/edit dialogs expose
an anchored picker with 18 icons, eight swatches and a custom color control; draft
changes only persist when the project is saved. The sidebar, library and project
heading share the same renderer.

Pinned projects have their own collapsible group. A project row expands its chats;
the adjacent folder action and an explicit Open project row open its home. Desktop
navigation can collapse to a rail; search and pinned shortcuts expand navigation
on both desktop and mobile. Library cards put edit, pin, archive and delete behind
an options menu. Delete retains an explicit confirmation with Cancel focused.

Menus support arrows, Home/End and Escape, stay inside the viewport, and use a
short opacity/position transition. Reduced-motion preferences disable it. Project
save failures leave the editor open and show the error immediately above its
footer. Settings retain their category structure with quieter row dividers.

## Shared optical material — 2026-09-13 continuation

Study 03's accepted sidebar material is now shared in the final application CSS.
Decorative `--glass-*` tokens extend tokens.css; existing text, focus, theme and
palette contracts remain authoritative. Settings navigation/header/selection,
composers, project cards and context rails share a directional rim and tonal depth.
Only bounded controls/popovers use background blur. Never filter/transform the
sidebar ancestor or composer ancestor; child menus must remain above the content.
Reading planes remain opaque. Reduced-transparency/contrast fallbacks remove
optical effects. See roadmap.md for implementation and verification scope;
this material is implemented locally and not deployed.

### Control interaction refinement

Enabled buttons, fields and bounded composer/card surfaces now share a fading,
pointer-following reflection. Animation settles and stops; it does not run an idle
page loop. Do not overwrite existing absolute/fixed control positioning or filter
menu ancestors. Shared control/panel radius tokens live in tokens.css. Settings
rows stack descriptions and align actions. Native selects progressively use a
styled base-select picker where supported, retaining native fallback and keyboard
behavior. Reduced preferences suppress optical motion/transparency.

## Optical reflection update — 2026-09-13

Pointer response combines a narrow white glint, an opposing cool reflection and
an angled warm sheen. Coordinates and angle ease with pointer movement, keeping
content sharp. This CSS material does not claim native optical refraction. Existing
reduced-motion, transparency and high-contrast fallbacks remain in place. All ten
mode/palette combinations pass the automated semantic contrast checks.

### Live scene supersedes pointer reflections

The September 13 rewrite removes mirrored pointer highlights and CSS ambient drift.
One locally generated WebGL field lights translucent surfaces from several moving
sources. Rounded edge-distance refraction is adapted from dashersw/liquid-glass-js
(MIT attribution in public/liquid-glass-LICENSE.txt); ybouane/liquidglass supplied
additional live compositing reference. It does not capture private page content.
No-WebGL, reduced-motion/transparency and contrast fallbacks keep opaque readable
surfaces. Background animation is owned exclusively by public/glass.js.

## Models & routing, and the layout mode — 2026-09-17

Model management arrived with its own `mm-*` vocabulary, written against the older
`--bg`/`--border` aliases and its own radii, so Settings → Models & routing read as a
different product from every other settings category. It now uses the same material as
the rest of the pane: `--bg-surface` on `--border-subtle`, `--radius-panel` for panels and
14px for rows, tiles, results and tables, `--radius-control` for fields and tabs, `--text-footnote`/1.6
secondary prose, and the shared rim/edge shadows with the same reduced-transparency
fallback. Its buttons follow the shell — 38px, rising to 44px below the mobile breakpoint —
rather than pinning 44px on desktop, and `.popup-tab` no longer gets a second flat border
drawn over the one the shell already gives it. This is presentation only; every `mm-*`
class name, and the structure of each tab, is unchanged.

`public/layout-mode.js` runs before the app and decides the size the interface is drawn at.
The preference (`cowork-layout-mode`: `auto`, `mobile`, `desktop`) is a Layout row in
Settings → Appearance, alongside chat font, density and motion; like those it is saved on
this device only. Detection prefers UA Client Hints
(`navigator.userAgentData.mobile`) over the UA string, with a coarse-pointer and
screen-size cross-check, and iPadOS's Mac user agent is resolved by `maxTouchPoints`.

The mechanism is the viewport meta tag, because that is the one input every `max-width`
rule in this codebase reads — there is deliberately no parallel breakpoint system.
Forcing desktop on a phone or tablet sets a fixed 1100px viewport, so the desktop rules
apply and the page scales down, exactly like a browser's "Request desktop site". Desktop
browsers ignore the viewport meta, so forcing the phone layout there instead sets
`data-layout="mobile"` on the root, which holds the app to a phone-width column and is
mirrored by the shell, Settings and model-manager rules at the end of `noevia.css`. Other
views still follow the real viewport width, and the control says so on screen.

## Visual system, motion contract and theme families — 2026-09-24 (#245, #247, #249)

This supersedes the material sections above where they disagree. Sources of truth:
`tokens.css` (scales), `themes.css` (families, tokens only), `motion.css` (keyframes and
reduced motion), `system.css` (loads last: the shared surface rules).

**Surfaces.** One elevation scale with three steps, each a fill, an edge and a shadow:
`flat` (`--elev-flat`, `--edge-flat`) for sidebar rows, New chat, buttons and menu items;
`raised` (`--surface-raised`, `--edge-raised`, `--elev-raised`) for the composer only, the
page's focal point; `overlay` (`--surface-overlay`, `--elev-overlay`) for menus, popovers, the
tool catalogue and dialogs. The old `--shadow-*` names alias onto the scale. No paired
light/dark (neumorphic) shadows, no per-element shadow values.

**Shape and space.** Three radius roles: `--radius-control` (buttons, rows, fields, menu
items), `--radius-overlay` (menus, popovers, cards) and `--radius-surface` (composer, panels,
dialogs). Spacing stays on the 4pt `--space-*` scale.

**Type.** Headings and the home greeting use `--font-display` with `--display-weight` and
`--display-tracking`; everything else uses `--font-ui`. The sidebar reads destinations
(primary, medium) before history (secondary, regular) before section labels (caption,
semibold, secondary). The chat font preference still overrides messages only.

**Motion.** Four purposes, each a duration and an easing token: `immediate` (hover, press,
colour; ~100ms, `ease`), `quick` (menus, popovers, toasts entering; 140–180ms, strong
ease-out), `considered` (Chat/Cowork and Chat/Code thumbs, drawers, dialogs, Settings;
220–300ms, drawer curve) and `async` (loading and tool-activity loops; 1.2s, linear). Five
keyframes remain, all in `motion.css`, each with its reason: `motion-enter`, `motion-exit`,
`motion-pulse`, `motion-spin`, `sidebar-title-scroll`; an element picks its travel with
`--enter-from` / `--exit-to`. Reduced motion (OS or Settings → Motion) makes entrances instant,
stops loops and removes transitions; state still changes through text and colour.
`npm run lint:design` rejects `transition: all` and literal durations in stylesheets.

**Theme families.** A family is the whole visual language, independent of accent and
light/dark: Editorial (default; warm paper, Fraunces display + Inter, soft bordered depth),
Contemporary (crisp tonal surfaces, Geist, tighter corners, near-flat depth) and Glass
(translucent chrome over an opaque reading plane, Sora display + Manrope, rounder shapes,
blur only on overlays and chrome). Mono is JetBrains Mono everywhere. Faces load per family
from Google Fonts after first paint (`public/fonts.js`) with system fallbacks of similar
metrics. The choice is a per-device preference (`noevia:theme-family`, `data-family` before
paint in `public/theme.js`); a saved `noevia:material` migrates (Soft → Editorial, Material 3 →
Contemporary, Liquid glass → Glass). Settings → Appearance shows each family as a live sample
in light and dark with the current accent (`.theme-scope` re-declares the semantic tokens on
the sample). Family-scoped component rules may change colour, depth and shape but never size,
spacing or font metrics (`tests/family-geometry.test.cjs`); family grounds are contrast-checked
for every accent (`tests/theme-family-contrast.test.cjs`). Screenshots:
`apps/web/qa/theme-families.cjs`.
