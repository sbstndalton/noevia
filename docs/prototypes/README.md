# Playful noevia study

Run `npm --prefix apps/web run build`, then `node docs/prototypes/preview.cjs`
from the repository root. Open http://localhost:31287.

This serves the real built app with a separate CSS layer and synthetic fixture
API on loopback ports 31287/31289. It does not contact production, models or a real
Diary. Only Projects, Chat shell and Diary browsing are design-review targets;
the fixture does not implement every settings, editing or persistence endpoint.
Use sample text only. Displayed online/model/storage labels are fixture values.

The latest user clarification takes priority: preserve the Claude/ChatGPT-inspired
layout. This prototype changes no app component hierarchy, navigation destinations,
sidebar sizing, reading-column widths, Settings structure or Diary panel placement.
The initial standalone alternative layout was discarded before delivery.

## Study 02 — architectural materials

The user rejected Study 01 as a superficial bevel/color pass with childish sample
names. They clarified that artistic, architectural materials and Apple's Liquid
Glass are the useful reference. Study 02 replaces the first stylesheet.

The content remains on an opaque reading surface. Translucent, blurred materials
are restricted to navigation, popovers and controls, with quiet optical edges and
solid fallbacks for reduced transparency, increased contrast or missing blur
support. This is a CSS interpretation, not Apple's native Liquid Glass renderer.
Reference: https://developer.apple.com/design/human-interface-guidelines/materials

Hierarchy now uses a larger project title, underlined section selection, separate
icon/title rows, stronger project names, distinct metadata baselines and editorial
Diary typography. Realistic synthetic project names, source counts and activity
replace the earlier decorative content. Navigation and screen regions remain.

Verification: 373 application tests, typecheck and build pass. Browser inspection
covered light/dark Projects at the normal window size. Resizing currently reports
sizes different from the requested viewport and produces composited screenshots;
do not count those captures as completed exact-breakpoint QA. Measured page width
and scroll width matched at the reported widths. Full cross-palette accessibility,
Diary and all-view regression remain required before production adoption.

## Study 03 — reproduced bugs and bounded glass

Reproduced the mobile account menu being painted behind the app: the filtered
sidebar formed a stacking context. Removed parent-level filters; a browser hit
test now confirms the entire menu sits above the page, and Settings opens from it.
Project menus were also checked above content, within the viewport, with Escape.
Removed root color overrides that disabled effective palette switching. All six
appearance combinations now produce their distinct existing canvas values.
Restored a visible search-field boundary and a three-line phone description.

The Chat/Code control is the bounded material study: transparent fill, inner rim,
background blur and a reflected highlight that follows the pointer via one queued
animation frame. The highlight's live coordinates were verified in browser.
No filters on the sidebar, composer or settings-navigation ancestors. Menus use
mostly opaque glass for readable text. Reduced motion stops tracking; reduced
transparency/increased contrast use opaque surfaces. This is not native refraction.

Browser verification now reports exact 375/768/1440 widths with matching page scroll
widths. Inspected Projects, mobile Settings, Diary and a populated synthetic chat;
checked both modes and all palette selections. These focused checks supersede the
previous resize limitation for these views; they do not claim every possible visual
issue or production integration is finished. 373 tests, typecheck/build pass.
