# Current continuation checkpoint — 2026-09-10

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
