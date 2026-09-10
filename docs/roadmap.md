# noevia roadmap

## PDF reduction, local thinking and shared Diary assessment — 2026-09-10

User-authorized follow-up: `2408c32` makes configured local Qwen3/3.5 Low/High
use actual `chat_template_kwargs.enable_thinking` false/true. Default remains
provider default; other providers retain their documented parameter/hint behavior.
[Qwen’s model card](https://huggingface.co/Qwen/Qwen3.5-9B) documents the template switch; the installed template was also verified.
This controls ordinary/project chat (including optional Diary extras), not the
separately configured Diary companion's effort. Its provider reasoning still streams.
The exact installed Qwen3.5-9B UD-Q4_K_XL GGUF was inspected read-only: it uses
`enable_thinking` in its template but contains no MTP metadata/tensors. Its disabled
MTP control is correct; the upstream model's training capability is insufficient.
[Unsloth's separate MTP GGUF](https://huggingface.co/unsloth/Qwen3.5-9B-MTP-GGUF)
is a potential replacement to validate, not an automatically installed model.

`ddbe852` allows PDFs up to 60 MB into bounded asynchronous reduction. Native text
is extracted, images recompressed, and a PDF under 25 MB is saved with a distinct
`.compressed.pdf` name only after validation and matching page counts. If that
fails, a complete native-text extract within the text limit may be saved as
`.extracted.txt`, explicitly warning that images/scanned text/layout are omitted.
Encrypted, malformed, over-300-page and unreducible files fail clearly. Originals
remain on the user's computer; ordinary files retain the 25 MB limit. The private
worker adds Ghostscript; no cloud document processor is used. Verification:
329 web tests, typecheck/build, 13 real Linux worker tests and synthetic browser
checks covering notices, failures preserving sources, and responsive UI.

Shared Diary API deployed in `12a1646`: dedicated revocable credentials and
version-checked Markdown operations prevent stale replacements. The Claude plugin
is packaged privately but not installed; Claude UI automation became unavailable.
Nextcloud push callbacks are repaired and all six self-tests pass after restart.
Desktop sync timing and pending Mac/cloud differences remain unverified; no real
Diary data changed. See [shared-editing status](spec-diary-shared-editing.md).
The broader roadmap stays paused for user testing.


Rollout complete: `ddbe852` on all three services; 281 Linux server and 13 worker
tests passed before cutover. Health and public assets match; rollback retained.

## MTP controls and persistent inference footer — 2026-09-10

User-authorized follow-up: fresh launch/reload opens an unsaved New chat (separately
tested/pushed as `df8a486`). Model selection/Manage now offer native MTP Yes/No,
with an explicit Apply and load action for administrators because Lemonade model
loading is shared. Native support comes from Lemonade's GGUF-derived `mtp` label
and llamacpp recipe, never a model-name guess. Saved options are preserved,
including context/cache/GPU split arguments. A successful load precedes saving the
preference; a failed load leaves saved options unchanged. No automatic reload or
model download happens on opening the selector. Native MTP models keep Lemonade's
automatic default until explicitly overridden. Unsupported models show why Yes is
unavailable; arbitrary tiny draft models are not automatically paired/downloaded.

Inference details now stay open at the bottom, including Diary. Loaded MTP models
show an acceptance bar using accepted/proposed draft-token totals. Newer backends
can report cumulative counters. This server's llama.cpp b9632 instead reports
per-response `draft_n`/`draft_n_accepted`: Chat and Diary forward these actual
timings, labelled **last response**, updated at completion. These samples are
user/model scoped, bounded and expire after ten minutes. Missing/invalid telemetry
stays unavailable. Polls do not overlap; failed stats requests clear acceptance.

Runtime inspected: Lemonade 10.8.0 / llama.cpp Vulkan; installed Qwen 3.5 4B has an
MTP label, while the installed 9B/Gemma variants do not. No live model load/settings
were changed for testing. Multi-GPU on/off throughput/latency/acceptance benchmarks
and compatible external draft-model configuration remain explicit experiments;
MTP is not assumed to be a free speedup. Broader roadmap pause remains in effect.

Sources: [versioned load API](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/docs/api/lemonade.md#post-v1load),
[native defaults](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/server/backends/llamacpp_server.cpp),
[GGUF capabilities](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/include/lemon/gguf_capabilities.h),
and [backend metrics normalization](https://github.com/lemonade-sdk/lemonade/blob/v10.8.0/src/cpp/server/prometheus_metrics.cpp).

Validation: 325 web tests, 178 Diary tests (3 skipped), typecheck/build; isolated real-app/fake-Lemonade browser
checks cover Yes/No before load, option preservation, persistence after success,
failed-load safety, unsupported/member rejection, and acceptance footer visibility
at 375/768/1440 widths in Chat and Diary. New-chat landing and Diary scrolling
regressions pass. No real Diary prompts or corpus changes. Deployment recorded
separately.

Rollout complete: `cac1778` on all three services, replacing `3ef0501`; 277 Linux
server and eight worker tests passed before cutover. Health/public assets match.
No production model settings or Diary corpus changed for testing.


## Live Diary activity and timeout feedback — 2026-09-10

The user's follow-up explicitly requests live visibility and reports a 524 after
leaving an active Diary view. The earlier after-completion reasoning fix was not
sufficient. The noevia Diary path now streams immediate headers and 5-second
keep-alives through both proxy and companion, actual provider reasoning/answer
chunks, and actual retrieval/classification/summary/save/memory progress. The
answer is visible before capture finishes; saving is confirmed separately.
Optional tool calls remain attached to their conversation turn with unchanged
approval gates. An elapsed timer accompanies the active phase. No synthetic tool
calls or invented reasoning are shown. Providers that buffer or omit reasoning
still show the real pipeline phase. The external OpenAI JSON surface is unchanged;
noevia opts into its activity event protocol explicitly.

Switching app views keeps the mounted request and transcript alive, without a
second submission. Interrupted streams preserve the attempted message/partial
response and report unconfirmed saving; no automatic retry. Proxy HTML is never
shown as the error text. A full browser reload/close still does not provide durable
conversation/job recovery; the journaled server operation may finish after the
connection closes, so check the saved record before resending. Durable recovery
remains open. Browser-local saves still require the connected folder and browser.

Verification: 319 web tests, typecheck/build, 177 Diary tests passed (3 skipped,
2 existing warnings). Tests cover headers/heartbeats before slow upstream, frame
fragmentation, disconnect/no-retry, provider reasoning before answer, hidden log
markers, rejection of truncated generation, server tenant context and memory-only
local capture. Synthetic browser checks cover live thinking, leave/return while
running, save phases, retained optional tool traces, sanitized 524 and partial-stream
failure, plus prior scrolling/composer/navigation checks. No real Diary prompts or
corpus edits. Broader roadmap remains paused. Deployed application `3ef0501`; all three
services and public assets verified after 271 Linux server/eight worker tests.
The following rollout-record commit is documentation only.


## Diary reading feedback — 2026-09-10

The user authorized this focused fix during the broader testing pause. Other
roadmap implementation remains paused. The active conversation now shows the
original user message and complete companion answer, with the saved diary record
in a separate disclosure (collapsed when this session has conversation turns).
The day composer is outside the transcript scroll. Diary and ordinary chat follow
new output only at the bottom; scrolling up pauses following, and returning to the
bottom or sending resumes it. Ordinary chat's smooth auto-scroll was removed
because its intermediate scroll events incorrectly disabled following.

Provider-returned reasoning is carried separately through both server and local
Diary exchanges and displayed using the existing thinking disclosure. It is not
included in journal prose or follow-up history. The companion still uses a single
non-streaming request: reasoning arrives with completion, only when returned by
the provider. Live Diary token/reasoning streaming and durable full conversational
history remain future work; reopening after reload shows the saved diary record.

Verification: 315 web tests, typecheck/build, 172 Diary tests passed (3 skipped,
2 existing warnings). Synthetic Chrome checks cover server/local Diary reasoning,
retained previous thoughts, history filtering, navigation/errors/extras/cancel,
saved-summary disclosure, scroll pause/resume, stationary day composer, landing,
both themes and 375/768/1440 widths. Ordinary chat scroll is also tested against
an isolated real app server and synthetic streaming provider. No real Diary test
prompts or corpus changes. Deployed application `ecaaa73` across all three services after 267 Linux server
and eight worker tests; health and public build assets verified. The following
rollout-record commit changes documentation only.


Originally written 2026-09-09 against `8a78172`; priorities updated 2026-09-10.
This is a mix of plans and completed work, not a claim that every item remains
unimplemented. Older sections retain their original context unless marked otherwise.

## User testing pause — 2026-09-10

Implementation and deployments are paused while the user tests the current release
for a couple of days. Resume when the user returns with feedback or explicitly
asks to continue; elapsed time alone is not permission to restart. No automatic
monitor or scheduled deployment is requested. Keep the current configuration
stable, including Diary extras off on reload and file sharing off.

Recorded application release: **`79cd24f`**, healthy at the last verification.
The documentation commits after it do not change the running application.

### Shipped versus remaining

Completed batches include reliability fixes, PDF/OCR/images and bounded DOCX
reading, shared composers, onboarding improvements, Diary navigation/landing/
scaffolding/timezone/direct prior-entry fallback, thinking controls v1, app
passwords, and limited default-off file sharing. Exact skill filenames and bounded
metadata are implemented; the full skills lifecycle is not.

**Roughly one third to one half of the work may remain by effort.** This is an
informal planning estimate, not measured completion, a delivery date or a count
of unchecked items. Several remaining items are large and still exploratory.

| Remaining area | What is still needed |
| --- | --- |
| Storage | Full WebDAV/file-manager compatibility and companion-backed namespace operations; managed-volume defaults and resolved Unraid /boot-path protection without silently moving existing data. |
| Instruction skills | Inspect/enable/disable/update lifecycle, explicit review/migration, and exclusion from every source/RAG path when disabled. The scoped proposal is complete; executable packages are not the chosen scope. |
| Tools and routing | Deferred tool discovery and planner/executor experiments. Plans are written; benefits have not been benchmarked and the new runtime behavior is not implemented. |
| Thinking/model behavior | Verified larger local budgets, broader provider/model support, and accuracy/performance evidence. Current high hints request 8,192 tokens; uncapped reasoning is not established. |
| Optional integration | Offline Wikipedia requires a selected available service; it is not a prerequisite for core Diary use. |
| Claude-like Diary behavior | Compare the available Claude Diary instructions and example behavior with noevia's prompts and synthetic exchanges before claiming equivalence. |

### Diary and Claude Cowork clarification

Diary is intended to retain its existing capture, retrieval and storage behavior.
Last verification: 314 web tests, typecheck/build, 171 Diary tests passed (3 skipped,
two existing warnings), and healthy deployed services. These checks used synthetic
data. No test entry was sent to the user's real diary, so private-data end-to-end
behavior has not been verified by the agent.

The **workflow decisions** from the shared Claude Cowork Diary description were
adapted: local date/time handling, bounded direct prior-entry reads when retrieval
fails or is empty, tenant file listing/guarded writing, and disk-backed memory
without a second Claude-side store. This is not an import of Claude's actual
`device_bash`, `remote-devices`, `project_memory_*`, or staging implementations.
Shell/heredoc appends were deliberately not ported: noevia must retain its journal
and conditional-write protections and generate Diary structure mechanically.

It has **not** been established that noevia follows Claude's exact rules for what
to log, entry wording, memory-update decisions or conversational responses. A
working Diary pipeline is not proof of Claude-equivalent Diary behavior. Make this
comparison an explicit follow-up informed by the user's testing, using available
reference instructions and synthetic fixtures; do not infer Claude's private
implementation or access the real corpus for testing without authorization.

Useful feedback during this pause: missing/duplicate entries, incorrect dates or
titles, unexpected wording, poor prior-entry recall, memory behavior, and response
latency/errors. User observations are not yet recorded as reproduced defects.

## Audited priorities — 2026-09-10

See [the code-based roadmap audit](roadmap-audit.md) for detailed evidence and
[the continuation checkpoint](continuation-checkpoint.md) for resume state.
The testing pause above takes precedence over earlier instructions to continue
autonomously. After feedback, prioritize reproduced Diary regressions and the
behavior comparison, then the remaining scoped work above. Historical sections
below retain their original context and are not evidence of shipped behavior.

## Product direction — 2026-09-10

- **UI and sidebar are accepted.** Preserve shared composer controls across chat,
  project landing, and Diary home/day views. No broad cosmetic redesign.
- **Diary extras are opt-in and OFF on reload.** The required companion pipeline
  remains active; its model is not replaced by the extras model selector.
- **PDF/OCR/image support has shipped.** Original files, OCR status and categorized
  uploads work; bounded DOCX body/table extraction is deployed. Model accuracy and latency remain limitations.
- **Skills use reusable instructions and existing approved tools.** The proposal
  and existing metadata fix are complete; the full lifecycle remains planned.

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

**Completed locally, 2026-09-10; not deployed.** Root `AGENTS.md` and `CLAUDE.md`
point to the agent brief, preserve cowork-prefixed identifiers, and distinguish
`DEPLOY.md` / `cowork.setup.json` (generic fresh installs) from the existing
[Unraid runbook](deployment.md) (tarball releases and separate Compose Manager copy).
The runbook was linked, not recreated. The generic docs and manifest describe the
actual account-step diary checkbox, optional diary storage step, and existing
models guidance; the proposed diary-first wizard is still unimplemented.

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

Thinking-effort v1 implemented 2026-09-10: global/project inheritance, composer
controls, actual request-mode labels, documented GPT-5.4 parameter support and
one-time field rejection fallback. High hints use an explicit 8,192-token budget;
this does not promise uncapped generation or an increase over unknown defaults.
Default omits fields; it does not universally equal Medium. See audit for provider
verification, real synthetic inference evidence and remaining limits. Deployed `6570c51`.

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
3. **Rework the storage step around the appliance decision (Workstream 7).** Two
   peer choices, not a flat list of four backends:
   - **"Let noevia hold my diary"** — the appliance path. Corpus in a
     noevia-managed volume. Follow-up question: *should other devices be able to
     reach these files?* — **Off / This network only / Reachable from anywhere**
     (7h), defaulting to Off. Anything but Off enables the WebDAV endpoint (7d) and
     ends setup by showing the mount URL and a generated app password **once**, the
     way the passkey step already handles a one-time secret. The LAN choice states,
     in one sentence, that plain http sends that password in cleartext across the
     local network, and takes an explicit acknowledgement rather than refusing.
   - **"Connect storage I already run"** — the existing `StoragePicker`:
     Nextcloud, WebDAV, S3.

   Each says plainly what it costs: the appliance path is reachable from other
   devices only if the endpoint is enabled; the connect path means noevia is not
   the system of record and the files keep whatever sync the user already has.
   Default to neither — this is exactly the "assume nothing" rule in point 7.
4. **Expand `prefs` past theme + auto-routing.** Add, as real questions:
   - Thinking-mode global default (Workstream 2) — the natural home for it.
   - `insights_badge`, which today is silently defaulted to `0` in `user_features`
     and **never asked anywhere**, in the wizard or Settings.
   - Display name / timezone confirmation (the diary stamps local dates; getting this
     wrong misfiles entries).
5. **Fix the invited-user hole.** `acceptInvite` in `auth.cjs` defaults `onboarded` to
   `1`, so anyone joining by invite **never sees the wizard at all** — no diary
   question, no provider, no prefs. Set `onboarded = 0` for invitees and give the
   wizard a `mode: 'invited'` that skips the setup-code/origin/admin-only steps.
6. **Audit `markOnboarded`**: verified in the 2026-09-10 onboarding batch.
   The conflict branch already preserves the stored choice atomically. Missing
   rows have no recorded opt-in and remain off; completion is not consent.
   The actual reproduced gap was repeated legacy backfill enabling missing rows
   on restart, now gated by the original migration marker.
7. **"Assume nothing" pass.** Every step keeps its explicit skip (already true), but
   no step may apply a value the user didn't see. Today `theme` is seeded from
   `localStorage` before it is asked — show what was detected rather than silently
   adopting it.

**2026-09-10 bounded correctness follow-up:** items 5/6 are implemented and
deployed as `baf38aa`, replacing `66af1ad`. New invitees resume onboarding; members skip
bootstrap and provider/global-model setup. Explicit Diary yes/no is read from
the authenticated account, saved on change, and retained across reload/completion.
The dead-end models step is removed without a manager probe or full storage/wizard
redesign. Back, sign-out/resume, and truthful preference skip semantics are tested.
278 web tests, typecheck/build; 157 diary passed, 3 skipped. Next: Workstream 4c.

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

Implemented 2026-09-10: create-only, journal-replayable first-entry seeds, with
legacy/imported corpus preservation and direct AI Memory context reads.
171 diary / 281 web tests, typecheck/build and synthetic manual verification pass.
Deployed as `b34c33f`.

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

4b implemented 2026-09-10: empty composer and populated tenant Memory/Entries/Other
sources panels, with up to seven dates from the latest two months and existing
month navigation below. Operator-wide external source folders remain admin-only;
exposing them requires tenant ownership, as recorded in the audit. Tests and
synthetic responsive/manual checks pass. Deployed as `8edacf7`.

**4c. Sending from the landing navigates to the day.** In `submit()`, when
`scope === 'home'`, compute `entryDay` as it already does, then `setMonth(...)` /
`setDay(entryDay)` *before* streaming, and route the streamed turns into the day's
scope rather than `'home'`. Net effect: you type, you land on today's log, and the
reply streams in there. Guard the existing `navigate()` draft-discard confirm so it
doesn't fire on this programmatic move.

**4c implementation, 2026-09-10:** day selection precedes streaming/preparation
for both saved storage and browser-local folders. A single pinned day owns recent
history, replies, failures and extra-tool scope; returning home does not split the
same day's conversation. 281 web / 157 diary tests (3 skipped), typecheck/build and
synthetic browser/manual checks pass. Deployed as `5b1ef12`.

**4d. UI polish** (the "still a little crude" note). Deliberately scoped small so it
doesn't swallow the rest: the diary landing, the composer, and the three panels get
`design-system.md` applied properly. `DiaryView.tsx` currently has
several 400+ character single-line JSX expressions — break the landing, calendar, and
sidebar into components while touching them anyway, or the next change here is
unreviewable. The `ui mockups/Diary-html` mockups are the reference.

4d implemented 2026-09-10: landing, calendar and context panel are separate
components; existing behavior, responsive styles and composer controls preserved.
281 web / 171 diary tests and both synthetic browser suites pass. Deployed `7a34a0a`.

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
**Completed locally, 2026-09-10; not deployed.** The three-round limit remains.
The streaming loop now owns an exchange-local result cache keyed by tool name and
recursive canonical JSON: object keys sorted, array order retained. Equivalent
calls reuse their full result while retaining each call ID and SSE chip/result
pair, including the non-streaming fallback and final round.

- Writes, denials, approval timeouts, and failed writes are reused for the whole
  exchange: no automatic retry or second approval, even after a different write.
- Reads (including errors) reuse results until an approved write is attempted.
  That attempt invalidates reads even if it fails, because partial mutation is
  possible. Denied/invalid/duplicate writes do not invalidate reads.
- Malformed JSON and non-object arguments return validation errors without
  approval or execution; corrected arguments can run. Empty arguments mean `{}`.
- The allowed-tool set is checked before cache lookup; the existing execution
  check and all three approval actions remain. Cancellation stops subsequent calls.
- Cache lifetime is one handler invocation, never a chat, user, or project store.
  Later exchanges can execute the same call again. This is loop protection, not
  durable idempotency or protection against concurrent separate exchanges.

Regression tests use the actual chat handler with mocked providers, approvals,
and tools; no real diary or production services are involved. Provider chat-template
investigation remains a separate deployment concern.

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

## Workstream 6 — Port Claude Cowork's diary-logging loop

Source: a Cowork session describing, in its own words, exactly how it logs to the
user's diary. Worth porting because it is a *working* implementation of the same
job noevia's diary does — but it runs on macOS through a device bridge, and noevia
runs in a container. The mechanics do not transfer; the **decisions** do.

### What Cowork actually does

Everything goes through one MCP server (`remote-devices`) bridging a cloud session
to the Mac. For the diary specifically it uses only four functions:

| Cowork | What it is for |
| --- | --- |
| `device_bash` | `date` for the clock; `cat`/`tail`/`grep` to read prior entries for context; `cat >> file << EOF` heredocs to append `### <time>` sections; `python3` for bulk edits when `sed -i` fails |
| `device_list_dir` | Check whether `Entries/2026/September/September 9, 2026.md` exists before touching it |
| `project_memory_read/write` | Persistent working notes — format rules, day-boundary rule — **on Claude's side, not on disk** |
| `device_stage_files` | Deliberately unused for the diary; only for files needing a tool the machine lacks |

No uploads, no artifacts, no staging. Read, append, done.

### The four decisions worth taking, and how each maps to a container

**6a. Do timezone conversion in the environment, never in arithmetic.** Cowork's
sandbox VM reports UTC and the model was manually subtracting 4 hours for EDT.
That arithmetic caused a real misfiled entry. Its own fix: run
`TZ=America/New_York date` so the conversion happens in the command.

Implemented in the repository: both compose definitions pass `TZ` to the diary
service, `.env.example` documents it, and setup's prefs step detects/confirms an
IANA zone and shows the setting for the operator to apply. Subprocess tests pin
the day and entry-header fallbacks across UTC midnight, including summer/winter
offsets. **Audit update 2026-09-10:** the separately authorized deployment has
also applied this to production; a read-only container check confirmed
`TZ=America/New_York` and `EDT -0400`. The exposure described below is historical.

**noevia has the identical exposure.** The diary container has `TZ` unset, so it
runs on UTC while the user does not.

*Reproduce it* — the window is local 20:00 to midnight, when UTC has already rolled
over:

```sh
ssh <host> "docker exec cowork-diary-1 python -c \
  'from datetime import datetime; print(datetime.now().date())'"
date +%F        # your machine
```

Measured 2026-09-09 21:20 EDT: container said `2026-09-10`, local said `2026-09-09`.
Outside that window both agree, which is exactly why it hides.

*Why it is latent and not live:* `DiaryView.tsx:130` computes `entryDay`/`entryTime`
from the browser clock, and `_run_exchange` (`app.py:399`) prefers them. The real
write path is therefore correct. Seven server-side sites use `datetime.now()` as the
**fallback**, and each is wrong by a day in that window:

| Site | What it decides |
| --- | --- |
| `app.py:399` | `now = entry_time or datetime.now()` — the day an entry is filed under |
| `app.py:517` | `api_day` with no month — which day "today's log" means |
| `app.py:626`, `:633` | file-date fallback |
| `pipeline.py:134`, `:159` | logging and re-log timestamps |
| `corpus.py:75` | the `### HH:MM` header itself — would read `01:20`, not `21:20` |

*The fix, and why it is this one:* set `TZ` on the diary container from a
user-configured timezone, so every fallback is already right. Auditing seven call
sites to thread a timezone through is the version that rots — a new `datetime.now()`
added later silently reintroduces the bug. Fixing the environment cannot be
forgotten by the next contributor.

Concretely: a `TZ` build/runtime var on the diary service in all three compose
copies; the timezone collected in the wizard's prefs step (Workstream 3, point 4,
which already proposes asking for it); a test that pins a fallback to the configured
zone rather than to the host's. `journal.py:76` and `:90` must **stay UTC** — those
are event timestamps, not diary dates, and UTC is correct for them.

*Related, and outstanding:* after the aux-model fix (`changelog.md`, 2026-09-09) a
new entry should render as `### HH:MM — Topic` rather than a bare `### HH:MM`. That
has not been observed yet — it needs a real diary write, which is the user's to
make. If topics are still missing on the next entry, the summariser is still not
running and the aux fix did not take.

**6b. Read prior entries as plain files, not through a retrieval index.** Cowork
uses `cat`/`grep` over the day files directly. noevia already has the equivalent in
`workspace_files.file_list` / `read_file`, exposed as `/api/diary/files`. The gap is
that the *diary companion model* reaches its own corpus only through the embedding
index — which currently fails open (`embedding failed for a chunk … will retry on
next reindex`, see `changelog.md`), leaving recent entries unreachable as context.
A direct file read is the honest fallback when retrieval has not caught up.

Implemented 2026-09-10: bounded direct reads when retrieval is absent, empty or
fails, using existing tenant storage and explicit reference framing. Two explicit
past ISO dates plus three preceding dates by default; no exhaustive search claim.
166 diary / 281 web tests, typecheck/build pass. Deployed as `23ba691`.

**6c. One memory store, not two kept in sync by hand.** Cowork's clearest warning:
`project_memory_*` lives on Claude's side and *"does NOT automatically sync to the
AI Memory folder on your actual disk — Two different stores, same content kept in
sync by hand."* Roadmap 4a proposes scaffolding `AI Memory/`. **Decide now that the
folder on disk is the only store.** If noevia later grows session-side memory, it
must read and write that folder, not shadow it.

**6d. Keep diary content out of any cross-session profile.** Cowork explicitly
refuses to write diary content into its broader user-profile memory: *"grief/safety
content from here has no business living in it."* noevia has no such store today.
If one is ever added, this boundary is the requirement, not a preference.

### What does NOT port

Shell-out-to-`bash` as the write mechanism. Cowork can afford it because it is
driving one user's Mac interactively. noevia is multi-tenant, writes through a
journal + ETag-guarded store precisely so a crash cannot corrupt the corpus, and
generates structure mechanically in `corpus.py`. A heredoc append would bypass all
of that. **The model must never write diary structure directly** — see `diary.md`.

---

## Workstream 7 — Self-contained storage when there is no cloud

Today `CORPUS_BACKEND` defaults to `local`, with `CORPUS_LOCAL_ROOT=/app/data/corpus`
bind-mounted from `${COWORK_STATE_DIR:-./state}/diary`. So "everything lives in the
container" already technically works. Three things make it unsatisfying in practice.

**7a. The `./state` default is a footgun on Unraid.** `${COWORK_STATE_DIR:-./state}`
resolves relative to the compose project directory. Under Compose Manager that is
`/boot/config/plugins/compose.manager/projects/Cowork` — **the USB boot flash**:
small, wear-sensitive, and not meant for live data. The live deployment sets
`COWORK_STATE_DIR=/mnt/docker/appdata/cowork/state` so it is fine *there*, but the
default is wrong for the platform the deploy examples target. Either default to a
named Docker volume (which Docker allocates and manages, and which never lands on
the flash) or refuse to start when the resolved path is under `/boot`.

**7b. Local files are unreachable from anywhere else.** The reason WebDAV/Nextcloud
is attractive is not storage — it is *access*: phone, laptop, file manager. A local
corpus is a directory on the server with no way in. The in-app Markdown
viewer/editor (`diary.md`) is the only door, and there is no sync client.

Options, roughly in order of effort:

1. **Expose the corpus over the app's own WebDAV endpoint.** noevia already speaks
   WebDAV as a *client* (`storage-client.cjs`, `webdav.py`); serving it is the
   mirror image. Any OS can mount it, including Nextcloud's own external-storage
   connector — which is how a local corpus becomes reachable without running
   Nextcloud at all.
2. **A share sidecar** — Samba or a WebDAV server container mounting the same
   volume. No app changes, but a second service and its own auth surface.
3. **Export/import in the UI** — a zip download and upload. Cheapest, and much
   weaker: not a live path, just a manual escape hatch.

Option 1 is the one that makes "local" a real peer of the cloud backends rather
than a lesser default. It also reuses the tenant-scoped path validation and
conditional-write guards the proxy routes already have.

**7c. The wizard makes the choice, and names the trade-off.** The storage step
currently lists Local / Nextcloud / WebDAV / S3 as if they were equivalent. They are
not — today "local" means "reachable only through this app." See Workstream 3 for
the reworked step; the short version is two real choices (noevia hosts it / connect
storage you already run), with the access consequence stated on each.

**ANSWERED 2026-09-09 — appliance, but opt-in.** noevia owns and serves its own
data *when the user chooses that*. It is an option, never a requirement, and the
choice is made during onboarding rather than in a config file. So: **option 1**.
Options 2 and 3 are not pursued — a share sidecar is a second service with its own
auth surface, and zip export is an escape hatch, not a storage mode.

### 7d. What "serves its own data" means concretely

- **A WebDAV endpoint noevia itself serves**, per user, tenant-scoped — the mirror
  image of the WebDAV *client* already in `storage-client.cjs` / `webdav.py`.
  Any OS can mount it; so can Nextcloud's external-storage connector, which is how
  someone keeps Nextcloud in the picture without noevia depending on it.
- **It must sit on top of the existing diary file API, not read the volume
  directly.** `/api/diary/files` and `/api/diary/file` already carry tenant scoping,
  relative-path validation, size limits and conditional writes; the journal and the
  ETag guard are what keep a crash from corrupting the corpus. A DAV layer that
  opens the files itself bypasses all of it. This is the same prohibition as
  Workstream 6's "no shell heredocs" — the corpus has exactly one write path.
- **Auth needs app passwords, not the session cookie.** WebDAV clients do not do
  cookie sessions or passkeys, and `LEGACY_AUTH_COMPAT=false` removed the bearer
  path deliberately. This wants per-device generated credentials, revocable
  individually, shown once — the model Nextcloud itself uses, and the same shape as
  the existing passkey list in Settings → Profile and security.
- **Which container serves it.** The web container: it is the only one that is
  supposed to be publicly reachable. The diary sidecar stays internal, per
  `SECURITY.md`. That reinforces the point above — the web container reaches the
  corpus through the diary API, so DAV naturally inherits the guarded path.
- **Off by default, and it widens the attack surface.** A new authenticated write
  surface reachable from outside needs its own section in `SECURITY.md`, its own
  rate limiting, and to stay disabled unless the user turned it on in setup.

### 7f-pre. The reference design: what Nextcloud does

noevia is copying a model that already works, so it is worth stating plainly. Four
pieces:

1. **Nextcloud does not do HTTPS itself.** It assumes a reverse proxy in front
   terminating TLS. "How do I get a certificate" is deliberately not its problem.
   noevia already takes the same posture, and should keep taking it — see 7h.
2. **The WebDAV URL is derived and shown, never asked for**:
   `https://<host>/remote.php/dav/files/<username>/`, where `<host>` comes from its
   `trusted_domains` list. That list is the direct analogue of noevia's
   `PUBLIC_ORIGIN` plus `ADDITIONAL_TRUSTED_ORIGINS`.
3. **App passwords.** WebDAV authenticates with HTTP Basic, meaning the credential
   is sent **on every single request**. So Nextcloud has you generate a long random
   per-device token in Settings → Security, shown once, pasted into the file client
   instead of the account password. Three reasons, all of which apply here equally:
   the real password never lands on the device; a lost device means revoking one
   token rather than changing the account password; and it is the only way a file
   client can authenticate at all when 2FA is on, since it cannot answer a 2FA
   prompt. Each token carries a name and a last-used timestamp and is revocable on
   its own.
4. **It warns rather than blocks.** An admin "Security & setup warnings" panel goes
   red on plain http or a misconfigured proxy. It does not prevent you running that
   way; it keeps telling you.

**noevia already has three of the four.** `PUBLIC_ORIGIN` is the trusted-domain
list; TLS is already the operator's job; Settings → Profile and security already
lists and revokes passkeys, which is the same shape a token list needs. The missing
piece is the tokens themselves, and the warning surface.

**A design constraint that follows from this.** The wizard must not ask the operator
to make a security judgement they are not equipped to make. Every choice should
default to the closed option, state its consequence in one plain sentence, and never
present an option whose wrong answer is silently dangerous. Where a real risk cannot
be removed — plain http on a LAN, say — name it in words a non-specialist can act
on, and record the acknowledgement, the way Nextcloud's warnings panel does.

### 7f. The endpoint URL — derive it, do not ask twice

**Nextcloud does not ask you for a WebDAV URL; it shows you one**
(`https://host/remote.php/dav/files/<user>/`), derived from its configured trusted
domain. noevia should do the same, because the wizard **already collects and
validates exactly that value**: the account step's canonical-URL field, checked by
`classifyOrigin()` into `public-https` / `loopback` / `private-lan-http` /
`invalid`. Asking a second time invites the two answers to disagree, and a DAV URL
that disagrees with `PUBLIC_ORIGIN` is a mount that silently fails.

So: the mount URL is `<PUBLIC_ORIGIN>/dav/<user>/`, displayed at the end of setup
with the generated app password. Offer an override field for split-horizon
deployments (a separate hostname for DAV, or DAV kept LAN-only while the app is
public), pre-filled from `PUBLIC_ORIGIN` and empty-means-inherit — never a second
mandatory question.

**HTTPS is required on the public path** — app passwords ride in a header on every
request with no session protecting them. But "block plain http outright" would kill
the ordinary homelab case, so the requirement is scoped to *reach*, not to DAV as a
whole. See 7h.

### 7i. App passwords — the piece noevia does not have yet

Of Nextcloud's four pieces (7f-pre), this is the only one with no existing analogue.
It is a prerequisite for DAV at any scope, so it is the first thing built in this
workstream, not the last.

**Why a token and not the account password.** WebDAV authenticates with HTTP Basic:
the credential is sent on *every request*, sitting in a file client's config on
every device. So the account password must never be the thing that is stored there.

**Shape** — deliberately the same as the passkey list already in Settings →
Profile and security, which is the closest existing thing:

- Generated server-side, high entropy, **displayed once** at creation and never
  retrievable again. Stored as a hash, like the account password
  (`auth.cjs` already uses Argon2id — reuse it, do not invent a second scheme).
- Carries a **name** ("laptop", "phone"), a **created** date, and a **last used**
  timestamp so a stale one is visible.
- **Revocable individually**, without touching the account password or any other
  device.
- **Scoped** to the access level it was minted under (7h). A LAN-scoped credential
  is refused on the public origin — defence in depth if the port is later exposed.
- **Never grants app login.** A DAV token authenticates DAV and nothing else; it
  must not be accepted at `/api/auth/*` or on any chat route. This is the difference
  between "a device can read my diary files" and "a device can act as me."

**Cross-checks against what already exists:**

- `LEGACY_AUTH_COMPAT=false` removed the general bearer-token path on purpose.
  This does not reinstate it: tokens are accepted only on the DAV port, only via
  Basic, only for corpus paths.
- Rate-limit failed DAV auth the way `llm-rate-limit` and the login limiter
  already do, and audit token creation and revocation through
  `authService.audit()` alongside logins and tool writes.
- Invited users get their own tokens; a token is per-user, never per-deployment.

### 7h. Three access scopes, chosen in the wizard

Exposure is a separate question from "do you want DAV at all", and the answer is not
binary. The storage step asks it as three choices:

| Scope | What it means | Transport |
| --- | --- | --- |
| **Off** (default) | Files reachable only through the app's own Markdown editor | n/a |
| **This network only** | Mountable from devices on the LAN; never leaves it | plain http allowed with an explicit acknowledgement; HTTPS if the operator fronts it |
| **Reachable from anywhere** | Mountable over the public origin | HTTPS enforced, no exception |

**Serve DAV on its own container port**, not a path on the public one. Compose
publishes exactly one port today (`${COWORK_PORT:-8021}:8021`); DAV gets a second.
Exposing a second port is then a deliberate act by the operator in whatever sits in
front — adding a hostname in a tunnel dashboard, a `location` block in nginx, a
port-forward. Doing nothing leaves it LAN-only.

**But noevia cannot verify that, and must not claim to.** Whether a port is
reachable from the internet depends entirely on infrastructure noevia has no view
of. Promising "LAN only" as though it were enforced would be a lie the user relies
on. The wizard should say what it actually means: *noevia serves this on port N and
does not publish it; if you have not deliberately exposed port N, it stays on your
network.*

An IP allowlist was considered and rejected. With `TRUST_PROXY=true` the client
address is read from `x-forwarded-for`, a caller-supplied header, so the allowlist
would be exactly as trustworthy as that header — security theatre, and worse than
honest wording because it *looks* like enforcement.

**Plain http is permitted on the LAN scope, with the trade-off stated.** It is not
safe — an app password crosses the LAN in cleartext, readable by anything else on
that network — but it is the difference between a usable feature and one nobody can
turn on. Say that in one sentence and require an explicit acknowledgement, the way
the account step already handles a `private-lan-http` origin instead of refusing it.

**HTTPS on the LAN scope is the operator's to provide, not noevia's.** A reverse
proxy with an internal CA, Caddy, Traefik, or Tailscale all work. noevia should
accept an override URL for that case and otherwise stay out of certificate
issuance — `ADDITIONAL_TRUSTED_ORIGINS` (already in `index.cjs:66` and
`compose.yaml:62`) is the existing seam for keeping a LAN name valid alongside the
public one.

**App passwords carry their scope.** A credential minted for LAN-only use records
that and is refused on the public origin. Defence in depth: if the port is later
routed publicly by mistake, existing LAN credentials do not silently become
internet-facing ones.

### 7g. Verified: a reverse proxy does not eat WebDAV verbs

WebDAV uses HTTP methods most proxies never see — `PROPFIND`, `MKCOL`, `MOVE`,
`LOCK`, `REPORT`. The standing worry is that whatever sits in front of noevia drops
them and the whole feature is unusable from outside.

Measured on one deployment (a Cloudflare tunnel, 2026-09-09) against a direct-to-
origin control:

| Method | through the proxy | direct to origin |
| --- | --- | --- |
| `GET` | 200 | 200 |
| `HEAD`, `OPTIONS`, `PROPFIND`, `MKCOL`, `LOCK`, `REPORT` | 404 | 404 |

Identical, so that proxy forwards them untouched and the 404s are **noevia's own
router**, which matches on `req.method === 'GET'` / `'POST'` and nothing else.

**This is evidence from one setup, not a design assumption.** noevia must not
require, detect, or special-case any particular proxy — operators run nginx, Caddy,
Traefik, Tailscale, a plain port-forward, or nothing at all. What the measurement
buys is confidence that the approach is sound in at least one common arrangement,
and a concrete failure mode to document: if a DAV client cannot mount, the first
thing to check is whether the proxy in front passes `PROPFIND`. Some do not by
default, and that is the operator's configuration to fix, not noevia's to work
around.

Two consequences for the build, neither proxy-specific:

- **`OPTIONS` and `HEAD` need real handling before anything else works.** Every DAV
  client opens with `OPTIONS` to read the `DAV:` capability header, and uses `HEAD`
  for cheap existence checks. Both currently 404 on *all* routes — a small wart
  worth fixing regardless of this workstream.
- **Proxies impose their own request-body limits** (Cloudflare's free tier caps at
  100 MB; nginx defaults to 1 MB via `client_max_body_size`). Diary Markdown is
  nowhere near either, but it caps what the corpus accepts from outside, so it
  belongs in the docs rather than being found by a failed upload.

### 7h. Three access scopes, chosen in the wizard

Exposure is a separate question from "do you want DAV at all", and the answer is not
binary. The storage step asks it as three choices:

| Scope | What it means | Transport |
| --- | --- | --- |
| **Off** (default) | Files reachable only through the app's own Markdown editor | n/a |
| **This network only** | Mountable from devices on the LAN; never leaves it | plain http allowed with an explicit acknowledgement; HTTPS if the operator fronts it |
| **Reachable from anywhere** | Mountable over the public origin | HTTPS enforced, no exception |

**Serve DAV on its own container port**, not a path on the public one. Compose
publishes exactly one port today (`${COWORK_PORT:-8021}:8021`); DAV gets a second.
Exposing a second port is then a deliberate act by the operator in whatever sits in
front — adding a hostname in a tunnel dashboard, a `location` block in nginx, a
port-forward. Doing nothing leaves it LAN-only.

**But noevia cannot verify that, and must not claim to.** Whether a port is
reachable from the internet depends entirely on infrastructure noevia has no view
of. Promising "LAN only" as though it were enforced would be a lie the user relies
on. The wizard should say what it actually means: *noevia serves this on port N and
does not publish it; if you have not deliberately exposed port N, it stays on your
network.*

An IP allowlist was considered and rejected. With `TRUST_PROXY=true` the client
address is read from `x-forwarded-for`, a caller-supplied header, so the allowlist
would be exactly as trustworthy as that header — security theatre, and worse than
honest wording because it *looks* like enforcement.

**Plain http is permitted on the LAN scope, with the trade-off stated.** It is not
safe — an app password crosses the LAN in cleartext, readable by anything else on
that network — but it is the difference between a usable feature and one nobody can
turn on. Say that in one sentence and require an explicit acknowledgement, the way
the account step already handles a `private-lan-http` origin instead of refusing it.

**HTTPS on the LAN scope is the operator's to provide, not noevia's.** A reverse
proxy with an internal CA, Caddy, Traefik, or Tailscale all work. noevia should
accept an override URL for that case and otherwise stay out of certificate
issuance — `ADDITIONAL_TRUSTED_ORIGINS` (already in `index.cjs:66` and
`compose.yaml:62`) is the existing seam for keeping a LAN name valid alongside the
public one.

**App passwords carry their scope.** A credential minted for LAN-only use records
that and is refused on the public origin. Defence in depth: if the port is later
routed publicly by mistake, existing LAN credentials do not silently become
internet-facing ones.

### 7g. Verified: Cloudflare Tunnel passes WebDAV verbs

The obvious risk with the current deployment — app on a Cloudflare tunnel — was
that Cloudflare would drop WebDAV's non-standard methods and make the whole
appliance path unworkable from outside. **It does not.** Measured 2026-09-09
against the live tunnel and, as a control, straight at the origin:

| Method | via Cloudflare | direct to origin |
| --- | --- | --- |
| `GET` | 200 | 200 |
| `HEAD`, `OPTIONS`, `PROPFIND`, `MKCOL`, `LOCK`, `REPORT` | 404 | 404 |

Identical either way. The 404s are **noevia's own router**, which matches on
`req.method === 'GET'` / `'POST'` and nothing else — Cloudflare is forwarding the
verbs untouched. So the tunnel is not a blocker, and no Cloudflare configuration
change is needed. (No Cloudflare Access sits in front either; if one is ever added,
DAV clients cannot complete its browser SSO flow and would need service tokens.)

Two consequences for the build:

- **`OPTIONS` and `HEAD` need real handling before anything else works.** Every DAV
  client starts with `OPTIONS` to read the `DAV:` capability header, and `HEAD` for
  cheap existence checks. Both currently 404 on *all* routes, which is also a small
  standalone wart worth fixing regardless of this workstream.
- **Cloudflare's free tier caps request bodies at 100 MB.** Diary Markdown is
  nowhere near it, but it caps what the corpus can accept from outside, so it
  belongs in the docs rather than being discovered by a failed upload.

### 7e. Where the corpus actually lives

With the appliance answer, the default should be a **named Docker volume** rather
than a bind mount: Docker allocates and manages it, it survives recreation, and it
cannot silently land on the Unraid boot flash the way `./state` does (7a). A bind
mount stays supported for operators who want the files at a known host path — which
is what the live deployment already does with
`COWORK_STATE_DIR=/mnt/docker/appdata/cowork/state`.

---

## Workstream 8 — PDFs, OCR, and image understanding

**Implemented, 2026-09-10:** native page extraction and originals, source status,
binary reads, bounded local OCR for scans/mixed pages, asynchronous source polling,
and image missing-file/truncation/cache fixes. The matching Qwen 9B projector is
configured and real synthetic transcription passed. See the latest
[roadmap audit](roadmap-audit.md) and [document understanding spec](spec-document-understanding.md)
for exact bounds and verification. Existing sources need refresh/re-upload to gain
OCR; native-only cached versions are invalidated. Handwriting and general table
reconstruction are not promised. Onboarding and diary navigation remain open.

The original investigation checklist follows for context:

1. **Audit the end-to-end experience.** Use synthetic or explicitly approved
   fixtures: text PDFs, scanned PDFs, mixed text/image pages, tables, screenshots,
   and photos. Check upload and folder refresh, extraction, retrieval, and the
   answering model. Record whether failures come from extraction, missing image
   capability, routing, or retrieval rather than treating all of them as OCR bugs.
2. **Specify PDF and OCR behavior.** Decide when to use a text layer, when OCR is
   needed (including mixed PDFs), and how to preserve page references, reading
   order, and useful table structure. Define handling for encrypted, malformed,
   oversized, partially readable, and truncated documents. Preserve original files;
   distinguish originals from derived text and avoid duplicate extraction on refresh.
3. **Specify image behavior.** Clarify when an image is sent directly to a capable
   model versus described by the configured vision model. Cover image-only PDFs,
   multiple images, unavailable models, and the difference between extracting text
   and understanding a picture. Make unsupported or failed processing visible.
4. **Evaluate implementation options.** Compare local OCR/vision choices against
   actual host resources, accuracy, latency, maintenance, and privacy requirements.
   Decide processing limits, caching, and whether long documents need background
   work. Do not add a runtime dependency or cloud processing by assumption.
5. **Make source state understandable.** Plan clear queued/processing/ready/failed
   states where needed, useful retry actions, and page/source attribution. An upload
   succeeding must not imply the model can read every page or image.

Deliverable: a short findings/spec document with recommended scope, open decisions,
and a fixture-based acceptance matrix before implementation. Test with known text
and page references; failures must be explicit, existing PDF text extraction must
stay working, and files must remain isolated to their owning user/project. Do not
use the real diary corpus as a test dataset or send diary prompts.

## Workstream 9 — Skills and reusable project workflows

**Proposal complete; implementation planned.** The user selected reusable instructions
using existing approved tools. See [the scoped proposal](spec-instruction-skills.md)
for lifecycle, context/permission boundaries and a representative workflow.

Start by agreeing what a skill means in noevia: reusable instructions, a workflow
that uses existing tools, or an executable package. Inventory project instructions,
toolboxes, MCP discovery, and the approval gate first. Coordinate with Workstream 5
so skills do not create a second competing system for tool selection.

Questions to resolve:

- How are skills created/imported, inspected, enabled, updated, and removed?
- Are they personal or shared, and selected per project, per chat, or automatically?
- How do skill instructions interact with project instructions and context limits?
- What formats are supported, and what compatibility is actually needed?
- If a skill requires tools or dependencies, how are those requirements surfaced?
- How does a user see which skill ran, what it did, and why it failed?

Deliverable: a scoped proposal and one representative workflow, followed by an
implementation plan. Skills must preserve tenant isolation and the existing write
approval gate; importing instructions must not silently grant execution or tool
permissions. Framework, package, and execution choices remain open decisions for
the proposal.

## Sequencing

The [audited priority order](roadmap-audit.md#corrected-priority-order) supersedes
this original sequence. Completed items below are retained for historical context;
consult the audit before treating any of them as new work.

1. Workstream 1 — hours, unblocks agent-driven deploys immediately.
2. Workstream 4c — one function, highest felt improvement per line changed.
3. Workstream 3 — wizard restructure.
4. Workstream 2 — thinking modes (touches the chat hot path; do it with the wizard's
   prefs step landed so it has a home).
5. Workstream 4a/4b/4d — the diary rebuild.
6. Workstream 5a (duplicate tool-call guard) — small, standalone, do it early;
   it is a bug fix, not a spike.
7. Workstream 5d (offline Wikipedia toolbox) — additive, no new machinery.
8. Workstream 6a (container `TZ`) — small and self-contained; do it early, before
   a client that omits the entry stamp makes it a live bug instead of a latent one.
9. Workstream 7a (`./state` default) — one line, and it currently points at the
   Unraid boot flash for anyone following the deploy examples.
10. Workstream 7e (named volume as the default corpus location) — with 7a, since
    both are about where state lands.
11. Workstream 7i (app passwords) — a prerequisite for DAV at any scope, and
    independently useful. Build it first within Workstream 7.
12. Workstream 7d (noevia's own WebDAV endpoint) + the Workstream 3 storage step —
    the appliance path. Biggest single item here: a new authenticated, externally
    reachable write surface, app-password auth, and a `SECURITY.md` section. Spec
    it first, the way `spec-reasoning-effort.md` was specced.
13. Workstream 5 proper + 5c + 6b — research spikes; a `docs/spec-*.md`, not code.

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


2026-09-10 upload follow-up: unified file uploads, grouped storage/UI, stored-only
opaque documents including DOCX, migration of earlier local image uploads on
refresh, transfer/processing progress, and image preparation status are implemented.
No DOCX reader, archive extractor, or other subsequent roadmap feature is implied.

2026-09-10 live audit follow-up: legacy migration now has one durable owner, and
image replacement retires obsolete vision input when the new original is stored
only. Actual server checks covered OCR, embeddings, Nextcloud approval actions,
and isolated diary capture. See [coverage and remaining concerns](live-audit-2026-09-10.md).

Account cleanup from that audit also fixed administrator deletion after issuing
invitations and protection of the last active administrator when other admins are
disabled. Issued tokens are revoked atomically; audit history is retained.

Composer follow-up: chat model selection now lives inside the text composer next
to Send instead of in the top bar. A future thinking-effort control should sit
beside it, using the reasoning behavior specified above; this placement change
does not implement or claim model support for thinking settings.

The same model control and composer layout now cover project landing pages and
Diary landing/day views as well as free/project chats. Diary shows its fixed
companion by default; only opt-in extras expose the optional context model picker.
Coding's preview already places its disabled model control beside its send action.
