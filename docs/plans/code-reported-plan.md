# Code task reported plan

Issue: [#64](https://github.com/sbstndalton/noevia/issues/64). Baseline: `c5ffec4cbd93b89954c66397e5aa7bb80b836867` (main after Code request ordering).

## Current behavior and scope

ACP `plan` updates become `plan.proposed` job events. The Code task view already returns the latest derived plan, but the task card does not show it. The producer limits each entry to 200 JavaScript characters and does not limit entry count. Old or synthetic journal rows can bypass producer limits. Research jobs use the same generic event types and must keep their current plan shape.

## Implemented change

- Code plan events are bounded at the harness and Code journal/replay path: at most 20 entries and 200 UTF-8 bytes per entry, with an explicit truncation flag if content is omitted. Research plan behavior and shape remain unchanged.
- The Code task card shows the latest report beneath approval and cancel actions in a bounded, scrollable plain-text section. It distinguishes proposed, edited, and skipped journal statuses, omits the section when no plan exists, and shows a shortening note when needed.
- Entries carry no inferred completion state from Code setup steps, task status, or ACP plan updates. Assistant output and all approval actions remain in place.

## Acceptance and checks

Synthetic producer and journal replay cases cover absent, proposed, edited, skipped, overlong Unicode text, more than 20 entries, and a legacy oversized Code event. A Research plan regression keeps its exact existing shape. Code UI fixtures cover active and terminal cards, HTML-like text as text, narrow screens and themes, no horizontal overflow, and intact output and approvals. Verification commands are the focused server suite, typecheck, build, design lint, and the Code browser regression.

The fixtures establish local data and UI behavior only; they do not claim live ACP compatibility or model quality.
