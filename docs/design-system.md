# noevia · Polymetal design system

Values below are transcribed from `src/styles/tokens.css` at `8a78172` and match
what ships. Do not substitute without re-measuring against
`tests/theme-contrast.test.cjs`.

> **Conflict resolved 2026-09-09.** The former `noevia-design-system.md` described
> a different palette — Night garnet `#DC2626`, secondary `#A3ADBA`, focus ring
> `#FF919D`. **None of those are in `tokens.css`.** That document predated the UI
> overhaul and was never updated when the palette shipped. It has been deleted;
> this file replaces it. If you find those hexes quoted anywhere else, they are
> stale too.

## The idea

Polymetal Gray works in a car because it is a cool industrial slate with soft
specular highlights, and the burgundy works because it is a muted oxblood against
dark textured leather and satin chrome — not a flat crimson flood fill.

So: **red means error, burgundy means brand.** Burgundy is interior trim — rich,
restrained, micro-doses. Destructive actions get their own conventional red
(`--danger`). Using the brand colour for active tabs, outlines and primary buttons
made the app feel permanently in a failure state; that was the single biggest
thing making it read as unfinished.

Polymetal Night is the default for new users, including **before React mounts** —
`tokens.css` sets the dark palette on bare `:root` precisely to prevent a flash of
the wrong palette. Keep it that way. Saved Day preferences are respected.

Inter is the UI and journaling font; JetBrains Mono is used for code,
thought-process and context text, and technical status. System fallbacks stay
usable without external fonts.

## Elevation

Four grounds, not one value plus hairlines: chrome (sidebar) sits below the app
ground, cards sit above it, popovers above those. Borders then refine an edge that
elevation has already established. The navigation rail uses the chrome colour; the
centre workspace uses a surface card.

## Dark — `:root, [data-theme='dark']`

| token | value |
| --- | --- |
| `--bg-chrome` | `#0c0e12` |
| `--bg-app` | `#12151c` |
| `--bg-canvas` | `#0c0e12` |
| `--bg-surface` | `#171b24` |
| `--bg-surface-hover` | `#1e2330` |
| `--bg-surface-active` | `#252b3b` |
| `--text-primary` | `#f0f2f5` (17.2 / 15.4 / 14.5) |
| `--text-secondary` | `#9aa1b0` (7.5 / 6.7 / 6.3) |
| `--text-muted` | `#717d8a` — palette reference, **not used for text** |
| `--accent-garnet` | `#942537` (white on it = 8.1) |
| `--accent-text` | `#e57385` (6.6 / 5.8 / 5.5) |
| `--tint-garnet` | `#2a1c27` (garnet at 15% over surface, flattened) |
| `--good` | `#8ED4B0` (11.2 / 10.0 / 9.4) |
| `--danger` | `#ef4444` |
| `--control-border` | `#6b6d73` (3.14 worst case) |
| `--focus-ring` | `#b84a60` (3.24 worst case) |
| `--border-subtle` | `rgba(255,255,255,0.08)` — decorative, untested |
| `--nav-hover` / `--nav-active` | `rgba(255,255,255,0.045)` / `0.08` |

Dark needs materially deeper shadows than light: on a near-black ground a 6%-black
shadow is invisible.

## Light — `[data-theme='light']`

| token | value |
| --- | --- |
| `--bg-chrome` | `#EBEEF4` |
| `--bg-app` / `--bg-canvas` | `#F5F6F9` — ceramic cool slate, not pure white |
| `--bg-surface` | `#FFFFFF` |
| `--bg-surface-hover` | `#f2f4f8` |
| `--bg-surface-active` | `#e9edf3` |
| `--text-primary` | `#13171A` (15.2 worst case) |
| `--text-secondary` / `--text-muted` | `#5A6572` (5.00 worst case) |
| `--accent-garnet` | `#942537` (white on it = 8.1) |
| `--accent-text` | `#881337` (8.06 worst case) |
| `--tint-garnet` | `#f4e9eb` |
| `--good` | `#246548` (5.84 worst case) |
| `--danger` | `#b3261e` |
| `--control-border` | `#727D89` (3.53 worst case) |
| `--focus-ring` | `#881337` (8.06 worst case) |
| `--border-subtle` | `#DDE2EC` — decorative hairline |
| `--nav-hover` / `--nav-active` | `rgba(19,23,26,0.035)` / `0.065` |

Light's problem was never its text — it was `--tint-garnet` at `#F4E2E8` bleeding
pink through the alias layer into `--bg-active`, `--bg-pinned` and
`--accent-2-soft`. Fixing that one value resolved most of the harshness.

## The contrast contract

`tests/theme-contrast.test.cjs` enforces, for **each** theme block, against **each**
of `--bg-canvas`, `--bg-surface` and `--tint-garnet`:

| token | required ratio |
| --- | --- |
| `--text-primary` | **7.0** (AAA) |
| `--text-secondary`, `--accent-text`, `--good` | 4.5 |
| `--focus-ring`, `--control-border` | 3.0 |
| `#FFFFFF` on `--accent-garnet` | 4.5 |

WCAG 2.2 requires 4.5:1 for normal AA text, 7:1 for AAA, 3:1 for relevant UI
indicators — <https://www.w3.org/TR/WCAG22/>.

The test parses **`#RRGGBB` literals only**. An `rgba()` value for any of those ten
tokens will not match its regex and the test will *throw* rather than fail cleanly.

This verifies the checked colour combinations — not every WCAG criterion, and not
future user-supplied content.

### Decorative and functional borders are different things

The hairline metallic border that gives this design its refinement is white at
6–18% opacity. Measured, that lands around 1.3–1.6 contrast — far below 3.0. Both
facts are true at once because the roles differ:

- **Decorative** — card outlines, separators, panel edges. No state, no
  accessibility requirement. Low-opacity hairlines in `--border-subtle`.
- **Functional** — the perceivable boundary of an input or control, and the focus
  ring. Must clear 3:1. These are the only two the test pins:
  `--control-border` and `--focus-ring`.

## The alias layer

`tokens.css` defines a semantic scale, then an alias layer the components consume
(`--bg`, `--bg-sidebar`, `--bg-card`, `--bg-panel`, `--bg-input`, `--bg-active`,
`--bg-pinned`, `--text`, `--border`, `--accent`, `--accent-ink`, `--accent-2`,
`--accent-2-soft`, `--radius-card`, `--radius-bubble`, `--radius-input`,
`--radius-pill`, `--shadow-soft`).

**Extend these names. Re-point aliases rather than editing every call site.** A
second parallel token set beside them will drift.

## Motion

`--ease-spring: cubic-bezier(0.16, 1, 0.3, 1)`, `--duration-fast: 120ms`,
`--duration-base: 180ms`. Theme background/border/colour changes transition over
200 ms. Reduced-motion preferences disable transitions and animations. Visible
keyboard focus rings apply throughout.

## Buttons

`.btn` at 34px height, 8px radius, 13px/500 text, `scale(0.97)` on `:active`,
transitions on `var(--duration-fast) var(--ease-spring)`. `.btn-primary` is
burgundy with a soft glow on hover; `.btn-secondary` is a surface fill with a
default border; `.btn-ghost` is transparent, brightening on hover; `.btn-icon` is
34×34.

## Theme plumbing — already wired, do not rebuild

- `App.tsx` holds `theme` state and sets `data-theme` on `documentElement`.
- Values are **`'dark'` and `'light'`**; persistence is
  **`localStorage['cowork-theme']`**.
- An `onToggleTheme` callback already reaches `AccountMenu` and `CodingWorkspace`;
  `SettingsShell.tsx` exposes a light/dark picker under Appearance.
- `App.tsx` also updates `<meta name="theme-color">`. **Change a canvas colour and
  this must change too**, or mobile browser chrome will not match.

Keep the attribute values and the storage key exactly as they are: they are
load-bearing for `tokens.css`, the contrast test, `SetupWizard.tsx`, and every
existing user's saved preference.
