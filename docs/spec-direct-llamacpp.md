# Direct native llama.cpp integration

Implemented on `feat/direct-llamacpp`, 2026-09-14. This supersedes the earlier
recommendation to keep Lemonade as the required management layer. noevia talks
directly to llama.cpp's existing router; it does not schedule model processes,
implement another router, or mount the Docker socket. Lemonade remains an optional
rollback adapter. Production application release is `2570a02`; its active inference backend remains
Lemonade until the native GPU workload qualification and cutover.

## Operator configuration

Set `MODEL_MANAGER_KIND=llamacpp`, `MODEL_MANAGER_BASE_URL=http://router:8080`
and `INFERENCE_BASE_URL=http://router:8080/v1`. Set the corresponding Diary chat,
auxiliary and embedding endpoints and **native model identities** explicitly.
Existing saved project/role names must match native preset names, or be changed
through their existing selectors. A preset may retain an old model name as its
section name to preserve existing selections; do not silently rewrite tenant data.

The optional `compose.llamacpp.yaml` overlay supplies an internal native router,
shared preset directory, separate writable cache and matching web/Diary endpoint
configuration. It uses the pinned Vulkan image from the existing DaServer
experiment. Required paths, devices and model IDs deliberately have no guessed
production defaults. This overlay is for generic Compose installs; Unraid retains
the separate Compose Manager flow in `deployment.md`. Do not run it beside the
production inference model on the shared GPU.

The public model tree stays read-only; native downloads use a separate writable
`LLAMA_CACHE`. Do not copy or erase the Lemonade cache. `--models-max 1` prevents
multiple loaded model processes, but is not a memory estimator. Embedding, vision,
classification and chat may evict each other and reload on demand. Qualification
must include that workload, including the Diary sidecar. Keep the existing host
RAM reserve and exact qualified context/KV/projector settings.

## Lifecycle and runtime context

Management uses native `/models`, `/models/load`, `/models/unload`, cache downloads
and cache deletion. `/models/load` acknowledges a launch before readiness, so the
adapter waits for `loaded` and propagates asynchronous failure. Cancellation stops
waiting without unloading a shared model. Polling uses `autoload=false`; listing
and telemetry never reload presets or wake a cold model. Auto role configuration
no longer preloads every role on native routing.

Model responses expose only normalized status/source/delete capability, not raw
process arguments, paths or secrets. Context comes from
`props.default_generation_settings.n_ctx`, which b10920's `server-context.cpp`
builds from `meta.slot_n_ctx`. It is already **per slot**. Observations retain slot
count, native build, and a digest of runtime configuration; they are allocation
observations, not maximum-context qualification. Unknown capacity stays a labelled
fallback. No architecture training ceiling is substituted for an allocation.

Native `/metrics?model=…&autoload=false` supplies token counters and actual draft /
accepted-token counters. Missing/disabled metrics stay unknown. Native totals are
scoped to currently loaded processes and reset after unload; they do not replace
noevia's tenant-owned usage ledger. No host CPU/GPU capacity or request count is
fabricated. Hardware planning remains manual because this router has no host
hardware API. MTP artifact detection remains separate from runtime support.

## Native profiles

Set `LLAMACPP_PRESET_PATH` to the app-visible **existing** native INI file. Bind its
parent directory into both processes; a single-file bind will not follow atomic
renames. The web process requires directory write permission. Only administrators
can read/edit these shared profiles. No endpoint permits arbitrary file paths,
commands, remote URLs, templates or credentials.

The editor changes a bounded set of resource/runtime options, preserves all other
options and sections, understands the corresponding short/environment aliases,
and checks the full file revision. Blank fields inherit router/global defaults.
Presets can be added as overrides for an already installed cache model; new local
artifact/projector registration remains an operator file operation.

Applying is explicit and checks that all models are unloaded and no downloads are
active. A maintenance gate excludes concurrent noevia chat, Diary proxy requests,
background project embeddings and other model mutations. The administrator must
stop other clients and independent Diary background inference first: noevia cannot
lock external clients of the native router. Run one noevia writer for the preset
file. Direct operator edits must also be quiesced during apply.

Writes use fsync + atomic rename and keep immutable mode-0600 recovery copies
named `models.ini.noevia-backup-<revision>` beside the preset. Back these up and
manage retention as operator configuration; they can contain private paths/options.
Only then is native `GET /models?reload=1` called. This GET is a mutation and never
occurs during routine polling. Failure restores the prior file if no subsequent
writer changed it, and reports an uncertain runtime rather than claiming success.
A crash between file write and reload cannot be made transactional with native
HTTP: stop clients, inspect the saved profile, and reapply before resuming.
Router CLI arguments still override INI values; success is not proof of capacity.

## Downloads

Public HF metadata lists unambiguous quant selectors and complete shard sets;
projectors and ambiguous variants are excluded from selectable primary weights.
No inference credential is forwarded to HF. A read-only live metadata check found
22 selectable variants for `unsloth/Qwen3.5-9B-GGUF`, including the existing
`Qwen3.5-9B-UD-Q4_K_XL.gguf` (5,966,095,584 bytes). No weights were downloaded. llama.cpp itself resolves/downloads
the selected repo/quant and its matching projector according to native policy.
Reported sizes are primary model files; the memory planner reserve includes the
projector/runtime/context. Missing size remains unknown.

A bounded durable job journal and native SSE terminal events distinguish completed,
failed, rejected and unknown transfers. Polling reconciles active byte progress;
a missing job is never itself evidence of success. Restart can lose an SSE event,
so unresolved transfers remain unknown until the cache listing proves installation
or a new event arrives. Noevia does not implement a separate downloader.

## Qualification and production boundary

Reproducible local checks:

- `npm test`, `npm run typecheck`, `npm run build` from `apps/web`.
- `node apps/web/qa/llamacpp-http.cjs`: real authenticated HTTP, cold/auto routing,
  changed allocation, failed load, native identities/status privacy, profile
  apply/conflict and capability endpoints against a synthetic router.
- `PLAYWRIGHT_MODULE=<existing module> node apps/web/qa/llamacpp-ui.cjs`: real browser,
  native profile controls, stale revision/draft recovery, explicit reload action,
  keyboard focus, light/dark 375/768/1440 layouts. Screenshots visually inspected.
- `DB_PATH=/tmp/noevia-native-diary/index.db services/diary/.venv/bin/python -m pytest
  services/diary/tests/test_native_router.py`: actual HTTP chat/aux/embedding model
  identity and embedding order. Synthetic strings only; no Diary corpus.

`experiments/direct-llamacpp/router-contract.sh` ran on DaServer against existing
image ID `sha256:9f88885b46c8af0696d02b6d0d93f39cc0d81f29b99fb45030dcaf3a0193e282`.
The disposable container had no GPU devices or actual model files. It verified
native listing/can_remove, non-autoloading props, preset-delete refusal, asynchronous
load failure, and explicit reload. It was removed afterward. The optional Compose
overlay passes the host's Docker Compose v2.40.3 config validation. The host warns
that swap-limit enforcement is unavailable; this test does not establish a memory
limit guarantee for real GPU workloads.

This is application/API/synthetic qualification. The earlier Vulkan high-context
trials remain workload evidence for their exact profiles; they are not an end-to-end
noevia cutover test. Still required before production backend replacement: a
quiescent GPU window, chat/vision/tools/Diary model swapping, long-context plus output
reserve, cancellation, memory reserve, and restoration of the original production
backend. Never send test prompts to the real Diary or import/edit its corpus.
The current release was already pushed/deployed before this rewrite; do not
repeat that rollout or infer authorization for an unqualified backend cutover.

Source contract: [pinned llama.cpp server documentation](https://github.com/ggml-org/llama.cpp/blob/b10920/tools/server/README.md),
[pinned router](https://github.com/ggml-org/llama.cpp/blob/b10920/tools/server/server-models.cpp),
[per-slot props](https://github.com/ggml-org/llama.cpp/blob/b10920/tools/server/server-context.cpp),
[metrics](https://github.com/ggml-org/llama.cpp/blob/b10920/tools/server/server-task.cpp).

Final local verification: **423 web tests passed; 218 Diary tests passed, 3 skipped**
(two existing dependency deprecation warnings). Typecheck and build passed. Native
HTTP and native-profile/model-guidance browser regressions passed. Native tests
cover reload exclusion across chat and all lifecycle mutations, aborted load
waiting, public variant filtering, durable download outcomes, profile recovery,
all three write approvals and vision-to-answer switching. Production rechecked:
web/Diary/OCR all `55b2767`, healthy, zero restarts and no OOM. No disposable native
contract container remains. No new production deployment was performed.
