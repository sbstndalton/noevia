# Code task request ordering

Plan only for [#62](https://github.com/sbstndalton/noevia/issues/62). This document does not implement the fix. Base: `main` at `1c3ab0e5c21f11d69380e720a9730cb8ea63f361`. Implement after [PR #61](https://github.com/sbstndalton/noevia/pull/61) merges, then reconcile against its CodePanel changes.

## Problem and evidence

`CodePanel.load()` applies every GET success/failure, while approval polls can overlap and `act()` performs a follow-up GET without invalidating older polls. In a synthetic Chrome run of the actual built App, a delayed `waiting_approval` poll returned after **Allow once** and its newer follow-up GET, restoring the consumed approval card. Direct Sidebar navigation from project A to B reused the unkeyed ProjectView/CodePanel; after B returned no tasks, a delayed A poll restored A's task under B's heading. Both sequences reproduced deterministically; see the private `R/code-poll-validation.md` and fixture. Server `owned()` checks still reject wrong-project decisions (404) and consumed approvals (409); this is a stale UI bug, not a demonstrated server isolation bypass.

## Intended change

- Bind Code GET/poll callbacks to the currently mounted project and a request/action generation. Ignore older success **and failure** callbacks after a newer GET, mutation, project switch, or unmount. Do not let an A mutation's post-action load, busy state, or error state settle into B.
- Avoid overlapping poll snapshots or order them so old snapshots cannot replace a newer state. Preserve the fast poll while approval is waiting.
- Reset Code task and compose state on project change, including repository, capabilities, harness, prompt, domains, and preparation. Ensure the App/ProjectView mount/access path does not briefly show A's Code controls under B. Keep the change within this client lifecycle; retain server project ownership and approval policy.

## Acceptance and verification

Add a synthetic browser regression using the real App, Sidebar, and CodePanel (a focused `apps/web/qa/code-request-ordering.cjs` is suitable). Hold an old waiting-approval GET, click **Allow once**, let the mutation and follow-up GET show running/completed, then release the old GET; the approval card must stay gone. Switch A→B directly while A GET is held, return B's empty snapshot, then release A's success or rejection; A task, approval, error, and compose selections must never appear under B. Hold an A mutation and its follow-up load across the switch; B must retain its own task/action feedback. Keep the three explicit write decisions and existing `qa/code-mode.cjs` behavior. Run `npm --prefix apps/web run typecheck`, `npm --prefix apps/web run build`, the focused browser QA, and existing `qa/code-mode.cjs` with the installed Playwright module.

No backend authorization change, live harness execution, repository mutation, account access, or deployment is part of this fix.
