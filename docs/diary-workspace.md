# Diary workspace

Diary now opens to a writing landing page. Month cards lead to calendars, and
selecting a day opens only that day's content. Sending from home uses the browser's
local date/time at submission; sending from a selected day appends to that date.
Browsing does not write anything. The separate Today card is removed.

The Memory & context panel browses the configured diary folder. Markdown files
open in a modal viewer/editor with an explicit Save action. MEMORY.md, context.md,
instructions.md, and up to eight files in memory/ or context/ are included as
bounded reference material in subsequent conversations. Existing entry files can
also be opened and edited through this browser. Rendered Markdown supports common
headings, bold, inline code, lists, quotes and fences; raw HTML is escaped.

## Temporary folder sessions

Choose Storage location → Edit → Folder on this computer. The native picker grants
read/write access to the selected folder. Mounted SMB shares can be selected here;
there is no direct smb:// connection from the browser. Browsers without the writable
folder API display an explanation and can use online storage instead. The browser
API is documented by [Chrome](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access).

Cowork does not persist directory handles. A reload/new window returns to the saved
connection. Switching between app tabs within the same page keeps the local session.
Only Markdown is scanned (500 files, 512 KiB per file, 12 MiB total, 10 folder levels).
Local conversations send the selected Markdown snapshot to the configured app and
inference service. Local-only processing uses an in-memory backend and SQLite
connections, without saving the snapshot in the server or online corpus. Historical
local reference uses bounded keyword-selected excerpts rather than a persistent
semantic index. The normal diary logging pipeline still determines what to log.

“Also sync to [saved connection]” is enabled by default and can be toggled. It applies
to changes made while enabled, not a bulk upload of every existing local file. Writes
save locally first; enabled sync then conditionally updates the same relative path in
the saved connection. A remote file already matching the result makes retry idempotent.
Divergent files are never silently overwritten. Pending sync remains visible with a
Retry action; resolve divergent content by reviewing the saved file. Unsynced local
copies remain on the user's computer. There is no background sync after the window
closes, and no dependence on unload handlers to perform writes. A close warning is
best effort; the browser/OS may end a session without allowing it.

## Safety and validation

All remote file operations use authenticated tenant-scoped proxy routes, CSRF checks,
relative-path validation, size limits, and conditional storage writes. Local snapshots
have a bounded 16 MiB proxy request allowance; other requests retain the 1 MiB cap.
The local inference endpoint shares the chat rate limiter. File edits invalidate
retrieval before writing and reindex after acknowledgment. No new dependencies.

Regression tests cover leap years, split-day views, date/time offsets, past-date
logging, tenant-relative paths, stale-file conflicts, local-only isolation, local
folder scans/writes, sync failures, and idempotent retries. Browser checks exercise
calendar/day navigation, Markdown save/reopen, storage wizard, light/dark layouts,
and phone-width bounds using synthetic data. Native folder selection requires a
user permission dialog; the automated UI check verifies it opens, while file API
behavior is tested with in-memory test handles. Real personal diary data is not
modified during verification.
