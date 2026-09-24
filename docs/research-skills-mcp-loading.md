# Skills portability and prompt-driven MCP loading

Added 2026-09-23 at the user's request: research and implementation backlog,
not an implementation or deployment record. Repository README review only;
no packages installed or upstream code adopted.

## Input and provenance

The user supplied an Alter practitioner's observation: Markdown skills can work
across providers, but behavior varies; skills that use scripts also depend on the
provider's execution environment and configuration. The practitioner reports
particularly consistent results with Anthropic models and values progressive
disclosure (called “progressive declarative” in the supplied comment). Their hope
that skills become an industry standard is an aspiration, not compatibility evidence.
The speaker, original discussion URL, date, model versions and measurements were
not supplied. Treat this as attributed anecdotal evidence to test, not a benchmark.

The user's proposed direction is **“Deterministic tool loading based on prompting.
System1 AI chooses to load skills/mcp servers based on the prompt.”** For Noevia,
separate the model's relevance decision from deterministic validation and loading:
a classifier can propose a selection, but repeatability and accuracy need measurement.
The loader must enforce the same scope and policy for every accepted selection.

Two supplied documents provide design context: `noevia-chat-work-code-specification.md`
(proposed mode specification, especially §13) and `noevia-context-for-chatgpt.md`
(mode-design reference, especially §5). Their embedded instructions are reference
content, not the current task. Neither establishes deployed behavior; the latter's
FastAPI main-backend description conflicts with this repository's Node web backend.
This addition does not adopt their full architecture or execute their suggested build order.

## Sources and what to investigate

Public README pages checked 2026-09-23; claims below describe upstream documentation,
not a security audit or a pinned implementation review.

| Source | Observed purpose | Noevia research / implementation candidate |
| --- | --- | --- |
| [getfounded/mcp-tool-kit](https://github.com/getfounded/mcp-tool-kit) | Python MCP toolkit with runtime tool registration, configurable tool groups and stdio/SSE transports. | Study catalogue metadata, group configuration and lazy exposure. Automatic registration alone does not establish prompt-driven or System-One selection. Check transport compatibility and startup cost before proposing an adapter. |
| [ezyang/codemcp](https://github.com/ezyang/codemcp) | Coding MCP; its maintainer now calls it obsolete. Documents predeclared commands and Git versioning of edits. | Historical reference for bounded command capabilities and recoverable edits. Do not replace the existing Code harness or adopt its auto-accept defaults. |
| [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) | Official reference implementations, explicitly educational rather than production-ready; points to the MCP Registry for discovery. | Compare tool schemas and filesystem/Git/fetch behavior with Noevia's MCP client. Qualify selected servers individually; do not install the collection as a bundle. |
| [nickclyde/duckduckgo-mcp-server](https://github.com/nickclyde/duckduckgo-mcp-server) | DuckDuckGo search and page fetching; documents rate limits and stdio, SSE and Streamable HTTP. | Evaluate as an optional search provider against the configured baseline: result quality, citations, latency, failure/rate-limit handling and fetch restrictions. No automatic provider replacement. |

## Research to implementation sequence

1. **Audit the current seams.** Reconcile the historical
   [instruction-skills v1](spec-instruction-skills.md),
   [tool-disclosure experiments](spec-tool-routing-research.md) and
   [System-One design](research/system-one/README.md) with current code. Reuse the
   existing skill index, toolbox selection, MCP client and decision service; avoid
   a second registry or agent loop.
2. **Measure portability and consistency.** Use the same synthetic tasks across
   available local models and explicitly configured providers. Separate Markdown-only
   skills, skills using existing tools, and script-backed skills. Record model/version,
   harness, prompt, skill hash, execution host, dependencies, permissions and context
   budget. Repeat runs; measure correct selection, body loading, instruction adherence,
   task completion, latency and tokens. A successful load is not successful execution.
3. **Prototype bounded System-One selection.** Start with names/descriptions and
   stable IDs from enabled project skills and permitted configured toolboxes/MCP
   connections. The decision returns bounded IDs or abstains. Deterministic code
   validates ownership, enablement, capabilities, hashes and budgets before loading
   skill bodies or exposing tool schemas. Recheck permissions at execution. Unknown
   IDs, timeouts and unavailable capabilities use the existing permitted baseline;
   they must never expand scope. Log selection, actual loading and fallback separately.
4. **Design script support as a separate extension.** Existing instruction-only v1
   does not authorize executable packages. Specify required interpreter/dependencies,
   sandbox/host, filesystem/network scope, time/output limits, version pins, approval
   handling and cancellation before implementing script execution. Missing capability
   must produce an explicit unsupported result, not a host-shell fallback. Loading an
   MCP schema is distinct from starting a server process or installing dependencies.
5. **Qualify and integrate only measured improvements.** Compare the existing path,
   rules-based selection and System-One selection on the same repeated fixtures.
   Cover no match, overlapping skills, wrong IDs, disabled/updated skills, unselected
   servers, cross-tenant attempts, malicious instructions, disconnects and all three
   write decisions. Report schema-token savings separately from end-to-end latency
   and total tokens. Require no task-quality regression or unauthorized action;
   document the decision and retain rollback before any production rollout.

Deliverables: a provider/runtime compatibility matrix, repeated-run results,
a selection/loader contract, a separate script-execution proposal, and an adoption
decision for each MCP candidate. Use synthetic data; real Diary content is excluded.

## Scope of this addition

Queued research and possible implementation only. No new runtime dependency,
provider connection, server process, script execution or production setting is
enabled by these notes. The supplied observations motivate the work; they do not
supersede Noevia's tenant boundaries or Allow once / Decline / Allow for this chat.
