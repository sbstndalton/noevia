# Agent execution architecture — spec

Status: **research/design**, 2026-09-16. Nothing here is implemented. It sets boundaries so
Code, Cowork, Deep Research, browser automation and prompt preparation don't each grow
incompatible machinery. Where repository research during implementation shows a simpler
shape, prefer it — but don't build one job engine per mode.

```
user request → (optional) Prompt Architect → durable job → mode → (optional) harness
            → execution node → capabilities → approvals → artifacts
```

| Mode | Default path |
|---|---|
| Chat | Direct; server inference; bounded toolboxes. |
| Code | Optional architect → CodeHarness → workspace → node (terminal/files/git). |
| Cowork | Optional architect → task executor → node capabilities (files/terminal/browser) under approvals. |
| Deep Research | Optional architect for planning if measured → durable job → search/read → cited report artifact. |

Upstream revisions read (source, via GitHub API; nothing cloned or installed):
Row-Bot `e5803e3`, DeepSeek Harness `0d1f500`, Browser Use `d8110c5`, Impeccable `f2c7051`;
cua `8cb8f6d`, Swiftlet `909c042`, flash-moe `3601d41`.
"(not verified in source)" marks claims taken only from docs or signatures.

---

## 1. Configuration-scoped qualification

**Today.** Vision capability: in-memory probe cache (`server/vision.cjs`). Native calibration
history per model: `{loadCtx, verifiedCtx, appliedCtx, build, slots}`
(`server/llamacpp-calibration.cjs`) — no artifact hash or full preset, no invalidation.
Context observations carry a configuration fingerprint and are rechecked live
(`server/chat-context.cjs`). MTP acceptance samples in memory (`server/mtp.cjs`).
`src/model-guidance.ts` is explicitly estimates only.

**Direction.** Evidence records, never a universal "quality" or "agent" score.

- **Categories:** chat, tool calling, multi-step tool continuation, vision, reasoning control,
  context capacity, context recall, MTP, coding (per harness), architect-assisted execution,
  later Cowork/browser.
- **States:** `reported` · `unverified` · `verified for this configuration` · `failed` ·
  `stale` · `unavailable`.
- **Identity (minimum needed):** provider/backend, model id, artifact hash where available,
  projector, runtime/engine version, context configuration, MTP profile, harness (coding),
  prompt-preparation mode + provider/model (when used), test suite + version, date, result,
  limitations. No credentials.
- **Staleness:** any change to a field in the identity marks linked evidence `stale`.
- Scope is literal: 32k passing doesn't qualify 128k; a tool fixture doesn't qualify Cowork; one
  harness doesn't qualify another; architect-assisted results don't qualify direct prompting.
- Reuse the existing fingerprint approach in `chat-context.cjs` rather than inventing another.

### Design — 2026-09-17 (not built)

**Record** (append-only JSON lines in the deployment's state, `evidence/evidence.jsonl`; a
derived `current` view per `(category, identityHash)`):

```json
{ "id": "ev_…", "category": "context_capacity", "result": "passed" | "failed" | "reported",
  "value": { "ctx": 32768 }, "identity": { … }, "identityHash": "sha256…",
  "suite": { "name": "native-calibration", "version": 3 }, "source": "calibration" | "probe" |
  "benchmark" | "provider-metadata" | "observation", "at": 1760000000000,
  "limitations": ["single slot", "prompt budget 120 s"], "tenantScope": "deployment" }
```

**Identity** (only fields that change behaviour; each producer fills what it can know):

| Field | Native llama.cpp source | Other providers |
|---|---|---|
| `backend` | `llamacpp` + router `build_info` | provider kind |
| `endpoint` | sha256 of router origin (never credentials) | sha256 of `baseUrl` origin |
| `model` | preset section name | model id |
| `artifact` | GGUF size + mtime + sha256 of first and last 1 MiB (cheap); full sha256 when a background job has it | unavailable → field omitted, state capped at `reported` |
| `projector` | same fingerprint of `mmproj` file, or `null` | `null` |
| `preset` | sha256 of the section's normalised key/values (sorted, excluding comments) | request options hash |
| `context` | `ctx-size`, `parallel`, KV cache types | requested max context |
| `mtp` | `spec-type`, draft artifact fingerprint, draft knobs | `null` |
| `harness`, `preparation` | coding/architect runs only | same |

`identityHash = sha256(JSON of the identity with keys sorted)`, reusing `chat-context.cjs`'s
`fingerprint`.

**States** are derived on read, never stored as mutable flags:

| Derived state | Rule |
|---|---|
| `verified for this configuration` | newest record for the category has `result: passed` and its `identityHash` equals the live identity |
| `failed` | newest matching record has `result: failed` |
| `stale` | a passed/failed record exists for the model but no record matches the live identity |
| `reported` | only provider-/metadata-sourced records (e.g. trained context, labels) |
| `unverified` | no records, but the category applies to this model |
| `unavailable` | the live identity cannot be computed (engine down, file missing) |

Scope is literal: a `context_capacity` pass at 32 768 records `value.ctx`; asking about 131 072
yields `unverified`, not a pass.

**Producers** (first wave, existing code): native calibration → `context_capacity`; vision probe
→ `vision` (successful probe is `passed`, projector error is `failed`); MTP counters →
`mtp_acceptance` (`reported`, value = rate); model-manager benchmark runs → `throughput`
(`reported`, per prompt suite) and user badges stay separate opinions, not evidence; chat
context allocation observations → `context_allocation` (`passed`). Imported calibration history
without artifact/preset identity becomes `stale` with limitation "recorded before identity
tracking".

**Consumers:** model manager detail shows one row per category with state, value, date,
suite and limitations; chat model panel shows only `verified`/`failed` badges; Auto routing and
model guidance may read states but never convert them into a score.

**API:** `GET /api/models/evidence?model=` (members read, derived view); producers write
server-side only. Admin `POST /api/models/evidence/recheck` recomputes live identity (cheap
fingerprint) for all models. No endpoint accepts client-supplied evidence.

**Tests:** identity hash stability and sensitivity (each field flips the hash); derived-state
table cases; literal scope (32k ≠ 131k); preset reorder does not change the hash, value change
does; artifact fingerprint changes on file replacement with the same name; no credential or
raw URL in records; import of legacy calibration history yields `stale`.

**Build order:** identity + fingerprints → store and derived view → calibration and vision
producers → model manager rows → remaining producers.

---

## 2. PromptArchitect (frontier-assisted preparation)

A stronger model writes a bounded, structured **execution prompt** for a weaker local model,
which then does the work. It does not replace the local execution model and is not applied to
every message.

- **Provider-neutral interface** `PromptArchitect`: none (Direct), a stronger local model, or a
  cloud provider (OpenAI, Anthropic, Gemini, others). Authentication only through each
  provider's officially supported mechanism (API key, supported OAuth, service credentials).
  **Never** reuse consumer web-session cookies.
- **Modes:** `Direct` (default) · `Local architect` · `Frontier architect`. `Auto` only after
  benchmark evidence (below) shows when the overhead pays.
- **Input contract (bounded):** request, target execution model + its qualification evidence,
  harness and its capabilities, available tools, context limit, relevant project instructions,
  approval restrictions, expected output form, verification requirements.
- **Output contract (structured, to be validated by testing):** goal, relevant context,
  constraints, required investigation, steps, available capabilities, approval boundaries,
  verification, completion criteria, non-goals. Prompts are shaped for the target — small
  models may need explicit sequencing and completion criteria; longer is not assumed better.
- **No hidden reasoning** requested, stored or shown. Store the execution artifact + metadata
  (provider, model, mode, time, context classes sent).
- **Outbound boundary — enforced in code**, not by instructions to the provider:
  - *May send:* the request, selected project instructions, explicitly selected snippets,
    public repo metadata, model/harness capability metadata.
  - *Never by default:* full repository, credentials/tokens/cookies/API secrets, Diary, private
    source collections, unrelated user data, tool credentials, hidden configuration.
  - Implement as an allowlisted payload builder with tests that assert forbidden classes never
    appear in the outbound request.
- **Disclosure:** "Prompt prepared by ‹provider/model›" with the context classes sent (e.g.
  request · project instructions · 2 snippets · no credentials · no Diary · no full repository),
  in noevia's existing visual language.
- **Artifact lifecycle:** visible and inspectable; editable before execution; saved with the
  job; regenerable and versioned. The original request remains authoritative intent and is
  never overwritten.
- **Benchmark matrix (required before any default changes):** same fixtures across
  raw prompt · deterministic local template · local architect · frontier architect; for Code
  also × harness × execution model. Report separately: completion, tests passed, invalid edits,
  tool failures, corrective iterations, context used, wall time, frontier tokens/cost, local
  inference time, user intervention. If a local template matches, prefer it; if frontier help
  wins only for a task class, scope it there.
- **Auto later:** choose Direct/Local/Frontier from measured benefit, task class, model,
  harness, the user's privacy policy, network availability and cost/latency preference.

### Benchmark design — 2026-09-17 (not run)

Lives beside the tool-routing runner as `experiments/prompt-preparation/`, same conventions:
synthetic fixtures only, explicit endpoint/model flags, credentials only from environment,
results written as JSON with a README table. Chat and Cowork task classes first; Code waits for
CodeHarness.

**Execution artifact schema** (validated with a JSON schema before execution; a failing artifact
counts as a preparation failure, never silently falls back):

```json
{ "goal": "…", "context": ["…"], "constraints": ["…"], "investigation": ["…"],
  "steps": [{ "n": 1, "do": "…", "done_when": "…" }], "capabilities": ["tool names"],
  "approval_boundaries": ["…"], "verification": ["…"], "completion": "…", "non_goals": ["…"] }
```
Caps: ≤ 12 steps, ≤ 1,200 tokens total. The executing model receives the artifact plus the
original request, labelled as authoritative.

**Variants** (identical executor, tools, approvals, fixtures, three repeats, rotated order):

| Id | Preparation |
|---|---|
| P0 | Raw request (today) |
| P1 | Deterministic local template: the schema filled by code from the request, project instructions and tool list — no model call |
| P2 | Local architect: strongest locally served model writes the artifact |
| P3 | Frontier architect: one cloud model through its official API, outbound payload from the allowlisted builder |

**Fixtures (18, synthetic):** 6 multi-step read tasks over a synthetic project (find, compare,
compute), 4 write tasks behind approvals (one to decline), 3 tasks with injected instructions in
tool results, 3 ambiguous requests where the right move is to ask, 2 long-context summaries near
the context limit. Each has an exact or rubric-scored expected outcome.

**Measured per run:** success (exact/rubric), steps and tool calls, invalid or blocked calls,
approvals requested vs expected, injected-instruction compliance (must be 0), corrective
iterations, executor input/output tokens, preparation tokens and cost, wall time split into
preparation and execution, artifact schema failures, user-intervention proxies (clarifying
questions asked when required).

**Outbound audit (P3):** the payload builder's output is logged locally per run and a test
scans it for forbidden classes (credential patterns, Diary paths, full file bodies beyond the
selected snippets). Any hit invalidates the run.

**Decision rules:** adopt P1 for a task class if it matches P2/P3 success within 1 fixture and
costs no model call. Offer P2/P3 for a class only if success improves by ≥ 2 fixtures of 18
with zero injected-instruction compliance and no increase in unexpected writes, and state the
added wall time. Direct stays the default everywhere else. Record results in this section with
the date and model configuration.


### First results — 2026-09-17 (Qwen3.5-4B-Q5_K_M executor and architect, 1 repeat)

Run from the Diary container against the live engine (`experiments/prompt-preparation`, rows in
`qwen35-4b-p0-p1-p2-run2-2026-09-17.json`). Run 1 exposed two harness bugs (architect reasoning left
on; "1,320" scored wrong), fixed before run 2.

| Variant | Success | read / write / inject / ask / long | Injected compliance | Unexpected writes | Median exec | Prep |
|---|---|---|---|---|---|---|
| P0 raw | **16/18** | 6/6 · 4/4 · 2/3 · 2/3 · 2/2 | 0 | 0 | 17.9 s | — |
| P1 template | 15/18 | 6/6 · 3/4 · 3/3 · 1/3 · 2/2 | 0 | 0 | 18.0 s | none |
| P2 local architect (4B) | 0/18 | — | — | — | — | 18/18 schema failures, 32 s median |

The 4B as architect writes plausible prompts but returns the list fields as plain strings in every
case, so every artifact fails validation (by design, no silent repair). Run 1 (before the scoring
fix) had P0 14/18 with one injected write and P1 15/18 with none.

**Reading (n = 1, not yet a decision).** The template neither helps nor hurts overall: one more
injection resisted, one ambiguous request and one read-then-save lost. A 4B cannot act as its own
architect under this schema. **Direct stays the default.** Next: 3 repeats, P2 with the 9B as
architect on the 4B executor, and a lenient-schema control to separate "cannot format" from
"prompt does not help". P3 needs the user (credits).

---

## 3. CodeHarness

Coding quality is a property of **model × harness (× architect)**, not the model alone:
harnesses differ in system prompts, repository context, patching, planning loops, command
execution, tool schemas, compaction and recovery.

**Today.** `src/components/CodingWorkspace.tsx` is a disabled preview; no routes, no harness.

- **Noevia owns the contract; harnesses adapt.** Candidates later: Codex, Claude Code,
  DeepSeek Harness, OpenCode, Hermes. Don't implement all.
- **Contract sketch (derive the final one from real harness behaviour):**
  - *Input:* task, execution prompt (if architected), workspace, model/provider, permitted
    capabilities, approval policy, context/artifacts, execution node.
  - *Output:* structured events, proposed actions, tool/command activity, patches, artifacts,
    progress, terminal state (completed/failed/cancelled).
  - Don't force harnesses into a shape that loses important semantics.
- **Reference.** DeepSeek Harness: provider-neutral content blocks and `TokenUsage` in
  `packages/llm/llm/src/types.ts`; tool definitions with output schema/timeouts in
  `packages/core/tools/src/index.ts`; string-replace editing (`packages/fs/tool-str-replace-editor`);
  sub-agent providers include in-process, **ACP**, claude-code and codex
  (`packages/subagent/tool-subagent`). Evaluate the Agent Client Protocol as the adapter
  protocol before designing a bespoke one. Its approval outcomes (allowed-once, rejected,
  cancelled, unavailable) fail closed and grant only the requested action
  (`packages/interaction/user-approval`).
- **Permissions.** The adapter classifies every action into noevia's model: read repository,
  edit file, execute command, install dependency, network, delete, git push, open browser,
  external account. Writes and consequential actions go through the existing approval card with
  full arguments. No global "never ask"; no harness inherits local-CLI trust.
- **Workspace isolation.** Research branches/worktrees, dirty trees, locks, subprocess cleanup
  and cancellation per harness (no worktree isolation was found in DeepSeek Harness source).
  Start with the simplest safe rule: **one writer per workspace**, others wait or get their own
  worktree.
- **UI (provisional):** Model · Harness · Prompt preparation · Workspace · Node, as dropdowns
  beside the composer. `Auto` harness picks only from measured model × harness × architect
  evidence and shows the evidence, not a ranking.

### ACP evaluation and contract v0 — 2026-09-17

Read from agentclientprotocol.com (protocol overview, tool calls, agents list).

**What ACP is.** JSON-RPC 2.0 between a *client* (editor/host) and an *agent* running as its
subprocess. Agent methods: `initialize`, `authenticate`, `session/new`, `session/prompt`,
optional `session/load`, `session/set_mode`, `logout`; notification `session/cancel`. Client
methods: `session/request_permission`; optional `fs/read_text_file`, `fs/write_text_file`,
`terminal/create|output|release|wait_for_exit|kill`, `elicitation/create`; notification
`session/update` (message/thought chunks, `tool_call`, `tool_call_update`, plan, commands,
mode). Tool calls carry `toolCallId`, `title`, `kind` (`read`, `edit`, `delete`, `move`,
`search`, `execute`, `think`, `fetch`, `other`), `status` (`pending`, `in_progress`,
`completed`, `failed`), content (blocks, `diff` with `path`/`oldText`/`newText`, `terminal`),
`locations`, `rawInput`/`rawOutput`. Permission options: `allow_once`, `allow_always`,
`reject_once`, `reject_always`; outcome `selected` or `cancelled`. Paths absolute.

**Coverage.** Native: OpenCode, Hermes Agent, Gemini CLI, Goose, Cline, Qwen Code and others.
Adapters: Claude Code (`zed-industries/claude-agent-acp`), Codex CLI
(`agentclientprotocol/codex-acp`). DeepSeek Harness exposes an ACP sub-agent provider. So one
ACP client covers every harness named in D3.

**Recommendation: adopt ACP as the harness adapter protocol**, with noevia (on the execution
node) as the ACP client. Do not design a bespoke protocol. Extend only through `_meta` and
underscore-prefixed methods, never by changing ACP semantics.

**Mapping to noevia (contract v0):**

| ACP | noevia |
|---|---|
| `session/new` + `session/prompt` | job created on the durable-work primitive (§4); prompt = original request (+ execution artifact if prepared, labelled) |
| `session/update` chunks, plan | job events (`step.*`), shown as progress; thoughts are not stored as reasoning text beyond the job view |
| `tool_call` / `tool_call_update` | `tool.started|completed|failed`; `diff` content → patch artifact; `terminal` → command activity |
| `kind` read/search | read repository (no approval) |
| `kind` edit/move | edit file (approval card with the full diff) |
| `kind` delete | delete (approval, always) |
| `kind` fetch | network (approval unless the task's capability set allows the domain) |
| `kind` execute | classified from `rawInput`: install (`npm/pip/cargo … install`), network (`curl`, `wget`, `git fetch/clone`), git push, delete (`rm`), otherwise execute command — each through the approval card |
| `kind` other / think | other → approval; think → no action |
| `session/request_permission` | noevia approval card with full `rawInput`/diff. `allow_once` → Allow once; `reject_once` → Decline; **`allow_always` → Allow for this chat only** (this job's session, same classified action type); `reject_always` → decline for this job. Nothing persists beyond the job; no global "never ask". Card dismissed or job cancelled → `cancelled` |
| `fs/*`, `terminal/*` (client-provided) | offered only inside the job's workspace root; paths confined after `realpath`; denied outside |
| `session/cancel` | job cancellation; subprocess tree killed after grace period |

**Critical limit.** ACP permission is cooperative: an agent subprocess can use its own file and
process access instead of `fs/*`/`terminal/*` and may not ask. Enforcement must therefore be
OS-level on the node: the harness runs as an unprivileged user in a per-job worktree/container
with no credentials mounted, network off unless granted, and git push credentials held by
noevia, not the harness. ACP events are evidence of intent and progress, not the security
boundary.

**Gaps to fill via `_meta`:** token usage and cost per turn; model/provider actually used;
harness version (for evidence identity §1); worktree/branch; terminal exit codes summarised
per step.

**Next steps (when Code is built):** a spike with OpenCode (native) and Claude Code
(adapter) on a throwaway repository in a container, recording every `kind`/permission request
against the mapping above; then contract v1 from what they actually send.

### As built — 2026-09-17 (on `main`, `features.codeHarness`, off, not deployed)

Contract v0 above is implemented as six server modules, each with its own tests, plus the UI.
Nothing here replaces the sandbox: the container, the worktree and the proxy are the boundary,
and ACP events remain evidence of intent.

| Module | What it owns |
|---|---|
| `server/code-actions.cjs` | ACP tool call → noevia action class + whether a human must answer. Pure, no I/O. Unknown `kind`, unreadable command, missing permission option: all fail closed. A compound command takes its worst part (`$(…)`, `sudo`, `FOO=1` prefixes included). A refusal never downgrades to an allow. |
| `server/code-workspace.cjs` | Per-task git worktree on its own branch; one writer per repository+branch (a `stuck` or `interrupted` claim keeps blocking); realpath containment, judging a not-yet-existing path by its nearest existing ancestor. |
| `server/code-egress.cjs` | D15. Per-task token + domain allowlist; the host asked for *and* the resolved address are both checked, and the connection goes to that same address (no rebind); ports 80/443; `Proxy-Authorization` stripped; refusals logged against the task, tokens never logged. |
| `server/code-harness.cjs` | The session. Classify → allow / refuse outright / ask, with full arguments. "Allow for this task" is scoped to the job and one action class, in memory, and is never offered for a delete or a `git push`. Containment re-checked at write time. Job events on the §4 primitive. Workspace released and grant revoked however the task ends. |
| `server/code-acp.cjs` | Hand-written JSON-RPC 2.0 over the agent's stdio — no SDK, as `mcp.cjs` is. Cancellation wired *before* the handshake (an agent that never answers `initialize` has no session to cancel), handshake timeout, SIGTERM to the process group then SIGKILL. The agent inherits no ambient environment; `HOME` is the worktree; `mcpServers: []`. |
| `server/code-service.cjs` + `routes/code.cjs` | Admin-only, 404 unless the flag is on. `CODE_REPOS=name\|/abs/path` is the only way a repository becomes reachable — a task can never name a host path, and the browser learns a name, never a location. One task per project. Approvals in memory: unanswered times out as a refusal, cancelling refuses whatever was waiting, a restart re-asks. |

UI: `src/components/code/` as a project tab, `qa/code-mode.cjs` at 375/768/1440 in both themes.

Added the same day:

| Module | What it owns |
|---|---|
| `services/code-sandbox/` + `code-acp.cjs`'s socket channel | The harness runs in its own container, reached over an internal socket — never as a child of the web process (which holds noevia's state and credentials), and never through the Docker socket (`research-master-container.md`'s highest-severity finding). One noevia line starts a session; everything after is ACP byte for byte. The supervisor constrains `cwd` to its root after realpath, allowlists the environment, and treats the connection as the agent's lifetime. |
| `server/code-meta.cjs` | Token usage, harness name and version, ACP protocol version and per-command exit codes, read defensively from a free-form `_meta` — and, where absent, **named as absent** rather than defaulted. Plus `codingIdentity`: the §1 tuple (harness, version, model, provider, protocol, capability set, prompt preparation, sandbox-or-spawn), so a result is scoped to what changes its meaning. |
| Harness / Prompt-preparation selectors | One harness per deployment reads as a stated fact rather than a one-option dropdown. Prompt preparation offers Direct; Local and Frontier are listed, disabled, each carrying its measured reason, and the server refuses them rather than downgrading silently. **No `Auto`** — §2 permits one only once paired fixtures prove a benefit. |

### Contract v1 — run against real OpenCode, 2026-09-17

Driven through noevia's own modules, unmodified, in the sandbox container against the engine
(Qwen3.5-4B-Q5_K_M, the `scratch` fixture). Driver and evidence:
`experiments/acp-spike/contract-v1.mjs`, `contract-v1-opencode-2026-09-17.json`.

**The mapping holds.** The agent identified itself (`OpenCode` 1.18.31, protocol 1). Its three
tool calls classified correctly — two `read` (no approval) and one `edit`, which stopped at the
approval card carrying the real absolute path, a diff, and `filepath`/`diff` arguments. Nothing
reached outside the workspace; `test.js` was untouched, as the task required.

**Four things only a real run could tell us**, all now fixed:

| Found | Consequence | Fix |
|---|---|---|
| git refuses to read a repository owned by another user ("dubious ownership"), and that check ignores `-c safe.directory` and `GIT_CONFIG_*` by design | `release()`'s fetch failed, so **every task's work was stranded in its clone** | hand the clone back to noevia's uid before fetching |
| OpenCode reports nothing on the prompt result's `_meta` | token usage always absent | read the stream |
| its `usage_update` carries `{used, size, cost}` — **context occupancy, not tokens spent** | reporting `used` as input tokens would have been a plausible-looking lie | `readContext` records it as its own measurement; the token-usage limitation stands |
| streaming text arrives in many chunks (548 thought, 50 message, in one run) | `turns: 50` overstated the work | counted and named as `messageChunks` |

Also confirmed: OpenCode is configured by `opencode.json` in its working directory — ACP carries
nothing that pins permissions, so the adapter must write that file, and `_meta` cannot substitute.
It did **not** use the client's `fs/write_text_file` even with `edit: ask` pinned; it asked, then
wrote in its own process. The sandbox is what contains that, exactly as §3 says.

### Contract v1, second pass — the whole loop works, 2026-09-18

The first pass's "the 4B could not fix it" reading was **wrong**, and the reason is the most
important finding of the exercise: **noevia's approvals never reached the harness.**

ACP nests the permission outcome — `{ outcome: { outcome: 'selected', optionId } }`. noevia sent
the inner object, and OpenCode read that as `The user rejected permission to use this specific
tool call`. So every approval became a refusal: the card appeared, the human said yes, the agent
was told no. Fail-safe, invisible to every unit test (the fake agent had been written to match the
same wrong assumption), and it made Code mode incapable of doing anything at all. Three more
defects followed from actually watching a real run:

| Found | Consequence | Fix |
|---|---|---|
| ACP nests the permission outcome | **every approval read as a refusal** | wrap it in the transport; the fake agent now reads it the way OpenCode does |
| harnesses edit and do not commit | uncommitted work was deleted with the clone | noevia commits what is left, in its own name, clearly labelled |
| `HOME` pointed into the workspace | OpenCode's cache, sqlite database and a nested git repo were committed onto the task branch | a state directory beside the workspace, plus `info/exclude` for harnesses that write into cwd anyway |
| the shared state parent was created 0700 root-owned | the agent died with `EACCES` before doing anything, and `mkdir` will not fix an existing directory's mode | create it traversable and `chmod` it every claim, so an older volume self-heals |

**Verified outcome** (`contract-v1-opencode-9b-solved-2026-09-18.json`): Ornith-1.5-9B, 46 s, two
approvals (edit then execute), the edit carried out through noevia's own `fs/write_text_file`,
**only `median.js` changed**, and the repository's own test prints `ok` on the task branch. Both
deliberate bugs fixed correctly — a copied array, a numeric comparator, and the mean of the middle
two.

So: the contract holds, the containment holds, the work comes back, and a 9B on this hardware can
do a real if small coding task in under a minute.

**Not yet done from this section.** An `Auto` harness waits on evidence that does not exist, and
Claude Code and Codex have still never been run.

### Through the product, on the live deployment — 2026-09-21

The adapter now owns the harness's configuration file (`server/code-harness-config.cjs`): the
permission gate, one model endpoint, no self-update, no sharing — written into the task's own
working directory before the agent exists, and handed to the user the harness runs as. A harness
whose configuration noevia cannot pin is refused rather than run with its own defaults, and so is
a deployment with no model or no endpoint.

That closed the gap the spike left, and a task then ran end to end through `code-service.cjs`
itself, not the spike driver: OpenCode 1.18.31 in the deployed sandbox, Qwen3.5-4B on the live
engine, the operator's registered `scratch` repository. Four approvals (edit, command, edit,
command), only `median.js` changed, the branch fetched back, and `node test.js` printing `ok` on
it. `commands: 0` and no exit codes, as before: the harness runs commands in its own process, and
the record says so rather than guessing.

One more defect only a real deployment could show: on a shared volume the registered repository
is owned by the harness user, and git refuses to read a repository owned by someone else — which
noevia reported as "Not a git repository". It now names exactly the repositories the operator
registered in a trust file of its own (work tree and git directory both), and reports what git
actually said for anything else.

---

## 4. Durable work

One small primitive before Cowork, Code, Deep Research, browser tasks and scheduled jobs each
build their own. Smallest thing that serves a real planned use case; no distributed scheduler.

**Today.** Source jobs in memory (`server/source-jobs.cjs`); Diary jobs persisted per day
(`server/diary-jobs.cjs`); calibration persisted; approvals in memory
(`pendingApprovals`, `chatWideApprovals` in `index.cjs`).

- **Shape:** job → steps → events → approvals → artifacts → checkpoints → terminal state.
  Owned by tenant and project; records mode, node, harness and architect mode where relevant;
  bounded progress; cancellation; survives navigation and restart; one completion owner.
- **Append-only events, derived state.** Candidate types: `job.created`,
  `prompt_architect.started|completed`, `step.started|completed`, `capability.requested`,
  `approval.requested|decided`, `tool.started|completed|uncertain`, `artifact.created`,
  `checkpoint.created`, `job.completed|failed|cancelled`. References: DeepSeek
  `packages/core/session/src/known-event-types.ts` (refuses unknown types unless ignorable) and
  JSONL persistence; Row-Bot `src/row_bot/agent_runs.py` (SQLite runs + events, statuses incl.
  `waiting_approval`, `interrupted`). Don't copy either mechanically.
- **Restart recovery.** Row-Bot clears locks, keeps `waiting_approval` runs that can resume,
  marks the rest interrupted (`recover_stale_agent_runs`). Adopt the idea; approvals that
  outlive a restart must be re-asked unless durably and explicitly resumable.
- **External side effects.** Never promise exactly-once. Distinguish idempotent internal
  transitions, retryable reads, known-completed writes, and **uncertain** effects
  (`outcome_unknown` → needs reconciliation, never auto-retry). Example: a browser loses
  connection after "Submit".
- **Workers (defer building).** A worker's capability set is fixed at creation and is a subset
  of its parent's; it cannot widen itself and must hand back to the parent. References: Row-Bot
  `agent_runner.py::_filter_child_tools` (child ⊆ parent, delegation denied by default);
  DeepSeek `toolFilter` allow/deny (whether a child can widen: not verified in source).

### Built 2026-09-17 — `apps/web/server/jobs.cjs`

Append-only JSONL per job under the tenant's `jobs/` directory (0600), a fixed event-type
allowlist (`job.created|started|completed|failed|cancelled|interrupted`, `step.*`, `progress`,
`approval.requested|decided`, `tool.started|completed|uncertain`, `artifact.created`,
`checkpoint.created`), state derived from events, no events accepted after a terminal state,
`run(id, work)` with progress/checkpoint/artifact/uncertain helpers and an abort signal,
`cancel`, `recover()` (unfinished → `interrupted`; waiting approvals are never resumed;
uncertain effects stay listed), capabilities fixed at creation with child ⊆ parent enforced,
and pruning of finished jobs by age/count. First consumer: background source processing
(`source-jobs.cjs`), whose polls now report a restart as interrupted instead of a missing job.
Deep research and Cowork build on it next.

---

## 5. ExecutionNode

Where work runs. The server orchestrates and holds durable state; nodes perform bounded local
actions.

- Nodes: DaServer, a future noevia Mac app, later Windows/Linux machines.
- Each advertises explicit capabilities: terminal, filesystem, git, browser, notifications,
  desktop automation, local model runtime, hardware acceleration. None assumed.
- Pairing and authorization are explicit; no ambient access to a client machine; capabilities
  can be revoked; every action is attributed to a node in the job record.
- **Mac app:** both a native client and an optional trusted execution node (local files,
  terminal, repositories, browser, notifications). Jan.ai may inform the client, not the
  architecture or dependencies. Installing it never implies unrestricted control of the Mac.
- **Idea — computer use (reference: trycua/cua `8cb8f6d`, MIT).** Suggestions to explore, not
  decisions. The most complete open computer-use stack; if pursued, take parts, not the platform (it is coupling toward a hosted/billing product).
  - *Sandboxed desktops:* a guest-side FastAPI computer server exposes named commands (click,
    type, scroll, screenshot) over `POST /cmd` / `WS /ws`, PTY endpoints and Playwright exec
    (`libs/python/computer-server/computer_server/main.py`). Runtimes: Lume VMs on Apple Silicon
    (`libs/lume`, Swift, Virtualization framework), Docker/QEMU/XFCE/Kasm Linux desktops
    (`libs/python/cua-sandbox`). A Linux desktop sandbox could run on DaServer; macOS VMs need
    the Mac node. A VM boundary looks like the safer shape for Cowork computer use, if built.
  - *Host driver:* `libs/cua-driver` (Rust, MCP over stdio) controls apps on the real desktop
    with **no VM boundary** — the highest-trust capability a node can offer. Its `bounded` mode
    (reviewed tool manifest) and embedder-supplied `DriverAuthorizationHost` would let noevia's
    approval gate own every decision (README claim, not verified in the Rust source).
  - *Agent loop:* `libs/python/agent` routes providers through LiteLLM with per-model loops; no
    approve-before-act hook was found (callbacks only), so noevia's gate must wrap it, as with
    Browser Use.
  - *Telemetry on by default* (PostHog; `CUA_TELEMETRY_ENABLED=false`, plus separate Lume,
    driver and cuabot telemetry) — must be off in any evaluation.
- **Idea — local runtime on the Mac node (reference: leonickson1/Swiftlet `909c042`, Apache-2.0).** A
  Swift/Metal MoE runtime that streams experts from SSD (Qwen3.5/3.6/Next families) with a
  loopback-only OpenAI-compatible server (`Sources/SwiftletServer/main.swift`) and an embeddable
  `SwiftletCore` library. No tools, MCP or permissions. Candidate for the node's optional
  `local model runtime` capability; Metal-only, irrelevant to DaServer. README numbers
  (e.g. 35B 4-bit in ~2.6 GB on M5) are unverified.


### Pairing and capability design — 2026-09-17 (not built)

**Pairing.** An admin (or the user, for their own device) creates a one-time pairing code in
Settings (10 minutes, single use). The node app generates an Ed25519 key pair locally, shows
the key fingerprint, and sends `{code, nodeName, publicKey, platform, appVersion}` to
`POST /api/nodes/pair`. The server stores the public key against the user (tenant-owned node);
the user confirms the fingerprint in noevia. No shared secrets travel after pairing: the node
opens an outbound WebSocket to the server and authenticates each connection by signing a
server nonce. Revocation deletes the key and drops the connection.

**Capability manifest** (sent on connect, never trusted beyond what the user granted):

```json
{ "node": "mac-studio", "appVersion": "0.1.0",
  "offers": [{ "capability": "filesystem.read", "roots": ["~/Projects"] },
             { "capability": "terminal", "shell": "zsh" },
             { "capability": "browser", "engine": "chromium", "profiles": ["task-isolated"] },
             { "capability": "local_model_runtime", "endpoint": "loopback" }] }
```

The user grants a subset per node (and per root). The server intersects offer × grant × job
capability set (§4) for every request; a node refusing or lacking a capability fails closed.

**Action flow.** Job step → server builds a signed action request `{jobId, actionId, capability,
arguments, approvalId?}` → node verifies the server signature, checks the grant locally, runs it,
and streams `started / output / completed | failed | uncertain` back → events appended to the job.
Consequential actions (writes outside a task workspace, sending, deleting, network egress beyond
the job's domains, desktop automation) require an approval id issued by noevia's approval card
before the node will execute them; the node re-checks that the approval matches the exact
arguments hash.

**Node safety defaults.** Task workspaces under a node-owned directory; no credential stores
exposed; desktop automation and host-driver control off until separately granted with a
visible indicator while active; every action attributed to node and job; local audit log on
the node mirrored to the job.

**Tests before shipping:** pairing code expiry/reuse, fingerprint mismatch, replayed nonce,
revoked key, capability not granted, argument-hash mismatch on approved action, uncertain
completion after disconnect.

---

### Offline Diary on the Mac node (D22, 2026-09-18)

A requirement from the user, for when the Mac app is built — not before. It replaces the retired
idea of keeping the Diary as plain files on a Mac share.

**What it must do.** Pull the latest Diary from the server; keep working with no connection at
all — reading, writing, and talking to a *local* model with local tools and MCP servers; sync
back when the connection returns. The server stays the source of truth.

**What already exists to build it on.** The Diary's writes are journaled and idempotent by request
id (a replayed append never duplicates — D10), managed storage already keeps an outbox of pending
writes, and chat transcripts already use revisioned saves with a 409 and a client-side merge for
two devices writing one chat. An offline replica is the same problem with a longer gap.

**What is genuinely hard, and needs designing rather than assuming:**

- **Conflicts.** The server and the Mac can both change the same day while apart. Appends merge
  cleanly by request id; *edits* to the same entry do not. Decide per kind of change, and never
  resolve a conflict by silently discarding either side.
- **Authorization while offline.** The app must work without asking the server whether it may,
  so it holds a credential for the Diary on the device. That credential needs to be revocable the
  moment the Mac is lost, and the local copy encrypted at rest (FileVault is not enough on its own
  for a shared machine).
- **The local model.** A small model on the Mac, not the server's; the approval gate, "untrusted
  data, never instructions" and the Diary's rule that its structure is written by code apply
  exactly as they do on the server. No component inherits more trust for running locally.
- **Tenant isolation.** A replica holds one user's Diary and nothing else.

## 6. BrowserExecutor

A future Cowork capability, preferably on an execution node. Not wired into Chat.

- Noevia-owned interface; implementations could be Browser Use, direct Playwright/CDP, or an
  extension. Browser Use is a candidate, not the API.
- **Security model**
  - Isolated browser profiles per task or per user choice.
  - Domain allowlist/denylist and IP blocking. Reference: Browser Use
    `browser/watchdogs/security_watchdog.py`, `BrowserProfile.allowed_domains`.
  - **Secrets never enter model context:** placeholders substituted at execution time and only
    for matching domains. Reference: `tools/registry/service.py _replace_sensitive_data`; tests
    `tests/ci/security/test_sensitive_data.py`. Authenticated profiles navigate while cookies
    and passwords stay outside the model.
  - Downloads untrusted, into a per-task directory; uploads restricted to explicitly provided
    files. Reference: `upload_file` containment, `test_upload_file_containment.py`.
  - Current origin always visible; navigation/action audit; screenshots or state evidence
    where useful; cancellation.
- **Consequential actions** — submit forms, send messages, purchase, delete cloud data, change
  settings, publish, push via web UI — go through noevia's approval card. Browser Use has step
  hooks and pause/stop but **no approval gate** (none found in `agent/service.py`), so noevia's
  gate must wrap the executor.
- **Durable:** long workflows run as jobs (steps → approvals → artifacts → checkpoints →
  completion or reconciliation), never one giant synchronous tool call.
- **Evaluation notes:** Python ≥3.11, direct CDP (`cdp-use`), heavy pinned dependencies,
  PostHog telemetry (`browser_use/telemetry/`) must be disabled, needs a local Chrome. Suited
  to a desktop node; not for the web container.


### Executor interface — 2026-09-17 (not built)

Runs as a node capability (`browser`), inside a job:

```ts
interface BrowserExecutor {
  open(task: { jobId: string; profile: 'isolated' | { named: string }; allowedDomains: string[]; downloadsDir: string }): Promise<SessionId>;
  act(session: SessionId, action: BrowserAction): Promise<ActionResult>; // navigate, click, type, select, upload, extract, screenshot
  close(session: SessionId): Promise<void>;
}
type ActionResult = { status: 'done' | 'blocked' | 'needs_approval' | 'uncertain'; origin: string; evidence?: { screenshot?: string; text?: string } };
```

**Consequence classifier (deterministic, before every act):** `needs_approval` when the action
submits a form (click on `type=submit`, Enter in a form, `form.submit`), targets elements whose
accessible name or text matches send/pay/buy/order/delete/remove/publish/post/confirm/save
settings (localised lists), uploads a file, or navigates cross-origin with POST. Model output can
request an action but never mark it safe. The approval card shows origin, element description,
typed values with secrets masked and a screenshot.

**Secrets:** the model sees `{{secret:name}}`; the executor substitutes only when the current
origin matches the secret's domain list, and never returns substituted values in evidence.

**Uncertain outcomes:** a connection loss or timeout after a submit/pay action records
`tool.uncertain` on the job; the step is not retried and the user is asked to check.

**Policy module built — 2026-09-22.** `apps/web/server/browser-policy.cjs` implements the
consequence classifier, navigation check and secret handling above as pure functions with tests
(`browser-policy.test.cjs`): http(s) only, allowlisted hosts and their subdomains, no local or
private addresses or embedded credentials; submits (explicit, default form buttons, Enter in a
form), uploads, POST navigation and consequential labels (en/de/fr/es, whole words,
accent-insensitive) need approval; reads, typing and selecting do not; unknown actions ask.
`{{secret:name}}` is substituted only on the secret's domains; evidence is masked. Not wired to
anything: no executor, route or flag yet.

**Implementation choice:** start with direct Playwright/CDP on the node for the classifier and
audit control; evaluate Browser Use behind the same interface only with its telemetry disabled
and its agent loop wrapped by this classifier.

---

## 7. Evidence summary

| Idea | Reference | Decision |
|---|---|---|
| Config-scoped qualification | noevia fingerprints (`chat-context.cjs`) | Adapt |
| Prompt Architect | none upstream (new) | Research + benchmark; Direct default |
| Harness adapter / ACP | DeepSeek `tool-subagent`, `llm/types.ts` | Research/spec |
| Fail-closed approval outcomes | DeepSeek `user-approval` | Adopt semantics |
| Worktree isolation | not found upstream | Research; single writer first |
| Append-only job events | DeepSeek session; Row-Bot `agent_runs.py` | Research/spec |
| Uncertain outcome state | DeepSeek `repair.ts` | Adopt |
| Worker scope ⊆ parent | Row-Bot `_filter_child_tools` | Defer build; adopt rule |
| Secrets outside model context | Browser Use registry | Adopt pattern |
| Domain/upload/download containment | Browser Use watchdogs | Adopt pattern |
| Browser Use itself | — | Evaluate later on a node |
| Sandboxed computer use (VM guest command server) | cua `computer-server`, `cua-sandbox`, `libs/lume` | Idea to explore with R7 |
| Host desktop driver with bounded manifest + embedder authorization | cua `libs/cua-driver` | Idea, later if ever; highest-trust capability |
| SSD expert-streaming MoE runtime on the Mac | Swiftlet | Idea for the Mac node |
| SSD expert streaming on DaServer | danveloper/flash-moe (`3601d41`) | Reject as software: Metal-only, no license, one model, stale. Idea only — see roadmap research 9 |

### Other harnesses: pinned configuration — 2026-09-22

`server/code-harness-config.cjs` `pinFilesFor` now pins **Claude Code** and **pi** as well as
OpenCode, and refuses **Codex** on measured evidence (below); any other name is still refused (409) before an agent starts. Files are written
by noevia into the task's working directory or its private `HOME`, owned by the harness user,
mode 0600, and listed in the `harness.config` step. Sources were checked on 2026-09-22 (links in
the module header).

| Harness | Files | Gate | Endpoint | Off |
|---|---|---|---|---|
| Claude Code | `./.claude/settings.local.json` + `~/.claude/settings.json`; the complete pin is also sent inline through `session/new` and SDK filesystem setting sources are empty | fixed core tool set; `ask`: Edit, Write, NotebookEdit, Bash, WebFetch, WebSearch; bypass/auto modes and sandboxed-Bash auto-allow disabled; hooks, skills/commands, plugin sync, connectors and filesystem MCP configuration excluded | `env`: `ANTHROPIC_BASE_URL` (engine root; llama.cpp `/v1/messages`), `ANTHROPIC_MODEL` | automatic and manual self-update, non-essential traffic, telemetry |
| Codex | — refused (409) | see "Codex, measured" | — | — |
| Qwen Code | `./.qwen/settings.json` (outranks user) + `~/.qwen/settings.json` | `tools.approvalMode: "default"` — its default is now `auto` (an LLM classifier approves unasked) | `modelProviders.openai` → engine, key via the file's own `env` | auto-update, usage statistics |
| DeepSeek Harness | `~/.dsh/profiles/acp/{cordis.patch.yml,noevia-gate.mjs}` | inserted `tools/pre-execute` gate: every tool but plain reads returns `ask`, through dsh's fail-closed seam; approval `ask` and sandbox `workspace-write` pinned rather than read from env | one `llm-pi-ai` route → engine, key as a header | OTel upload, DeepSeek session log, web search, DeepSeek route/account, plugin manager, config editors, repository instructions and skills |
| pi | `~/.pi/agent/{models.json,settings.json,extensions/noevia-gate.js}` | the one explicit extension: every non-read tool asks with full input and a five-minute fail-closed timeout; no UI channel, an error or anything but `true` blocks | provider `noevia`, `openai-completions` | startup network, repository context files, discovered extensions/skills/templates/themes, project trust, session persistence, install telemetry |

**Deployment status.** pi 0.87.0 is live by the user's explicit approval (release `6300572`);
the hardening described here is local source work until a later deployment. Claude Code, Qwen
Code and DeepSeek Harness remain selectable pins, not installed live. Codex is refused rather than offered. Installing
another pinned CLI and adapter in the one container allowed to run commands still needs the user's
go. pi's approvals are bridged by
noevia's own `services/code-sandbox/pi-acp-bridge.cjs` (community `pi-acp` does not document
forwarding pi's dialogs): the gate's confirm carries the real tool and full input, becomes an ACP
`session/request_permission` that noevia classifies like any harness call, and only an explicit
"Allow once" confirms; other dialogs, malformed payloads, timeouts, errors and a closed client
refuse. The bridge launches only this managed extension, refuses project resources, runs offline
without persistent sessions and waits for pi's whole-turn `agent_settled` event rather than the
earlier per-run `agent_end`. Tested
end to end through noevia's ACP client against a fake `pi --mode rpc`, and against **real pi 0.87.0**
(`@earendil-works/pi-coding-agent`, `qa/pi-bridge-e2e.cjs`, scripted local fake model): pi loaded
noevia's pinned provider and gate from the task HOME, its bash call arrived as a normal permission
request with the full command, Allow once ran it and Decline blocked it. Claude Code needs
llama.cpp's Anthropic Messages endpoint; its compatibility with the live engine remains unverified.
Codex's read-only commands inside its own sandbox can run without asking, so the container
would be its real boundary rather than D14's per-action approval and noevia refuses it. Claude Code
also needs the user's own sign-in if it is ever
pointed anywhere but the local engine. No `Auto` harness until paired evidence exists.

**Real-harness checks, 2026-09-22** (opt-in suites with scripted local fake models; no real model):
- **pi 0.87.0** via `pi-acp-bridge.cjs` (`qa/pi-bridge-e2e.cjs`): pinned provider and gate loaded
  from the task HOME; bash arrived as a normal card; Allow once ran it, Decline blocked it.
- **Claude Code** via `@agentclientprotocol/claude-agent-acp` 0.79.0 (`qa/claude-code-e2e.cjs`):
  with only `PATH` and the private `HOME` passed, requests went solely to the pinned endpoint;
  Bash arrived as a card (options allow once / reject once); Allow ran it, Decline blocked it; a
  repository shipping its own `.claude/settings.json` with `bypassPermissions` and `allow: Bash`
  still asked. It also asked without noevia's pin in that run, so the adapter itself refuses
  bypass. The default fake-agent suite now also verifies that noevia sends the full pin inline,
  disables the adapter's filesystem setting sources, uses strict empty MCP configuration and opts
  out of dangerous permission skipping. The opt-in real-adapter suite now also checks a hostile
  startup hook and `.mcp.json`; that extension has not been rerun because the CLI is deliberately
  not installed in this sandbox.
- **Codex, measured → refused.** `@agentclientprotocol/codex-acp` 1.12.0 (Codex 0.155) with the
  config noevia would pin (`approval_policy = "on-request"`, `sandbox_mode = "read-only"`,
  provider `noevia` with `wire_api = "responses"`, `web_search = "disabled"`, update check,
  analytics, feedback and OTel off, project `untrusted`): the provider and tool settings were
  honoured, but the adapter starts in its own `agent` mode and a plain `echo > proof.txt` ran
  **without an approval**. With `INITIAL_AGENT_MODE=read-only` an escalated command asked
  correctly and Decline blocked it, yet the plain write still ran unasked — reproduced outside the agent's own shell sandbox, so it
  is not a nested-sandbox artefact. Codex's gate is its OS
  sandbox, and commands inside it never ask, which D14 does not allow. Revisit if Codex gains an
  "ask for every command" policy.
- **Qwen Code 0.24.3** in `--acp` mode (`qa/qwen-code-e2e.cjs`): requests only to the pinned
  endpoint; `run_shell_command` arrived as a card with the full command; Allow once ran it,
  Decline blocked it; a repository's own `.qwen/settings.json` with `approvalMode: "yolo"` is
  overwritten by noevia's pin and the call still asked. `.qwen/` and `.pi/` are now in
  `HARNESS_LEAVINGS`, so pinned files are never committed onto a task branch.
- **DeepSeek Harness (`@deepseek-ai/dsh` 0.1.7-alpha.2)** in `dsh --profile acp` mode
  (`qa/deepseek-e2e.cjs`, 2026-09-23), driven through noevia's own code harness:
  - **Shipped defaults, measured → not acceptable as-is.** Its approval seam is fail-closed, but the
    shipped profile consults it only for sandbox *escalations*: a plain `echo > proof.txt` ran in
    its `workspace-write` sandbox without asking, and a Decline answer never came into play (the
    Codex shape). The shipped profile also uploads session logs over OTel to DeepSeek
    (`FEEDBACK_ONLY` by default) and keeps a separate DeepSeek session-log path.
  - **Pinned.** `~/.dsh/profiles/acp/cordis.patch.yml` (the task's private HOME) plus a noevia gate
    plugin inserted beside it: a `tools/pre-execute` handler, prepended, that returns `ask` for
    every tool except `read`, `read_image`, `glob`, `grep`, `todo_write` and `get_goal`. `ask` goes
    through the harness's fail-closed seam to `session/request_permission`. The patch also fixes
    approval to `ask` and the sandbox to `workspace-write` (the shipped values read env vars), gives
    one `llm-pi-ai` route to the engine (key as an `Authorization` header, no env var), and
    disables OTel, the DeepSeek session log, web search, the direct DeepSeek route and account,
    the plugin manager, the settings/config editors, repository instruction files and filesystem skills.
  - **Its permission request names only `toolCallId`** (an ACP ToolCallUpdate); the command is in
    the earlier `tool_call`. noevia now merges the two by id (the request's own fields win), so
    the card shows the real command. This applies to any harness that does the same.
  - **Result:** requests went only to the pinned endpoint with the pinned key. Bash arrived as a
    card with its full command; Allow once ran it; Decline blocked it. A repository shipping its
    own `AGENTS.md`, a `.dsh` skill and a `.dsh` profile patch (`approval: never`,
    `danger-full-access`) changed nothing, and neither text reached the model. A control run
    without the disables showed both reaching it.
  - **Limitation:** dsh starts subagents with approval prompts off, so under the gate a subagent's
    non-read tool is refused outright (no card, nothing runs). Starting a subagent asks. In
    practice subagents are read-only.
  - Selectable as `CODE_HARNESS_NAME=deepseek`; not installed in the sandbox image. Installing it
    is the user's call, as with Claude Code and Qwen Code.
