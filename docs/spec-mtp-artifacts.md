# MTP head evidence for Hugging Face downloads

The model manager's Download tab offers **Check MTP head** for each selected
quantization. The server resolves its actual filenames through Lemonade and reads
only bounded GGUF metadata/tensor directories from an immutable Hugging Face
revision. It reports recognized tensors found, no recognized tensors, or
unverified. Model-family names and repository descriptions are not evidence.

Checks are explicit to avoid reading headers for every search result. Limits:
16 MiB per file, four shards per variant, two concurrent inspections, bounded
metadata counts, timeouts, and five-minute public-result cache. Incomplete headers,
missing shards, unsupported formats and inconsistent metadata remain unverified.
Separate MTP files that are not part of the selected variant are not included.
This does not attach a separate draft/head file automatically, change a download,
load a model, enable MTP, or guarantee that all required head weights are usable.
The inspected revision is shown; Lemonade's later pull may resolve a newer revision.
Installed model controls continue to depend on backend capability; a missing label
now explicitly means unverified rather than claiming absent weights.

Evidence: GGUF `nextn_predict_layers` and tensor naming follow
[llama.cpp's constants](https://github.com/ggml-org/llama.cpp/blob/master/gguf-py/gguf/constants.py).
Hugging Face documents [GGUF header inspection](https://huggingface.co/docs/hub/gguf).

## Verification — 2026-09-12

353 web tests, typecheck/build; authenticated synthetic-server HTTP checks against
public GGUF headers passed, including invalid variant and unauthenticated access.
`unsloth/Qwen3.5-9B-GGUF`, revision
`3885219b6810b007914f3a7950a8d1b469d598a5`, Q4_K_M: 427 tensor entries,
no recognized MTP tensors. `unsloth/Qwen3.5-9B-MTP-GGUF`, revision
`9716a636ee4bddc3fed678220b7a33dd2a4160ae`, Q4_K_M: 442 entries, four
NextN tensors and one declared prediction layer. These are artifact inspections,
not generation benchmarks or verified installed-file hashes.
