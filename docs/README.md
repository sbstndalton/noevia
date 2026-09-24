# noevia docs

Use this page to find current project documentation. The roadmap tracks shipped
features and active work; the changelog and deployment runbook record releases.

| File | What it is | Read it when |
| --- | --- | --- |
| [agent-brief.md](agent-brief.md) | Orientation, build/test, architecture, the hard "do not" rules | **Start here** on any fresh session |
| [roadmap.md](roadmap.md) | The one plan: where things stand, what is done, what is next in order, what needs the user | Deciding what to do next |
| [sources.md](sources.md) | Every outside repo, product and document used, and whether it ships | Checking what something is built on, or adding a new source |
| [master-prompt.md](master-prompt.md) | The one executable brief: rules, testing, deploying, decisions D1–D27 | Handing work to an agent |
| [roadmap-history.md](roadmap-history.md), [master-prompt-history.md](master-prompt-history.md), [ui-overhaul-master-prompt.md](ui-overhaul-master-prompt.md), [ui-overhaul-phase2-prompt.md](ui-overhaul-phase2-prompt.md) | Archived plans and briefs — the reasoning behind past decisions, not status | Asking *why* something was decided |
| [session-kickoff.md](session-kickoff.md) | The short prompt to paste when starting a session | Starting a new agent session |
| [deployment.md](deployment.md) | Live DaServer runbook; `deploy/examples/overlay-release.sh` | Shipping to production |
| [changelog.md](changelog.md) | What was fixed and how it was verified | Checking whether something is done |
| [design-system.md](design-system.md), [spec-ui-direction.md](spec-ui-direction.md), [ui-reference-review.md](ui-reference-review.md) | Palette, contrast, visual direction, references | Touching UI |
| [diary.md](diary.md), [dav.md](dav.md), [spec-diary-markdown-workspace.md](spec-diary-markdown-workspace.md), [spec-diary-recovery.md](spec-diary-recovery.md), [spec-diary-shared-editing.md](spec-diary-shared-editing.md), [spec-diary-smb.md](spec-diary-smb.md), [spec-managed-diary.md](spec-managed-diary.md), [spec-storage-appliance.md](spec-storage-appliance.md) | Diary and storage | Touching the Diary or storage |
| [spec-context-projection.md](spec-context-projection.md), [spec-agent-execution.md](spec-agent-execution.md), [spec-deep-research.md](spec-deep-research.md) | Context layers/compaction/reduction; qualification, Prompt Architect, CodeHarness, durable work, execution nodes, browser; deep research | Context, agent-execution or deep research work |
| [research/system-one/](research/system-one/README.md) | Local-first System-One architecture: decision layer, residency, checkpoints, adaptive model switching, capability DB, provider/OAuth matrix, benchmark plan | Any routing, RAG, model-lifecycle or provider work |
| [research-skills-mcp-loading.md](research-skills-mcp-loading.md) | Plan for measured skill/toolbox selection, skills portability, script support and four MCP candidates | Researching or implementing skill/tool loading |
| [research-remote-access.md](research-remote-access.md) | Headscale vs NetBird vs Tailscale recommendation | Changing remote access |
| [research-master-container.md](research-master-container.md) | Docker socket threat model and master-container recommendation | Changing container lifecycle or the model manager |
| [research-known-good-settings.md](research-known-good-settings.md) | Hardware, live presets vs measured context, provisional limits | Changing model presets |
| [research-language-consolidation.md](research-language-consolidation.md) | Languages in use, where a chat turn's time goes (measured), and why nothing is ported | Before proposing a rewrite or a port |
| [spec-reasoning-effort.md](spec-reasoning-effort.md), [spec-tool-routing-research.md](spec-tool-routing-research.md), [spec-model-guidance.md](spec-model-guidance.md), [spec-document-understanding.md](spec-document-understanding.md), [spec-mtp-artifacts.md](spec-mtp-artifacts.md), [spec-instruction-skills.md](spec-instruction-skills.md), [spec-backend-portability.md](spec-backend-portability.md), [spec-direct-llamacpp.md](spec-direct-llamacpp.md) | Design specs: reasoning effort, tool routing, model guidance, documents, MTP, skills, backend | Working in that area |

Repo-root docs are unchanged and remain authoritative for their subjects:
`README.md` (quick start), `DEPLOY.md` + `cowork.setup.json` (generic
agent-executable deploy), `SECURITY.md` (trust model).
