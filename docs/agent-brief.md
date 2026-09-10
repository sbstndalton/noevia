# noevia — agent brief

Read this top to bottom before touching anything. It assumes no prior context.
State verified at commit `8a78172`, 2026-09-09.

## What noevia is

A self-hosted web chat UI over a local OpenAI-compatible inference endpoint,
with projects, sources, a diary, MCP tool calling, and a human approval gate on
every write. Repo is `sbstndalton/noevia`, renamed from `cowork`.

Structurally it is a **harness**: a self-hosted container plus a GUI, wrapping a
model with tools, permissions, and a session loop. That framing explains two
design choices that otherwise look like local quirks — the toolbox permission
gating, and a diary whose *structure* is written by code while only its prose
comes from the model.

**Internal identifiers were deliberately kept as `cowork`** — env vars, image
and container names, session cookies, the package name, the state directory, and
`localStorage` keys. Do not "fix" those. Renaming any of them requires a
coordinated migration across the live deployment; see `deployment.md`.

## Orientation

- `apps/web/src/` — React + plain CSS. No Tailwind, no PostCSS. Constrain widths
  with `max-width` + `margin-inline: auto`.
- `apps/web/src/styles/` — `tokens.css`, `app.css`, `shell.css`, `noevia.css`,
  `popup.css`, `diary-tab.css`. **`noevia.css` loads LAST and overrides
  everything.** Rules added elsewhere can be silently dead. This has bitten twice.
- `apps/web/src/App.tsx` (842 lines) — chat state, SSE consumption, theme manager.
- `apps/web/server/index.cjs` (~3700 lines) — the whole server: routes, tools,
  MCP, routing, approvals.
- `apps/web/server/` — also `storage-client.cjs` (WebDAV/S3), `documents.cjs`
  (PDF text), `rag.cjs`, `mcp.cjs`, `workspace.cjs`, `auth.cjs`, `secrets.cjs`,
  `vision.cjs`, `model-manager.cjs`.
- `services/diary/` — FastAPI sidecar, multi-tenant by `X-Cowork-User-ID` header.
- `apps/web/tests/theme-contrast.test.cjs` — parses `tokens.css` directly.

### Build and test, from `apps/web/`

```sh
npm test        # 161 passing at 8a78172
npm run build
npm run typecheck
```

All three, every change — **`vite build` does not typecheck**, so a green build
proves nothing about types.

> Both master prompts warned that `npm run typecheck` was broken (`.bin` symlinks
> on the Nextcloud-backed filesystem lack the exec bit). **That was fixed** in the
> 2026-09-08 QA pass: every script in `package.json` now invokes Node directly
> (`node node_modules/typescript/bin/tsc --noEmit`). Ignore the old workaround.

`apps/web/node_modules` is a symlink to `~/.noevia-deps/node_modules`, and
`apps/web/dist` links to `/tmp/noevia-qa-dist` — the Nextcloud-synced copies
silently dropped files. Keep dependency installs and build output outside folders
the sync client evicts.

The local Node runtime lacks the optional `sqlite-vec` dependency, so smoke tests
fall back to direct source injection. A live RAG/embedding test needs the real
deployment.

## Architecture reference

### Sources

A project holds four kinds of source, and they are not interchangeable:

- **Text files** — stored as text, RAG-indexed.
- **PDFs** — native page text extracted by `documents.cjs` (`unpdf`).
  `document-sources.cjs` keeps originals and versioned pages within each user/project;
  compact text feeds RAG. Partial/failed/stale states reach the UI and model.
  **Not OCR**: image-bearing pages are conservatively flagged for OCR. Older local
  sources need re-uploading to preserve originals; see `spec-document-understanding.md`.
- **Images** — stored as bytes under `workspace.assetDir(projectId)`, never inline
  in `projects.json`. Attached to the last user turn as `image_url` parts.
- **Attached storage folders** — re-read on sync. Files from them carry
  `source: <folder>`; uploads do not. **The server owns folder-derived files; the
  client sends only uploads.** Breaking that invariant blanks file contents.

Every project created since `0a451e8` gets its own Nextcloud folder at
`noevia projects/<name>`, auto-attached as a source (new WebDAV projects; a
numbered suffix handles collisions). Existing paths remain unchanged; S3 retains
the unique ID suffix because it cannot atomically create directories. Uploads are written
there as real files then synced in — one path whether the file came from the
browser or was dropped into the folder from a phone.

`ownsFile()` in `index.cjs` guards deletion: a file may be deleted only if it sits
**directly** in a folder the project has attached. Sub-paths, traversal and
lookalike prefixes are refused. It has its own test. Deleting removes the file
from storage, not just from the project.

### Tools

- `MCP_SERVERS` takes `id|url|auth` entries. `auth` is `nextcloud` (forward the
  user's Nextcloud app password), `bearer:ENV_NAME` (a service token read from
  that env var), or `none`. **Omitting or misspelling it yields `none`** — a
  server never inherits a credential by accident.
- `MCP_SERVER_URL` still works and means one Nextcloud server with the credential.
- Currently: `nextcloud` (160 tools) + `tavily` (5 tools, `bearer:TAVILY_API_KEY`).
- `ENABLED_TOOLBOXES` selects which curated boxes are offered; unset offers all.
  `core` is always offered.
- Boxes must fit `toolCapFor()` — a box is all-or-nothing, and exceeding the cap
  silently delivers part of it.
- Two independent limits bind at resolve time: `toolCapFor(model)` and
  `toolTokenBudgetFor(model)`, the latter from *measured* prefill rate against the
  live endpoint (`tokens ≈ 240 + chars/3.6`, error table in `index.cjs`). Dropped
  tools are reported, never silently withheld.

**The approval gate is a security control, not decoration.** Every write tool
blocks the chat until a human answers. Arguments are shown in full and
untruncated — that IS the gate. Three distinct actions (Allow once / Decline /
Allow for this chat). There is **no global "never ask"** and there must not be.

**Prompt injection is live.** Search results are untrusted text entering context,
and the same project can hold Nextcloud tools including delete and public-link
creation. The approval gate is the real protection. Be deliberate about enabling
`web-search` alongside `nextcloud-sharing`.

### Models and vision

Lemonade at `http://10.69.0.130:13305/v1`. Installed: `Gemma-4-E4B-it-GGUF`,
`gemma-4-E2B-it-GGUF-UD-Q4_K_XL`, `Qwen3.5-9B-GGUF-UD-Q4_K_XL`,
`nomic-embed-text-v1-GGUF`.

Auto-routing has `fast`, `smart`, and an optional **`vision`** role. With `vision`
set, that model describes the project's images and the answering model reasons
over the description as text — so a model that cannot see can still answer about a
picture. Verified: Qwen3.5-9B read an invoice correctly from a Gemma-4-E4B
description.

Without a `vision` role, images go to the answering model if a cached probe says
it can read them. **A model that cannot read images answers 400 for the whole
request**, which is why the probe exists. Probes are scoped to endpoint,
credentials and model, expire, and now distinguish a missing projector from an
unsupported model — see `backlog.md` for the outstanding Qwen mmproj work.

### Placeholder surfaces

`Scheduled`, `Plugins` and `Explore` (`Sidebar.tsx`) route to `PreviewPanel`. The
Coding workspace renders `Interface preview · no execution` — separate navigation,
empty project/task areas, an activity grid, a draft composer, a collapsible
workspace panel. It does not read repositories, run commands, call a coding model,
or modify files; its draft resets when leaving coding mode. Scheduled tasks,
plugins, integrations, privacy, billing and usage tracking are marked previews with
disabled controls. Activity values are empty, not simulated.

## What NOT to do

- **Do not rename existing design tokens, `data-theme` values, or the
  `cowork-theme` storage key.** The contrast suite, the setup wizard, and every
  user's saved preference depend on them.
- **Do not introduce a parallel token system.** Extend the semantic scale.
- **Do not add Tailwind.** Plain CSS by choice.
- **Do not use `rgba()` for `--control-border` or `--focus-ring`** — the contrast
  test parses `#RRGGBB` only and *throws* on anything else. Decorative borders may
  use `rgba()` freely.
- **Do not remove or simplify the tool-approval card**, and never add a global
  "never ask".
- **Do not hard-code a user's name or data into the shell.**
- **Do not put a secret in a URL.** `MCP_SERVERS` URLs are logged verbatim on every
  startup. Tokens go in their own env var via `bearer:NAME`.
- **Do not let the client send folder-derived files back to the server.**
- **Do not vendor an agent framework.** `mcp.cjs` deliberately implements three
  JSON-RPC calls — `initialize`, `tools/list`, `tools/call` — and nothing more.
- **Do not send prompts to the diary.** It is the user's real private journal.

## Verification expectations

Automated tests have twice passed code that was obviously broken in one real
interaction. Manual verification is mandatory and has repeatedly caught what tests
did not.

For UI work: toggle the theme in **every** view (Chat, Projects, Code, Diary,
Settings, setup wizard) confirming no reload and no flash of the wrong palette
before React mounts; check 375 / 768 / 1440 widths in both themes; confirm no
horizontal overflow; tab through and confirm focus rings are visible on both
canvases.

For tool work: drive a real chat (one chip per tool *call*, named, with a result),
then a real **write** call — the approval card appears with full arguments and all
three buttons, declining returns a readable message, and "Allow for this chat"
suppresses the next prompt in that chat but **not** in another.

Verify against the live instance where behaviour depends on real data — Nextcloud
folders, MCP tools, vision. Several bugs here only appeared with real files
attached. `LEGACY_AUTH_COMPAT=false` on live, so there is no bearer-token path:
verifying needs a real browser session.

## Test artifacts left on the live instance

Safe to delete, listed so they are not mistaken for real data:

- Nextcloud notes `NOEVIA DELETE ME 1` (id 487351) and `NOEVIA DELETE ME 2`
  (487352), category `noevia-test`
- `Documents/noevia-folder-test/` and `made-from-ui/` inside it
- `noevia projects/ZZ Folder Test/` — empty, left by design when its project was
  deleted
- Project **Random Questions** has `Documents/Important Documents/Diary/Raw
  Sources` attached and its toolboxes set to `core` + `web-search` from testing.
  Its four diary files were pulled in as sources. Detach if unwanted.


### 2026-09-10 OCR/image follow-up

The later user request authorized finishing PDF/photo support, pushing, and
production rollout. `services/ocr` now supplies bounded local Poppler/Tesseract
OCR, preserving original/native text and labelling transcriptions. Source polling
keeps long jobs out of a single proxy request; restart recovery is manual retry.
Missing/truncated image handling and description cache scope are fixed. Qwen 9B's
matching mmproj was configured and verified on synthetic image content. See the
latest audit/deployment sections for limits and final rollout evidence; historical
native-only observations above describe the earlier state.
