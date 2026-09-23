# Executable skills: separate capability proposal

**Status: design only; unsupported by the skills/MCP experiment.** Reviewed Markdown remains reference instructions. A `scripts/` mention, `allowed-tools`, executable path, command, dependency URL or model proposal cannot create executable authority. No shell fallback, package installation or MCP process startup is permitted. Existing Code execution contracts do not automatically enroll skill packages.

This proposal extends the boundaries in [spec-agent-execution](../../../docs/spec-agent-execution.md) and [spec-instruction-skills](../../../docs/spec-instruction-skills.md); it does not add a second harness or approval system.

## Proposed request and execution boundary

1. An operator reviews a pinned artifact manifest separately from enabling its Markdown. The manifest names a content digest, source revision, license, entrypoint digest, interpreter/version, locked dependency digests and a supported executor capability. No interpreter/package may be inferred from prose or downloaded at execution time.
2. A request names that reviewed artifact and entrypoint ID, structured arguments, tenant/project/chat and an idempotency key. The server resolves all paths from the pinned manifest. Model-supplied paths, shell fragments, credentials, environment overrides or mount requests cannot select executables.
3. The authoritative executor verifies owner/project, current artifact/review hash, capability, argument schema, account policy and resource grants before approval or launch. Unsupported capability returns an explicit `unsupported` result with a bounded reason such as `executor_unavailable`; it never tries the host shell or a different interpreter.
4. After approval, revalidate hashes, scope and grants immediately before launch. Execute only in the declared sandbox; publish bounded results/artifacts with provenance. Changed pins or grants require a new request/review, not silent substitution.

## Required contract before implementation

| Concern | Required behavior |
| --- | --- |
| Executor identity | Explicit host/node, harness/version, sandbox image digest, interpreter/version and capability report. Refuse missing or weaker isolation; ordinary process spawning is not a sandbox guarantee. |
| Filesystem | Read-only artifact/dependencies, private per-run scratch, explicit project-scoped input copies/mounts, no ambient home or host mounts. Reject traversal and symlink escapes; writes leave the sandbox only through approved publication. |
| Network/credentials | Deny egress by default. Any network grant specifies scheme/host/port, DNS/redirect/private-network rules and byte/time limits. Secrets come from scoped references and minimal environment injection; no inherited ambient environment, logs or credential-bearing URLs. |
| Resource bounds | Manifest/operator ceilings for wall time, CPU, memory, processes, disk, file count and output bytes; request may narrow but never raise them. Truncate output with an explicit marker and final status. |
| Approval | Reuse Allow once / Decline / Allow for this chat, showing complete executable identity, arguments and requested effects. A write never becomes globally allowed. Chat approval is tenant/chat/capability scoped and cannot survive a changed artifact or expanded permission envelope. Decline launches nothing. |
| Script effects | A shell program cannot be safely classified as read-only from its text. Enforce no-write/network grants in the sandbox or classify the action as requiring approval. Approval does not remove isolation. |
| Cancellation | Propagate abort through preparation, approval wait, launch and execution. Terminate the entire process group/container with bounded grace then force termination; revoke grants and clean scratch. If completion/effects are uncertain, report `unknown` and do not retry automatically. |
| Provenance | Record request/run ID, scoped owner references, artifact/entrypoint/dependency digests, executor identity, permission-envelope hash, approval ID/outcome, timestamps, exit status, limit/cancellation reason and output artifact digests. Keep task text, bodies, arguments and secrets out of experiment metrics; protected approval records are a separate access-controlled surface. |
| Publication | Validate output paths, type/size and ownership before export. Treat stdout/files as untrusted content; a script cannot issue follow-up permissions or modify the authoritative conversation record. |

Suggested terminal outcomes are `unsupported`, `rejected`, `declined`, `cancelled`, `timed_out`, `failed`, `succeeded` and `unknown`; absence of an executor is not success. These names are a future design vocabulary, not an implemented runtime API.

## Acceptance and adoption gate

A future implementation needs synthetic isolation tests for cross-tenant/path/symlink escapes, changed artifact pins, missing interpreter/dependencies, blocked egress/redirects, secret redaction, resource/output exhaustion, cancellation before and after launch, process descendants, all three approval decisions and chat-scope separation. Verify that an unavailable executor causes no subprocess, install, network call or fallback execution. Test uncertain completion without automatic retry and validate publication ownership.

Only after these contracts are implemented and independently reviewed should an explicitly authorized sandbox integration run be proposed. Quality measurement then distinguishes instruction adherence, script correctness and final task completion. This offline slice neither implements that executor nor supplies evidence to enable it.
