# Auto-tune polling order

Issue: #40

Implemented: only the current status request can update job/history/error state or notify completion. Start/cancel immediately invalidate older requests and block polling during their POST. Model changes/unmount invalidate old work; completion callbacks use the latest callback and fire once per current terminal job. Current status errors have a retry control separate from action errors.

Cancel continues to accept HTTP202/running while server abort/restoration finishes. A current terminal poll ends polling; older running responses cannot restore the Cancel button. Initial loading no longer adds redundant refreshes on each status change.

## Verification

- 1247 unit tests, typecheck and production build passed.
- `qa/autotune-poll-ordering.cjs` bundles/mounts the shipped React component with real CSS and synthetic APIs/timer ticks: cancelled/passed/failed versus older running,202/running cancellation, stale errors, one completion callback, restart, model switch/unmount and current error retry.
- Chrome375/768/1440 CSS pixels, light/dark, overflow/keyboard focus; mobile light and desktop dark component screenshots inspected. This is a component harness, not the entire model-manager shell.
- Sol independent review and Impeccable detector: no actionable findings.

No live model, benchmark, production configuration, or private data was used. Physical device/screen reader behavior remains untested. Draft for review; no merge/deployment.
