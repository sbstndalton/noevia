# Saved-storage Diary conversation recovery

New browser exchanges include a random ID. Before contacting the companion, the
web service records the ID, date and raw user message under the authenticated
user's private workspace. Replies, reasoning, progress and acknowledged save
outcomes are updated atomically. The proxy keeps collecting that one operation
when the browser disconnects. Duplicate IDs return 409; they never dispatch again.
The Diary view recovers a day's latest 100 recorded exchanges and polls active
ones. Today's recovered conversation is accessible from the landing composer.

A web-server restart, deadline, transport error or incomplete save acknowledgement
leaves an explicitly uncertain outcome. It is not automatically retried. Check
the saved corpus before manually sending again; this is not distributed exactly-once
execution or automatic reconciliation with the companion's journal. Existing
conversations from before this release cannot be reconstructed from lost browser
memory. Optional-tool preparation events are not part of this recovered transcript.

Browser-local folder processing remains session-only, preserving its promise that
sync-off processing does not save a copy on the server. Local folder pending saves
and reload recovery require a separate browser-storage/permission design. No folder
permissions, corpus backend or automatic Diary capture behavior changes here.

Records stay under each user's web state and therefore enter the existing backup.
No automatic transcript deletion. Recovered answer/reasoning fields cap at 200,000
characters each; a truncated record explicitly says so. The read API is authenticated,
Diary-consent gated and tenant scoped. No new credentials or write permissions.

## Validation — 2026-09-12

356 web tests, typecheck/build pass. Real HTTP tests with a synthetic companion
verify durable reply/status, duplicate rejection, invalid dates and account isolation.
A real socket disconnect test proves the result is collected once after the browser
leaves. Orphaned running records recover as uncertain. Browser QA submits a new
synthetic message, reloads and restores both exchanges; mobile wrapping is verified.
No real Diary prompt, corpus write or inference request used.

Deployed in `f7b9d95`; 308 Linux server checks passed and all services are healthy.
