# Research request lifecycle

Issue [#66](https://github.com/sbstndalton/noevia/issues/66). Baseline `5a7d485d0d69aebefb2f8488e6f53a283783c090`.

## Reproduction and impact

The synthetic App/Sidebar test enters `A private draft` and a proposed plan in Project A, then opens Project B directly. On the baseline, B's Research question still says `A private draft`. An unkeyed panel holds project-local state while ProjectView switches identity. Source review also shows unguarded async plan/GET completions and overlapping polls. Server ownership checks prevent cross-project job operations; the UI can still show or submit the wrong project's intent.

## Intended fix

Key the Research panel by project and make access state project-specific before it renders. Guard async state updates, callbacks and mutations against the current mount/project. Allow only one ordinary poll at a time; mutation refreshes invalidate prior reads. Apply successful start/cancel/save job snapshots before refreshing so a failed GET cannot hide a successful action. Keep refresh errors visible, and keep partial save explicit.

## Verification

Controlled browser cases cover direct A→B navigation, pending A plan/read completions, same-project read order, and POST success followed by GET failure. Run the full web unit suite, typecheck, build, design lint, new race QA and existing Research QA. Use synthetic data only; no backend change, live model or production operation.
