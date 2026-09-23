# Failed Google Drive Cancel feedback

Fixes #49. Audited against `59f38d0bbc497aeb0bf234535f6cb3df97c2d3f6`.

The shared `GoogleDriveConnect` component catches an unsuccessful Cancel request, but its pending sign-in view did not show the caught error. Settings → Backups and the setup wizard both use that view. The pending branch now renders the error as a `route-note` alert, consistent with the component’s other states. The code, Open Google link, polling, and Cancel retry remain available.

The existing synthetic browser flows now force a disconnect failure while Google sign-in remains pending. In each caller, they check the alert, keyboard activation of Cancel, retry availability, and page width at 375, 768, and 1440 pixels in light and dark themes. They then let Cancel succeed, confirm the error clears and the view exits pending, and continue through a fresh connection and approval. No server or live Google behavior changes.

Verification commands from the repository root: `npm --prefix apps/web test`, `npm --prefix apps/web run typecheck`, `npm --prefix apps/web run build`, `npm --prefix apps/web run lint:design`, `node apps/web/qa/google-drive.cjs`, and `node apps/web/qa/wizard-backup.cjs` (with the local Playwright module set for the browser scripts).
