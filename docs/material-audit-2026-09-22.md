# Material audit and refinement — 2026-09-22

Scope: all main views and all 17 Settings destinations, in Soft, Liquid Glass and
Material 3. User explicitly removed the fourth material. Original checkout preserved;
work starts at `9cf92b3` on `ui/material-refinement`.

## References and interpretation

- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials):
  reserve Liquid Glass for controls/navigation, keep content readable, use the regular
  treatment for text-rich interfaces and avoid stacking glass.
- [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/): functional
  layer above content; accessibility preferences are part of the material behavior.
- [Material 3 color roles](https://m3.material.io/styles/color/roles): pair container and
  on-container roles, maintain surface hierarchy across breakpoints, use outline for
  control boundaries and outline-variant for dividers.
- [Liquid Aqua 2.0 reference](https://codepen.io/editor/jaredcwhite/pen/019f9caf-09be-707b-89f7-b1964b77a003):
  inspected the rendered controls; informs restrained rim/highlight treatment. No code
  copied. It is a visual reference, not Apple's implementation or a conformance standard.

This is a web adaptation. Native automatic backdrop luminance adaptation and optical
compositing cannot be promised by CSS. Chromium receives bounded edge refraction;
other engines use the readable CSS material. The shared component geometry, brand,
semantic colors, all three write approvals and tenant isolation are preserved.

## Initial findings

Implementation integrity: failed at the material boundary. The underlying token palette,
keyboard navigation and responsive geometry are sound, but shared legacy rules leak
between visual modes.

| Dimension | Initial score / 4 | Evidence |
| --- | --- | --- |
| Accessibility | 2 | Liquid selection can refract labels; app motion preference did not stop lens work |
| Performance | 2 | Pointer highlight runs in every mode; resize observers stay active outside Liquid |
| Responsive design | 3 | Existing multi-width suites pass; complete material sweep underway |
| Theming | 2 | Soft/M3 inherit translucent surfaces and glints |
| Implementation integrity | 2 | Material 3 sliding glass indicator and missing tab indicator height |
| Total | 11/20 | Significant material-specific correction required |

- **P1: label distortion.** `materials.css` places the selected indicator above text and
  refracts it while moving. Labels need to remain readable through the interaction.
  Move the indicator behind text and remove its refraction. `/impeccable harden`.
- **P2: effects ignore mode and app preference.** `glass-highlight.js` accepts all modes;
  `lens.js` ignores `data-motion` and retains resize observers. Scope to Liquid, react to
  preference changes, disconnect when inactive. `/impeccable optimize`.
- **P2: incomplete Material roles/states.** `material3.css` inherits glass indicator
  shadows and blur; pressed primary actions can pick up a secondary fill; the Projects
  active indicator lacks height. Use paired roles, static segment selection and an
  explicit indicator. `/impeccable polish`.
- **P2: Soft loses material consistency.** Legacy menus/stats and navigation chrome
  inherit translucent backgrounds. Make Soft opaque and reduce heavy paired shadows.
  Preserve clear control edges. `/impeccable polish`.

Positive findings: semantic M3 palette and contrast tests, visible focus tokens,
keyboard-operable native controls, lazy Settings/Diary/Projects chunks, and complete
approval arguments/actions already exist and remain in place.

## Change log

1. Removed the retired mode from preferences, pre-paint initialization, selector, CSS,
   phone-mode override and current testing instructions. Legacy stored values safely
   fall back to Soft before paint. Historical release records remain historical evidence.
2. Liquid: restrained highlights, no pointer tilt or label refraction, opaque content,
   no nested glass, bounded refraction, explicit reduced-motion/transparency behavior.
3. Soft: matte surfaces and popovers, gentler depth, visible off-switch outline.
4. Material 3: stable segment fills, role-correct pressed/disabled states, no optical
   effects, active tab indicator, consistent Settings surfaces.

## Validation log

First implementation: 1,246 unit tests pass. Broad synthetic inventory in progress;
final visual findings, scores and release evidence will be recorded after verification.

Iteration 2:
- First 396-state sweep: no horizontal overflow or page errors. Computed-style inspection
  found three remaining blur sources: mobile drawer toggle, active Settings destination,
  and Material sticky New chat area. Scoped overrides remove these in matte modes.
- Second 396-state sweep: zero blur leaks, overflow or page errors.
- Screenshot inspection caught incomplete mock responses for Personalization, Usage,
  Users, Web address and Features. These were fixture defects, not evidence that the normal
  panels had been audited. Added complete synthetic responses and bottom-of-scroll captures.
- Dynamic preferences suite passes both themes: mode switching, visible keyboard focus,
  labels never refract, app and OS reduced motion, reduced transparency, increased contrast.
- Impeccable static detector reported five layout-animation warnings. Removed dimension
  transitions on selection indicators, switch knobs and the tools budget meter. Translation
  still animates; size changes settle immediately. No remaining matching dimension transitions
  in the inspected material/phone stylesheets. Detector was run once, per skill guidance.
- Updated both source and generated UI reference samples to remove the retired option.
- 1,247 unit tests, typecheck and design lint pass. The final build/interaction confirmation
  after removing dimension transitions is recorded below.
- One parallel browser run hit `EADDRINUSE`: `phone-drawer-settings` and `code-mode` both
  use port 31377. Retried after the drawer suite completed; no application failure involved.

Synthetic checks do not access the real Diary corpus, saved credentials, production model
inference or user files. Setup tests use temporary accounts and disposable local servers.

Validated candidate checkpoint:
- Final application build succeeds; 1,247/1,247 tests pass, zero skips; typecheck and design
  lint pass. No dependency, backend, tenancy, approval or harness configuration changes.
- Expanded inventory: 468 recorded states, zero overflow/blur-leak/error defects. Additional
  confirmation uses the last content element to reach mobile panel bottoms reliably.
- All three materials pass Code flow, full mobile approval decisions and fresh/invited-account
  onboarding. Drawer/settings, projects library, appearance, models/settings, full-auto-tune,
  Diary navigation and connectors pass. The final motion-only confirmation is in progress.
- Predeployment backup `ab_20260922_143433` completed without issues. Web, Diary and extra-file
  archives independently pass `gzip -t`; production is still release `04780e6`.
