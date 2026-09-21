# Continuation verification — 2026-09-21

Scope: local source at d933118 plus two additional process-death regression tests; read-only
inspection of the user's open Noevia, Unraid and Nextcloud pages. No production deployment,
real inference, dependency/model downloads, personal-source refresh, or real Diary access.
The earlier explicit resource restrictions remained in force.

## Automated checks

From `apps/web`, with existing dependencies:

- `npm test`: 1162 passed before adding process-death tests; 1164 passed afterward.
- `npm run typecheck`: passed.
- `npm run build`: passed.
- `npm run lint:design`: passed.

From repository root:

```sh
node --test apps/web/server/decision/*.test.cjs experiments/system-one/decisions/*.test.cjs
# 64 passed; temporary Node fixtures only, no real model worker.
node --test apps/web/server/chat-turns.test.cjs apps/web/server/chat-durability.test.cjs
# 22 passed, including two new separate-process SIGKILL cases.
```

From `apps/web`, individually with isolated environment variables and a 45-second watchdog:

```sh
node qa/model-context-http.cjs
node qa/mcp-internal-http.cjs
node qa/usage-http.cjs
node qa/instruction-skills-http.cjs
```

All four passed. They use disposable account directories and loopback stubs. Coverage includes
cold-model budget sequencing, changed context limits, blocked failed loads, MCP discovery,
invalid/expired/replayed capability tokens, unapproved writes, two-tenant isolation, usage
privacy and authorization, and instruction-skill review/hash/update/source-exclusion rules.
The model manager and completion responses in these tests are mocks.

The new process-death tests launch only a tiny Node journal writer. The parent waits for the
checkpoint, sends SIGKILL, then constructs a new service from disk. A completed tool result
survives and reaches a mocked replacement provider with the same identity and approval history.
A tool-start without a result restores as outcome-unknown and blocks continuation. This tests
process death, not power loss or distributed concurrency.

## Browser checks

The built local frontend was served by `qa/diary-fixture.cjs` (all APIs synthetic). Through the
in-app browser, verified:

- A finished response shows two named tool calls and one declined call.
- Expanding a tool shows its arguments and full fixture result.
- Viewports 375, 768 and 1440 pixels have no document-level horizontal overflow.
- A pending write shows untruncated arguments and Allow once / Decline / Allow for this chat.
- Stop removes approval buttons and marks the call not run; it does not imply approval.
- No captured browser warnings/errors in the local test tab.

Screenshots were visually inspected at phone and tablet sizes. This was a targeted dark-theme
check, not the entire historical browser QA suite or an exhaustive theme/accessibility audit.
The temporary tab/server were closed and the viewport override reset.

Live pages (read-only):

- Noevia settings and service status load, with no captured browser errors. Inference and
  project retrieval report available, and 175 tools are discovered across three servers.
  The Diary setting is disabled for this account; Service status presents that as unavailable.
  This is not evidence of a Diary service outage.
- Unraid reports the array started, parity valid and zero errors from its last parity check.
  Its container inventory lists the core cowork services started. No starts, stops, updates,
  parity checks, model loads or configuration changes were performed.
- Nextcloud dashboard loads in the signed-in session. Its captured console contains
  `[ERROR] viewer: Could not register handler`. No file-preview failure was reproduced;
  personal files and messages were not opened. This remains an observation to investigate,
  not a validated explanation or a claim that Nextcloud fully passes.

The user's live tabs were left on their original pages. The new chat-durability seam remains
unwired in production, so these live checks do not validate the new code on the server.

## Remaining limits

Not run: real model inference/startup/cancellation, model or storage benchmarks, power-loss
validation, full historical browser sweep, real Nextcloud writes/uploads/sync, production
recovery, or a live reranker/Diary test. No production behavior was enabled. There is no test
failure blocking the bounded source slice; “everything passes in production” is not established.
