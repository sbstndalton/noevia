# Bound the native PDF reader queue

Issue: [#42](https://github.com/sbstndalton/noevia/issues/42). Audited at `5c551958ad3c407cbfecf5c48d7def4d7768167a`.

The native reader copies each PDF before an unbounded one-worker queue. Its 120-second worker timer excludes queue wait. Synchronous document uploads and folder sync can arrive from different projects while earlier readers run.

Implementation plan:

1. Give the native reader a small, explicit pending count and aggregate-byte budget. Check admission before making a transferable copy. Keep one active worker so RSS-growth attribution remains meaningful.
2. Start a bounded timer on admission for pending work. A queued timeout or full queue returns a distinct busy/retryable result; the active worker keeps its existing time, heap, and RSS limits. Release every reservation and timer after completion or cancellation.
3. Carry busy/retryable results through `documents.cjs` and `document-sources.cjs` so pressure is visible and does not become a permanently cached parse failure. Preserve page records, stale readable versions, tenant storage paths, and direct/managed upload behavior.
4. Exercise delayed synthetic workers for copy timing, limits, expiry, cleanup, and capacity reuse; test the extraction/cache contract. Then run the full web tests, typecheck, and build.

This changes the default native PDF reader only. Docling takes a different path. No production or private Diary data is needed for validation.
