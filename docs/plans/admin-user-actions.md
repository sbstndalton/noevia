# Plan: recoverable Admin Users actions

Issue: #24

Status: implemented and verified with synthetic fixtures (2026-09-23).

## Problem

Admin Users mutations and link creation use unguarded promise chains. Rejected requests and clipboard denial have no rendered recovery state, and repeated activation can send duplicate mutations.

## Intended changes

- Route disable/enable, delete, recovery, and invitation operations through explicit async handlers with pending state and announced errors.
- Scope pending state to the affected user/action so unrelated rows remain usable while duplicate activation is blocked.
- Preserve the current users list on failure and refresh it after a successful account mutation.
- Treat token creation and clipboard writing as separate outcomes. If copying fails after creation, expose a safe, usable recovery path without claiming the server request failed.
- Reuse the component's existing notice/error presentation where it communicates the action clearly; avoid unrelated visual changes.

## Acceptance criteria

- Failed disable/enable and delete requests leave the current row intact and show an actionable error.
- Actions cannot be submitted twice while their request is pending.
- Successful mutations refresh the list.
- Recovery/invitation server failure and clipboard denial produce distinct feedback; a created link remains recoverable when copying fails.
- Feedback uses alert/status semantics appropriate to failure/success.

## Verification

- Add focused component tests for request rejection, success plus refresh, duplicate activation, and clipboard denial after token creation.
- Run the web unit tests, typecheck, and build.
- Verify the Users screen in Chromium with synthetic admin fixtures. Do not call production account APIs.

## Compatibility constraints

Keep server authorization as the real gate, preserve current endpoint contracts and confirmation wording, and do not expose tokens beyond the existing administrator flow.

## Implementation verification

`npm test` passed all 1,247 tests; `npm run typecheck` and `npm run build` passed. `qa/admin-user-actions.cjs` drives the real React components in installed Chrome with intercepted synthetic APIs. Checked relevant failure/recovery states at 375, 768 and 1440 pixels in light/dark, keyboard focus and document overflow. Impeccable detector returned no findings. No production APIs, private Diary corpus, physical devices or screen readers were used.
