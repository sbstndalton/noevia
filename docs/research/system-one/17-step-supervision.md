# Step supervision: provider-neutral experimental slice

Implemented with injected mocked providers, disabled and unavailable in production. The
Experimental settings registry exposes a separate Step supervision entry with an explicit
unavailable reason. Neither an admin setting nor an environment override can activate it
without a future provider integration. No Jev/Laya endpoint, SDK, model or credential is added.

`createStepSupervision({enabled, provider, deadlineMs})` accepts a provider with
`decide({round, goal, outputs, choices}, {signal})`. The response is exactly
`{action: 'continue' | 'verify' | 'escalate'}`. Default-off behavior, missing providers,
errors, malformed responses, cancellation and a 500 ms deadline (maximum 1500 ms)
fall back to the current loop. The deadline bounds waiting even if a provider ignores
cancellation; a future adapter must actually cancel its external request.

The ordinary chat handler accepts this supervisor by dependency injection. It runs only
after a completed tool batch and before another permitted generation round. It does not
run for Diary, after a final answer, beyond the existing three-round cap, or when durable
state has unresolved tool outcomes. ERROR tool results bypass the provider. The decision
input is a disposable projection: the latest user message (1500 characters) and at most
eight assistant/tool outputs (1500 characters each). No reasoning channels, credentials,
approval grants or mutable checkpoint objects are passed. Project/conversation ownership
remains with the existing request scope. Provider state is request-local.

- Continue keeps the existing next step.
- Verify appends a fixed checking instruction to model-facing context, within the existing
  next round and context budget. It grants no tools or extra rounds, and does not rewrite
  canonical outputs or tool results.
- Escalate ends generation with a review message. It does not switch models or execute tools.
  If the durable recorder is injected, the action and review requirement are persisted in
  the existing jobs checkpoint. Restore requires review and cannot resume generation.

Approval policy (approve / deny / approve_all), retry limits, tenant scope and tool execution
remain owned by existing code. No autonomous replay or automatic model switching is added.
This is checkpoint supervision, not a replacement for hidden reasoning or a final-answer judge.

Verification: focused supervisor and real chat-loop tests use synthetic providers/tools;
full web suite 1181 tests passes, typecheck/build/design lint pass. Tests cover invalid and
hanging providers, cancellation, independent concurrent inputs, projection isolation,
verification, persisted escalation, preserved approve_all, and no duplicate write after an
ambiguous outcome. Existing approval and tenant-isolation suites remain in the full run.
Local synthetic Experimental page checked visually; no full all-view responsive sweep,
real model inference, provider quality/cost/latency benchmark or production activation.
