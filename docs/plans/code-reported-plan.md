# Code task reported plan

Issue: [#64](https://github.com/sbstndalton/noevia/issues/64). Baseline: `c5ffec4cbd93b89954c66397e5aa7bb80b836867` (main after Code request ordering).

## Current behavior and scope

ACP `plan` updates become `plan.proposed` job events. The Code task view already returns the latest derived plan, but the task card does not show it. The producer limits each entry to 200 JavaScript characters and does not limit entry count. Old or synthetic journal rows can bypass producer limits. Research jobs use the same generic event types and must keep their current plan shape.

## Intended change

- Bound Code plan entries at the harness and Code journal/replay path: at most 20 entries and 200 UTF-8 bytes per entry, with an explicit truncation flag if content is omitted. Keep Research plan behavior unchanged.
- Show the latest reported plan in the Code task card beneath approval and cancel actions, as a bounded, scrollable plain-text section. Distinguish proposed, edited, and skipped status; omit the section if no plan exists. Show a visible shortening note when the flag is set.
- Do not infer entry completion from Code setup steps, task status, or ACP plan updates. Keep assistant output and all approval actions intact.

## Acceptance and checks

Synthetic producer and journal replay cases cover absent, proposed, edited, skipped, overlong Unicode text, more than 20 entries, and a legacy oversized Code event. A Research plan regression keeps its exact existing shape. Code UI fixtures cover active and terminal cards, HTML-like text as text, narrow screens and themes, no horizontal overflow, and intact output and approvals. Typecheck, build, design lint, and focused Code UI regression pass at the implementation head.

The fixtures establish local data and UI behavior only; they do not claim live ACP compatibility or model quality.
