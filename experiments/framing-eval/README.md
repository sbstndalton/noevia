# Framing eval harness (#750)

Scripted eval for two questions: do answers improve with a confirmed chat frame
(`chat-frame-steering.cjs`), and which model should fill the reasoner slot
(`framing-reasoner.cjs`, `docs/spec-task-packet.md`). Synthetic cases only
(`cases.json`: search, action, idea, question, code; each with a gold frame, a
must-contain fact, the expected tool and, for injected results, a canary that must
never reach a tool call or a packet's goal/constraints).

**Built and unit-tested with stubs. Every real run needs the owner's per-run approval**
(host, config, cases, memory, duration; smoke test first). The runner refuses to build a
backend without `--approved-run <id>`.

```bash
# 1. plan only: prints host, config, cases, estimated memory and duration; touches nothing
node experiments/framing-eval/run.cjs --dry-run --host <label> --engine-url <url> \
  --answer-model <id> --candidates <id>,<id> --reference <id> --memory-estimates estimates.json

# 2. after the owner approves: smoke (2 cases) first, then the full set
node experiments/framing-eval/run.cjs --smoke --approved-run <id> ...same options...
node experiments/framing-eval/run.cjs --approved-run <id> ...same options...
```

`--memory-estimates` is the Models page export (`inferenceEstimates`: `{ budgetGib, models:
[{ model, estimate }] }`) or a `{ model: estimate }` map. The estimate is at each model's
configured context, so a number that is not at 32768 is shown but not judged. `--reference`
names the 7-8B candidate the others are compared with. Tunables: `--budget-gib` (16),
`--deadline-ms` (6000), `--sec-per-call` (10), `--load-sec` (60) for the duration estimate.

### Remote OpenAI-compatible API candidates

`--remote-models a,b` marks model ids (answer model and/or candidates) that a remote API serves.
They need no memory estimate: the plan shows "remote (no local memory)", the advisory memory line
reads "n/a (remote)", and they count 0 load seconds. The engine URL may be https. The key comes only
from the `FRAMING_EVAL_API_KEY` environment variable; it is sent as the bearer header and is never
printed, logged or written to a report (errors are scrubbed).

```bash
# list the model ids the API serves (read-only GET /v1/models, no inference, no --approved-run; needs the key)
FRAMING_EVAL_API_KEY=... node experiments/framing-eval/run.cjs --list-models --engine-url https://<host>/v1
```

Remote calls retry 429 and 5xx with backoff (1 s, 2 s, 4 s; at most 3 retries). `--max-calls <n>`
(default 60) caps API calls: a plan over the cap is refused, and a run that exceeds it (retries count)
aborts. The report records call count, retries and token usage from the responses' `usage`.

## What it measures

- **Framed vs unframed**: the same answer model and cases, the only difference being the
  frame block in the system prompt. Mean score, success rate, per-kind delta.
- **Reasoner slot**, per candidate, through the real `condense()` pipeline: packet validity,
  sufficiency (answer from the packet alone vs from the raw result, over the cases where the raw
  answer succeeds), injection robustness (canary absent from goal/constraints and from tool
  calls; an invalid packet falls back to the raw result as in production), latency (median, p95,
  deadline), memory from the estimate.
- **Kill criteria** from the issue: sufficiency below 0.85, or packet success below 0.70 of the
  reference model's on the same packets. Injection, latency and memory lines are advisory.

Phases keep model loads to a minimum (answer model, each candidate, answer model). The harness
assumes the engine loads what a request names and runs one model at a time. Reports go to
`experiments/framing-eval/results/` (gitignored) as `<id>.md` and `<id>.json`.

Offline test: `node --require ./apps/web/tests/hermetic-network.cjs --test experiments/framing-eval/*.test.cjs`.
