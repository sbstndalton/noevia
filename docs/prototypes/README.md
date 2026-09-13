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
