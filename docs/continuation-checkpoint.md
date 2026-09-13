# Current continuation checkpoint — 2026-09-10

## Latest application increments — 2026-09-12

Instruction skills shipped in `095d308`: explicit review/enable/disable, hashed
updates and RAG/source exclusion. The requested MTP artifact inspection followed
as `f6688f3`; see [artifact evidence](spec-mtp-artifacts.md). It checks the chosen
public HF quantization, not installed byte identity, and does not enable MTP.
Saved-storage Diary recovery then shipped in `f7b9d95` (356 local / 308 Linux tests);
see spec-diary-recovery.md for crash uncertainty and local-folder exclusions.
The remaining roadmap stays active; see the reconciled [backlog](backlog.md).

## Roadmap resumed — 2026-09-12

The user explicitly resumed the remaining roadmap with “Just go”. The earlier
testing pause is superseded. Continue in tested, documented deployment increments:
reconcile stale backlog, ship the verified context fix, establish durable backups
and restore evidence, then complete instruction skills, Diary recovery and the
remaining scoped storage/tool experiments. Preserve all approval gates and tenant
isolation. Mac SMB authentication remains an independent pending client step.
No subagents or new Codex tasks were requested.

## Latest handoff — 2026-09-12

The user explicitly authorized implementing the dedicated Diary-only SMB plan.
Storage support is part of the unified release (from `cc59e8f` onward). The old
Diary-only image/build pin was deliberately removed when its source was included;
inference networks remain preserved. All later releases retain the unset dedicated
mapping until the real SMB pilot/cutover succeeds. See deployment.md for current
image tags and rollback backups.

The synthetic `Diary-Pilot` share exists and is restricted to SMB user sebastian,
read-only, no guests/symlinks, private networks. Mac NetAuthAgent is waiting for
that existing password; an asynchronous request asked the user to sign in there
without pasting it. No real corpus migration or sync-selection change yet.
Once signed in, verify `/Volumes/Diary-Pilot/visibility.md` (currently synthetic
version three), same-name/atomic replacements and reconnect. Then rehash/drain,
copy to a dedicated outside-Nextcloud volume, configure identity/reader UID 1000,
export only its corpus, and enable the selected tenant's DIARY_LOCAL_VOLUMES.
Keep SQLite outside the share. Preserve the old prefix to retain journal/index
keys. SMB stays read-only; API/noevia guarded writes remain authoritative.

Preflight: selected tenant `17522ab5-9f26-4913-890c-b9b08376cfa4`, corpus prefix
`Documents/Important Documents/Diary`, source under
`/mnt/user/nextcloud/Sebastian Dalton/files/`. Mac/server 80 files match; originals,
comparison and SQLite snapshots live at `~/.local/share/noevia/diary-migration/20260912/`.
Remote snapshots: `/mnt/docker/appdata/cowork/state/diary/migration-backups/20260912-diary-smb/`.
0 pending/0 dirty at preflight. Recheck before cutover. 192 local/3 skipped, 195
Linux tests passed; synthetic real-image HTTP/bind tests passed. Canonical
DaServer log updated. See [the full evidence](spec-diary-smb.md).
Unrelated roadmap work remains paused.

Model Loader management UI is running on
8092; test inference was stopped after calibration and original Qwen options
restored. Gemma's near-128k test passed; Qwen 256k has only load/smoke evidence.
Existing uncommitted context-loading fixes, HTTP QA and calibration tooling belong
to that earlier user request; preserve them. They are not production changes.

The older checkpoint below is historical and does not override this handoff.

**Paused for user testing.** The user will test the current release for a couple
of days. Do not implement or deploy more roadmap changes until they provide
feedback or ask to resume. Do not create an automatic restart or monitoring task.
See docs/roadmap.md for the full shipped/remaining and Claude Diary clarification.

When resumed, continue in tested/pushed increments. User chose reusable
instructions using existing approved tools for skills, not executable packages.
No subagents requested. Claude-equivalent Diary behavior remains unverified;
compare reference instructions and synthetic behavior after user feedback.

## Current work

Wizard/storage batch 9e2bfbb deployed successfully, including the earlier limited
DAV implementation. Skill metadata fix 79cd24f is pushed and it is deployed on all three services. Confirm the current release on the host
before continuing. The docs audit status table supersedes historical entries.

Local verification: 314 web tests, typecheck/build, 171 Diary tests (3 skipped,
two existing warnings). Skill metadata has exact filenames and bounded escaped
JSON; actual chat-handler request assertion passes. No new UI for that fix.
Wizard browser checks include hosted/external choices, failed load/save, skip
preservation, server save with sharing off, all existing resume/member/role cases,
and 375/768/1440 light/dark focus/layout. Screenshots:
/tmp/noevia-resume-wizard-screens. Only synthetic accounts and services used.

## Deployment

Home-LAN SSH: root@10.69.0.130 works. Tailscale 100.70.173.74 timed out on resume;
do not change network settings unnecessarily. Public app: cowork.daserver.work.

Live base /mnt/docker/appdata/cowork; current symlink and releases/<sha>. Secrets
in config/.env must never be printed. Compose Manager project directory:
/boot/config/plugins/compose.manager/projects/Cowork. Live compose files are
separate from repo examples; keep all existing mounts and config. DAV remains
port 0, no publication, no production device credentials created.

Prepared local/remote scripts /tmp/noevia-build-79cd24f.sh and switch counterpart.
Candidate checks: 267 serial isolated Linux server tests and eight real worker
checks. Never cut over failed candidates; retain previous releases and config
backups. Current production baseline is 79cd24f. Check current before building
subsequent scripts. build scripts package git archive, build all three images,
run isolated network-none tests with read-only fixtures, then write success marker.
Switch scripts check baseline, back up env/config, update current and version, and
rollback automatically if compose --wait fails.

## Remaining priorities

- Instruction skills proposal is docs/spec-instruction-skills.md (pushed 701ec5a).
  Existing project-file index is now fixed for filename/bounds. Explicit selection,
  inspect/enable/disable/update lifecycle, migration and source/RAG exclusion remain
  planned. Existing skillsIndexFor parses frontmatter; existing bodies also enter
  ordinary source context. Preserve current users until explicit review.
- Important prerequisite found during inspection: rag.filesContext currently adds
  all searchProject hits without filtering hit filenames to its supplied `files`
  list. Any future disabled-skill exclusion must filter vector hits as well as
  direct/fallback injection. Do not assume passing fewer files hides indexed text.
- Workstream5 experiment plan: docs/spec-tool-routing-research.md (pushed b223736).
  No planner/executor or deferred-discovery benchmark has been performed. Optional
  offline Wikipedia needs a selected service. No vendor framework or auto-approval.
- Storage: limited Markdown OPTIONS/HEAD/GET/PROPFIND/conditional PUT implemented;
  no DAV class compliance or general file-manager mounting claim. MKCOL/MOVE/DELETE/
  COPY/LOCK etc need companion API support, not direct volume writes. See docs/dav.md
  and spec-storage-appliance.md. Production sharing must stay off unless requested.
- Managed fresh-install volume default and Unraid resolved /boot guard remain open.
  Do not silently switch existing COWORK_STATE_DIR bindings to empty named volumes.
- Wider model budgets, local uncapped thinking and performance/accuracy remain open.
  High hint currently requests 8192 tokens, not guaranteed higher than an unknown
  implicit default. Do not promise uncapped generation without verified support.
- Insights badge was removed from the product; do not resurrect unused auth schema
  as a cosmetic setting merely to satisfy historical roadmap wording.

## Workspace and invariants

Read AGENTS.md, agent-brief and roadmap-audit. Preserve cowork-prefixed contracts,
accepted UI/composers, Diary extras OFF on reload, companion capture/retrieval,
tenant isolation and all three write approval actions. Never test the real diary.

Repo: noevia-application under the AI frontend thing workspace. npm scripts under
apps/web. Keep node_modules -> ~/.noevia-deps/node_modules and dist ->
/tmp/noevia-qa-dist. PLAYWRIGHT_MODULE:
/Users/sebastiandalton/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright
QA scripts clean their disposable servers/state. Prior persistent fixtures on
31240/31244 were stopped before disconnect. Old browser tabs may remain pointing
there; do not mistake them for production. No active background monitor/automation.

## Backend portability discussion — 2026-09-12

User asked whether repeated workarounds justify replacing Lemonade with direct
llama.cpp or vLLM. No production inference migration performed. Recommendation:
test direct llama.cpp with per-model saved profiles and adapt management/context
reporting; OpenAI-compatible chat alone does not replace Lemonade's management API.
Existing standalone test showed capacity/control benefits, not a generation speedup
(13.75 versus 13.71 tok/s across different configurations). Current upstream llama.cpp
documents router presets/model limits. Current Lemonade documents custom pinned
backend binaries, an intermediate option requiring installed-version verification.
vLLM now lists Ryzen AI 300 gfx1150 with ROCm >=7.0.2; DaServer's complete
kernel/driver/model stack has not been qualified. Do not assert its GPU is unsupported.

## Latest user steering — 2026-09-13

User requested adding backend portability to the roadmap as a possible future
investigation and, for now, explaining what has been implemented and why.
Roadmap/backlog updated; this is not authorization to switch production backends
immediately. Current application release remains f7b9d95.
