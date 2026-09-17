# Known-good settings per model × hardware — baseline

Roadmap R8. Written 2026-09-17 from **read-only** inspection of DaServer (live `models.ini`,
native calibration history, hardware). No model was loaded and no preset changed for this
document. Measurements to fill the gaps are listed at the end.

## Hardware

- Host RAM 29 GiB (`MemTotal` 30 414 080 kB); engine memory limit `LLAMACPP_MEMORY_LIMIT`
  (default 14 GiB in compose).
- GPU in `lspci`: Intel Arc A380 (DG2). The engine runs llama.cpp `server-vulkan`.
  `/sys/class/drm/*/mem_info_vram_total` reports 2 GiB, which is an AMD-driver file; which
  device Vulkan actually uses should be confirmed from the engine log before relying on either
  figure.

## Live presets vs recorded evidence

| Model (preset) | Live `ctx-size` | Recorded calibration | Gap |
|---|---|---|---|
| Qwen3.5-4B-Q5_K_M | 262 144 | none | unverified |
| gemma-4-E2B_q4_0-it | 131 072 | none (a different model, Gemma-4-E4B, verified 24 576 at a 60 s prompt budget) | unverified |
| Ornith-1.5-9B-Q5_K_M | 262 144 | none (Qwen3.5-9B verified **16 384**; long prompts at 131 072 and 57 344 made the engine fail; 24 576 exceeded 60 s; loads passed up to 262 144) | unverified, likely too large for full prompts |

All three presets share: `ngl 999`, `flash-attn on`, KV `q8_0/q8_0`, `parallel 1`,
`split-mode layer`, `jinja`, `reasoning auto`, a vision projector, and
**`spec-type draft-eagle3` with no draft model configured** — speculative decoding of that
type needs a draft; whether llama.cpp ignores it or degrades is unverified.

What the history shows generally on this box: a model **loading** at a context size says little
about **using** it — memory allocation passed at 262 144 while filling prompts failed far
below that. Qualification evidence (spec §1) must record the verified prompt size, not the load
size.

## Provisional known-good baseline (until measured)

| Model class on this box | Context to trust | Why |
|---|---|---|
| ~9B Q5 | ≤ 16 384 | the one measured 9B |
| ~4B Q5 / E4B-class | ≤ 24 576 | the measured E4B; 4B untested |
| E2B-class | ≤ 24 576 (likely more) | untested; no evidence yet for larger |

KV cache `q8_0` and flash attention on are the configurations these results were measured
with; `parallel 1` (a single slot) is assumed throughout.

## Measurements to run (each is a production engine action — schedule with the user)

1. Native calibration (Settings → model details → Measure context) for each registered model
   at a 120 s prompt budget, one at a time, with chats paused. Evidence records land
   automatically (qualification evidence, first wave).
2. For one model: calibration with KV `q4_0/q4_0` vs `q8_0/q8_0` to see how much context the
   smaller cache buys and at what quality cost (spot-check with a fixed recall prompt).
3. Remove `spec-type draft-eagle3` from one model and compare tokens/s from the benchmark suite;
   then enable MTP/draft only where a matching head exists.
4. Confirm the Vulkan device from the engine log and record it in `deployment.md`.

Record results here with date, build and preset hash (the evidence identity).
