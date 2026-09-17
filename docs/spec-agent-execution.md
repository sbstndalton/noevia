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

---

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
