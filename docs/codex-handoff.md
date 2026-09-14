# Paste-ready Codex continuation prompt

Continue work on noevia in this repository:
`/Users/sebastiandalton/Library/CloudStorage/Nextcloud-drive.daserver.work-SebastianDalton/Documents/ai-agentic-folder/Projects/Docker App Projects/AI frontend thing/noevia-application`

Read `AGENTS.md`, `docs/agent-brief.md`, `docs/roadmap-audit.md`,
`docs/spec-ui-direction.md`, `docs/design-system.md`, `docs/ui-reference-review.md`
and `docs/prototypes/README.md` first. Use the latest dated instructions when
historical roadmap statements conflict. Check git status and current state before
editing. Do not discard existing work.

## My immediate request

“The glass is looking quite good in the sidebar. Now just needs to be implemented
across the whole ui. Top to bottom. The settings panel is untouched. Also, need to
start working on these settings.”

Keep the existing layout I developed through Claude and ChatGPT suggestions.
I want mature, artistic design, with the precision/material interest of
architecture and Apple Liquid Glass. I rejected childish names, pastel toy tiles,
and superficial bevel/color changes. The current sidebar treatment is a good
starting point: extend it consistently through the whole app, including Settings,
without moving the established navigation, project grid, chat reading column,
composer, Settings structure or Diary side panel.

Audit Settings category by category against actual frontend and server code.
Identify what works, what is only a preview, and what lacks wiring or persistence.
Start implementing concrete missing behavior, with honest loading/error states,
persistence and verification. Do not invent a large feature set from vague labels.
Ask about actual conflicts or missing decisions while continuing independent work.

Use the installed UI UX Pro Max skill at
`/Users/sebastiandalton/.codex/skills/ui-ux-pro-max/SKILL.md`.
Its upstream is https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.
Previous agents installed/read/searched it and reviewed saved textual layout
references and Apple's materials guidance. They did not complete a proper visual
reference study of architecture, Apple or Lego. Do not claim otherwise. Generic
marketing/children's design-system suggestions were unsuitable. Preserve my latest
positive feedback rather than starting another unrelated visual direction.

## Current implementation and preview

Last implementation commit: `5dd573c`, pushed to main at
https://github.com/sbstndalton/noevia. Later handoff documentation may be at HEAD.
No app-wide glass or new Settings behavior has been implemented since that commit.

Local preview: http://localhost:31287/
Run `npm --prefix apps/web run build`, then `node docs/prototypes/preview.cjs`
if it is not running. This wraps the real built React app with a synthetic fixture
on ports 31287/31289. Source: `docs/prototypes/preview.cjs`, `playful.css`,
`glass.js`. The stylesheet filename is historical, not a request for childish UI.
The preview is not production. Many settings/edit/persistence endpoints are not
implemented in this fixture. Extend mocks intentionally; a generic successful
mock response is not proof of real functionality.

Study 03 fixed a real mobile account-menu bug: sidebar backdrop-filter formed a
stacking context that put the menu behind content. Do not reintroduce filtered
ancestors that trap menus. It also removed root palette overrides that prevented
Warm/Cool/Neutral from working. All six appearance combinations now work.
The mode switch has bounded blur, optical rim and pointer reflection; menus have
readable glass surfaces. Reduced-motion/transparency and contrast fallbacks exist.
This is a web CSS material treatment, not Apple's native refraction renderer.
Settings has not yet received the requested complete treatment.

373 web tests, typecheck and build passed at last implementation. Focused browser
QA covered Projects at 375/768/1440, both themes, all palettes, mobile account menu
and Settings opening, project menus, Diary and a synthetic chat. This is not full
all-view QA or evidence of production integration. Inspect the running app yourself.

## Implementation and safety constraints

React and plain CSS, no Tailwind. `apps/web/src/styles/noevia.css` loads last.
Extend existing semantic tokens; preserve theme/palette identifiers and
`cowork-theme` / `cowork-palette` storage keys. Keep all compatibility identifiers.
Use synthetic data only: never send test prompts to the real Diary or modify its
corpus. Preserve tenant isolation, complete tool arguments and all three approval
actions (Allow once / Decline / Allow for this chat). No global approval bypass.

Run `npm --prefix apps/web test`, `npm --prefix apps/web run typecheck`, and
`npm --prefix apps/web run build` after code changes. Verify every view, Settings
category, light/dark and all palettes, widths 375/768/1440, overflow, keyboard focus,
menus, reading/editing and loading/error/empty states. Keep dependencies/builds off
the synced filesystem: current node_modules and dist symlinks are intentional.
Use available browser controls for visual QA. An earlier native Codex-app access
was safety denied; do not retry or bypass that. Browser controls later worked.

## Deployment and remaining roadmap

Continue the roadmap autonomously in tested increments; I previously authorized
implementation and deployment and said to ask about conflicts while continuing
other work. Do not claim the entire roadmap is complete. Do not spawn agents or
new tasks unless explicitly authorized. Do not send messages to others.

Production was last verified on `8fa1112`; candidate `8bc4339` images are built but
not deployed. Candidate includes opt-in browser-local Diary recovery (my explicit
choice; default off), preparation history, title fixes, healthchecks, MCP status,
explicit usage rates/admin totals and model-manager metadata. It passed 373 local
web tests, 318 isolated Linux web tests and 199 Linux Diary tests, plus image health
probes. Remaining browser QA gates deployment. Keep the functional candidate
reviewable independently of the redesign. Recheck live state before any rollout.

Live host: root@10.69.0.130, app https://cowork.daserver.work.
Follow `docs/deployment.md`, not generic DEPLOY.md for this existing installation.
All Compose up operations must use
`/mnt/docker/appdata/cowork/tools/preflight/up.sh`.
Do not expose credentials or change server/storage configuration speculatively.

Other outstanding items:
- Dedicated Diary SMB pilot exists with synthetic data, but Mac authenticated
  mount/visibility and real cutover remain pending. Keep SQLite journal local;
  do not assume WAL is safe on a network filesystem. No unverified live migration.
- Off-site backups await destination and budget. I said I do not recall what this
  refers to; explain the current backup scope when asking. Local synthetic restore
  passed; current WebDAV corpus is not automatically included. Do not choose a
  paid/external destination on my behalf.
- Managed DAV rename/delete policy remains undecided. Protect managed paths.
- Claude Diary bridge protocol checks passed; actual client synthetic workflow
  remains to verify. Never print connection secrets.
- Qwen context calibration completed at 262144 context / 253944 input with q8 KV,
  one Vulkan slot, b10920; marker test passed. Production Gemma 32768 settings were
  restored; no active calibration remains. See docs/evidence and experiment docs.
  Synthetic capacity success is not quality, vision or concurrent-load validation.
- HF selected-artifact MTP checks and cold-load context improvements are already
  implemented; inspect current docs/code before duplicating them. Backend swap
  research (Lemonade vs custom llama.cpp/vLLM) remains a roadmap experiment, not
  authorization to silently migrate production. Saved backend candidate not started.

Start by inspecting the current preview and Settings implementation. Preserve what
I now like, make the app-wide treatment concrete, and keep the roadmap updated with
what is implemented, verified, deployed and still undecided.
