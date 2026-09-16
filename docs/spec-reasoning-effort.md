# Reasoning effort — spec

Moved out of the roadmap on 2026-09-16. V1 is shipped (admin default plus project, free-chat and extras overrides, labelled hints, rejection fallback). Open: verified larger local budgets; uncapped generation is not promised.

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
