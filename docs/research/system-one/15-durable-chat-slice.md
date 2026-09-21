# 15. Durable chat: first internal slice

Implemented locally, disabled by default, not deployed. This is source work with synthetic
providers/tools, not model switching qualification or System-One model selection.

`createChatHandler` accepts an optional `durableChat` collaborator from `chat-turns.cjs`.
Production construction does not pass one. There is no environment switch, admin toggle,
HTTP resume route, scheduler, autonomous replay, or provider failover. Enabling the internal
seam requires explicit source injection with `createChatTurns({enabled:true})`.

The recorder starts after context preparation for ordinary chats only. It snapshots the
uncompacted input, identity (tenant, project, conversation and server-owned turn UUID), selected
model configuration, round, retry allowances, emitted preambles/answers, complete tool-call
IDs/arguments/results and approval decisions. The prepared request is stored separately as a
disposable projection; reduction does not overwrite canonical results. Credentials and model
reasoning channels are not recorded. A caught stream failure retains partial visible text as
an incomplete output, never as a completed assistant message. A process kill can lose tokens
since the last boundary; it cannot transfer hidden reasoning, activations or KV cache.

Persistence reuses `jobs.cjs` and the existing per-tenant `jobs/<uuid>.jsonl` files. Its opt-in
durable mode hashes/chains and fsyncs records. Readers verify hashed records even when accessed
through another job-store instance. Existing un-hashed jobs remain readable, and retention is
kind-scoped. Corrupt/unreadable journals fail closed rather than masquerading as missing jobs.
Unlike the earlier draft's rollback suggestion, this slice requires review on corruption:
rolling back might hide a tool-start record. Hashes detect corruption, not malicious rewriting
by an actor with filesystem access. The journal is still a single-process primitive; this is
not a distributed lease or an exactly-once external-effects guarantee.

Every tool start is persisted before execution. A start without a result, a thrown tool error,
or an ERROR response after execution stays outcome-unknown. The display error is retained
without manufacturing a successful canonical tool result. Restoring such a turn returns
`review` and cannot invoke a provider or tool. No current tool reconciliation interface is
available here, so no reconciliation is guessed. Calls not started return `approval`; historical
approve / deny / approve_all and original approval IDs remain recorded, but grants are never
reinstated. The existing gate records the original action before normalizing approve_all to
approve for its caller. Completed calls are never replayed.

`restore` is read-only. `resumeGeneration` is an explicitly invoked internal test seam: it
consumes a persisted retry before invoking an injected projection builder and replacement
provider. It validates tool-group balance and context fit using the existing context meter,
accepts text-only completion, and records replacement configuration alongside the original.
It has no tool executor. Checkpoint compare-and-set prevents stale in-process writers, and
retry consumption prevents concurrent replacement attempts spending the same allowance.
The ordinary three-round bound and three possible empty-stream fallbacks remain distinct from
the one manual replacement-generation allowance.

## Scope still to implement before any production enablement

- Recovery UI, authenticated resume routes, re-asking approvals and tool-specific reconciliation.
- Persistence before retrieval, vision and compaction; this slice starts at the answer loop.
- Incremental token persistence, journal sizing/retention policy for long conversations, and
  crash/power-loss validation on an approved host. Full snapshots intentionally favor a bounded
  testable implementation; no storage or throughput benchmark was run.
- Rebuilding replacement requests through the live provider qualification and policy path.
  Current replacement tests use injected synthetic providers only; no inference was authorized.
- Browser reconnection, multiple server processes, and complete tool-capability restoration.

No deployment, engine/reranker change, real Diary access, model/dependency download, or real
provider call is part of this implementation. Dedicated System-One candidates remain undecided.

## Local verification commands (2026-09-21)

Repository root, already-installed Node/dependencies only:

```sh
node --test apps/web/server/decision/readout-bounds.test.cjs experiments/system-one/decisions/run-budget.test.cjs experiments/system-one/decisions/run-cutoff.test.cjs
# 28 passed (batch 1, independently verified here)
node --test apps/web/server/decision/index.test.cjs apps/web/server/decision/logit.test.cjs experiments/system-one/decisions/harness.test.cjs experiments/system-one/decisions/state-v2.test.cjs experiments/system-one/decisions/residency.test.cjs
# 36 passed (existing decision/experiment coverage, batch 1)
node --test apps/web/server/chat-turns.test.cjs apps/web/server/chat-durability.test.cjs apps/web/server/jobs.test.cjs apps/web/server/approvals.test.cjs apps/web/server/vision-routing.test.cjs
# 45 passed (final durable slice)
cd apps/web
npm test
# Batch 1: 1138 passed. Final batch 2: 1162 passed. No skips or failures.
npm run typecheck
npm run build
npm run lint:design
# All three pass for each batch.
```

Early development runs exposed an invalid-ID error regression and a synthetic response fixture
that omitted its finish event, leaving a heartbeat timer alive. Both were corrected; the hung
test processes were stopped. One npm invocation from the repository root had no package.json;
all recorded successful npm checks above ran from apps/web. The final checks are fresh runs,
not the bundle's earlier 28-test isolated evidence.

Not run: browser suites (no UI change), live tool/provider checks, real model startup/cancellation,
model inference/benchmarks, power-loss and storage-load testing, deployment tests. These need
separate authorization where they cross the user's resource or production boundaries.
