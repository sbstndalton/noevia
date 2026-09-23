# Google Drive connector refresh ordering

Issue: #37

Implemented: connector list reads commit only when current. Drive action start and returned state invalidate older reads; pending polling pauses while an action is busy and resumes only if still pending. Back navigation and unmount invalidate outstanding reads. Action errors and Nextcloud behavior retain their existing contracts.

## Verification

- 1247 unit tests, typecheck and production build passed.
- Real Chrome UI via `qa/connector-drive-ordering.cjs`: held pending poll then Cancel, reconnect, connected-state policy update, stale poll failure, action recovery, current load retry and poll stop/resume.
- Synthetic timer ticks invoke the actual interval callback; synthetic APIs use no live Google/OAuth account.
- 375/768/1440 CSS pixels in light/dark, overflow and keyboard focus checks; mobile light and desktop dark screenshots inspected.
- Sol independent review and Impeccable detector: no actionable findings.

Physical devices, screen readers and production integrations were not tested. No merge or deployment.
