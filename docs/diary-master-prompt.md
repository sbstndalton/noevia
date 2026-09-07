# Cowork — diary landing, calendar, files, and session storage

This replaces the previous master prompt. The user's clarified requirements below are the source of truth. Preserve existing chat, authentication, tenant isolation, and diary integrity behavior.

## Diary experience
- Open Diary to an inviting landing page in Cowork's existing light/dark style. A greeting and prominent composer are the main focus.
- Remove the separate Today card. Resolve the user's computer date, time, and timezone at submission, including after midnight.
- Put month navigation below the composer. Opening a month shows a calendar, marks days with entries, and lets users open individual dates (including empty past dates).
- A selected date displays only that day's entries. Its composer clearly identifies the date being appended to. Merely browsing never mutates diary data. Return home to write to today's date.
- Replies and thoughtful questions belong inside diary conversations. No separate Insights feature.

## Context and Markdown
- A right-hand panel exposes memory/context files and the active diary storage location.
- Clicking a Markdown file opens an accessible modal viewer/editor with preview, explicit Save, Cancel, unsaved-change protection, and visible errors.
- Edits must be scoped to the signed-in user's corpus, size-limited, and protected against concurrent overwrites. Updated memory/context must be available to subsequent diary responses.

## Storage wizard
- Edit location opens a modal wizard. Offer a folder on the computer running the browser, or existing online backends: Nextcloud, WebDAV, and S3-compatible storage.
- SMB shares use the folder picker after the user mounts the share on their computer. Do not pretend the browser can connect directly to arbitrary smb:// URLs.
- Browser folder permission is explicitly granted through its native picker. Detect unsupported browsers and explain available alternatives.
- A local folder is a temporary session override. Never replace the saved online connection or persist a directory handle. On reopening/reloading Cowork, resume the saved connection (Nextcloud for this user).
- Include a configurable “Also sync to Nextcloud” toggle (or the saved connection's name), enabled by default. Sync changes as they happen, not only when closing the window. Disabled means local-only changes.
- Local files can be sent to the configured app/inference service to answer diary questions, but local-only mode must not write them to the saved online corpus. Explain this distinction in the picker.
- Surface pending/failed sync and support retry. Never overwrite divergent remote/local changes silently. Preserve the local copy when remote sync fails. Do not rely on unload callbacks for persistence.

## Delivery and verification
Implement the full flow, reuse existing storage integrations, and retain unrelated functionality. Verify calendar/date targeting, scoped file editing, conflicts, local-only behavior, sync retry, and return to saved storage. Exercise responsive light/dark UI. Run relevant regression tests and a production build. Push the changes to GitHub and deploy via ssh daserver with a backup and rollback path, as authorized in this task. Report limitations honestly. Ask concise questions if a substantive ambiguity blocks progress; do not spend excessive effort guessing.
