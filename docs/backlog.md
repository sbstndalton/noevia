# Backlog — reconciled 2026-09-12

The user resumed roadmap implementation. This replaces the stale checklist;
[roadmap.md](roadmap.md) and the latest audit record deployment evidence.

## Completed from the older backlog

- Qwen3.5 9B vision projector configuration and synthetic image verification.
- Bounded DOCX reading, PDF/OCR and image processing.
- Repeated real Linux container builds, Compose validation and deployments.
- noevia daily backups on a separate array disk, with a verified isolated restore.
  See [the backup runbook](../deploy/backups/README.md) for actual scope and limits.
- Cold-model context resolution and per-model allocation observations: `cc59e8f`.
  This is not automatic maximum-capacity calibration or a model speedup.

- Instruction-skill lifecycle and source/RAG exclusion: `095d308`.
- Host-side Unraid boot-storage preflight and gated Compose-up wrapper;
  installed and verified against live configuration in dry-run mode.

## Active work

- Complete authenticated Mac SMB pilot and real Diary cutover. Existing 80-file
  originals match and are preserved; the production dedicated mapping is not on.
- Browser-local Diary pending-save recovery and optional-tool preparation history;
  saved-storage conversation recovery is implemented (see spec-diary-recovery.md).
- Install and verify the scoped Claude Diary bridge; compare reference behavior
  using synthetic examples, without real Diary prompts.
- Finish per-model capacity qualification and evaluate deployment profiles;
  preserve workload/hardware/backend identity and safe memory headroom.
- Deferred tool discovery and planner/executor experiments, following the scoped
  research plan rather than adopting an unmeasured framework.
- Remaining storage appliance managed-volume defaults and companion-backed
  namespace operations; do not advertise general DAV compliance prematurely.

## Queued investigation — 2026-09-13

- Backend portability: evaluate direct llama.cpp, a pinned/custom backend under
  Lemonade, and separately vLLM. Include management/context adapters and portable
  tested profiles, with measured reliability and performance. The user requested
  roadmap inclusion for consideration; no immediate backend migration.

## Smaller open items

- Automatic/staleness-based refresh of attached project sources.
- Review older projects without a managed folder; preserve existing attachments.
- Optional empty-folder cleanup after project deletion (currently retained safely).
- Updated chat titles after message edits; branching remains a product/data-model
  decision rather than an implied change to existing destructive editing.
- MCP availability/degraded-state indicator and current toolbox-manifest audit.
- Usage cost estimates and administrator aggregation.
- Scheduled/Plugins/Explore/Coding preview treatment; these are not functional
  execution systems. Optional offline Wikipedia needs an available service.
- Broader model accuracy, reasoning-budget, MTP and multi-GPU benchmarks.

Backup follow-ups: include the new Diary corpus after migration, exercise a full
restored companion/provider workflow (web startup is verified), and establish off-site recovery if chosen.
The new job does not back up unrelated appdata or the entire Nextcloud service.
