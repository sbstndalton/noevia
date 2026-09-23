# Backup status ordering

Issue: #35

Implemented: every status request has an identity; only the current request can update status or report a load error. Starting a backup/restore action invalidates earlier reads immediately, and its follow-up refresh supersedes earlier action and Google Drive refreshes. Unmount invalidates pending reads. Status failures have a Reload status action and remain separate from action POST failures.

The original mount/action example was unreachable because action controls are hidden before the initial response. The corrected regression uses enabled successive actions and Google Drive copy followed by a restore test.

## Verification

- 1247 unit tests, typecheck and production build passed.
- `qa/backup-status-ordering.cjs` exercises the real settings UI with deferred synthetic APIs: successive action and Google/action overlap, stale success/error, earlier response during a later POST, initial loading gate, current status retry and separate action errors.
- Chrome at375/768/1440 CSS pixels in light/dark: no horizontal overflow and visible keyboard focus. Mobile light and desktop dark screenshots inspected.
- Impeccable detector: no findings. Independent Sol review: no actionable findings.

No live backup, Google endpoint, private data, physical device or screen reader was used. Endpoint contracts, server operation exclusivity, polling, and recovery-key flow remain unchanged. Draft for review; no merge or deployment.
