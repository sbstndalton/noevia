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

## Opt-in browser-local recovery — 2026-09-13 (candidate)

The user chose opt-in recovery on the same browser. Local-folder sessions can now
save a per-user/session IndexedDB record: unsent draft, selected date, conversation
and optional tool history, pending local/sync changes with their conflict baselines,
unsaved Markdown editor text, and a structured-cloned directory identity. No local
recovery copy is uploaded to the server. This does not encrypt records separately
from the browser profile; the opt-in explains profile access and browser-data loss.

Reopening offers explicit reconnect/recover. File System Access `isSameEntry`
requires the original folder; changed online connection identity blocks restoring
pending sync. New online sync defaults off after recovery. No prompt or file write
is replayed. Pending approvals become denied history without reusable IDs. An
interrupted operation stays labelled uncertain. Explicit retries accept matching
completed content or an empty new-file placeholder, but differing nonempty text
conflicts. This is best-effort File System Access conflict checking, not a lock
against arbitrary concurrent external editors.

Records are limited to 4 MiB of UTF-8 state; oversize/quota errors are visible,
and persistence is awaited before a local write/sync or local inference dispatch.
Typing and streamed-history snapshots debounce for 200 ms; sudden page/process
loss can omit the latest unflushed text. Folder access still requires a reconnect
selection. Turning the option off removes this session's copy; other saved sessions
have explicit Forget controls. There is no automatic deletion of recovery records.
Saved-storage optional-tool preparation recovery remains separate work.

Synthetic real-IndexedDB/OPFS checks passed: opt-in, failed disk write, fresh-page
recovery, wrong-folder refusal, competing-content conflict, successful explicit
retry, draft/editor/tool-result recovery, account isolation and no automatic
inference redispatch. Browser control stalled during final layout/disable checks;
those remain pending before rollout. 361 web tests, typecheck/build pass.


### Saved-storage optional preparation candidate — 2026-09-13

Preparation receives its own durable record before the tool/model path starts.
A capture links to a completed same-tenant/day/message preparation; duplicate IDs
are refused. Reopening groups preparation and capture into one visible exchange.
Unlinked preparation is explicitly not a saved entry. Recovery strips approval
IDs and presents tool history without actionable approval controls. Interrupted
calls are historical and never replayed. Reference material stays labelled as
optional context, not a companion answer. Local-folder sessions do not request
this server journal; their separate browser recovery remains opt-in.

Tool history has bounded per-call/overall storage and reports truncation. Existing
streamed tool result previews remain previews (up to300characters), not a claim
that complete private tool output is archived. Application restart does not replay
preparation or infer whether an interrupted external write succeeded. Candidate
verification/rollout is pending; production behavior is still the earlier version.
