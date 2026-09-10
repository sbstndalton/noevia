# The diary

Merged from `diary-master-prompt.md` (requirements) and `diary-workspace.md`
(as-built). Planned changes — zero-state landing, folder scaffolding, first-entry
navigation — are in `roadmap.md` Workstream 4, not here.

**Do not send prompts to the live diary. It is the user's real private journal.**

---

## Part 1 — Requirements

The clarified requirements are the source of truth. Preserve existing chat,
authentication, tenant isolation, and diary integrity behaviour.

### Diary experience

- Diary opens to an inviting landing page in the existing light/dark style. A
  greeting and prominent composer are the main focus.
- No separate Today card. Resolve the user's computer date, time and timezone **at
  submission**, including after midnight.
- Month navigation sits below the composer. Opening a month shows a calendar, marks
  days with entries, and lets users open individual dates — including empty past
  dates.
- A selected date displays only that day's entries. Its composer clearly identifies
  the date being appended to. **Merely browsing never mutates diary data.** Return
  home to write to today.
- Replies and thoughtful questions belong inside diary conversations. **No separate
  Insights feature** — it was built, then removed.

### Context and Markdown

- A right-hand panel exposes memory/context files and the active storage location.
- Clicking a Markdown file opens an accessible modal viewer/editor with preview,
  explicit Save, Cancel, unsaved-change protection, and visible errors.
- Edits are scoped to the signed-in user's corpus, size-limited, and protected
  against concurrent overwrites. Updated memory/context must reach subsequent
  responses.

### Storage wizard

- Edit location opens a modal wizard offering a folder on the computer running the
  browser, or an online backend: Nextcloud, WebDAV, S3-compatible.
- SMB shares use the folder picker **after the user mounts the share**. Do not
  pretend the browser can connect to arbitrary `smb://` URLs.
- Browser folder permission is granted through the native picker. Detect
  unsupported browsers and explain the alternatives.
- A local folder is a **temporary session override**. Never replace the saved online
  connection, never persist a directory handle. Reopening resumes the saved
  connection.
- A configurable "Also sync to [saved connection]" toggle, enabled by default,
  syncing as changes happen — not only on close. Disabled means local-only.
- Local files may be sent to the inference service to answer questions, but
  local-only mode must not write them to the saved online corpus. Explain this
  distinction in the picker.
- Surface pending and failed sync with retry. Never overwrite divergent changes
  silently. Preserve the local copy when remote sync fails. **Do not rely on unload
  callbacks for persistence.**

---

## Part 2 — As built

### Landing, calendar, and dates

Diary opens to a writing landing page. Month cards lead to calendars; selecting a
day opens only that day's content. Sending from home uses the browser's local
date/time at submission; sending from a selected day appends to that date. Browsing
writes nothing.

The diary container's `TZ` controls every server-side date/time fallback when a
client omits its entry stamp. Set an IANA timezone in the deployment `.env` (the
compose examples default to `America/New_York`), then recreate the diary container
to load the changed environment; restarting alone retains the old value. Named
zones account for daylight saving automatically. This fallback is shared across
tenants; browser-supplied dates/times still take precedence. Journal event
timestamps remain UTC.

Setup's preferences step detects the browser timezone and lets the user confirm
or edit it, producing the `TZ=...` setting for the administrator to apply. The
wizard does not modify Compose or claim to apply a container environment change.

### Entry format

Structure is generated **mechanically by code, never by the LLM** — this is the
core division of labour and should stay that way:

```
## Saturday, August 30, 2026
### 14:32 — Topic
**Me:** …
**Assistant:** …
<!-- xid:UUID -->
```

Default layout is `daily`: `Entries/YYYY/<MonthName>/<MonthName> D, YYYY.md`.
Legacy monthly layout is `{year}-{month02}.md`. Writes go journal →
`apply_pending()` → `_guarded_write()` with an ETag create/modify loop (5 attempts).

Standing sections live in `INDEX.md` and are **disabled by default**
(`DIARY_INDEX_ENABLED=false`), so `update_standing_sections()` is a no-op on a fresh
install.

### Memory and context panel

Browses the configured diary folder. Markdown files open in a modal viewer/editor
with explicit Save. `MEMORY.md`, `context.md`, `instructions.md`, and up to eight
files in `memory/` or `context/` are included as bounded reference material in
subsequent conversations. Existing entry files can also be opened and edited here.
Rendered Markdown supports headings, bold, inline code, lists, quotes, fences and
tables; raw HTML is escaped.

> `AI Memory/` and `Raw Sources/` are named in `services/diary/README.md` but are
> created and surfaced by **nothing**. They are an unimplemented convention —
> `roadmap.md` Workstream 4a proposes scaffolding them.

### Temporary folder sessions

Storage location → Edit → Folder on this computer. The native picker grants
read/write access. Mounted SMB shares can be selected; there is no direct `smb://`
connection. Browsers without the writable folder API get an explanation and can use
online storage. ([Chrome docs](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access))

Directory handles are **not persisted**. A reload or new window returns to the saved
connection; switching between app tabs within the same page keeps the local session.
Only Markdown is scanned — 500 files, 512 KiB per file, 12 MiB total, 10 folder
levels.

Local conversations send the selected Markdown snapshot to the configured inference
service. Local-only processing uses an in-memory backend and SQLite connections
without saving the snapshot to the server or online corpus. Historical local
reference uses bounded keyword-selected excerpts rather than a persistent semantic
index. The normal logging pipeline still decides what gets logged.

### Sync

"Also sync to [saved connection]" is on by default and toggleable. It applies to
changes made while enabled — **not** a bulk upload of existing local files. Writes
save locally first; sync then conditionally updates the same relative path remotely.
A remote file already matching the result makes retry idempotent. Divergent files
are never silently overwritten; pending sync stays visible with a Retry action.
Unsynced local copies remain on the user's computer. There is no background sync
after the window closes and no dependence on unload handlers. The close warning is
best effort — the browser or OS may end a session without allowing it.

### The service

FastAPI sidecar, multi-tenant by `X-Cowork-User-ID` (UUID) plus an optional base64
`X-Cowork-Storage` blob. Per-tenant SQLite index at `data/users/<uuid>/index.db`.
**Never expose it directly** — it trusts a single shared `DIARY_AUTH_TOKEN`.

Web proxy routes (`index.cjs`) are all gated on `diaryEnabled(user.id)` and 404 when
off: `/api/diary/files`, `/file`, `/local-exchange`, `/source`, `/today`, `/history`,
`/external-sources` (**admin-only**), `/external-sources/import`, `/entries/edit`.
Diary chat is not a diary route — it is `spaceId === 'diary'` inside the chat
stream, emitting `{type:'diary', decision, xid}`.

Prompts live in `services/diary/config/prompts/`: `system.md` (companion persona,
four-layer context contract, the logging marker line) and `logging.md` (a
`skip_classifier` LOG/SKIP template, a third-person `summarizer`, and others),
consumed by `pipeline.py::_aux_call` and `context.py::_system_prompt`.

### Safety and validation

All remote file operations use authenticated tenant-scoped proxy routes, CSRF
checks, relative-path validation, size limits, and conditional storage writes. Local
snapshots get a bounded 16 MiB proxy allowance; other requests keep the 1 MiB cap.
The local inference endpoint shares the chat rate limiter. Edits invalidate
retrieval before writing and reindex after acknowledgment.

Regression tests cover leap years, split-day views, date/time offsets, past-date
logging, tenant-relative paths, stale-file conflicts, local-only isolation, local
folder scans and writes, sync failures, and idempotent retries. Browser checks
exercise calendar/day navigation, Markdown save and reopen, the storage wizard,
light/dark layouts and phone widths **using synthetic data**. Native folder
selection needs a user permission dialog, so the automated check verifies only that
it opens; file API behaviour is tested with in-memory handles. Real personal diary
data is not modified during verification.
