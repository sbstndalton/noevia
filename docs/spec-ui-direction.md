# UI direction — 2026-09-13

## User concern

The interface works, but its design language feels generically AI-generated and
too similar across surfaces. Treat this as a composition and identity problem,
not another bug-fixing, palette-only or border-radius pass.

## Reference skill

UI UX Pro Max is installed locally at ~/.codex/skills/ui-ux-pro-max from
nextlevelbuilder/ui-ux-pro-max-skill commit
7f69fed6a2717900085f1bc3b263721f8ba025e2. It contains the skill instructions,
references, local data and search scripts. Use full local script paths; the
upstream Claude-specific example environment variable is not needed in Codex.
Upstream: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill

A system query for “personal knowledge workspace editorial” returned a marketing
Hero/Features/CTA pattern. That result was rejected as unsuitable and was not
saved as the application's design system. A focused style query for “editorial
typography reading” returned Editorial Grid / Magazine and E-Ink / Paper. These
provide references for typography, reading width and content hierarchy, not a
requirement to add magazine columns, paper textures, parallax or drop caps.
Keep dark mode, accessibility and existing repository constraints.

## Initial source observations

This is a stylesheet review, not a completed visual audit. noevia.css explicitly
shares typography and restrained surfaces between Settings and Diary. The global
UI font is Inter; Projects uses a repeated card grid. Earlier changes already
removed many shadows and panel backgrounds. Further cosmetic subtraction alone
is unlikely to answer the user's request.

## Accepted direction and layout constraint

The user described the playful precision of Apple and Lego, with room for
serious work, then explicitly required keeping the layout developed from their
Claude and ChatGPT suggestions. Preserve docs/design-system.md and the latest
sidebar behavior in docs/ui-reference-review.md as the structural reference.
The previous proposal to turn Projects into a new list/library arrangement is
superseded. Do not reorganize screens to manufacture visual novelty.

Apply character through tactile controls, considered project identities, rounded
heading typography, restrained color and clear pressed/selected states. Keep the
continuous canvas, sidebar/rail, centred project grid, chat column/composer,
Settings dialog and Diary memory/storage panel. Functional content stays focused.

The first attempt is [the actual-app preview](prototypes/README.md), using the
existing React component tree and an isolated stylesheet. Synthetic projects and
Diary entries demonstrate the treatment without accessing real user content.
The earlier standalone layout experiment was discarded. This is a local design
study, not a deployed redesign or a completed all-view accessibility review.

## Implementation and release constraints

Use existing React/plain CSS and semantic tokens. Preserve saved theme keys,
tenant isolation, recovery, storage, navigation and all three tool-write actions.
Keep the already-tested functional candidate separate from the redesign so its
remaining QA can finish independently. No production UI or behavior was changed
by this investigation.

Manual visual review is still required: populated/empty/error states, actual
reading and editing, visible focus, both themes and responsive layouts. Browser controls resumed during this prototype review. Source inspection or a
generated design-system report cannot substitute for visual QA.
