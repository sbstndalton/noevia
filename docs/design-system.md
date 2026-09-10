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
Day uses an off-white canvas with neutral gray navigation. Night uses charcoal
with a slightly darker sidebar. Burgundy stays in the wordmark and focus/details;
primary actions use primary text color as their background with app-canvas text.
Destructive actions retain their own danger color.

## Source of truth

`apps/web/src/styles/tokens.css` owns the palette, spacing, radii, and aliases.
`noevia.css` loads last and owns shared visual rules and responsive refinements.
Component files keep their functional layout rules. Extend the existing semantic
names; do not introduce another palette or framework.

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
  restrained card outlines, and a distinct New project action in the header.
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

`tests/theme-contrast.test.cjs` checks both themes against canvas, surface,
sidebar, app, and garnet tint: primary text at least 7:1; secondary/accent/success
text at least 4.5:1; focus rings and control boundaries at least 3:1. Keep checked
tokens as six-digit hex literals. Decorative borders may use transparency.

`public/theme.js` runs before React and stylesheet loading, restoring the saved
Day preference or defaulting to Night. It also sets the browser chrome color.
App and setup changes update `data-theme` and that meta color without reloading.
Reduced-motion preferences disable transitions and animation.

## Functional boundaries

UI work does not alter authentication, tool approvals, diary dates, or storage.
The approval card always shows full arguments and all three decisions. Diary
browsing remains read-only; drafts are only submitted by explicit user action.
Use synthetic fixtures for visual verification, never a live diary prompt.
