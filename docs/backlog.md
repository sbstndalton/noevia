# Backlog — current execution 2026-09-14

Native chat selection/MTP guidance fixes and full mobile approval-card coverage
are deployed and production-verified as 02495a7. Continue Markdown date/tag filtering and portable workspace recovery.
GPU/app qualification and backend cutover are complete; see roadmap-audit.md.


Production was verified on `02495a7` on September 14. The dated checklist below
is historical; this current list supersedes its shipped/pending labels.

- Continue mobile bug fixes and phone/landscape UI verification, then repeat
  GitHub, candidate-image, production deployment and production verification.
  The user explicitly authorized this release cycle on September 14.
- Native llama.cpp is qualified and active in production. Keep one GPU inference
  backend active and retain the tested rollback configuration.
- App-owned Diary, Markdown editing, calendar, recovery, edited-message titles,
  service health checks, MCP availability and usage pricing/aggregation shipped
  by `55b2767`. Do not reimplement the older pending entries below.
- App-owned Diary supersedes the SMB working-corpus proposal. The real Diary
  remains on WebDAV until explicit verified import; use synthetic data for QA.
- Remaining scoped work: Markdown date/tag filtering and portable workspace
  export, the scoped Claude bridge client verification, and native workload
  reliability. Inspect existing storage/version/backup contracts before adding
  overlapping revision or retention features.
- DAV rename/delete/locking and general client interoperability need a defined
  storage contract. Empty remote folders remain retained to avoid racing uploads.
- Off-site recovery requires a destination/budget; optional Wikipedia requires
  a selected service. Neither is an installed capability or a release claim.

## Historical reconciliation — 2026-09-13

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
- Guarded generic fresh-install managed-volume setup; existing binds remain
  compatible and the live Unraid storage layout remains unchanged.

- Active-project source refresh (`8fa1112`): return/focus/online refresh with a one-minute
  cooldown and five-minute staleness checks while visible; waits during generation.

## Active work

- Complete authenticated Mac SMB pilot and real Diary cutover. Existing 80-file
  originals match and are preserved; the production dedicated mapping is not on.
- Finish browser QA and release of opt-in browser-local Diary recovery and optional-tool preparation history; implementation and synthetic HTTP checks are complete (see spec-diary-recovery.md).
- Install and verify the scoped Claude Diary bridge; compare reference behavior
  using synthetic examples, without real Diary prompts.
- Gemma 131,072 and Qwen 262,144 synthetic one-slot capacity profiles now qualify. Applying those profiles to another backend/build and broader workloads still needs measurement; preserve exact configuration identity and memory headroom.
- Initial deferred-discovery/planning comparison is complete: retain current routing.
  Distinct Smart/Fast pairs remain a later adoption gate; see the experiment report.
- Companion-backed DAV folder creation is implemented and tested. Rename/delete policy awaits the managed-path decision; locks and real client interoperability remain open. Do not advertise general DAV compliance prematurely.

## Queued investigation — 2026-09-13

- [Backend portability review](spec-backend-portability.md): evaluate direct llama.cpp, a pinned/custom backend under
  Lemonade, and separately vLLM. Include management/context adapters and portable
  tested profiles, with measured reliability and performance. The user requested
  roadmap inclusion for consideration; no immediate backend migration.

## Smaller open items

- Older-project audit complete: 52 ordinary projects, five managed; the remaining
  47 have no references/uploads/assets. Existing lazy folder creation is sufficient;
  no empty-folder migration performed.
- Optional empty-folder cleanup after project deletion (currently retained safely).
- Updated chat titles after message edits; branching remains a product/data-model
  decision rather than an implied change to existing destructive editing.
- Explicit Docker health checks for web/OCR (HTTP checks currently verify rollout).
- MCP availability/degraded-state indicator and current toolbox-manifest audit.
- Usage cost estimates and administrator aggregation.
- Scheduled/Plugins/Explore/Coding preview treatment is already implemented with
  disabled controls and explicit labels. Optional offline Wikipedia still needs
  a selected service; it is not an installed execution system.
- Broader model accuracy, reasoning-budget, MTP and multi-GPU benchmarks.

Backup follow-ups: include the new Diary corpus after migration, the full
synthetic restored companion/provider workflow now passes, and establish off-site recovery if chosen.
The new job does not back up unrelated appdata or the entire Nextcloud service.

## Implemented candidates awaiting UI verification / rollout

Production remains `8fa1112`. Candidate `6c45621` adds opt-in browser-local Diary
recovery, edited-first-message automatic titles and web/OCR Docker healthchecks.
The real image probes pass healthy/503-negative tests. Recovery behavior has passed
synthetic folder failure/conflict/reopen/account-isolation checks; final layout,
forget/disable and title interactions are pending stalled browser controls.

The next candidate adds MCP availability/degraded status, explicit administrator
model pricing and administrator aggregate usage. 367 tests, typecheck/build and
real HTTP permissions/isolation/pricing tests pass. Live read-only MCP audit:
160 Nextcloud and five Tavily tools; no missing curated names or explicit write
annotations in curated read allowlists. Discovery is not proof of execution access.

Off-site backup destination and budget are undecided by the user. Existing local
backups continue. Empty managed folders stay retained: recursive WebDAV deletion
can race a new external upload, so automatic cleanup needs a safer storage contract.


Latest candidate `8bc4339` includes all implementations above plus preparation
recovery, DAV folder creation and explicit manager-versus-engine version metadata.
Local verification passes 373 web tests, typecheck and build. Linux Diary passed
199 tests. The initial Linux web run exposed a same-millisecond test-ordering
assumption; the assertion now locates the capture by its ID. Final image validation
is recorded in roadmap-audit.md. Production remains `8fa1112` until UI verification.

The user selected browser-local recovery as opt-in. Off-site backup still has no
chosen destination or budget: it means another copy away from DaServer for host or
site loss. The existing local backup job remains in place; no external storage or
paid service has been provisioned. The production WebDAV corpus is outside that
job's current scope; dedicated-corpus coverage follows the storage cutover.
