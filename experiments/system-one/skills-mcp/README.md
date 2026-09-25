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

## Live-model harness for issue #265 (code only; no run has been made)

[#265](https://github.com/sbstndalton/noevia/issues/265) needs measurements that the offline runner reports as null. `live.cjs` is a separate runner beside `run.cjs`. It reuses `contract.cjs` unchanged and adds a model endpoint for two things: the System-One proposal, and one task turn per case. Every run needs per-run owner approval (see the run plan in `docs/handoffs/2026-09-25-run-plan-265.md`).

- **Arms:** `baseline` (no automatic skill body; every permitted tool), `embedding` (the existing rules/embedding routers with the keyword stub vectors from `fixtures.cjs`), and `system-one` (the model proposes; `contract.cjs` validates the proposal strictly and loads within its bounds).
- **Tasks:** `live-fixtures.cjs` extends the synthetic fixtures with an expected outcome per task: `expected.tool` (the call that completes the task, or none), `expected.allowedTools` and `expected.selection`. The tool catalogue is the fake MCP catalogue. There are no real servers, skills or data. The `overlap` case has an `expectedSelection` of `null` (no expected accepted IDs), so `selectionCorrect` there scores true only when an arm accepts nothing; it does not score which one of the two allowed tools gets called, which `expected.tool`/`toolChoiceCorrect` still cover.
- **Per run (JSONL):** task completion, selection correctness (accepted IDs match the expected skill and toolbox), tool-choice correctness, unauthorized actions (each tool call outside `allowedTools`, including invented names), fallback reasons, schema count, bytes and estimated tokens, body bytes, endpoint `usage` for the selection, task and bare calls, measured schema+body tokens (task prompt tokens minus the prompt tokens of a bare call with the same index and task but no schemas or bodies), and latency (selection, model and total). The records exclude task text, skill bodies and tool arguments.
- **Safety:** Skill scripts are never executed, and a model's tool calls are never executed either; they are recorded and scored. Each MCP candidate stays behind its own gate, because only fake schemas are offered. The endpoint has no default: `--base-url`/`SKILL_EVAL_BASE_URL` and `--model`/`SKILL_EVAL_MODEL` are required. `SKILL_EVAL_API_KEY` is optional and is sent as a bearer token. A base URL that embeds credentials is refused.
- **Determinism:** `temperature: 0`, `seed = --seed + repetition` (the same seed for every arm within a repetition), a fixed case order, and `--repeats N` (default 3).

```sh
# Tests (mocked endpoint on 127.0.0.1, hermetic network guard)
node --require ./apps/web/tests/hermetic-network.cjs --test experiments/system-one/skills-mcp/*.test.cjs
# Validate config and fixtures; makes no endpoint call
node experiments/system-one/skills-mcp/live.cjs --dry-run --base-url "$SKILL_EVAL_BASE_URL" --model "$SKILL_EVAL_MODEL"
# Approved live run only
node experiments/system-one/skills-mcp/live.cjs --base-url "$SKILL_EVAL_BASE_URL" --model "$SKILL_EVAL_MODEL" \
  --repeats 3 --seed 265 --out experiments/system-one/skills-mcp/results/live-$(date +%Y%m%d)
```

The output is `results.jsonl` (run rows plus a final summary row) and `summary.md` (a table per arm and split, with indicators). The runner refuses to overwrite existing output. The exit code is 1 if any unauthorized action occurred. A mid-run crash appends a trailing `type: "error"` row instead of the summary row and exits 1; a `results.jsonl` with run rows but no summary (or error) row as its last line means the run was aborted, never a completed run to read as-is. The adopt/revise/defer decision and the rollback conditions are left blank for the owner.

**Pass/fail criteria (copied from #265 "Done when"):**
- Report task completion, correct Skill/tool selection, schema/body token cost, latency, fallbacks, and unauthorized-action count across repeated runs.
- Keep Skill script execution and each MCP candidate behind separate qualification gates.
- Record an adopt, revise, or defer decision, plus rollback conditions. Do not enable production selection solely because the offline contract exists.

The harness's indicators follow the protocol above: zero unauthorized actions, and held-out task completion no lower than baseline. They inform the decision; they do not make it.

Known limits: the embedding arm uses keyword stub vectors, not a live embedding model. The eight live tasks are synthetic and small, so the results are not a general accuracy claim. Each task is a single turn, and task completion means that the expected tool was called with JSON arguments and nothing unauthorized was called.
