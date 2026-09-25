# Verify #262 on the next authorized project open — Docling re-read of the tax folder

Read-only validation only. **Do not open, name, quote, or reproduce the
contents of any tax-folder document anywhere in this session, in chat, in a
filed issue, or in this ledger.** Everything below is checked through file
names/paths, per-file status, byte counts and log event names, never content.

This session (`claude/docling-verify`, PR "Docling: storage-path regression QA
and live verification handoff (#262)") did everything that could be done
without the live project: it added a synthetic reproduction of the
2026-09-21 storage-path fix (`apps/web/qa/docling-storage-path.cjs`) and found
and fixed one small related bug (a filename with a character outside Latin-1
crashed `docling.cjs`'s `extractDocument` before any request left the process
— `headerSafeName()` in `apps/web/server/docling.cjs`). Neither of those
proves the real Docling worker reads the real tax folder; only this live
check does.

## No-change statement

Nothing here changes anything. Every step is a read: log greps, one GET
request to the running web API, and a look at the Sources tab already open in
the browser. If step 3 below shows a live problem, the fix is a **separate**
PR — do not patch anything in place during this check.

## 1. Confirm what is actually running

```sh
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -E 'cowork-(web|docling)'
docker inspect cowork-web-1 --format '{{.Config.Env}}' | tr ',' '\n' | grep DOCLING_BASE_URL
```

`DOCLING_BASE_URL` must be set and reachable — if it is empty, the project is
running the pdf.js fallback and there is nothing Docling-specific to verify
here; stop and say so rather than checking the wrong pipeline.

## 2. Trigger the re-read

Open the tax project in the UI (the "next authorized project open" the issue
asks for) and use its existing "Sources" → re-sync action (or just open the
project; a sync fires automatically on the existing schedule/whichever
mechanism is live — check `docs/deployment.md`/`docs/spec-service-boundaries.md`
if unsure which). Do not open, preview, or ask the model to read any
individual document's content as part of this check.

## 3. Logs — what they will and will not show

**`docling` container: by design, almost nothing.** `services/docling/server.py`'s
`Handler.log_message` is a deliberate no-op ("Never log document contents,
names, or credentials") — do not expect to see per-file log lines there. What
IS worth checking:

```sh
docker logs --since 10m cowork-docling-1
```

- Clean: no crash/traceback lines, process still up (`docker ps` shows no
  restart since before the sync).
- A restart or a Python traceback here is a real, separate problem — file it
  per step 5, do not try to fix it live.

**`web` container: also has no per-document log line today** (verified by
reading `apps/web/server/routes/projects.cjs`, `document-sources.cjs`,
`documents.cjs` and `docling.cjs` — none of them call `console.log`/`warn` on
a per-file extraction outcome; that is intentional, matching the "never log
document contents or names" posture the whole pipeline shares with OCR). What
DOES appear if something goes wrong:

```sh
docker logs --since 10m cowork-web-1 | grep -E '\[documents\]|\[uploads\]|\[noevia\] unhandled promise rejection'
```

- `[documents] indexing <projectId>/<fileName> failed:` — RAG indexing
  failed after extraction; the file name appears (path, not content) — treat
  a hit here as a lead, not proof of the Docling bug itself.
- `[noevia] unhandled promise rejection:` — anything here is a bug on its
  own, independent of #262; file it separately per step 5.
- **No log line at all is the expected, healthy outcome.** The absence of
  logs is not itself evidence of success or failure — use step 4 for that.

## 4. Confirm the 400 is gone and read per-file status (no content)

The per-file extraction status is visible without exposing content in two
places:

- **UI**: the project's Sources tab lists each file with a status chip/row
  (ready / partial / failed / stale) — this is the `problem()`/`notice()`
  text built in `apps/web/server/document-sources.cjs` from `file.document`,
  which never includes `file.content`.
- **API** (same data the UI reads, useful for a precise grep): as the signed-in
  admin, from a machine that can reach the host,

  ```sh
  curl -s -b <session-cookie-jar> https://noevia.daserver.work/api/workspace \
    | jq '.projects[] | select(.name == "<the tax project name>")
          | .files[] | {name, state: .document.state, stale: .document.stale,
                         pages: .document.pages, error: .document.error}'
  ```

  (Get a cookie jar the normal way — sign in once in a browser, or use
  whatever session token the deployment runbook already uses for read-only API
  checks. Never echo `.content` — the `jq` filter above deliberately excludes it.)

**The 400 signature to search for and confirm is ABSENT:**

```
noevia sent this document in a form the extractor refused; it will be read again after the next update.
```

That exact string (from `apps/web/server/docling.cjs`) is what a file's
`document.error` reads when the worker answers HTTP 400 — the failure mode
the 2026-09-21 fix targeted. Its absence across every file in the tax
project's `document.error` field, combined with every file's `document.state`
being `ready` or `partial` (not stuck `failed` with that message), is the
positive confirmation the issue asks for.

## 5. Done when (from #262), plus this session's addition

- [ ] Every tax-folder file's `document.state` is `ready` or `partial` (not
      `failed` with the 400 message above) — confirms the documents were
      re-read without the prior 400.
- [ ] The project's per-file status (Sources tab or the API query above)
      matches what is actually in the folder (right count, no file stuck on
      an old `stale`/`failed` state from before the fix).
- [ ] Any remaining failure — a file still `failed`, a docling container
      restart, an unhandled-rejection log line — is filed as its own issue,
      reproducible with a synthetic fixture, **contents excluded**: name the
      failing file by path only (never quote or describe its contents), the
      exact `document.error` string, and the docling/web log lines above.
      Use the `bug`, `synthetic repro` labels and this footer:

      ```
      _Generated by [Claude Code](https://claude.ai/code)_
      ```
- [ ] Once all of the above hold, close #262 referencing this handoff and
      PR "Docling: storage-path regression QA and live verification handoff
      (#262)".

## Rollback

None needed — this entire procedure is read-only (log greps, one GET, and
looking at an already-open UI tab). If step 3 or 4 surfaces a live regression,
the response is a new issue and a new PR, not a rollback of this check.
