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

## Proposed direction to prototype

A personal working library with a distinct writing space:

- Diary: date-led hierarchy, generous reading measure and a considered serif for
  prose/headings where it improves reading; compact sans-serif controls. Entries
  should feel like writing, with clear separation of text, activity and metadata.
- Projects: a browsable library, with title, purpose and recent activity aligned
  for scanning. Use rows or meaningful grouping instead of identical large cards
  for every item. Keep project actions discoverable with keyboard and touch.
- Chat: let the conversation occupy the page; distinguish speaker, reply and tool
  activity through typography and placement. Keep the composer easy to find.
- Settings: compact, labelled controls and clear section structure appropriate
  to configuration work. Avoid giving each setting a decorative content card.
- Shared identity: one deliberate type hierarchy, consistent navigation and a
  restrained accent. Vary density and composition according to the task, while
  preserving learned control behavior. Both themes must be designed deliberately.

These are proposals, not user-approved visual choices. A useful next artifact is
one populated Diary view and one populated Projects view using synthetic content,
including a narrow-screen treatment. Compare their visual character before a
system-wide replacement. User-provided references can refine the direction.

## Implementation and release constraints

Use existing React/plain CSS and semantic tokens. Preserve saved theme keys,
tenant isolation, recovery, storage, navigation and all three tool-write actions.
Keep the already-tested functional candidate separate from the redesign so its
remaining QA can finish independently. No production UI or behavior was changed
by this investigation.

Manual visual review is still required: populated/empty/error states, actual
reading and editing, visible focus, both themes and responsive layouts. The
current stalled synthetic browser dialog remains a browser automation blocker;
source inspection or a generated design-system report cannot substitute for QA.
