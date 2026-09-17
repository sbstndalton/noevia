# Research findings — 2026-09-17

What was measured or learned this session, what it changed, and what is still unknown. Each
finding names its evidence. Numbers come from this deployment (DaServer, native llama.cpp on
Vulkan, integrated GPU with unified memory) unless stated.

## 1. Served models and context caps (D3)

**Question.** The live presets asked for 131K–262K context while only 16K (9B) and 24K (E4B-class)
had ever been verified. Do the proposed caps actually run, and how fast?

**Method.** One cold request per model straight to the engine: a prompt just over the cap, then one
just under it, 16 output tokens.

| Model | Cap | Over cap | Near cap | Wall time | Prefill |
|---|---|---|---|---|---|
| Qwen3.5-4B-Q5_K_M | 24 576 | 26 475 tok → clean 400 | 22 695 tok → 200 | 46.0 s | 503 tok/s |
| Ornith-1.5-9B-Q5_K_M | 16 384 | 17 025 tok → clean 400 | 15 135 tok → 200 | 50.3 s | 309 tok/s |

**Findings.**
- Both caps work and fail cleanly above the limit. A full window costs about 46–50 s of prefill,
  so the practical interactive ceiling is roughly these caps; larger caps would break the 60 s target
  even if memory allowed them.
- `nomic-embed-text-v1` (Q8_0, 146 MB) returns 768-dimension vectors on the same engine.
- The saved Auto roles named two models that no longer existed. Every Auto message would have
  failed upstream. Fixed in data and in code (release 8e4dcd0: 409 with the role named, settings alert).

**Open.** Larger caps were not probed. Evidence: `research-known-good-settings.md` § D3 applied.

## 2. Task-conditional tool loading (roadmap E)

**Question.** Does ranking tools by embedding before the first model call beat sending the whole
selection, without losing completions or approvals?

**Method.** `experiments/tool-routing`, seven synthetic fixtures (reads, a missing tool, injected
content, allowed/denied/chat-wide writes), two repeats, rotated order, Qwen3.5-4B, top-3 at 0.35.

| Mode | Correct | Median | Input tokens | Writes / approvals |
|---|---|---|---|---|
| Send everything | 14/14 | 10.59 s | 12 872 | 6 / 6 |
| Router | 14/14 | 9.72 s | 9 872 | 6 / 6 |

**Findings.**
- The gate passes: equal completion, slightly faster, 23% fewer input tokens. The saving
  concentrates in large catalogues (2 476 → 976 tokens per case); small selections gain nothing.
- Router overhead is ~15–85 ms warm but ~1.3 s when the embedding model must load, which on a
  `--models-max 1` engine would also evict the chat model. The router only pays off where the
  embedding model can stay loaded next to the chat model.
- This contradicts nothing from 2026-09-13: model-driven tool *search* (a discovery round) is
  still slower (12.91 s vs 8.64 s). Ranking before the call is different from asking the model.

**Built.** `chat-tool-routing.cjs`, box-level, narrows only, fails open; `features.toolRouter`, off.
**Open.** n = 2 per fixture; production-shaped measurement (real Nextcloud boxes) not run.

## 3. Deep research gate (roadmap I, spec §8)

**Status: not measured.** The fixture set grew to the spec's size (12 questions, 4 needing project
sources, 2 adversarial pages) and the harness now runs variants A (chat-style), B (pipeline) and
C (pipeline + plan) with production-identical request shape. The run on Ornith-9B was cut off when
DaServer became unreachable (§5). No adoption claim can be made; the feature is on only for
administrators with its budgets.

**Carried forward from earlier:** citation checks prove a claim is *in* a source, not that the
source is honest; injected pages have to be resisted by the model plus framing, and that is only
measurable, not verifiable.

## 4. Interface: Apple HIG and the "generated look"

**Sources.** Apple HIG (via `justinwetch/HIGAgentSkills`, a distilled, source-checked corpus) and
`aka-kika/akakika-skills` (MIT; sidebars, empty states, feedback/status, settings, typography).
Used as checklists, not dependencies.

**Audit (measured from the stylesheets).**
- 33 distinct font sizes including half pixels (12.5, 11.5, 13.5 px …) and nine weights
  (450, 550, 650, 750 …). A small fixed hierarchy is the single clearest HIG rule the app broke,
  and the in-between values are a recognisable generated-UI tell.
- ~200 raw colour literals outside the token file (not yet addressed).
- Repetition: the same page title shown two or three times (bar, heading, first row).
- Double selection cues (fill *and* outline ring).
- Empty states without an action, or with two identical primary buttons on screen.
- Model-facing text shown to people ("ERROR: the user declined this action.").
- Keyboard hints on touch devices; "You" / "Assistant ·" labels restating what bubble position shows.

**Applied (all with QA at phone/desktop, light/dark).**
- Type scale: 13 role tokens (`--text-caption2` … `--text-hero`), four weights, enforced by
  `npm run lint:design`. 475 declarations migrated.
- One selection cue; page title hidden when the page has its own heading; "Mode" row.
- Projects empty and no-match states with exactly one action; "projects" not "workspaces".
- Plain-language tool rows; sender labels only for screen readers; no Enter hint on touch.

**Decision kept.** The user asked for glass across the UI (2026-09-13). HIG's Liquid Glass guidance
puts material on the navigation/control layer, so glass stays there; only redundant cues were
removed, not the material.

**Next.** Colour literals → tokens with a lint rule; status vocabulary (Idle/Running/Waiting/
Failed…) unified across jobs, models and Diary; icon sizes on a scale.

## 5. Operations: DaServer became unreachable

**Observation.** About 20 minutes after enabling `--models-max 2`, downloading a 52 GB ZIM to
the array and running an appdata backup, SSH accepted TCP but timed out in banner exchange, and
the Unraid web UI timed out. The public app kept serving (index 200 in 0.28 s, session 401).
The user suspects the Docker/mover schedule.

**Hypotheses, ranked.**
1. *Memory.* On a unified-memory iGPU, Vulkan allocations (weights + KV cache) come from system RAM
   and are not counted in the container's `mem_limit`. Two chat models plus the embedding model can
   exceed what the 14 GB limit suggests. Earlier the host showed 9 GB available with both loaded;
   a backup, mover and page cache on top may have exhausted it.
2. *I/O.* Mover or backup on the array plus the 52 GB write starving sshd/emhttp (which run from
   RAM but block on shared storage paths).
3. Both.

**How to tell next time.** After boot: `dmesg | grep -i -E "oom|killed"`, the syslog around 04:15,
mover logs, and `free -m` with both models loaded and no backup running.
**Mitigation until known.** `--models-max 1` (backup of the override kept), no large downloads or
benchmarks during backup/mover windows, and a memory check in the model manager that counts
GPU allocations on unified-memory hosts (proposed, not built).

## 6. Research priorities — status

| # | Item | Status |
|---|---|---|
| 1 | Context efficiency (scripts before tokens) | Logging shipped; no reducers yet; needs live logs |
| 2 | Configuration-scoped qualification | First wave shipped; D3 evidence added |
| 3 | Impeccable/design lint | Adopted; type-scale and weight rules added today |
| 4 | Prompt Architect | Benchmark designed, not run (needs server) |
| 5 | CodeHarness / ACP | Contract v0 written; spike not started |
| 6 | Durable jobs | Built |
| 7 | ExecutionNode / BrowserExecutor | Not started |
| 8 | Known-good settings | D3 caps verified; larger caps unprobed |
| 9 | Wider model evidence / MoE offload | Not started |
| 10 | Backend portability | Spec only |
| 11 | Headscale vs NetBird | Recommendation: don't migrate yet |
| 12 | AIO master container | Recommendation: don't build |
| E | Tool routing | Measured, passed, built behind a flag |
| I | Deep research gate | Harness ready, run interrupted |
