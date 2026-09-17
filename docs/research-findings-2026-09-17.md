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
- 87 raw colour literals outside the token file, almost all deliberate (theme swatch previews, chart
  colours, white on accent). The real defect was different: 5 `var()` references to tokens defined
  nowhere, whose light fallbacks broke the message edit box in dark mode (fixed; lint rule added).
- The accepted glass study's pointer glint was never ported: CSS read `--glass-x` that nothing set
  (fixed: `public/glass-highlight.js`).
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

**Next.** Status vocabulary (Idle/Running/Waiting/
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
| 10 | Backend portability | Researched (§8): stay on llama.cpp Vulkan; revisit gates listed |
| 11 | Headscale vs NetBird | Recommendation: don't migrate yet |
| 12 | AIO master container | Recommendation: don't build |
| E | Tool routing | Measured, passed, built behind a flag |
| I | Deep research gate | Harness ready, run interrupted |

## 7. Keeping the engine inside host memory on a unified-memory iGPU

**Question.** Follows §5: how can the engine be prevented from starving Unraid, whose root
filesystem itself lives in RAM?

**Findings (llama.cpp server README, current master; verify against the pinned image before use).**
- The container `mem_limit` does not bound Vulkan allocations on an APU. The Vulkan backend
  addresses BIOS VRAM **plus GTT**, and GTT is ordinary system RAM mapped for the GPU. So two loaded
  models can use far more RAM than the 14 GB limit suggests.
- The engine has its own fit logic. `--fit on` adjusts unset options to fit device memory,
  `--fit-target MiB,…` sets a per-device safety margin, and `--fit-ctx N` sets a floor for context.
  With `--models-max N` this is the engine-side guard, but "device memory" on an APU is the GTT size,
  which by default can reach most of RAM.
- The kernel is the hard bound. On amdgpu, GTT size is set by the `amdgpu.gttsize` parameter or the
  TTM `pages_limit`. Capping GTT below physical RAM minus what Unraid needs (RAM root fs, Docker,
  page cache) turns an OOM or thrash into a clean load failure that the engine reports.
- `--cpu-moe` / `--n-cpu-moe N` keep expert weights on the CPU side. On a unified-memory host that
  saves no memory, only GPU address space, so MoE offload (priority 9) is not a memory fix here.
- `--load-mode` (mmap, mlock, …) decides whether weights sit in reclaimable page cache (mmap) or
  pinned memory. mlock on this host would make pressure worse.

**Recommendation (not applied; the server is down).**
1. Keep `--models-max 1` until the cause is confirmed.
2. Measure the real peak: `free -m` and `/sys/class/drm/card*/device/mem_info_gtt_used` with the 9B
   and 4B loaded, and with no backup or mover running.
3. Cap GTT at about physical RAM − 10 GB, and add `--fit on --fit-target <MiB margin>` to the engine
   command. Then retry `--models-max 2` and record the result in `research-known-good-settings.md`.
4. Product follow-up: the Hardware tab should show GTT used/total next to RAM on unified-memory
   hosts. `model-manager` already reads GPU memory, so this is a small addition.

Sources: [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md),
[llama.cpp #19818 (APU OOM, GTT vs VRAM)](https://github.com/ggml-org/llama.cpp/issues/19818),
[llama.cpp discussion #18839 (shared memory)](https://github.com/ggml-org/llama.cpp/discussions/18839),
[AMD GPUs notes (llm-tracker)](https://llm-tracker.info/howto/AMD-GPUs).

## 8. Backend portability: stay on llama.cpp Vulkan for now (priority 10)

**Question.** Should the ROCm vLLM candidate in `spec-backend-portability.md` (gfx1150 artifact)
move ahead?

**Findings.**
- On the same APU family (Strix Point, gfx1150), llama.cpp issue #19818 (still open) reports
  that **ROCm sees only the BIOS VRAM area** (6.4 GiB of 96 GiB) and does not use GTT. Vulkan on the
  same machine sees 53 GiB. A 30B model got SIGKILLed under ROCm right after its first request but
  ran fully under Vulkan. That is the same ROCm stack vLLM uses on AMD.
- vLLM's unified-memory (UMA) handling was still receiving fixes in mid-2026, and its GGUF
  support is secondary to safetensors. The GGUF presets, projectors and evidence this deployment has
  collected would not transfer as-is.
- The immediate risk on this host is memory bounding (§5, §7). A second engine with a different
  allocator makes that harder to reason about, not easier.

**Recommendation.** Keep llama.cpp Vulkan as the only engine. Revisit vLLM once three things hold:
(a) ROCm enumerates GTT on gfx1150 (#19818 closed); (b) a GTT cap is in place and measured here;
(c) a workload vLLM should win on exists, for example several concurrent users, where continuous
batching matters. Single-user chat at 300–500 tok/s prefill is not that workload. The equal-workload
comparison in the spec stays the gate.

Sources: [llama.cpp #19818](https://github.com/ggml-org/llama.cpp/issues/19818),
[vLLM on ROCm (AMD docs)](https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/inference/vllm.html),
[AMD GPUs notes (llm-tracker)](https://llm-tracker.info/howto/AMD-GPUs).
