# Research request lifecycle

Issue [#66](https://github.com/sbstndalton/noevia/issues/66). Baseline `5a7d485d0d69aebefb2f8488e6f53a283783c090`.

## Reproduction and impact

The synthetic App/Sidebar test enters `A private draft` and a proposed plan in Project A, then opens Project B directly. On the baseline, B's Research question still says `A private draft`. An unkeyed panel holds project-local state while ProjectView switches identity. Source review also shows unguarded async plan/GET completions and overlapping polls. Server ownership checks prevent cross-project job operations; the UI can still show or submit the wrong project's intent.

## Implemented fix

The Research panel is keyed by project and access state is project-specific before it renders. Async state updates, callbacks and mutations check the current mount and mutation owner. Ordinary polling is single-flight; mutation refreshes invalidate prior reads. Successful start/cancel/save job snapshots are applied before refreshing, so a failed GET cannot hide a successful action. Refresh errors remain visible and partial save remains explicit.

## Verification

Controlled browser cases cover direct A→B navigation, a pending A plan completion, an old same-project poll after cancellation, and successful start/cancel/save POSTs followed by failed GETs. The routed checks are the full web unit suite, typecheck, build, design lint, new race QA and existing Research QA. Use synthetic data only; no backend change, live model or production operation.
