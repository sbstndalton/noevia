# Plan: show a failed Google Drive Cancel during pending sign-in

Issue: #49. Audited against `59f38d0bbc497aeb0bf234535f6cb3df97c2d3f6`.

When Cancel fails during the Google device flow, `GoogleDriveConnect` already catches the API error, but its pending branch does not render it. Both Settings → Backups and the setup wizard use this component. The user sees the waiting message and can retry, yet gets no explanation that cancellation failed.

## Intended change

- Render the existing `error` in the pending branch as a `route-note` alert, matching the connected and start branches. Keep the code, Open Google link, polling, and Cancel retry controls.
- Extend the synthetic browser contracts in `apps/web/qa/google-drive.cjs` and `apps/web/qa/wizard-backup.cjs`: while pending, force the disconnect POST to fail; return pending again on status refresh; assert the alert is visible and a second Cancel can be attempted. Continue their current success paths.
- Keep all changes inside the shared UI and its browser QA. Do not change server disconnect semantics or the status-ordering work tracked by #35 and #37.

## Acceptance and verification

A failed Cancel appears as an accessible alert while the flow remains pending. Retrying remains possible in both real callers. Successful cancellation still leaves pending state. The two browser scripts run against synthetic server/Google fixtures, and the full web test, typecheck, build, and design lint pass from `apps/web/`.

This PR is a plan only; no behavior is changed yet.
