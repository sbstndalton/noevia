# Plan: keep Google Drive connector refreshes ordered

Issue: #37

Status: plan only; implementation pending.

## Problem

The Google Drive detail page polls the parent connector list while sign-in is pending, while Drive actions install their returned state directly. A parent refresh started before an action can resolve afterward and replace the action's newer state.

## Intended changes

- Give parent connector loads a monotonically increasing request identity or abort superseded requests.
- Apply connector state and load errors only from the current request.
- Invalidate parent loads already in flight when a Drive action starts or commits its returned state.
- Keep pending-state polling, but ensure a poll started before Cancel/connect/action completion cannot replace that result.
- Preserve direct action feedback and keep Nextcloud updates independent.
- Keep the mechanism local to this connector surface unless an existing narrowly typed helper fits; do not introduce a general request framework.

## Acceptance criteria

- A pending-state poll resolving after Cancel cannot restore the pending panel.
- A parent load started before connect, policy, or backup-copy completion cannot replace that action's returned Drive state.
- Stale failures cannot surface over a newer connector state or current action error.
- Leaving the connector page or unmounting prevents obsolete loads from changing visible state.
- Per-account connection and tool-policy contracts remain unchanged.

## Verification

- Add real-component deferred-response coverage: hold a pending poll, complete Cancel, release the old pending response, and assert the disconnected controls remain.
- Cover successful connect and one connected-state action against an older parent refresh.
- Cover stale load failure, current load retry, and action failure recovery.
- Assert polling continues while the current state is pending and stops after the action changes it.
- Run web tests, typecheck, and production build.
- Exercise Settings → Connectors → Google Drive in Chromium with synthetic APIs at 375, 768, and 1440 CSS pixels in light/dark; no live Google calls.

## Compatibility constraints

Preserve connector endpoints, OAuth popup timing, polling interval, tool policy semantics, backup-copy controls, and Nextcloud behavior. Do not access live OAuth tokens, external APIs, production accounts, or private data.
