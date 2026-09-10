# noevia: setup, thinking modes, and diary zero-state

Status: **plan only — nothing here is implemented.** Written 2026-09-09, against
`8a78172`. Companion to the reasoning-effort spec (now the appendix below), which Workstream 2
implements (with one of its open questions answered the other way — see 5b).

## Context

A batch of ideas landed at once: agent-driven auto-deploy, low/medium/high thinking
modes, a Nextcloud-style first-run setup, a diary toggle asked early, a diary landing
page that starts empty, and "the UI is still a little crude."

Reading the code first changes the shape of the work considerably. Three of the six
asks are **already built** and need refinement rather than construction:

| Ask | Reality |
| --- | --- |
| MD file an AI reads to auto-deploy | `DEPLOY.md` (agent-executable playbook, `STOP AND ASK THE HUMAN` markers) + `cowork.setup.json` (~35 declarative env vars, preconditions, health checks) already exist. |
| Thinking modes | the reasoning-effort spec (appendix below) is complete — explicitly "spec only, no implementation", with three open questions now answered. |
| First-run setup wizard | `apps/web/src/components/SetupWizard.tsx` is a 6-step, one-question-at-a-time flow with explicit skips, resumable mid-setup. |
| Diary as an early toggle | Exists — but as a checkbox at the *bottom* of the account form, not a question. |
| Diary zero-state landing | Real gap. Landing always renders the same hero + composer + month grid. |
| Landing entry → current day | Real gap. Submitting from `scope: 'home'` writes to today but leaves you on the landing page. |

So the work is: **one small honesty fix to the agent contract, one spec to implement,
one wizard to restructure, and one genuinely new diary zero-state.**

Decisions taken (from the clarifying round):
- Thinking modes: **global default + per-project override**.
- Diary: **scaffold `Entries/`, `AI Memory/`, `Raw Sources/` on first entry, and surface all three**.
- Setup: **restructure and fill the real gaps** (not a full schema-driven rebuild).

---

## Workstream 1 — Agent-readable deploy contract (small)

The manifest exists; nothing points an agent at it. `cowork.setup.json` and
`DEPLOY.md` are only discoverable if you already know they're there, and there is
**no `CLAUDE.md` or `AGENTS.md` anywhere in the repo**.

- Add a root `CLAUDE.md` (symlink or short mirror at `AGENTS.md`) that does three
  things and nothing else: names `DEPLOY.md` as authoritative for deployment,
  `cowork.setup.json` as its declarative companion, and records the
  **`cowork`-identifiers-are-intentional** rule so no agent "helpfully" renames env
  vars, images, or the `cowork_session` cookie.
- Add the live-deploy reality that no repo doc currently states: the Unraid Compose
  Manager copy at
  `/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml` is a
  *separate file* from the repo's `compose.yaml`, and the tarball-ship + `current`
  symlink release flow is how new commits reach the server (there are no GitHub
  credentials on daserver). `DEPLOY.md` currently describes a fresh single-host
  `docker compose up` that does not match production.
- Extend `cowork.setup.json` `post_deploy_human_steps[]` with the wizard's new first
  question (diary on/off) so the manifest and the wizard stay in step.

Files: new `CLAUDE.md`, `AGENTS.md`; edit `DEPLOY.md`, `cowork.setup.json`.

---

## Workstream 2 — Thinking modes (implement the parked spec)

Follow the appendix spec verbatim except for the scope decision, which
is now **global default + per-project override**. Keep the spec's two load-bearing
safety properties — they are the reason it was parked, not incidental:

1. **Three states: `default` / `low` / `high`.** No `medium` — it equals `default` on
   every backend in the table, and a knob that does nothing anywhere is worse than no
   knob. (This contradicts the literal "low medium high" ask; the honest version is
   `default` in the middle slot.)
2. **Never send a parameter the backend wasn't verified to accept.** A local Lemonade
   server that 400s on an unknown field would break all chat for a project.

Implementation:
- **Schema**: `settings.reasoning_effort_default` (server-wide, admin-set) +
  optional `reasoningEffort` on each project in `projects.json`. Absent = inherit;
  older files stay valid. Resolution order: project → global → `default`.
- **Server** (`apps/web/server/index.cjs`, near the chat body build at ~1693-1723,
  where `chat_template_kwargs.enable_thinking` is already handled — reuse that seam):
  apply the resolved effort to the outgoing body only for a provider marked verified.
  On a 4xx mentioning the field, retry once without it, mark that provider base URL
  `unverified` for the process lifetime, and fall back to the prompt hint.
- **Fallback hints** (spec §5, verbatim): `low` → "Answer directly and concisely;
  skip step-by-step reasoning."  `high` → "Think through this step by step before
  answering."
- **SSE**: emit `meta.reasoning` = `real | hint | off` so the UI can label the mode
  honestly rather than implying a parameter was sent.
- **UI**: a three-way selector in Settings → Models & routing (global) and in
  `EditProjectModal.tsx` (override, with an "Inherit" state); a small badge in the
  chat header whenever the resolved mode isn't `default`, styled to distinguish
  `real` from `hint`.
- **`high` raises `max_tokens` on the local/hint path** — see Workstream 5b. This
  deliberately reverses the spec's open question (c). On a local endpoint that
  ignores `reasoning_effort`, lifting the output ceiling is the only lever that does
  anything real, and unattended long thinking is the thing local models are
  genuinely good at.
- **Out of scope, per spec**: Anthropic `thinking.budget_tokens` wire format,
  per-message toggles, and any change to the diary pipeline (it runs on the aux model
  with its own prompts — deliberately unaffected).

Files: `apps/web/server/index.cjs`, `apps/web/src/components/ModelPopup.tsx` or
`SettingsView.tsx`, `EditProjectModal.tsx`, `ChatView.tsx`, `types.ts`, `api.ts`.

---

## Workstream 3 — Setup wizard restructure

Current order: `account → provider → diary → models → prefs → passkey`.
Proposed: `welcome → diary → account → provider → storage → prefs → passkey → done`.

Concrete changes to `SetupWizard.tsx`:

1. **Diary becomes its own question, before the account form.** Two large cards
   ("Yes, I want a diary" / "Chat only") rather than a checkbox buried under the
   password field. The answer is carried into `completeSetup({ diaryEnabled })`
   unchanged — no server change needed.
2. **Delete the `models` step.** It is currently a wall of text telling the user to
   edit `.env` and restart, with a single Continue button — a dead end that teaches
   the user the wizard can't be trusted to do anything. Replace it with a live probe:
   if `MODEL_MANAGER_KIND` is set, show the detected manager and its model count; if
   not, one sentence and move on. Fold the result into the provider step.
3. **Expand `prefs` past theme + auto-routing.** Add, as real questions:
   - Thinking-mode global default (Workstream 2) — the natural home for it.
   - `insights_badge`, which today is silently defaulted to `0` in `user_features`
     and **never asked anywhere**, in the wizard or Settings.
   - Display name / timezone confirmation (the diary stamps local dates; getting this
     wrong misfiles entries).
4. **Fix the invited-user hole.** `acceptInvite` in `auth.cjs` defaults `onboarded` to
   `1`, so anyone joining by invite **never sees the wizard at all** — no diary
   question, no provider, no prefs. Set `onboarded = 0` for invitees and give the
   wizard a `mode: 'invited'` that skips the setup-code/origin/admin-only steps.
5. **Audit `markOnboarded` (`auth.cjs:490`)**: its insert branch writes
   `diary_enabled = 0`, which can silently undo the wizard's answer on a race. The
   conflict branch preserves it; make both preserve it.
6. **"Assume nothing" pass.** Every step keeps its explicit skip (already true), but
   no step may apply a value the user didn't see. Today `theme` is seeded from
   `localStorage` before it is asked — show what was detected rather than silently
   adopting it.

Files: `apps/web/src/components/SetupWizard.tsx`, `apps/web/server/auth.cjs`,
`apps/web/server/index.cjs` (`/api/setup/*`, `/api/profile/features`).

---

## Workstream 4 — Diary zero-state and first-entry flow

This is the only fully-new work.

**4a. Bootstrap the folder structure.** There is currently *no* bootstrap: `Entries/`
appears lazily on first write (`local_storage.py:15`, `webdav.py:89`), and
`AI Memory/` + `Raw Sources/` are mentioned in exactly one line of
`services/diary/README.md` and created by nothing. On the first entry, scaffold all
three with a one-line seed `README.md` each, so the file browser and the new panels
have something to render and the user can see where things go.

**4b. Landing page becomes state-dependent.** `DiaryView.tsx` renders one landing for
everyone. Split it:

- **Empty** (`/api/diary/source` returns no months, no memory files): drop the hero
  and the month grid entirely. The composer is the only thing on the page, centred,
  placeholder **"Write your first entry…"**. One line under it explaining that the
  first entry creates the diary's folder structure.
- **Populated**: three panels — **Memory** (`AI Memory/` + `MEMORY.md`, already
  reachable via `listFiles()`), **Entries** (recent days, not just a month grid), and
  **Other sources** (`Raw Sources/`, plus the `external-sources` API which today is
  **admin-only with no user-facing surface at all**). The month grid moves below
  these or into the sidebar.

**4c. Sending from the landing navigates to the day.** In `submit()`, when
`scope === 'home'`, compute `entryDay` as it already does, then `setMonth(...)` /
`setDay(entryDay)` *before* streaming, and route the streamed turns into the day's
scope rather than `'home'`. Net effect: you type, you land on today's log, and the
reply streams in there. Guard the existing `navigate()` draft-discard confirm so it
doesn't fire on this programmatic move.

**4d. UI polish** (the "still a little crude" note). Deliberately scoped small so it
doesn't swallow the rest: the diary landing, the composer, and the three panels get
`design-system.md` applied properly. `DiaryView.tsx` currently has
several 400+ character single-line JSX expressions — break the landing, calendar, and
sidebar into components while touching them anyway, or the next change here is
unreviewable. The `ui mockups/Diary-html` mockups are the reference.

Files: `apps/web/src/components/DiaryView.tsx` (split into `DiaryLanding.tsx`,
`DiaryCalendar.tsx`, `DiaryContextPanel.tsx`), `apps/web/src/diary-workspace.ts`,
`services/diary/agent/corpus_store.py` (scaffold), `apps/web/server/index.cjs`
(expose external-sources to non-admins, read-only).

---

---

## Workstream 5 — Scaling past a fixed tool catalogue (research → maybe)

**Prior art check: noevia already has a better answer to "too many tools" than most
of what's published.** `apps/web/server/index.cjs:565-850` implements toolboxes —
named working sets, per-project selection, read/write gating per tool
(`reads[]`), and two independent limits applied at resolve time: `toolCapFor(model)`
and `toolTokenBudgetFor(model)`, the latter derived from *measured* prefill rate
against the live endpoint with a documented `tokens ≈ 240 + chars/3.6` estimator and
a real error table. Dropped tools are reported, never silently withheld. The
`nextcloud-mcp-server` link in the batch is already wired in as the `nc_*` boxes.

So this workstream is not "solve the problem" — it's the one tier above what's built.

**The gap: selection is static per project.** A project that ticks Calendar + Files +
Contacts + Deck pays for all four catalogues on *every* turn, at ~14 tok/s, whether
or not the message is about a calendar. The budget then truncates in selection order,
so late boxes become unreachable for reasons the user can't see.

**The technique to evaluate — progressive/deferred tool disclosure.** Instead of
sending every selected tool, send a small always-on core plus one meta-tool that
searches the catalogue and loads schemas on demand. This is exactly what the Claude
Code session that wrote this plan does: ~30 tools live, ~120 deferred behind a
`ToolSearch` call. Applied to noevia:

- Always send: `core` box + a `find_tools(query)` tool + one-line summaries of each
  enabled box (`toolboxSummaries` already exists at line 1550 and already carries
  `estTokens`).
- `find_tools` returns full schemas for the 3-8 matching tools, injected into the
  next turn's `tools` array for the rest of the conversation.
- Cost model: box summaries are cheap; the full Calendar catalogue (4,512 measured
  tokens) is only paid by conversations that actually reach for a calendar.

**Honest caveats, and why this is "maybe" rather than "do it":**
- It costs an extra round trip on the first tool use — at ~14 tok/s that is felt.
- It depends on the model reliably calling a meta-tool, which small local models do
  *less* well than they call ordinary tools. On a 9B this may simply not work.
- The existing measured-budget machinery already prevents the catastrophic failure
  (catalogue crowding out the conversation). This is an optimisation, not a fix.

**Recommended shape if pursued**: build it behind an env flag as a third resolution
mode alongside the existing cap/budget, measure it on the actual 9B target the same
way `TOOL_PREAMBLE_TOKENS` was measured, and keep static resolution as the default
until the numbers justify a switch. `resolveTools()` is the single seam.

**On the rest of the link batch** — assessed, mostly not worth adopting:
- `omnigent-ai/omnigent` — a meta-harness over Claude Code/Codex/Cursor. Wrong layer;
  noevia's `MASTER-PROMPT` explicitly says "do not vendor an agent framework", and
  `mcp.cjs` deliberately implements only three JSON-RPC calls. Ignore.
- `mufasadb/ai-lego-bricks` — JSON-configured LLM workflow library. Same objection.
- `cbcoutinho/nextcloud-mcp-server` — **already integrated** as the `nc_*` boxes. The
  only actionable item: it now advertises 110+ tools and semantic search across
  Notes/Files/Deck/Mail, so `MCP_TOOLBOX_MANIFEST` is likely behind upstream. Worth a
  re-scan for newly-added tools that belong in existing boxes.
- `ayghri/i-have-adhd` — a terse-output prompt skill. Not architecture, but the
  *format discipline* is a fair reference for
  `services/diary/config/prompts/system.md` if diary replies feel padded.
- arXiv 2406.06608 — "The Prompt Report", a 58-technique prompting taxonomy. A
  reference to keep, not a change to make. Useful when tuning the diary's
  `skip_classifier` and `summarizer` prompts in `config/prompts/logging.md`.

### From the Reddit batch (pasted as text; Reddit itself is unreachable here)

Four items survive review. The model-recommendation threads are hardware shopping,
not architecture, and are noted only where they touch code.

**5a. Tool-call looping on Qwen3.8-27B — a real defect class, cheaply mitigated.**
One thread reports Qwen3.8-27B repeating an identical tool call until manually
stopped, ~1-2×/day, fixed by swapping the chat template
(`huggingface.co/froggeric/Qwen-Fixed-Chat-Templates`, reported over 500M tokens).
noevia bounds this already — `index.cjs:2224` caps the loop at 3 rounds — but a cap
only limits the damage; it still burns two rounds and a chunk of the context on the
same call, which at ~14 tok/s the user *feels*. Add a duplicate-call guard in the
round loop: hash `(name, normalised args)` per chat turn, and on a repeat return a
synthetic tool result (`ERROR: <name> was already called with these exact arguments
this turn; the previous result stands. Do not call it again.`) instead of
re-executing. Cheap, provider-agnostic, and it makes the failure legible rather than
silent. Separately, worth checking which chat template Lemonade serves for the
target model — this is a deployment note for the live `.env`, not app code.

**5b. Uncapped local thinking is the actual argument for Workstream 2.** The most
substantive claim in the batch: local models beat commercial ones at *planning*
specifically because there is no artificial thinking cap — "tens of thousands of
thinking tokens, stress-testing edge cases" at 3-12 tok/s, unattended. This sharpens
the reasoning-effort design: on a local provider, `high` should mean *remove the
ceiling*, not "send `reasoning_effort: high`" (which local endpoints ignore anyway).
Concretely, `high` on an unverified/local provider should raise `max_tokens` rather
than only injecting the prompt hint — which is exactly open question **(c)** in
the appendix, currently answered "out of scope". **Reverse that
answer for the local path only.** The spec's caution was about honesty on providers
that ignore the parameter; raising the output ceiling is a real, honest lever that
works everywhere.

**5c. Plan-with-big / execute-with-small is a better Auto router than Fast/Smart.**
Same thread describes the pipeline that works: the large model maps out the
architecture, a smaller fast model executes, and the pair beats either running solo.
noevia's existing auto-router (`heuristicWantsSmart`, `classifierVerdict`) classifies
each *message* as easy-or-hard. The suggested shape instead splits by *phase* within
one exchange. Worth a spike, not a rewrite: the router already has the seam, and the
change is which model handles the first turn versus the tool-execution rounds. File
alongside Workstream 5 as a second research item.

**5d. An offline Wikipedia RAG endpoint is a good toolbox candidate.** One link is a
local API that serves full Wikipedia articles matched to a query. Against Tavily —
already integrated as `web-search` / `web-crawl` — it has two properties that suit
this deployment: it works with no internet, and it spends no metered credits (the
`web-crawl` box's comment explicitly worries about burning "a month of credits on a
single large site"). A `wikipedia` box of one or two read-only tools fits the
existing `MCP_TOOLBOX_MANIFEST` shape with no new machinery. Low effort, clearly
additive.

**Noted, no action**: the 8GB-VRAM benchmark thread and the adaptive-KV-streaming
tutorial are Lemonade/hardware tuning, not app changes — though the benchmark's
split (fast-but-shallow vs slow-but-accurate) is the empirical case for 5c. One
detail does touch code: MoE names like `Qwen3.6-35B-A3B` carry both a total and an
active parameter count, and `toolTokenBudgetFor`'s fallback regex
(`index.cjs:~790`) reads the first one. It happens to land on the right side here,
and the measured-prefill path overrides it within a request or two, so this is a
comment-worthy edge case rather than a bug.

**5e. Settles the "is Cowork a harness" question, and reframes noevia.** The clearest
answer in the batch: Claude.ai is an LLM with a cloud container; Claude Cowork is the
same model with a container *you* host, giving it durable files and skills; Claude
Code is a full agentic harness with no container unless you build one. The line that
matters for this project: *"You can pretty easily make Claude Code operate like
Cowork by putting it in a micro-VM and building a GUI on the front."* That is a
one-sentence description of what noevia already is — a self-hosted container plus a
GUI, wrapping a model with tools, permissions, and a session loop. Worth writing into
the new `CLAUDE.md` (Workstream 1) as the project's own framing, because it explains
*why* the toolbox permission gating and the mechanical diary writer exist rather than
leaving them as local quirks.

---

## Sequencing

1. Workstream 1 — hours, unblocks agent-driven deploys immediately.
2. Workstream 4c — one function, highest felt improvement per line changed.
3. Workstream 3 — wizard restructure.
4. Workstream 2 — thinking modes (touches the chat hot path; do it with the wizard's
   prefs step landed so it has a home).
5. Workstream 4a/4b/4d — the diary rebuild.
6. Workstream 5a (duplicate tool-call guard) — small, standalone, do it early;
   it is a bug fix, not a spike.
7. Workstream 5d (offline Wikipedia toolbox) — additive, no new machinery.
8. Workstream 5 proper + 5c — research spikes only; a `docs/spec-*.md` like the
   reasoning-effort one, not code, until measured on the 9B target.

## Verification

- **Fresh install**: `docker compose up` from a clean `COWORK_STATE_DIR`, grab the
  setup code from `docker compose logs web`, walk the wizard answering *no* to diary,
  then *yes* on a second clean run. Confirm `user_features` matches the answer in both
  cases and that nothing was applied that wasn't shown.
- **Invite path**: generate an invite from Settings → Users, accept in a private
  window, confirm the wizard now runs for the invitee.
- **Zero-state diary**: point at an empty corpus root; landing shows only the
  composer. Send one entry; confirm `Entries/`, `AI Memory/`, `Raw Sources/` are
  created, the view navigates to today, and the reply streams into the day log.
- **Thinking modes**: set global `high` against a known-good OpenAI-compatible
  endpoint (badge reads "real"), then against local Lemonade (badge reads "hint",
  chat does not break). Verify a project override beats the global, and that a 400 on
  the field retries once and downgrades rather than failing the message.
- **Tests**: `apps/web/server/*.test.cjs` (node test runner) and
  `services/diary/tests/` (pytest). New tests: reasoning-effort resolution order and
  the unverified-provider fallback; diary scaffold idempotency; `markOnboarded` not
  clearing `diary_enabled`.

## Explicitly not doing

- Renaming any `cowork` identifier (env vars, images, cookies, Unraid project name) —
  intentional compatibility preservation, per `agent-brief.md`.
- Anthropic extended-thinking wire format, per-message thinking toggles, or exposing
  model reasoning tokens.
- A schema-driven wizard that mirrors every Settings category.

---

# Appendix — reasoning-effort spec

Folded in from the former `spec-reasoning-effort.md`. Workstream 2 above
implements it, with two of its open questions now answered — see the note after
the table.

## The idea, and why it was parked

A per-project or per-message control that trades reasoning depth against
speed and cost (low / medium / high). Parked because the feature has an
honest implementation on only a subset of providers, and a dishonest-feeling
one on the rest — and "silently does nothing" is worse than "not offered."

## Provider landscape (the whole problem in one table)

| Provider family | Real mechanism | Shape |
| --- | --- | --- |
| OpenAI, OpenRouter-style `reasoning_effort` | Yes — `reasoning_effort` on the chat completion | one string: `low` / `medium` / `high` |
| Anthropic-style extended thinking | Yes, but a **different shape**: `thinking: { type: "enabled", budget_tokens: N }` plus a required minimum output budget | token budget, not a level |
| Locally hosted (Lemonade, Ollama, LM Studio, llama.cpp servers) | **No standard parameter.** Some model runtimes (not APIs) accept soft hints like `/think` or `/no_think` in the prompt; effect varies per model | none — at best a prompt hint |
| Unknown/generic OpenAI-compatible endpoints | Unknown. Sending `reasoning_effort` is either ignored (harmless) or rejected with a 4xx (breaking chat) | unknown |

The registry is intentionally generic: any OpenAI-compatible endpoint can be
registered. So the provider family cannot always be known up front — which is
exactly the trap. See "Capability detection" below.

## Core design decisions (proposed)

1. **Scope: per-project setting, defaulting to "default" (send nothing).**
   Not per-message. A per-message toggle multiplies UI surface for a feature
   whose value is mostly "set once per project"; the chat composer should not
   grow a knob that most users on local models can never use honestly. A
   per-project setting lives next to the existing per-project model choice
   and reads the same way.
2. **Three states: `default` / `low` / `high`.** Medium equals default in
   every backend we know of; offering it invites a knob that does nothing
   anywhere. `default` sends no parameter at all, which is the only choice
   that is honest on every provider.
3. **Never send a parameter the backend wasn't verified to accept.** The
   failure mode to design against is breaking all chat for a project because
   a local server 400s on an unknown field. Concretely:
   - When the user picks `low`/`high`, the server sends `reasoning_effort`
     **only** if the selected provider has been verified (see detection),
     else falls back to the prompt hint — and says so.
4. **Capability detection is optimistic-probe, cached, per provider base
   URL.** First request after a mode change sends `reasoning_effort` with
   `reasoning: { exclude: true }`-free minimal payload? No — simpler and
   better: send the real request with the parameter; on a 4xx whose body
   mentions the field (or a 400/422 generally, once, flag-worthy), retry once
   without it, mark the provider `unverified` in memory, and surface a
   one-time warning ("this provider rejected the reasoning setting; using
   best-effort hints instead"). The cache lives for the process lifetime;
   a provider edit resets it. This avoids both the probe-request cost and
   the "test call lies about chat behavior" problem.
5. **The honest fallback is a visible hint, not a hidden one.** When no real
   mechanism applies, the injected hint is:
   - `low`: "Answer directly and concisely; skip step-by-step reasoning."
   - `high`: "Think through this step by step before answering."
   The UI shows the selected mode with an indicator distinguishing "real"
   (parameter sent) from "hint" (prompt-injected, best-effort), per the
   parking-lot requirement that users not be misled.
6. **Anthropic-shape providers are out of scope for v1.** The registry
   speaks OpenAI-compatible chat completions; teaching it a second wire
   format is a separate, larger project. The spec consciously ships without
   it rather than pretending `reasoning_effort` covers it.
7. **The diary pipeline is untouched.** Logging, editing, and commentary run
   on the aux model with their own prompts; they are deliberately not
   subject to the project's reasoning-effort choice.

## What v1 actually is (mechanical once agreed)

- `projects.json` schema: add optional `reasoningEffort: 'default' | 'low' | 'high'` (absent = default; older files stay valid).
- Server: project read/write endpoints accept the field; the chat path, when a project is active and the field is `low`/`high`, applies decision 3/4 against the chat's resolved provider.
- Chat SSE: emit a `meta.reasoning` event (`real` / `hint` / `off`) so the UI can label the mode honestly.
- UI: a three-way selector in project settings; a small mode badge in the chat header when anything other than `default` is active.
- No changes to provider registry storage, RAG, or the diary.

## Open decisions — ANSWERED 2026-09-09

- **(a)** Scope. Spec proposed per-project only. **Answered: global default +
  per-project override.** Workstream 2 above is written to that decision, and it
  supersedes the "per-project setting" wording in decision 1 and in the v1 list.
- **(b)** Fallback hint on unverified providers — silent with a badge, or ask once?
  **Answered: badge, no prompt.** Spec's proposal stands.
- **(c)** Should `high` also raise `max_tokens`? Spec proposed out of scope.
  **Answered: reversed for the local/hint path** — see Workstream 5b. On an endpoint
  that ignores `reasoning_effort` entirely, the output ceiling is the only lever that
  does anything real. It remains out of scope on verified providers, where the
  parameter itself does the work.

## Non-goals

- Per-message toggles; Anthropic wire format; chain-of-thought visibility
  (the app never displays model reasoning tokens regardless of provider);
  any change to the diary pipeline's aux-model behavior.
