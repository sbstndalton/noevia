# Theme shape and Glass material repair — 2026-09-27

Mode: **Operate**. Preserve the three incumbent families. This is a shared shape/material repair, not a replacement design or a native-platform parity claim. Issues: #492 (shape drift), #493 (Glass foreground text bleed). Historical #448 remains covered.

## Shape ownership

Components consume semantic roles in `tokens.css`; `themes.css` owns the family values. Legacy `radius-xs` through `radius-2xl` now derive from those roles, so older surfaces follow the active family too. Former literal corners in shell, settings, Diary, project, Code and Research styles now use roles.

| Role | Editorial | Contemporary | Glass |
|---|---:|---:|---:|
| Control / row | 10px | 8px | 12px |
| Action button | 10px | full pill | 12px |
| Input | 10px | 4px | 12px |
| Card / menu | 14px | 16px | 18px |
| Surface / dialog / composer | 20px | 28px | 24px |
| Message | 14px | 20px, one 4px corner | 18px |

Nested segmented indicators subtract the control inset from their parent's action shape. Preview tiles are cards even though implemented as buttons. Native switches and their knobs, status chips, avatars, send/add circles, chart bar ends, tiny checkbox corners and identity marks retain intentional geometry. Underlined project tabs and flush phone sheet edges retain square joining edges. The shape scale governs all other migrated corners; it does not change size or spacing.

## Material ownership

Glass keeps its atmospheric canvas and translucent pane/reading layers. Foreground menus and dialogs now use a separate 97% tint instead of the pane's 74–76% fill. This obscures sharply rendered content even when a nested backdrop root prevents the overlay blur from sampling it. Reduced transparency and increased contrast make the relevant layers opaque and remove backdrop filters. Message content no longer establishes an unnecessary backdrop-filter root. The #448 sticky tint remains intact.

## Guidance and interpretation

The repository's `PRODUCT.md`, `docs/ui-overhaul-master-prompt.md`, family specifications and existing screenshots are the binding product direction. Impeccable 4.3.1 polish/extract/audit/craft guidance and UI/UX Pro Max's local contrast guidance were used.

[Google's Material 3 documentation](https://developer.android.com/develop/ui/compose/designsystems/material3) establishes shared color, typography and shape roles and tonal surface hierarchy. Noevia's existing Contemporary values are retained; this does not adopt the newer M3 Expressive component redesign.

[Apple's Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) places emphasis on readable navigation/control layers and respecting transparency/contrast preferences. The 97% web overlay tint and the Glass pixel radii are Noevia implementation choices, not Apple-prescribed dimensions or native Liquid Glass equivalence.

Editorial's warm paper, serif display and hairline treatment are Noevia's own design brief; no external platform compliance is implied.

## Verification contract

`qa/theme-shape-material-492.cjs` serves a built app through synthetic `page.route` APIs. It covers all three families, both color modes, 1440/768/390 widths, all five accents (iris/warm/cool/neutral/sage), action/control/card/input/menu/sheet radii, a changed button-token propagation probe, motion and layout modes, overflow and browser errors. Glass also runs with filtering manually unavailable, reduced transparency and increased contrast.

`qa/theme-families.cjs` additionally exercises Chat/Cowork, real synthetic messages, all three reading fonts and both densities, opening/closing menus/sheets, family changes, legacy migration, display fonts and hover-pull behavior. `QA_WIDTHS` selects the viewport matrix; all widths now produce screenshots.

`qa/material-preferences.cjs` checks live family switching, focus, switch contrast, optical-effect shutdown and both motion preference sources. `qa/appearance-system.cjs` checks automatic OS scheme tracking, explicit light/dark pins and before-paint restoration. `qa/glass-sticky-strips-448.cjs` retains the pixel-based scrolled-sidebar regression.

The matrix covers every exposed appearance setting and representative shared surfaces, not the Cartesian product of every preference with every feature, data state and browser. Chrome desktop and emulated touch viewports are verified; native Safari, physical mobile hardware and real inference/credentials/Diary content are outside this synthetic run. No live settings were changed.

## Coverage matrix

| Exposed setting / state | Expected behavior | Evidence |
|---|---|---|
| Editorial, Contemporary, Glass | Distinct fonts, tone, depth and the shape roles above | Three families × light/dark × 1440/768/390; home, menus, model sheets, Settings, synthetic chat |
| Iris, Warm, Cool, Neutral, Sage | Palette changes without changing family shape or layout | 90 home captures; existing palette/family contrast unit tests |
| Light / Dark | Paired readable surfaces; family identity retained | Full family/width matrix |
| System appearance | Follow OS changes until explicit light/dark choice; restore before paint | `appearance-system.cjs`, 375/1440 |
| Sans / Serif / Mono chat font | Only message reading face changes; all three resolve distinctly | 108 actual synthetic-message captures in `theme-families.cjs` |
| Comfortable / Compact density | Tighter vertical rhythm with preserved inline insets and touch sizes | Both densities with all three fonts; Settings captures; geometry unit contract |
| System / Reduced motion | State remains visible; no pull/refraction under reduction | Actual radio changes in shape suite; `material-preferences.cjs`; reduced-motion family suite |
| Automatic / Phone / Desktop layout | Existing layout API and preference apply without overflow | All three settings in all 18 family/mode/width cases; Chrome emulation, not physical-device viewport verification |
| OS reduced transparency / increased contrast | Glass becomes opaque and outlined; no visible backdrop filters | Each Glass family/mode/width case plus dynamic preference suite |
| No backdrop filtering | Foreground menu stays readable without nested blur | Glass menu captures with filter explicitly disabled |
| Overflowing sidebar / collapsed sidebar | Sticky account strip does not show history through its text | Existing #448 pixel suite, 42 synthetic chats |
| Circles, badges, indicators, flush edges | Preserve functional geometry rather than forcing an action shape | Documented shape exceptions; screenshots and source review |

Mechanical Impeccable detector: three unchanged findings. The Diary Markdown blockquote rule is content semantics, and the two 10px swatch borders depict miniature sidebars (already documented design-lint exceptions). No new detector finding was introduced. `lint:design` passes.
