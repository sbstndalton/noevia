# Model guidance

Status: first implementation local, 2026-09-14. Not deployed.

## Reference and fit for noevia

Reviewed [CanIRun.ai](https://github.com/midudev/canirun.ai), including its
[compatibility engine](https://github.com/midudev/canirun.ai/blob/main/packages/compatibility/src/index.ts)
and [model metadata](https://github.com/midudev/canirun.ai/blob/main/packages/models/src/index.ts).
Its useful product pattern combines hardware, intended use, quantization and
explanations. The README declares MIT. No code, GPU database, model catalogue or
package was imported, and no calls to its hosted API were added.

noevia's inference machine can be remote from the browser. Browser GPU detection
would therefore answer the wrong question for a DaServer-backed session. Ranking
by estimated speed or parameter count would also not establish tool reliability,
vision support, context fit, or response quality for this deployment.

## Implemented

Models → Guidance reads the existing model-manager catalogue. It filters on
reported vision/reasoning/tool labels; missing labels stay unverified. Ordering
puts models with room in the entered memory budget first, then tight, unknown
and over-budget candidates; currently loaded models break ties. This is a review
order, not a model-quality score or automatic routing decision.

The memory plan stays in the mounted model window. It represents one pool:
single-GPU VRAM, unified memory, or CPU RAM. Capacity minus reported model file
size minus the user's reserve gives planning headroom. Missing/invalid values
produce unknown fit. Less than max(1 GB, 10% of capacity) remaining is labelled
little headroom. The initial 4 GB reserve is explicitly a placeholder for other
workloads, runtime buffers, context cache and vision projectors; it does not
predict those requirements. No generated tokens/second or letter grades.

Download variants show the same assessment. The previous unqualified
“recommended quant” label for the first listed variant was removed. Search and
variant errors are validated before rendering; Switch/Manage expose loading,
empty and retry states. Existing explicit download/load/delete/routing actions
are unchanged.

Read inference hardware makes an explicit GET to the configured model manager's
`/v1/system-info`, through authenticated `/api/models/hardware`. The response
allowlists CPU name, physical memory and available GPU capacities/shared memory.
Paths, environment, provider configuration and other system metadata are omitted.
Shared pools remain separate. Applying a reported capacity is another explicit
click; reading hardware does not replace the user's plan.

[Lemonade's API](https://lemonade-server.ai/docs/api/lemonade/) documents system
information separately from current resource usage. The existing `system-stats`
RAM/VRAM values describe usage, so they are not reused as capacity. A read-only
check of the configured live inference host returned physical memory and an AMD
GPU with separate VRAM/shared fields; no model was loaded or benchmarked. This
verifies the upstream schema, not deployment of the new noevia route.

## Verification

404 web tests, typecheck/build in the combined local set. Unit tests cover
unknown/invalid budgets, no combined memory pools, capability labels, bounded
hardware requests and hardware-field allowlisting. Actual synthetic HTTP checks
cover authentication, GET-only semantics, upstream failure/retry and private-field
exclusion. Browser checks cover capability filters, unknown and over-budget fits,
explicit hardware reading/applying, shared plan in Download, load failure/retry,
375/768/1440 light/dark layout and zero model mutations/inference calls.

## Remaining qualification

- Context-cache and projector requirements from verified per-artifact metadata.
- Runtime/backend support for the exact downloaded artifact, not just a family.
- An optional curated catalogue with dated primary model-card/benchmark sources.
- Task-specific synthetic evaluations for chat, coding, tool use and vision.
- Measured performance attached to its hardware, runtime, load configuration and
  context length. Never treat model size or hardware fit as proof of quality.

Guidance does not change production models, auto roles, storage or public ports.
CanIRun remains a product reference and external discovery link, not a runtime
dependency or a compatibility guarantee.
