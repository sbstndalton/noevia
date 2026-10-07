# ADR 0001: Rust for untrusted-input leaf work, and splitting the repo

Status: accepted, 2026-10-06. Issue: [#897](https://github.com/sbstndalton/noevia/issues/897).
Amended 2026-10-06 with the owner's language rule ([#952](https://github.com/sbstndalton/noevia/issues/952)).
Supersedes §4 "Do not port anything" of
[research-language-consolidation.md](research-language-consolidation.md).

## Context

On 2026-10-06 the owner set two directions:

1. **Rust is the preferred language for new native work.** Later the same day the owner made
   this a rule: all new non-browser code is Rust (see "Language rule" below).
2. **Separate repositories** for the web client, the backend and the macOS app, instead of
   one monorepo.

The 2026-09-21 measurement still stands: Node is about 0.6 % of a paced reply's wall time
(41 ms of CPU across 7.3 s), so a port buys no user-visible speed. Rust is chosen for a
different reason: **memory and bounds safety where noevia parses untrusted input** (uploaded
documents, archives, imported exports, tool and model output, DAV bodies), plus the owner's
preference. Speed is not the argument and must not be used as one in later PRs.

## Decision

### Language rule (owner, 2026-10-06)

- **All new code that does not run in the browser is Rust**: server endpoints and services,
  workers, CLIs, and build and release tooling. New Node, `.cjs`, Python or shell tooling is not
  added beyond trivial glue (a CI step, a few lines in an existing script) or edits to existing
  files.
- **Code that runs in the browser stays as it is**: TypeScript, React, CSS, HTML.
- **Existing Node keeps running until it is replaced slice by slice.** There is no big-bang
  rewrite. Each slice follows the strangler rule below: contract-tested against the Node
  implementation and shipped dark behind a flag the owner switches on. Existing Python sidecars
  keep running too; a fix inside them is an edit to existing code, not new code.

The first example is `tools/repo-split` (#952), the extraction tool for the repository split,
written in Rust under this rule.

### What may move to Rust (strangler rule)

- This governs **moving existing Node code**; new code follows the language rule above.
- Only **leaf work** moves: a pure function or a self-contained parser/transformer with no
  session, tenant or approval state of its own.
- It sits behind an **internal HTTP endpoint, a CLI, or a WASM module**, called from the existing
  Node code. Node remains the caller and owns every policy decision.
- Each port is **contract-tested**: the same synthetic fixtures run against the Node and the Rust
  implementation, and both must agree before the Rust path is used.
- It ships **dark**: behind a feature flag that defaults off. Only the owner switches it on.
  The Node implementation stays until the owner removes it.

### What is not ported yet

These keep their existing implementation for now. "Not ported" means no port is scheduled; it
does not exempt new work there from the language rule.

- **Diary** (services/diary) and its corpus handling.
- The **chat loop**, **write approvals** (all three actions: Allow once, Decline, Allow for this
  chat), **auth**, **CSRF**, and **tenant scope** checks. These are policy, and policy stays in
  one place: the Node server owns it until a slice is deliberately replaced with its own ADR,
  contract tests against the Node behaviour, and a flag. A Rust service never re-implements
  these checks on the side.

### Request path: no Rust gateway in front of Node (yet)

- **No Rust gateway or proxy in front of `server/index.cjs`.** The request path, session gate
  and mounts stay in Node until the owner decides otherwise in a later ADR.
- **New server functionality is Rust** all the same: it runs as an internal service or CLI that
  the Node server calls (behind its session, tenant and approval checks), not as new Node modules.
  Over time those Rust services replace Node slice by slice; the gateway question is decided when
  enough of the request path has moved for it to matter.

### Repository map

| Repo | Owns |
| --- | --- |
| `noevia` | Integration and release: docs, deploy/, compose files, qa/, `release/versions.lock` |
| `noevia-web` | React client (today `apps/web/src/`, `public/`, build scripts) |
| `noevia-core` | Node server (today `apps/web/server/`) and `services/code-sandbox`; owns `contracts/` |
| `noevia-macos` | macOS app ([sbstndalton/noevia-macos](https://github.com/sbstndalton/noevia-macos); split out of `clients/macos/` in #900) |
| `noevia-rs` | Cargo workspace for Rust leaf crates (created 2026-10-06) |
| `noevia-services` | The Python sidecars (diary, docling, laya, model-manager, ocr) |

Created 2026-10-06 (#952): [noevia-web](https://github.com/sbstndalton/noevia-web),
[noevia-core](https://github.com/sbstndalton/noevia-core) and
[noevia-services](https://github.com/sbstndalton/noevia-services), extracted from noevia with
history by `tools/repo-split`. Until the cutover in
[repo-split-cutover.md](repo-split-cutover.md) the paths still live here and noevia stays the
source of truth; `release/versions.lock` keeps `self` for all three.

`contracts/` (today `apps/web/contracts/`) holds the data both client and server read
(project icons, project limits). noevia-core owns it; noevia-web consumes a pinned copy.

### Release assembly

- The Mac assembles a release from **pinned sources**: `release/versions.lock` names one commit
  per repo, and each is exported with `git archive` into the release tree. The server has no git
  credentials and never clones.
- `COWORK_VERSION` stays equal to the **integration repo (`noevia`) SHA**. Per-service tags
  (`DIARY_VERSION`, `OCR_VERSION`, …) keep their current meaning. `NOEVIA_SERVICES_REF` pins
  noevia-services the same way `NOEVIA_WEB_REF` / `NOEVIA_CORE_REF` pin web and core.
- `cowork*` identifiers are unchanged by the split.

## Preparation in this repo (#897)

Done before any repository is created, so main stays releasable at every step:

- `apps/web/contracts/` holds `project-icons.json` and `project-limits.json`; the runtime image
  copies it next to `server/` and the overlay release ships it.
- `apps/web/tests/` is split into `tests/client/` and `tests/server/` (`npm run test:client`,
  `npm run test:server`; `npm test` runs both).
- `scripts/check-boundaries.cjs` fails CI if `src/` imports from `server/` or the reverse.

## Consequences

- Every cross-boundary need goes through `contracts/` or an HTTP API, never a relative import.
- A Rust PR must state the untrusted input it hardens, link its contract tests, and name its flag.
- Multi-repo releases need the lock file and an assembly script before the first split lands;
  until then this monorepo remains the single source.
