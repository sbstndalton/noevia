# Shared Diary editing: Claude and noevia

## Updated direction — 2026-09-12

The user now wants a direct SMB-mounted Diary working folder on the Mac. The
[server-local/SMB migration plan](spec-diary-smb.md) supersedes the assumption below
that Nextcloud must remain the long-term authority. It remains the current
storage until a verified migration occurs; neither copy has been reconciled or
moved by this update. Keep the scoped Diary API for guarded edits, including when
its storage becomes local. Arbitrary SMB editing is not covered by its version
checks, and the client sync diagnosis remains unverified.

The 2026-09-10 decision and implementation evidence below are historical.

Decision (2026-09-10): use the live Nextcloud copy as the authority. The user chose
the most reliable integration rather than requiring a Mac-folder workflow.
The scoped API is deployed in `12a1646`. The private Claude plugin is packaged,
but has not been imported into Claude; no local/cloud files have been reconciled.

## Observed state

- noevia writes directly to Nextcloud WebDAV through its Diary companion. The
  storage layer uses ETags and conditional writes with bounded conflict retries.
- Claude currently edits a Nextcloud-synced Mac folder. The local save and remote
  save are separate events, in both directions. noevia cannot see an unuploaded
  local edit; a server ETag cannot protect against that invisible version.
- Nextcloud Desktop 34.0.3 and its File Provider process are running on the Mac.
  macOS denied access to protected client state/logs, so client queue health and
  the cause of delayed local uploads remain unverified. No permissions bypassed.
- The server's `occ notify_push:self-test` passed Redis delivery, database mount
  lookup and Nextcloud connectivity, but failed proxy trust. The test address was
  resolved to the server LAN address, not the expected synthetic client address.
  This is a concrete notification-path defect, not proof of the entire sync cause.
- No local MCP servers appear in Claude's standard desktop MCP configuration.
  That does not establish the state of its separately configured remote connectors.
- No journal contents were changed or test prompts sent. Sync databases and
  local/cloud copies remain untouched. Push callbacks were repaired as below.

## Chosen integration

Expose a narrowly scoped, authenticated Diary tool adapter to Claude. It should
use the same server-side storage/version contract as noevia, regardless of whether
storage is WebDAV or local. Reads return content plus an opaque version; replacement
writes require that version. A mismatch returns a conflict with the proposed edit
retained, never a silent overwrite or automatic last-writer-wins merge.

Prefer semantic append-entry operations through the companion for journal entries,
with idempotency keys, over generating and replacing an entire monthly file.
Arbitrary Markdown edits remain explicit and version-checked. Preserve existing
write approvals, user isolation and separate read/write credential scopes. Report
success only after the server acknowledges the write; a timed-out operation needs
status recovery before retrying. The adapter must expose only the user's Diary,
not Nextcloud-wide access or other projects. Credentials stay outside synced files.

Claude's workflow should use these tools for Diary reads and writes. A local copy
can remain available for offline reading. Offline edits must be treated as drafts
and reconciled explicitly with the latest server version when reconnecting.
Before switching, compare and reconcile any pending Mac/cloud differences without
choosing either copy automatically, then retain a backup of both versions.

The API and stdio plugin are implemented; Claude installation remains outstanding.
A generic filesystem folder or a non-conditional write tool is not equivalent.

## Independent sync repair

Repaired with `deploy/nextcloud/repair-push.py` (`c42f16a`): callbacks use
`http://nextcloud-aio-apache.nextcloud-aio:23973`. Only that exact internal hostname
was added to trusted domains. Trusted proxies and the public push endpoint are
unchanged. All six self-tests pass, including after container restart. AIO may
recreate this container during updates; rerun the documented repair afterward. Do not broadly trust arbitrary networks or
forwarded headers just to make the test green. Check the Mac client queue/status
through its UI; protected logs were unavailable to this session. Verify both
upload and download with a disposable non-Diary file and measured timestamps.
Push health improves responsiveness but does not make two writers transactional.

## Acceptance checks for the adapter

1. Both clients read the same version immediately after an acknowledged write.
2. A stale replacement conflicts and preserves the proposal.
3. An append retried after a lost response does not duplicate an entry.
4. Another user or an out-of-scope path cannot be read or written.
5. An offline or interrupted request never claims a confirmed save.
6. All integration tests use synthetic storage, not the real journal.

References: [Nextcloud macOS File Provider documentation](https://docs.nextcloud.com/server/stable/user_manual/en/desktop/macosvfs.html),
[notify-push and self-test](https://github.com/nextcloud/notify_push),
[reverse-proxy trust configuration](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html).

## Implemented and verified — 2026-09-10

Production `12a1646` exposes dedicated hashed, revocable per-user credentials and
only Markdown list/read/versioned-write operations. Browser sessions cannot
substitute for connector credentials; Origin requests, traversal, disabled users
and stale versions are rejected. Tests use an isolated synthetic companion.
332 web tests, typecheck/build, three Python bridge tests, synthetic HTTP QA,
284 Linux server and 13 worker tests pass. Production rejects invalid credentials
and out-of-scope paths without touching the corpus.

The private plugin/config ZIP is outside Git and Nextcloud, under
`~/.local/share/noevia/`. Its MCP initialization exposes three tools. Claude UI
automation became unavailable before import; installation and a real Claude
round trip are not verified. Import grants live Diary access and must preserve
write approvals. Separate read-only credentials, semantic append/idempotent
recovery, pending Mac/cloud reconciliation and measured desktop sync remain open.
Whole-file writes currently require a read version and never automatically retry.
