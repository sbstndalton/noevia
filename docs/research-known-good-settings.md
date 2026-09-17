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

## D3 preset proposal — prepared and applied 2026-09-17

Decision D3: serve a small qualified set — one ~4B general model, one ~9B capped at its verified
context, and `nomic-embed-text-v1` for retrieval — and drop `spec-type draft-eagle3` where no draft
model exists. **Applied live 2026-09-17** (user go given in the follow-up session; evidence below).

Live state read on 2026-09-17 (read-only; this corrects the brief's "no models served"): the
engine (`--models-preset /config/models.ini --models-max 1`) lists three presets, all unloaded;
`/mnt/user/ai-models` holds Ornith-1.5-9B-Q5_K_M (6.6 GB + 0.9 GB projector), Qwen3.5-4B-Q5_K_M
(3.2 GB + projectors), Qwen3.5-4B-Q8_0 (4.6 GB, unregistered), gemma-4-E2B_q4_0-it (3.3 GB + 1.0 GB
projector) and an `OsaurusAI` folder (18 GB, not GGUF presets). No embedding model is present.

Choices: the 4B is Qwen3.5-4B-Q5_K_M (registered, smaller than Q8_0, has a projector); the 9B is
Ornith-1.5-9B-Q5_K_M; gemma-4-E2B leaves the served set (its files stay on disk). Context caps are
the provisional baseline above until Measure context runs in a maintenance window (D2).

```diff
--- models.ini (live, 2026-09-16 00:03)
+++ models.ini (proposed)
 version = 1

 [Qwen3.5-4B-Q5_K_M]
 model = /models/Qwen3.5-4B-Q5_K_M/Qwen3.5-4B-Q5_K_M.gguf
-ctx-size = 262144
+ctx-size = 24576
 ngl = 999
 flash-attn = on
 cache-type-k = q8_0
 cache-type-v = q8_0
 parallel = 1
 jinja = true
 split-mode = layer
 mmproj = /models/Qwen3.5-4B-Q5_K_M/mmproj-BF16.gguf
-spec-type = draft-eagle3
 reasoning = auto

-[gemma-4-E2B_q4_0-it]
-model = /models/gemma-4-E2B_q4_0-it/gemma-4-E2B_q4_0-it.gguf
-ctx-size = 131072
-ngl = 999
-flash-attn = on
-cache-type-k = q8_0
-cache-type-v = q8_0
-parallel = 1
-jinja = true
-split-mode = layer
-mmproj = /models/gemma-4-E2B_q4_0-it/gemma-4-E2B-it-mmproj.gguf
-spec-type = draft-eagle3
-reasoning = auto
-
 [Ornith-1.5-9B-Q5_K_M]
 model = /models/Ornith-1.5-9B-Q5_K_M/Ornith-1.5-9B-Q5_K_M.gguf
-ctx-size = 262144
+ctx-size = 16384
 ngl = 999
 flash-attn = on
 cache-type-k = q8_0
 cache-type-v = q8_0
 parallel = 1
 jinja = true
 split-mode = layer
 mmproj = /models/Ornith-1.5-9B-Q5_K_M/mmproj-Ornith-1.5-9B-BF16.gguf
-spec-type = draft-eagle3
 reasoning = auto
 reasoning-format = deepseek
 reasoning-budget-message = Final Answer
+
+[nomic-embed-text-v1]
+model = /models/nomic-embed-text-v1/nomic-embed-text-v1.Q8_0.gguf
+embedding = true
+pooling = mean
+ctx-size = 2048
+ngl = 999
+parallel = 1
```

Steps when the user says go (in a maintenance window, `docs/deployment.md` backup first):

1. Download the embedding GGUF into `/mnt/user/ai-models/nomic-embed-text-v1/` (Q8_0, ~140 MB) with
   the model manager's Discover flow, checking the file name matches the preset.
2. Apply the diff with Settings → Models → Raw file, or edit the file; the engine keeps the previous
   file as `models.ini.bak-*`. Presets reload without unloading a running model.
3. **Engine flag:** the live engine runs `--models-max 1`, so loading the embedding model evicts the
   chat model on every retrieval. Raise it to `--models-max 2` in the live Compose file (a user edit)
   or retrieval will thrash; the embedding model needs ~0.3 GB.
4. Run Measure context for both chat models (120 s budget, one at a time) and replace the
   provisional caps with the verified sizes; record evidence here.
5. Set Auto routing: Fast = Qwen3.5-4B-Q5_K_M, Smart = Ornith-1.5-9B-Q5_K_M; set
   `EMBEDDING_MODEL=nomic-embed-text-v1`.

### D3 applied — evidence 2026-09-17

Build 657d21b, llama.cpp server-vulkan @sha256:94bd70ef…, `--models-max 2`, 29 GiB host / 14 GiB engine limit.

- `nomic-embed-text-v1.Q8_0.gguf` (146 146 432 bytes, GGUF magic checked) from
  `huggingface.co/nomic-ai/nomic-embed-text-v1-GGUF`; `/v1/embeddings` returns 768 dimensions.
  `EMBEDDING_MODEL` in `.env` renamed from `nomic-embed-text-v1-GGUF` to the preset name.
- `models.ini` replaced with the diff above (previous file `models.ini.bak-before-d3`);
  `/models` lists exactly Ornith-1.5-9B-Q5_K_M, Qwen3.5-4B-Q5_K_M, nomic-embed-text-v1.
- Context measurement (direct engine request, cold load, 16 output tokens):

| Model | Cap | Over-cap request | Near-cap prompt | Wall time | Prefill |
|---|---|---|---|---|---|
| Qwen3.5-4B-Q5_K_M | 24 576 | 26 475 → 400 (refused cleanly) | 22 695 → 200 | 46.0 s | 503 tok/s |
| Ornith-1.5-9B-Q5_K_M | 16 384 | 17 025 → 400 | 15 135 → 200 | 50.3 s | 309 tok/s |

  Both inside the 120 s budget, no engine errors, host available memory stayed ≥ 9 GiB. The caps
  are verified as served; larger caps were not probed (would exceed the 60 s interactive target).
- Auto routing (`ui-data/auto-roles.json`, previous copy `.bak.before-d3`) pointed at two Gemma
  models no longer served, so Auto would have failed on every request. Now Fast =
  Qwen3.5-4B-Q5_K_M, Smart = Ornith-1.5-9B-Q5_K_M, Vision = Qwen3.5-4B-Q5_K_M.

## APU memory and retrieval swap — measured 2026-09-17 09:50 EDT

Release 127b300, llama.cpp b10920 (`eafe15a5e`), `--models-max 1`, 29 701 MiB RAM, no swap, no
backup or mover running, nobody chatting. Sampled every 0.5 s (`free -m`,
`/sys/class/drm/card1/device/mem_info_{gtt,vram}_used`); one short request per phase.

**Kernel bounds already in place.** `amdgpu.gttsize=-1` (default), `ttm.pages_limit=3 801 760`
pages, so `mem_info_gtt_total` = **14 850 MiB** (half of RAM), plus a 2 048 MiB BIOS VRAM carve-out.
GPU allocations are therefore hard-capped at about 16.9 GiB. The syslog mirror is **not** enabled
(`/boot/config/rsyslog.cfg` empty).

| Loaded model | GTT used | VRAM used | Host `used` | `available` |
|---|---|---|---|---|
| gemma-4-E2B_q4_0-it, ctx 131 072 (not in D3; preset added 08:32) | 4 050 MiB | 2 017 MiB | 11 743 MiB | 17 950 MiB |
| Qwen3.5-4B-Q5_K_M, ctx 24 576 | 3 145 MiB | 1 938 MiB | 10 761 MiB | 18 939 MiB |
| nomic-embed-text-v1 (GPU) | 44 MiB | 280 MiB | 7 560 MiB | 22 140 MiB |
| CPU-only nomic sidecar (`--device none`, 4 threads) beside the 4B | +0 | +0 | +280 MiB RSS | — |

Host baseline without a chat model is about 7.5 GiB used (containers plus the RAM root filesystem);
~20 GiB is page cache (reclaimable, including mmap'd weights).

**Retrieval swap cost under `--models-max 1`** (wall time from the host, one request each):

| Step | Time |
|---|---|
| 4B cold load + 8 tokens | 4.86 s |
| 4B warm | 0.77 s |
| embedding request, evicting the 4B | 0.74 s |
| embedding warm | 0.06 s |
| 4B again after the embedding (reload) | 3.84 s |
| CPU sidecar: query / 1 200-char chunk / batch of 8 chunks (minus 53 ms `docker exec`) | ~30 ms / ~100–140 ms / ~780 ms |

A RAG turn therefore adds about **4.6 s of swapping** and also drops the chat model's prompt cache,
so a long chat re-prefills from scratch (at ~500 tok/s on the 4B, +20 s for 10k tokens). The CPU
sidecar removes both, costs no GPU memory and answers a query in ~30 ms.

**Proposal to the user (not applied).**
1. **GTT:** keep the kernel default (14.85 GiB). It is already below "RAM − 10 GiB" (19.7 GiB);
   lowering it further would block the 9B at longer contexts for no measured gain. What is missing
   is evidence of what filled RAM during the outage: enable the syslog mirror first.
2. **Engine guard:** add `--fit on --fit-target 1024` to the router command (both flags exist in
   b10920), so a load that would overrun device memory shrinks unset options or fails cleanly.
3. **Retrieval:** run nomic on CPU as a small service (`llama-server --device none -m
   …nomic-embed-text-v1.Q8_0.gguf --embedding --pooling mean -c 2048 -t 4`) and set
   `EMBEDDING_BASE_URL` on web (supported from this commit). Keep `--models-max 1` for chat models.
   This also removes the memory objection to `features.toolRouter`.
4. Only after 1–2 and a measured peak with the 9B loaded: consider `--models-max 2`.

Outage hypothesis update: GPU memory alone cannot exceed ~16.9 GiB, and host baseline is ~7.5 GiB,
so the engine by itself stayed below physical RAM even with two models. More likely contributors are
RAM-backed paths (Unraid root filesystem, `/tmp`) during the 52 GB ZIM download or the appdata backup
staging. Unverified; the syslog mirror is the way to find out.

Project RAG after the `EMBEDDING_MODEL` rename: production has **no** project indexes
(`ui-data/rag` is empty, no per-user `rag` folders), so nothing is stale and no reindex is needed.
Indexes store only the vector dimension, not the model; a model change with a different dimension
would be caught by the query-length check, one with the same dimension would not. Add a model
stamp before switching embedding models.
