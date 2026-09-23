# Code task request ordering

Implemented for [#62](https://github.com/sbstndalton/noevia/issues/62) after [PR #61](https://github.com/sbstndalton/noevia/pull/61) merged. The branch preserves PR61's bounded assistant output and the existing server ownership and approval contracts.

## Problem and evidence

`CodePanel.load()` applies every GET success/failure, while approval polls can overlap and `act()` performs a follow-up GET without invalidating older polls. In a synthetic Chrome run of the actual built App, a delayed `waiting_approval` poll returned after **Allow once** and its newer follow-up GET, restoring the consumed approval card. Direct Sidebar navigation from project A to B reused the unkeyed ProjectView/CodePanel; after B returned no tasks, a delayed A poll restored A's task under B's heading. Both sequences reproduced deterministically; see the private `R/code-poll-validation.md` and fixture. Server `owned()` checks still reject wrong-project decisions (404) and consumed approvals (409); this is a stale UI bug, not a demonstrated server isolation bypass.

## Implementation

- `CodePanel` gives each project a keyed child lifecycle. Task snapshots, errors, busy state, repository, capabilities, harness, prompt, domains, and preparation are discarded in the same render that changes project identity.
- Ordinary GETs are single-flight. A request generation accepts only the current success or failure, while a mutation invalidates any earlier read and performs an authoritative follow-up refresh. Mutation callbacks and `finally` handlers are ignored after unmount.
- Polls pause during a mutation and resume afterwards. A slow ordinary poll remains eligible instead of being starved by the one- or two-second timer; a mutation refresh can still supersede an older held poll.
- `useCodeAccess` binds its result to the project that produced it, so the prior project's Code permission cannot keep the panel mounted during the next project's access check.

## Acceptance and verification

`apps/web/qa/code-request-ordering.cjs` drives the actual App, Sidebar, ProjectView, and CodePanel against controlled synthetic APIs. It covers a slow current poll, obsolete same-project success and failure, consumed approval, a delayed A success before B's response, a rejected A read after B is current, immediate composer reset, a held post-mutation refresh, a rejected old-project mutation, and independent B busy settlement. `qa/code-mode.cjs` continues to cover all three explicit decisions, output, and normal project revisits.

Required verification is the web unit suite, typecheck, production build, design lint, focused request-ordering browser QA, and existing Code output/approval browser QA. All browser data is synthetic; no harness or live repository is contacted.

No backend authorization change, live harness execution, repository mutation, account access, or deployment is part of this fix.
