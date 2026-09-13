# Backend portability investigation — 2026-09-13

Decision: retain production Lemonade while qualifying an isolated pinned backend.
The user's request was to investigate a replacement, not migrate immediately.
Existing direct llama.cpp staging proved larger context is feasible, but its
roughly 13.75 versus 13.71 token/s comparison did not show a useful speed gain.
See [the measured configuration and limits](../experiments/model-loader/README.md).

## What a swap changes

noevia already separates its OpenAI-compatible inference endpoint from model
management. `apps/web/server/model-manager.cjs` supports Lemonade or disabled
management; merely changing inference URLs does not port load/unload/download,
health, metrics or configured-context discovery. A new manager must explicitly
report supported operations and per-slot allocation. Missing capacity must remain
unknown/conservative, never silently become the model's architecture maximum.

| Option | Existing evidence | Remaining qualification |
| --- | --- | --- |
| Pinned llama.cpp under Lemonade | Official custom binary configuration exists; preserves current manager API | Exact installed-version support, library compatibility, model load/unload, vision, tools, context and rollback |
| Direct llama.cpp router | Existing isolated Vulkan preset test and near-capacity Gemma validation | noevia lifecycle adapter, download policy, actual context/slot reporting, health/metrics translation and cold model swaps |
| vLLM ROCm | Official requirements include Ryzen AI 300 gfx1150 with ROCm 7.0.2+ | Actual host/container/PyTorch/ROCm/model/quantization support, memory use and equal-workload comparison |

Current upstream documentation describes custom backend paths; it is not proof
that every setting works unchanged in installed Lemonade 10.8.0. Pin both manager
and backend image/binary versions for the experiment; avoid the mutable latest tag
in any new qualified configuration. Existing production currently uses that tag,
but this investigation has not pulled or restarted it.
[Lemonade custom backends](https://lemonade-server.ai/docs/embeddable/backends/),
[configuration](https://lemonade-server.ai/docs/guide/configuration/),
[llama.cpp server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md),
[vLLM GPU requirements](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/).

Host read-only check: kernel6.18.38-Unraid; /dev/kfd and the configured AMD
/dev/dri/renderD129 exist. Device existence is not ROCm runtime qualification.
The integrated GPU shares host memory; capacity results must preserve a reserve
for other services. No vLLM image, additional model weights or host driver was
installed as part of this review.

## Qualification contract

Record model artifact/revision/hash and quantization; engine/version; GPU and
driver; KV types; context per slot; slot count; offload; projector/MTP settings;
free-memory starting point and reserve. Distinguish model maximum, configured
allocation, longest successful input and safe reusable workload profile.

Exercise cold load, short response, near-capacity prompt plus output reserve,
tools/structured arguments, all write approvals with synthetic tools, vision when
claimed, cancellation, unload/reload and rollback. Record actual provider input,
output, latency, memory peak, failures and configuration fingerprints. A successful
allocation or short smoke test alone cannot qualify a maximum-context profile.
Test one inference configuration at a time; do not compete with production on the
shared GPU or change saved production options to obtain a benchmark.

MTP presence, backend support and enabled acceleration are separate observations.
Existing HF artifact inspection answers presence only. Do not advertise a speedup
from an MTP head without a compatible execution test and measured improvement.

Adopt a replacement only after it meets the current behavior contract and delivers
measured reliability, capacity or latency benefits that justify its maintenance.
The initial architecture/source review is complete; runtime qualification of the
custom-Lemonade and vLLM alternatives remains open.
