# UI overhaul — the five phases

Originally a standalone master prompt written against `a5f5c99`. **Most of it has
shipped.** Status below was verified against `8a78172` on 2026-09-09; the palette
itself now lives in `design-system.md`.

## The goal it was written to fix

Five things made the interface read as unfinished:

1. **No surface elevation** — everything sat on a near-flat canvas like a wireframe.
2. **Unanchored layout** — the projects grid stretched full width, leaving small
   cards adrift.
3. **Cards were outlines, not objects** — no icon badge, no clamped description, no
   metadata chips, no hover response.
4. **Active nav used a border outline** rather than a filled row with an accent pip,
   and section headers lacked the tracked-uppercase treatment.
5. **Red was doing the wrong job** — see `design-system.md`. This was the most
   important and hardest to get right.

## Phase status

| Phase | Scope | Status at `8a78172` |
| --- | --- | --- |
| 1 | Tokens, elevation, motion, buttons | **Shipped.** Palette, four grounds, `--danger`, motion tokens, `.btn-*` all present; the hard-coded `var(--danger, #b3261e)` fallbacks are gone and the `theme-color` hexes match the new canvases |
| 2 | Sidebar and layout frame | **Shipped.** Accent pip is an inset box-shadow in `noevia.css` (which loads last and is authoritative — a `::before` in `shell.css` would double it) |
| 3 | Chat | **Shipped.** Inspector is a slide-over toggled from the header (`App.tsx`, `inspectorOpen`) |
| 4 | Diary | **Partly.** Tint fix landed; the landing-page rework is now tracked in `roadmap.md` Workstream 4, not here |
| 5 | Projects | **Shipped.** Grid constrained to 1160px centred, 2-line clamp on descriptions |

Remaining UI work is in `roadmap.md` (diary zero-state) and `backlog.md`.

## Phase 3 — the box that still matters

Whatever else changes in `ChatView.tsx`, these three survive:

> **1. The pending tool-approval card (`PendingToolCall`).** When the model wants
> to run a *write* tool, the server streams `tool_pending` and **the chat blocks
> until a human answers**. The card renders the call and its arguments and posts to
> `/api/tool-approvals/:id`.
>
> It is a security control, not decoration:
> - Arguments are shown **in full and deliberately untruncated**. Seeing exactly
>   what the model proposes *is* the gate. Do not clamp or hide them.
> - **Allow once / Decline / Allow for this chat** are three distinct actions on
>   purpose. Do not collapse them into one confirm button.
> - There is **no global "never ask"**, and there must not be one.
> - If the card disappears, writes become unapprovable and the chat hangs for five
>   minutes before timing out as a denial.
>
> **2. `ToolChips`** — one chip per tool *call* with its status
> (`running`/`pending`/`done`/`denied`), never one per stream delta. Repeated calls
> across inference rounds keep distinct chip identities.
>
> **3. The toolbox picker in `ModelPopup.tsx`** shows each toolbox's per-turn token
> cost and warns when the selection exceeds what the model can carry. Those numbers
> are load-bearing: the catalogue is re-read on every message and costs real seconds
> before the first token.

### The `MarkdownPreview` trap

`MarkdownPreview` lives in `DiaryModal.tsx` and is imported by `ChatView.tsx`.
"Fix chat typography" and "fix diary typography" are the **same component**. Design
once, or extract deliberately — but know which you are doing.

Its two known bugs (URLs containing parentheses truncating at the first `)`, and
unsupported tables) were fixed in the 2026-09-08 pass — see `changelog.md`.

## Design details worth keeping

Recorded because they are decisions, not defaults:

- **Conversation** constrained to ~820px and centred.
- **User messages** right-aligned bubble, `--radius-bubble`, padding `12px 18px`.
- **Assistant messages** a card on `--bg-surface` with `--border-subtle` and
  `--radius-card`; header carries a small glyph and model attribution
  (`via Qwen3.5-9B · <project> context`); footer carries monospace telemetry
  (elapsed, tokens, tok/s) plus copy and reaction actions.
- **Composer** a floating card with a soft shadow and 1px border, an auto-expanding
  textarea, an `+ Add context` chip, the model pill, and a circular burgundy send
  button. **At least 36px clearance above the telemetry strip** so the two never
  overlap.
- **Nav** active rows get `--nav-active`, high-contrast text and a left accent pip;
  section headers 10–11px, semibold, `letter-spacing: 0.06em`, uppercase.
- **Project cards** icon badge, 2-line clamped description in `--text-secondary`,
  footer with a 1px divider, metadata chips and a relative timestamp; hover is
  `translateY(-2px)` + border highlight + `--bg-surface-hover` + soft shadow on
  `--duration-base var(--ease-spring)`.
- **Sidebar footer** shows the authenticated session's user — avatar, display name,
  live status dot. Never a hard-coded name.
- **StatsBar** already renders TOK/S, TTFT, IN/OUT, GPU and VRAM from `LiveStats`
  in `types.ts`. The telemetry strip was a restyle, not new plumbing.

## Still open from this document

- **"Local MCP Active" indicator.** Achievable from `GET /api/toolboxes`, which
  returns `{ mcp: { configured, error, discovered } }`. **Not wired.** Show a
  degraded state when `mcp.error` is non-null.
- **The placeholder question.** `Scheduled`, `Plugins`, `Explore` and the Coding
  workspace are previews. Styling them as first-class navigation advertises four
  features that do nothing; hiding them behind a flag is the opposite call.
  **This was never decided — ask the operator.**
