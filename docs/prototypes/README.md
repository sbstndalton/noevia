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

Visual changes: tactile project identity tiles, gentle depth on controls,
rounded heading typography, a warm light/forest dark study palette, and small
geometric distinctions in Diary sections. This is a proposed appearance, not a
production theme migration. Sample tile colors are matched to the three synthetic
project identities; production integration must derive them from saved metadata.

Verified in the browser: project filtering, Diary landing/entry navigation, theme
toggle, mobile rail and responsive layouts at 375/768/1440. No page-level horizontal
overflow in measured views. Full cross-palette accessibility and all-view regression
review remain requirements before any production adoption. Application tests,
typecheck and build pass; the production bundle is unchanged by these files.
