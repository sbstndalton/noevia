# Tool disclosure and planner/executor research plan

Workstream 5 asks for scoped investigation, not a vendor-framework rewrite.
This document records code evidence and a bounded experiment plan. It does not
claim measured speed or model-quality improvements.

## Current behavior

`index.cjs` resolves tools from selected curated toolboxes, applies model tool
count and estimated prefill-token budgets, and checks the resolved allowlist again
at execution. MCP discovery comes from the existing three-call client. Chat has
three tool rounds, per-exchange duplicate-call protection, cancellation and three
write approval decisions. Fast/Smart routing chooses a model for a message; it is
not a planner/executor pipeline. Skills currently use project files, so skill
requirements must share the toolbox system rather than enable a second registry.

## Deferred tool disclosure experiment

Keep the user's selected toolbox ids as the absolute permission ceiling. Initially
provide a small metadata catalogue plus core tools and a read-only find_tools
operation. Discovery may return schemas only from that selection, scoped to the
current user's provider/MCP context. Querying by name must never expand permissions
or reveal another user's credentials. Newly offered schemas remain subject to
count/token limits and the same execution allowlist and approval gate.

The extra discovery round consumes part of the existing three-round budget.
Measure that cost explicitly before changing the round limit. Discovery results
must be deterministic enough to inspect, bounded in size, and must clearly explain
when a requested capability is unavailable. Preserve duplicate-call handling and
invalidate relevant read caches after attempted writes as today.

Fixture matrix: small selected toolbox, large catalogue, missing requested tool,
wrong-name hallucination, duplicate search, malicious result instructions,
mid-exchange deselection, cancellation, and each write approval decision. Compare
serialized schema bytes and approximate tokens separately from actual measured
latency. Success requires fewer schema tokens without a lower task-completion
rate or an extra unintended write. Do not label a token estimate as a timing result.

## Planner/executor experiment

Retain current Fast/Smart routing by default. Add an isolated experimental runner
that asks the configured Smart model for a bounded plan and uses the configured
Fast model for subsequent tool work. Plans are task context, not authorization.
The executor receives the current user request, selected tools, results and
approval state; it cannot use a planner instruction to skip a write decision.
Neither model may choose arbitrary provider URLs or obtain additional credentials.

Keep the same provider failure/cancellation behavior and the three-round ceiling.
Compare against the existing single-model handler on synthetic read-only tasks
first, then synthetic writes with mocked tools and human decisions. Record total
wall time, input/output tokens, calls, completed tasks, failed final answers,
repeated calls and approval count. A faster but less accurate answer is not success.
Provider/default output limits remain visible; this experiment does not prove
uncapped local thinking or support for an undocumented reasoning parameter.

Adopt only if the measured tradeoff is useful on the configured local models.
No benchmark has been run for this proposed pipeline, so it remains an experiment
plan rather than a production router change.

## Optional offline Wikipedia

No configured offline Wikipedia service was found in the repository inventory.
Do not silently install a corpus, allocate disk, or route private prompts to a
public substitute. Once an operator selects a reachable service, integrate one
or two read-only tools through the existing MCP manifest, with explicit selection,
source attribution and output limits. This optional integration does not block
skills, document handling or storage correctness.

## Deliverables and order

1. Synthetic fixture/measurement runner with the baseline handler unchanged.
2. Deferred-disclosure experiment under an off-by-default flag; review accuracy,
   schema budget and round use before wider rollout.
3. Planner/executor comparison on the same fixtures with separate results.
4. Integrate only evidence-supported changes; retain the existing simple path.

The user-selected instruction-skills proposal in spec-instruction-skills.md shares
these permission boundaries. None of these research items authorizes new executable
packages, a global auto-approve mode, or real Diary corpus testing.
