# Material audit and refinement — 2026-09-22

**Complete:** application release `827932b` is pushed to main and deployed.

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

Final review notes:
- The Code compose, approval, delete and result screens were visually reviewed in all three
  materials, light/dark, at phone width. Full arguments remain visible; all three ordinary
  write actions remain reachable; delete/push still cannot receive standing approval.
- Corrected General's description: theme and accent sync through the account; material,
  density and motion are browser preferences. The old copy incorrectly promised material sync.
- No known unresolved finding from this audit. This is not a claim of native Apple rendering,
  complete Material platform certification, or physical-device/screen-reader certification.
  Browser coverage is installed Chrome plus the Codex browser; the non-Chromium CSS fallback
  and reduced-preference behavior are covered structurally/unit-wise, not on physical Safari.
- Shared sizing/typography remain intentional product constraints. The Material skin maps
  roles, shape, elevation and interaction states without reflowing the application when a
  person switches material. Soft has no separate platform standard; its criteria here are
  opacity, restrained depth, readable boundaries, focus and touch reachability.

Reproduce from `apps/web` (set `PLAYWRIGHT_MODULE` to the installed Playwright module):

```sh
npm test
npm run typecheck
npm run build
npm run lint:design
node qa/materials.cjs
node qa/material-preferences.cjs
node qa/general-settings.cjs
node qa/settings-navigation.cjs
node qa/projects-library.cjs
node qa/phone-drawer-settings.cjs
node qa/appearance-system.cjs
node qa/models-settings.cjs
node qa/models-autotune.cjs
node qa/diary-navigation.cjs
node qa/connectors.cjs
for material in soft liquid material; do
  QA_MATERIAL=$material node qa/code-mode.cjs
  QA_MATERIAL=$material node qa/mobile-approvals.cjs
  QA_MATERIAL=$material node qa/onboarding.cjs
done
```

Run the fixed-port suites serially. `qa/materials.cjs` writes its full synthetic inventory
and screenshots to `QA_SCREENSHOTS` (default `/tmp/noevia-material-audit`); `QA_SECTIONS`
optionally limits Settings destinations with `|` separators. The initial and final test logs
in this work session are `/tmp/noevia-material-*.log`, `/tmp/noevia-code-*.log`,
`/tmp/noevia-approvals-*.log` and `/tmp/noevia-onboarding-*.log`. They are temporary local
artifacts; this document is the durable result and failure/fix record.

Final contrast correction:
- Reviewing the normal Personalization/Features panels exposed the second switch
  implementation (`input.noevia-switch`): it still hard-coded white knobs in every theme.
  Replaced these with outline/on-primary roles, added a visible off-track boundary, and
  removed optical knob shadows in Material 3. Shared geometry is unchanged.
- Added rendered knob/track contrast assertions for on/off, three materials and two themes;
  all 12 combinations meet at least 3:1. The test waits for the existing background transition
  to settle; its first attempt incorrectly sampled the transition immediately after toggling.
- 1,247 tests, typecheck, build and design lint pass again. Dynamic accessibility/preferences
  checks pass. A focused all-width sweep covers General, Personalization, Features and Security
  plus the main views after this last correction; rollout evidence follows below.

## Verified outcome

Final broad run: **468 states, zero defects/errors**. Focused confirmation after the native
switch/copy correction: **198 states, zero defects/errors**. All required commands and the
14 distinct browser suites listed above pass; Code, mobile approvals and onboarding each
pass in Soft, Liquid and Material. Unit count remains **1,247**, with no failures/skips.

Guarded deployment completed; public bundle/CSS and the three material scripts match the
validated build; unauthenticated protected endpoints return 401. All app services are healthy
with zero restarts. The native engine, embeddings and pi sandbox are unchanged. Full backup,
checksum, release and rollback evidence: [deployment record](deployment.md).

## Cloud continuation — state-layer correction (not deployed)

The earlier release remains a baseline, not visual acceptance. On the fresh `1af80af`
checkout, source review found that Material 3's wrapped segmented choices retained
single-row separators and that selected Chat/Code controls had no selected hover/press
layer. Menu press, outlined-button press and destructive-button hover/press also lacked
role-paired layers. These now use the foreground role of their actual container; wrapped
choices get individual outlines while keeping shared dimensions. Liquid primary actions
now retain their primary color on hover/press, including those inside a popover/dialog.

The cloud runtime has Playwright's module but no Chrome/Chromium executable. Its browser
download returned a zero-byte archive because external browser CDN access is blocked.
No new before/after screenshot or rendered parity claim is made for this continuation;
the prior screenshots are evidence only for the prior release. The full 17-destination,
multi-device visual reinspection and non-Chromium fallback remain open. This CSS-only
checkpoint does not touch approval, account, Diary, model or deployment code. Validation
and Git commit for this checkpoint are recorded below when available.

### Hermetic cloud test continuation — 2026-09-23

The generic `npm test` previously imported `server/index.cjs` without an inference
override, so its fallback was `http://host.docker.internal:11434`. The SSRF
admin-probe test also intentionally fetched an arbitrary loopback port. The test
script now preloads a worker-local isolated state directory, replaces inference,
manager and Diary URLs with inert loopback port zero, clears connected services,
and rejects outbound sockets unless they target a `127.0.0.1` port opened by a
fixture in that worker. The SSRF probe now uses an HTTP 503 fixture; the egress
disconnect test uses a disposable upstream instead of allowing a race to reach
port 80. The guard refuses Unix sockets, external hosts and arbitrary local
ports, including 11434. No production data or model service was contacted.

Validation in the guarded configuration: **1,247/1,247** tests pass with zero
skips; typecheck, build and design lint pass; `git diff --check` passes. The
cloud browser is provisioned, but opening the disposable fixture at
`http://127.0.0.1:31239` returned `ERR_BLOCKED_BY_CLIENT`. There is still no
new rendered before/after inspection, so the CSS checkpoint remains unvalidated
visually and undeployed. The earlier browser download failure is historical.


## Local recovery and release validation — 2026-09-22 EDT

With explicit user authorization to use local access, recovered the complete diff of
cloud commits `0c5c7558a456a0871af9415945726b15314ee861` and
`989229c527803ebfa54eccdf821e6793c5afb774` onto a clean integration branch from
`origin/main` at `1af80af`. The remote cloud branch was only a pointer to that
baseline and contained neither correction; no stale alternative was merged.

The guarded suite passes all 1,247 tests, zero skips. Separate probes confirm that
the guard refuses model port 11434, external hosts, arbitrary loopback ports and
Unix sockets before connecting. Typecheck, build, design lint and diff checks pass.
No production data, real Diary corpus or live inference was used.

The full synthetic browser inventory covers 468 states: all 17 Settings destinations,
Chat, Projects, project menus, Plugins and Diary, in three materials, two themes and
375/768/1440 widths. Zero page errors, horizontal overflow or matte-mode blur leaks.
Representative desktop and mobile screenshots were inspected. Dynamic preferences,
12 switch contrast pairs, keyboard focus and reduced effects pass. Code mode and
mobile approvals pass, including all three decisions and complete command arguments.

A new interaction regression (`qa/material-states.cjs`) exposed a nested Liquid
primary action whose hover rule overrode its pressed layer. Added the matching
container-specific pressed rule. Collapsed Material mode switches also need their
state layers to override the shared rail skin. Both corrections now pass rendered
hover/press checks in light and dark, including the collapsed rail. Shared geometry
and application behavior remain unchanged. The final focused confirmation passes
126 states (General plus main views, all modes/themes/sizes), with zero errors or
defects. The production rollout is recorded in the deployment log.

This closes the cloud checkpoint's missing Chromium visual validation. It does not
certify native Apple rendering parity, physical Safari behavior, or every possible
content/interaction combination. The historical cloud blockers above remain as an
audit trail, not the current release status.
