# 7. Provider / authentication architecture (draft for review)

## 7.1 Today

- `providers.cjs`: `{ id, label, baseUrl, apiKey?, defaultModel?, shared? }`; every provider is an
  OpenAI-compatible HTTP endpoint with an optional bearer key.
- `chat.cjs` builds the URL and headers inline. MCP servers already have a real OAuth 2.1 + PKCE
  client (`mcp-oauth.cjs`), which could be reused.
- There is no notion of billing class, locality or capability.

## 7.2 Target structure

```
server/generation/
  index.cjs            registry + capability lookup; the only thing chat/code call
  local-llamacpp.cjs   router-mode llama.cpp (wraps llamacpp-manager; logprobs, rerank, slots)
  openai-compatible.cjs  any OpenAI-shaped endpoint (OpenRouter, vLLM, LM Studio, Ollama, DeepSeek, Z.ai API, Qwen Model Studio)
  anthropic.cjs        Messages API (API key only — doc 8)
  google.cjs           Gemini API (API key or OAuth to the user's own Cloud project)
server/auth-providers/
  none.cjs  api-key.cjs  oauth-pkce.cjs  (reuses mcp-oauth.cjs internals)
server/harnesses/      (Code mode; doc 8 "Tier 4")
  opencode.cjs  claude-code.cjs  codex.cjs           — deferred by the user
```

`generation/*` adapters implement one interface and never see how the credential was obtained:

```js
{ id, kind: 'local'|'remote',
  describe() → { models: [{ id, ctx, vision, tools, reasoning, logprobs, rerank }] },
  async chat({ model, messages, tools, stream, effort, signal }) → stream of normalised events,
  async decide?(req)   // optional: logprob-capable adapters can back the decision layer (doc 4)
  async rerank?(q, docs) }
```

## 7.3 Provider record (what is stored)

```js
{ id, label, adapter: 'openai-compatible'|'anthropic'|'google'|'local-llamacpp',
  baseUrl?, auth: { kind: 'none'|'api-key'|'oauth-pkce', ref: '<secret id in the existing encrypted store>' },
  billing: 'local'|'free-quota'|'metered',        // declared, shown in the UI; never inferred
  costClass: 'LOCAL'|'FREE_QUOTA'|'METERED_LOW'|'METERED_HIGH',
  prices?: { inPerM, outPerM, currency, source, checkedAt },
  owner: 'shared'|userId, locality: 'local'|'lan'|'internet' }
```

- There is no `billing: 'subscription'` on a chat provider. Doc 8 shows no provider legitimately
  offers it to third-party apps. `SUBSCRIPTION_INCLUDED` exists only on Code-mode harnesses.
- **Only supported combinations can be created.** For example, `anthropic` + `oauth-pkce` is
  rejected with the reason and a link to the terms.

## 7.4 Cost classes and routing

| Class | Examples | Allowed by policy level |
|---|---|---|
| `LOCAL` | llama.cpp on this machine or LAN | always |
| `SUBSCRIPTION_INCLUDED` | Claude Code / Codex harness signed in by the user (Code mode only) | "Local + subscription" and above |
| `FREE_QUOTA` | Gemini API free tier | "Allow inexpensive APIs" and above |
| `METERED_LOW` / `METERED_HIGH` | OpenRouter, DeepSeek, Anthropic API, OpenAI API | "Allow inexpensive" (low) / "Allow all" (high) |

**User policy** (account default; the project can only tighten it, never loosen it):

- `Local only`
- `Prefer local`
- `Local + subscription providers`
- `Allow inexpensive APIs`
- `Allow all configured providers`

Plus a per-project `cloud_allowed=false` that overrides everything.

**Metered spend is never silent:**
- every metered call is shown in the chat ("Used OpenRouter · ~$0.004");
- it is recorded in `usage.cjs` with its cost;
- it is bounded by a per-user monthly cap. Reaching the cap degrades to local, with a notice.

**When a subscription hits its limit** (Code mode): the harness reports it, and noevia shows it
and offers the next allowed tier. It never silently switches to metered.

## 7.5 Escalation path (local-first)

```
local S1 decides → local S2 (fast) → S1 evaluate → retry / local S2 (smart / code) → S1 evaluate
   → [policy allows?] Code mode: subscription harness  |  Chat: metered provider (cheapest that fits)
   → otherwise: return the best local answer + say what was not possible, or ask the user
```

Escalation triggers:
- local confidence inadequate *after* local retries;
- a missing local capability (for example vision, when no local vision model exists);
- the user explicitly chose a remote model;
- context too large for any local model.

"Remote is simpler" is never a trigger.

## 7.6 Degradation (the "no internet" test)

Every remote adapter is optional. With all of them removed, noevia still runs chat, RAG, tools,
Code mode (OpenCode on the local engine), the Diary and decisions, because the decision layer's
floor is the heuristic and the generation floor is local. The only loss is the tasks the evaluator
could not pass locally, which are then answered with an explicit "best local answer" notice.
