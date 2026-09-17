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
Row-Bot `e5803e3`, DeepSeek Harness `0d1f500`, Browser Use `d8110c5`, Impeccable `f2c7051`.
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
- **Computer use (reference: trycua/cua `8cb8f6d`, MIT).** The most complete open computer-use
  stack; evaluate parts, not the platform (it is coupling toward a hosted/billing product).
  - *Sandboxed desktops:* a guest-side FastAPI computer server exposes named commands (click,
    type, scroll, screenshot) over `POST /cmd` / `WS /ws`, PTY endpoints and Playwright exec
    (`libs/python/computer-server/computer_server/main.py`). Runtimes: Lume VMs on Apple Silicon
    (`libs/lume`, Swift, Virtualization framework), Docker/QEMU/XFCE/Kasm Linux desktops
    (`libs/python/cua-sandbox`). A Linux desktop sandbox could run on DaServer; macOS VMs need
    the Mac node. A VM boundary is the preferred shape for Cowork computer use.
  - *Host driver:* `libs/cua-driver` (Rust, MCP over stdio) controls apps on the real desktop
    with **no VM boundary** — the highest-trust capability a node can offer. Its `bounded` mode
    (reviewed tool manifest) and embedder-supplied `DriverAuthorizationHost` would let noevia's
    approval gate own every decision (README claim, not verified in the Rust source).
  - *Agent loop:* `libs/python/agent` routes providers through LiteLLM with per-model loops; no
    approve-before-act hook was found (callbacks only), so noevia's gate must wrap it, as with
    Browser Use.
  - *Telemetry on by default* (PostHog; `CUA_TELEMETRY_ENABLED=false`, plus separate Lume,
    driver and cuabot telemetry) — must be off in any evaluation.
- **Local runtime on the Mac node (reference: leonickson1/Swiftlet `909c042`, Apache-2.0).** A
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
| Sandboxed computer use (VM guest command server) | cua `computer-server`, `cua-sandbox`, `libs/lume` | Research with R7; VM boundary preferred |
| Host desktop driver with bounded manifest + embedder authorization | cua `libs/cua-driver` | Research later; highest-trust capability |
| SSD expert-streaming MoE runtime on the Mac | Swiftlet | Defer to the Mac node |
| SSD expert streaming on DaServer | danveloper/flash-moe (`3601d41`) | Reject as software: Metal-only, no license, one model, stale. Idea only — see roadmap research 9 |
