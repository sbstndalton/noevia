# 1. Current noevia architecture map

Read from the source on 2026-09-21 (`main` at `860316b`, live release `067ac1d`). File references
are to `apps/web/server/` unless stated. This describes what the code does, not what older roadmap
text says it does.

## Request path for one chat message

`POST /api/chat` → `routes/chat.cjs` → `chat.cjs` `handleChat` (687 lines), which in order:

1. **Resolves the space and project.** Diary chats are proxied whole to the Diary companion
   (`services/diary`, Python) and leave this path. Project mode gate: `project-modes.cjs`.
2. **Builds the system prompt** from account instructions (`account-instructions.cjs`), account and
   project memory (`account-memory.cjs`), project goal/instructions, knowledge files
   (`rag.filesContext`), the skills index (`skill-index.cjs`), shared Code context
   (`shared-context.cjs`, new today) and diary extras.
3. **Loads at most one skill body** by embedding similarity (`chat-skill-routing.cjs`).
4. **Chooses the model** (see "Model selection" below).
5. **Resolves tools** from the project's toolboxes, narrowed by embedding similarity
   (`chat-tool-routing.cjs` → `tool-router.cjs`), capped by count and by a prefill-time token
   budget (`toolboxes.cjs`, `prefill.cjs`).
6. **Runs a vision pass** for attached images when the model cannot see (`visionProbe`).
7. **Prepares and, if needed, compacts context** (`chat-context.cjs`): measures tokens against the
   runtime context limit, summarises older turns with the same model when over threshold.
8. **Streams up to three tool rounds** against an OpenAI-compatible `/v1/chat/completions`
   endpoint. Each tool call passes the deterministic policy (`toolPolicy`, `isWriteTool`,
   approvals with the three actions approve / deny / approve_all, per chat), executes
   (`executeToolCall`, MCP via `mcp-wiring.cjs`), and its result is reduced
   (`tool-result-reduce.cjs`) before the next round.
9. **Records usage** (`usage.cjs`); the browser then saves the transcript
   (`POST /api/chats/:id/history`, `routes/chat-lists.cjs`).

## Providers and models

- **Providers** (`providers.cjs`, `routes/providers.cjs`): a registry of OpenAI-compatible endpoints,
  each `{ id, label, baseUrl, apiKey?, defaultModel?, shared? }`. Auth is one optional bearer
  key. There is no provider-type abstraction: every provider is assumed to speak the OpenAI chat
  API. Member-registered endpoints pass the SSRF policy (`ssrf.cjs` `createEndpointApproved`).
- **Default provider** is the local engine: native llama.cpp in router mode (`llamacpp-manager.cjs`),
  which loads and unloads GGUF models on request (`/models/load`, `/models/unload`,
  `makeRoomFor`), reads presets from `models.ini` (`llamacpp-presets.cjs`), and sizes them from
  GGUF headers and host memory (`llamacpp-autoconfig.cjs`, `gguf-meta.cjs`, calibration and
  auto-tune modules).
- **Embeddings** come from a separate embedding endpoint (`EMBEDDING_BASE_URL`; `rag.embed`).
- **Model selection** in `chat.cjs`:
  - project model if set; else
  - if the project's `routing === 'auto'` and it uses the default provider, the **auto router**
    (`auto-router.cjs`) picks a role — `fast`, `smart` or (when configured) `code` — whose model
    names come from `autoRoles()` (`models.cjs`); else
  - whatever the model manager reports as last loaded.
- **Reasoning effort** (`reasoning-effort.cjs`): project → admin default; a capability table says
  which provider/model combinations accept which effort parameter.

## Retrieval (RAG)

`rag.cjs` (333 lines): per project and per user, a sqlite-vec index of 1,200-char chunks
(150-char stride). Query: embed the message, cosine top-**6** with score ≥ **0.3**. Files at or
under 2,400 chars are injected whole; larger files contribute retrieved excerpts; on any failure,
large files are pasted verbatim up to 24,000 chars. **No reranking stage.** Documents are extracted
by Docling (`docling.cjs`) or the built-in PDF walk and OCR (`documents.cjs`).

## Tools

- Built-in boxes, MCP servers (`mcp-servers.cjs`, `mcp-wiring.cjs`, `mcp-oauth.cjs` with OAuth
  2.1 + PKCE for MCP), the curated box manifest (`mcp-toolbox-manifest.cjs`, 24 boxes), Kiwix,
  Google Drive.
- Selection: project selection (user-chosen boxes) → embedding narrowing (only removes, never
  adds; gated by `features.toolRouter`) → count cap (12 for ≤12B by name, else 24) → token budget
  (5,000 / 8,000, adjusted by measured prefill rate).
- Authority is deterministic: `toolPolicy` (Allow / Ask / Block per tool), `isWriteTool`,
  approvals in memory per request, write tools always ask unless the user chose approve_all for
  that chat.

## Session and state

| State | Where | Durable? |
|---|---|---|
| Transcript | browser, saved via `/api/chats/:id/history` after the reply | yes, after the turn |
| Compaction summary + context meter | `chat-context.cjs` per chat file | yes |
| In-flight tool loop (rounds, pending results) | `chat.cjs` locals | **no** |
| Pending approvals | memory (`approvals.cjs`) | no, by design (a restart must re-ask) |
| Project config, memories, skills | per-user `projects.json` + files | yes |
| Code tasks | `jobs.cjs` event journal + `code-workspace.cjs` worktrees, with `recover()` | yes |
| Deep research runs | `jobs.cjs` | yes |
| Diary exchanges | companion journal (`diary-jobs.cjs`) | yes |

So a **Code task** and a **research run** survive a process or model death; a **chat turn** does
not — its partial reply and tool rounds live only in the request.

## Code mode

`code-service.cjs` → `code-harness.cjs` → ACP (`code-acp.cjs`) → an OpenCode agent in the
`code-sandbox` container, with every action classified deterministically (`code-actions.cjs`) and
asked, egress only through `code-egress.cjs`, worktrees in `code-workspace.cjs`. Prompt
preparation modes exist (`PROMPT_PREPARATION`: direct, local architect, frontier architect) but only
Direct is offered: the local architect measured 0 of 18 usable execution prompts.

## Diary companion (Python)

`services/diary/agent/pipeline.py`: a **skip classifier** (LOG/SKIP, fail-open to LOG) on an
auxiliary model, then summarisation. This is another System-One-shaped decision living in a
different language and process.

## Hardware knowledge today

`llamacpp-autoconfig.cjs` reads GGUF metadata and host memory to propose context and offload;
calibration and auto-tune measure real load behaviour. Engine flags on the reference deployment
(`--models-max 2`, Vulkan) live in deployment config, not in code — good. There is no general
capability profile (accelerators, NPUs, free disk) that the rest of the app reads.

## Layering, as it stands

```
routes/*  →  chat.cjs (orchestration, 687 lines, 46 injected deps)
                ├─ decisions: auto-router, chat-tool-routing, chat-skill-routing, rag thresholds,
                │             toolboxes caps, chat-context thresholds, reasoning-effort
                ├─ policy:    toolPolicy, isWriteTool, approvals, ssrf, project-modes, features
                ├─ generation: one OpenAI-compatible fetch per round (no provider abstraction)
                └─ state:     chat-context, usage, (browser-saved transcript)
llamacpp-manager (load/unload) — only the default provider knows about residency
```

The decisions are already small, injected and fail-open, which makes them easy to put behind one
interface. What is missing is (a) that interface, (b) a provider abstraction richer than "OpenAI
URL + key", (c) a server-owned chat turn, and (d) a residency manager that the chat path calls.

## Target architecture (proposed, for review)

```
noevia core (owns: state, retrieval, tools, permissions, orchestration, user data)
│
├── Policy            auth · tenancy · toolPolicy/approvals · cloud policy & spend caps · step/budget caps   [deterministic]
├── Decision          decide() + wrappers; backends: heuristic · llama-logit · llama-rerank · embed · laya · sidecar · jev   (doc 4)
├── Generation        adapters: local-llamacpp · openai-compatible · anthropic · google                   (doc 7)
├── Auth providers    none · api-key · oauth-pkce                                                        (doc 7)
├── Harnesses         opencode (live) · claude-code · codex (deferred)                                   (docs 7, 8)
├── Retrieval         rag.cjs + rerank stage
├── Tools             toolboxes, MCP, egress
├── Session Store     durable turns on jobs.cjs, checkpoints                                             (doc 6)
├── Model Manager     roles, residency, leases, plan/apply, capability profile                          (doc 5)
└── Capability DB     per exact model/runtime config: priors, benchmarks, real outcomes                 (doc 12)
```

A turn under the target design:

```
policy → S1: route (phase, model) → [ModelManager ensureLoaded] → retrieve → S1: rerank → S1: select tools
  → S2 step → tool (policy + approval) → checkpoint
  → S1: evaluate / continue? / still the right model for the next phase?     ← safe boundary
        KEEP_CURRENT │ PRELOAD_NEXT │ CHECKPOINT_AND_SWAP │ HIBERNATE_CURRENT │ RESTORE_PREVIOUS
  → next S2 step (possibly on another model, rebuilt from the checkpoint + handover note) … → answer
  → record outcome to the Capability DB
```

Mid-task model switching (doc 12) is a first-class path through the same boundaries, not a special
case: routing is re-evaluated at every safe boundary where a trigger fires, in both directions
(escalate, de-escalate, specialise, generalise).
