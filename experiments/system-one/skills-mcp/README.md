# Offline skills/MCP selection contract

Runnable experiment for [issue #19](https://github.com/sbstndalton/noevia/issues/19). Production adoption is **deferred**. Nothing imports this directory from chat, registers a selector, changes a setting, installs a candidate or starts an MCP/script process.

From the repository root, using the existing Node runtime:

```sh
node --require ./apps/web/tests/hermetic-network.cjs --test experiments/system-one/skills-mcp/*.test.cjs
node experiments/system-one/skills-mcp/run.cjs --run-offline > /tmp/noevia-skills-mcp.jsonl
```

The CLI refuses to run without `--run-offline`, accepts no endpoint/credential/external fixture options, and preloads the repository's outbound network guard. It needs no new dependencies. A dedicated CI job runs these offline checks independently of the existing application pipeline. The library also defaults to `enabled: false`; enabling it requires explicitly injected scripted answers or synthetic embeddings. Injection is a test seam, **not a sandbox for arbitrary JavaScript**.

## What is implemented

`contract.cjs` prepares a private clone of synthetic project/current state and discovery snapshots. It reuses:

- `instruction-skills` for enabled/reviewed hash inspection and pinned reads;
- `skill-index` and `chat-skill-routing` for actual metadata/body formatting;
- `chat-skill-routing` and `chat-tool-routing` for the embedding comparator;
- shared `decision.rank` for deadline/locality behavior, with stricter experiment validation;
- `toolboxes.resolveTools` for actual schemas and count/token budgets.

The fixture envelope supplies already-observed server/account readiness and a configuration revision. This is **not** live discovery, OAuth, a credential store or an alternate registry. Account blocks in the selection experiment are frozen policy results. `execution.test.cjs` separately exercises real account-policy, approval, exchange and executor collaborators with synthetic storage/discovery/execution.

The rank request contains a bounded task question and metadata labels, never skill bodies. The answer permits only `selected`, `scores`, `confidence`, `abstain`. IDs must be offered and unique, every selected ID needs a finite 0–1 score, confidence must be finite and sufficient, and cardinality and explicit abstention must agree. No command, URL, argument, credential or arbitrary backend metadata is accepted. Generic `multi` remains unchanged and unused.

Deterministic loading intersects pinned and current project ownership, selection, reviewed hashes, discovery readiness and revision. Dependency closure remains inside that ceiling. Decision proposals admit whole tool groups only if all schemas survive blocks, collisions and the real resolver budget. A skill requires its toolboxes to survive, and oversized bodies are rejected instead of counting a truncated body as fully loaded. Default decision limits: one skill, three proposed boxes, 12,000 body bytes, 0.6 confidence, 0.5 per-ID score and a 50 ms scripted deadline. Dependencies may expand the resolved boxes within the resolver's schema budget.

On routing failure, skills retain their enabled metadata index and load **no body**; tools restore the permitted project selection through normal policy/count/token resolution. A valid partial proposal can retain accepted groups while reporting rejected groups separately. `proposed`, `accepted`, `loaded`, `rejected`, aggregate fallback and per-kind routing fallback are distinct fields. Unknown proposed strings are omitted from telemetry to prevent them becoming a text/secret logging channel.

## Comparison and evidence limits

The three modes share the same frozen input snapshots and deterministic experiment loading boundary:

| Mode | Selection source | Interpretation |
| --- | --- | --- |
| Baseline | No automatic skill body; permitted selected tools | Current fallback control; `baseline` is a control reason, not an outage |
| Embedding | Existing routers, injected three-axis keyword vectors | Router contract behavior; not a measured embedding model |
| Decision | Scripted rank answers, strict validation | Proposal/loading contract behavior; not System-One model quality |

The common experimental boundary is intentionally stricter than production auto-loading (whole dependency groups, no truncated skill loads). Thus this isolates selection under one boundary; it is **not** a byte-for-byte replay of production chat. The offline embedding wrapper also bounds the existing skill router, which has no own deadline; no production timeout fix is claimed. Snapshots are pinned for one run; a future production adapter must obtain authoritative scope/readiness and revalidate changing state before each real operation.

`fixtures.cjs` fixes 8 development and 8 held-out-labelled synthetic cases. Each mode runs each fixture three times (144 records). The split documents a future measurement protocol; it is not unseen model evaluation, and repeated scripted outputs are not stochastic evidence. Adversarial tests additionally cover malformed/unknown/duplicate/cross-project IDs, missing/non-finite scores, confidence, abstention, timeout/error/cancellation, dependency failures, stale/disabled skills, unready/unselected servers, configuration changes, collisions and budgets. Malicious descriptions are treated as data; the test proves no code execution, not resistance of a model to prompt injection.

JSONL records include fixture/set/config/catalogue hashes, opaque hashed IDs and bounded reason codes, actual body/schema byte counts, the real resolver's **estimated** schema tokens and local harness latency. They omit task text, descriptions, skill bodies, arguments and credentials. `scriptedSelectionAgreement` is exact accepted-ID agreement on five explicitly labelled simple fixtures; null elsewhere. It is deliberately not selection accuracy on real tasks. `forbiddenExposure` counts fixture schemas outside scope/readiness/dependency/block ceilings. The runner executes no actions, so `unauthorizedActions` is null. Execution tests assert actual synthetic call counts behind all three approval outcomes, account blocks and cancellation.

Instruction adherence, task completion and measured tokens remain null. Schema savings cannot establish total-token savings or end-to-end latency. See [results](results.md), [compatibility and candidate decisions](compatibility.md), and [separate script-execution design](script-execution-design.md).

For future authorized model runs: freeze a new held-out corpus before tuning; record runtime/model/version/host/dependencies/permissions/context; repeat stochastic cases at least three times; measure selection, loading, adherence, completion, latency, actual tokens and unauthorized actions independently. Require zero unauthorized actions and no held-out task-completion regression before a production proposal. Rollback for this slice is simply to leave the experiment unwired.
