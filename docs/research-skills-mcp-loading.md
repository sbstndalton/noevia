# Skills portability and bounded skill/toolbox selection

Implementation and research gates for [issue #19](https://github.com/sbstndalton/noevia/issues/19). The offline experiment is implemented; live quality and adoption remain pending. This is not a deployment record.

Run instructions, contract boundaries and reproducible results: [offline experiment](../experiments/system-one/skills-mcp/README.md). The [runtime matrix](../experiments/system-one/skills-mcp/compatibility.md) and [script design](../experiments/system-one/skills-mcp/script-execution-design.md) separate supported behavior from deferred capabilities.

## Evidence and current behavior

A practitioner observation supplied by the user says Markdown skills can work across providers, with variable consistency, and that script-backed skills also depend on the execution environment. Its speaker, original URL/date, model versions and measurements were unavailable. Treat it as a hypothesis, not evidence of provider superiority or a common standard.

Noevia already has the authoritative boundaries this work must reuse:

- reviewed, enabled, project-owned Markdown skills are pinned for one exchange;
- the model sees a bounded skill metadata index and can load a body through the existing project-file tool;
- optional embedding routing auto-loads at most one reviewed skill body and otherwise loads none;
- optional embedding routing narrows only project-selected toolboxes and otherwise retains the full permitted selection;
- deterministic code applies MCP availability/auth readiness, tool count/token budgets, account policy, execution allowlists and write approval.

System-One currently routes model roles and supports step supervision. It does not select skills or MCP toolboxes. MCP discovery is configured-server discovery, not prompt-driven authorization.

## First implementation slice: offline and default-off

The fixture-driven experiment lives under `experiments/system-one/skills-mcp/`. It must not be wired into production chat, call a live model/provider, install a package, start an MCP server, execute a skill script or change a production setting.

Compare three modes on identical frozen and held-out synthetic fixtures:

1. current permitted baseline;
2. current embedding/rules routing; and
3. a bounded decision proposal followed by deterministic validation.

Inputs are a synthetic task plus pinned eligible catalogues. Skill candidates carry stable project/file identity, reviewed/enabled state, content hash, bounded name/description, body size and optional requirements. Toolbox candidates carry stable box/server IDs, descriptions/tool summaries, project selection, account readiness, dependencies, count/token estimates and configuration revision.

The untrusted selector returns only candidate IDs, scores/confidence and optional abstention. It cannot return a URL, credential, command, executable path, package or server process. Deterministic code then rejects unknown, duplicate, stale-hash, disabled, cross-project, unselected, unready, dependency-incomplete, blocked and over-budget candidates before loading a body or exposing a schema.

Preserve the current distinct fallbacks:

- skill routing failure keeps the enabled metadata index and auto-loads no skill body;
- toolbox routing failure keeps the project's full permitted selected toolbox set.

Accepted selection never grants credentials, write permission or executable authority. Skill bodies come only from the pinned snapshot; tool schemas and calls continue through existing resolution, policy, allowlist and approval paths.

The generic decision layer advertises `multi`, but its result validator does not currently validate the selected array and no production caller was found. Reuse a fully specified primitive such as `rank`/bounded `choice`, or first define and test `multi`: selected type, offered IDs, duplicates, abstention, min/max cardinality, score requirements, confidence and fallback.

## Fixtures and measurements

Contract fixtures cover exact/no/overlapping matches; changed or disabled skills; missing requirements; unselected/unready servers; dependencies, collisions and budgets; unknown/duplicate/malformed IDs; partial/non-finite scores; low confidence; remote disallowed by policy; timeout/error/cancellation; malicious instructions; cross-project IDs; configuration changes; `more_tools`; account block; and Allow once, Decline and Allow for this chat.

Record fixture/config/catalogue hashes, eligible/proposed/accepted/loaded IDs, fallback reason, actual body/schema load, selection correctness, instruction adherence, task completion, latency, prompt/schema bytes, estimated and measured tokens where available, and unauthorized actions. Logs contain no task text, skill bodies, arguments, credentials or private source content.

Scripted decision answers prove validation and fallback only. Live selector quality remains unavailable until configured runtimes are explicitly authorized. When measured, freeze a held-out set, record model/runtime/version/host/dependencies/permissions/context, repeat stochastic cases at least three times, and do not tune against held-out results.

Adoption requires zero unauthorized actions and no held-out task-completion regression. Report schema-token savings separately from end-to-end latency and total tokens. Publish adopt/defer/reject, with rollback, rather than inferring adoption from confidence or one successful load.

## Script-backed skills: separate proposal

Instruction-only skills do not authorize executable packages. Before any implementation, specify interpreter and dependencies, pinned artifact identity, sandbox/host, filesystem and network/egress scope, time/output limits, cancellation, approval behavior and audit evidence. Missing capability returns an explicit unsupported result; it never falls back to the host shell. Loading an MCP schema is separate from starting a server process or installing dependencies.

## MCP candidate decisions

README review is source discovery, not a security or compatibility audit. Before adoption, pin a revision/version and inspect license, maintenance, Streamable HTTP compatibility, schema conversion, credential/network behavior, startup/dependency cost, failure handling and measured value.

- **getfounded/mcp-tool-kit — reject adoption.** GitHub marks it archived. Its documented stdio/SSE transports and broad registration do not fit the current Streamable HTTP client and curated manifests. Catalogue/group ideas remain a historical reference.
- **ezyang/codemcp — historical reference.** Its maintainer calls it obsolete. Predeclared capabilities and Git-versioned edits may inform Code mode; auto-accept and harness replacement are excluded.
- **modelcontextprotocol/servers — qualify individually.** The repository describes educational reference implementations, not a production bundle.
- **nickclyde/duckduckgo-mcp-server — defer.** Consider only after pinned transport and maintenance review plus synthetic retrieval quality, citations, latency, rate-limit and fetch-control comparison with the configured baseline.

## Verification baseline

The contract audit used `fd5f0e0689ada46ad9a8c7ee518a11e5128abba3`. With the checkout's expected server dependencies available, the repository suite passed 1,247/1,247. No live model/MCP call, private Diary read or candidate installation contributed to these conclusions.
