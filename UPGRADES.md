# Cowork stack — upgrade & pin procedures

The stack is pinned against upstream drift so routine server maintenance
(`docker compose pull`, upstream image pushes, retags) can never silently change
behavior. Dependency updates arrive only as deliberate, reversible, changelogged
commits — matching the ground rules in MIGRATION.md.

## What is pinned, and how

| Image | Pin | Why this form |
|---|---|---|
| `ghcr.io/mintplex-labs/anything-llm` | `:latest@sha256:eb812f3d…` (index digest, captured 2026-09-03) | multi-arch index digest — same reference resolves on any host arch |
| `ghcr.io/berriai/litellm` | `:main-stable@sha256:a53a7d3f…` (index digest, captured 2026-09-03) | same |
| `diary-companion` | `:0.1.2` (locally built tag) | our code; the tag moves only via tracked commits + the release procedure below |

Digest pins never auto-update. That is the point: an upstream push cannot move a
running stack. Upgrades happen only through the procedures below.

## Upgrading an upstream image (deliberate, gated)

1. **Pre-flight:** read the upstream release notes for breaking changes; decide the
   upgrade window. Nothing is touched server-side yet.
2. **GO-gate:** explicit user sign-off (same rule as every deploy step in MIGRATION.md).
3. **Capture the new index digest** (any machine with Docker, or the registry API):
   ```bash
   docker buildx imagetools inspect ghcr.io/mintplex-labs/anything-llm:latest
   # → copy the top-level "Digest:" line (the multi-arch index digest)
   ```
4. **Re-pin in a tracked commit:** edit `docker-compose.yml`, swap only the
   `@sha256:…` suffix (keep the tag for readability). One commit per image upgrade.
5. **Deploy:** rsync to `/mnt/docker/appdata/cowork/`, then on the server:
   `docker compose up -d` — recreates only services whose image reference changed.
6. **Verify:** `docker compose ps` (all healthy); one `e4b` chat round-trip in
   AnythingLLM; one `diary` round-trip landing in the corpus;
   `docker compose logs --since 10m litellm` for routing errors.
7. **Changelog:** draft the row in `CHANGELOG-drafts.md` first, then append it to
   `DaServer.md` alongside the work (house rule: never after the fact).

**Rollback:** `git revert` the re-pin commit, rsync, `docker compose up -d`.
The old digest still exists upstream — nothing else to do.

## Releasing diary-companion (our code) into the stack

1. In the `diary-companion` repo: bump `agent/__init__.py __version__`, commit,
   tag `v<X.Y.Z>`, push `main` + tags.
2. On the server, rebuild so the tag exists on the host (build context is the repo
   checkout in appdata):
   `docker build -t diary-companion:<X.Y.Z> /mnt/docker/appdata/diary-companion`
3. Only then move cowork's pin: `docker-compose.yml` `image: diary-companion:<X.Y.Z>`
   + the README version-contract line, commit, push. **Never point the pin at a tag
   that does not already exist on the host.**
4. rsync + gated `docker compose up -d` (steps 5–7 above).

The standalone container (`:8010`) and the cowork sidecar may briefly run different
versions during a migration window — only one of them owns the corpus at a time
(MIGRATION.md §4), so no double-write risk.
