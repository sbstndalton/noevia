# Plan: keep backup settings status refreshes ordered

Issue: #35

Status: plan only; implementation pending.

## Problem

Backup settings starts status refreshes after backup and restore-test actions and from Google Drive changes/polling. These requests can overlap, and every response can replace component state. A slower earlier refresh can therefore make a later completed action appear to revert.

## Intended changes

- Give every backup-status load a monotonically increasing request identity or abort superseded requests.
- Allow only the current refresh to update `status` or surface a load error.
- Keep action POST failures distinct from status-refresh failures so a successful refresh does not erase useful action feedback and a stale load failure cannot obscure current state.
- Ensure the follow-up refresh launched by an action is authoritative relative to all earlier loads.
- Preserve Google Drive `onChange` and pending-state polling while applying the same ordering rule to their loads.
- Keep the solution local to this settings surface unless a small existing helper already matches the contract; do not introduce a general request framework.

## Acceptance criteria

- A delayed refresh from an earlier action cannot replace status returned after a later action.
- A Google Drive refresh or poll cannot replace a newer action result, and a superseded error cannot become the current alert.
- Backup, restore-test, copy, connect, disconnect, and polling controls retain their existing operation/pending behavior.
- Server-side operation exclusivity remains unchanged.

## Verification

- Add real-component tests using deferred intercepted APIs. Complete one enabled action and hold refresh A, complete a second enabled action and return refresh B, then release A; assert B remains visible.
- Cover overlap between a Google Drive `onChange` or pending poll and an action refresh.
- Cover stale success and stale failure, plus an ordinary action POST failure and recovery.
- Assert the initial loading state still gates action controls until the first status arrives.
- Run web tests, typecheck, and production build.
- Exercise Settings → Backups in Chromium with synthetic APIs at 375, 768, and 1440 CSS pixels in light and dark themes; no live backup or Google calls.

## Compatibility constraints

Preserve current endpoint contracts, server exclusivity, Google polling interval, recovery-key flow, status wording, and action labels. Do not access live backups, credentials, production APIs, or private data.
