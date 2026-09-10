# Backlog

Every open item from every source, deduplicated. Planned *projects* live in
`roadmap.md`; this is the list of loose ends.

Sources merged: both master prompts' open-work sections, `QA-2026-09-08.md`'s
remaining live work, and `ui-overhaul.md`'s leftovers.

## Infrastructure — top priority

**Backups.** `/mnt/docker` is a single-device btrfs pool on one NVMe with no
redundancy and no backup, holding `secrets.key`, which decrypts stored provider API
keys. The Unraid Appdata Backup plugin is installed but unconfigured. Everything
else on this page is less important than this.

## Models and vision

1. **Qwen3.5 mmproj.** Qwen3.5 *is* a vision model; it currently fails with
   `image input is not supported — hint: you may need to provide the mmproj`. Its
   multimodal projector was never downloaded. unsloth publishes `mmproj-BF16.gguf`,
   `mmproj-F16.gguf`, `mmproj-F32.gguf` in `unsloth/Qwen3.5-9B-GGUF`; model files
   live at `/mnt/user/ai-models/models--unsloth--*/snapshots/<hash>/`.

   **`gemma-4-E2B` has its mmproj on disk and still fails the probe**, so Lemonade
   is not automatically loading projectors. Find out how it is configured to load
   one for E4B before assuming a download alone fixes Qwen. If Qwen gains vision it
   both sees and reasons well, which may remove the need for the two-stage
   pipeline — though the pipeline stays useful for choosing which model looks.

2. ~~Vision probe reports a verdict, not a reason~~ — **done**, see `changelog.md`.

## Projects and sources

3. **Periodic source re-sync.** Sources refresh on project-dialog save and on manual
   Refresh. A file edited directly in Nextcloud is not noticed until one of those.
   Consider a staleness check on project open, or a background re-sync.
4. **Backfill project folders.** Projects created before `0a451e8` have no
   `projectFolder`, so uploads there fail with a message saying so. Live has one:
   **Random Questions**. Projects that already share a folder are not automatically
   split or moved either.
5. **Deleting a project leaves its folder.** Deliberate — removing a project should
   not destroy files — but folders accumulate. Consider offering to remove an empty
   one.
6. **Documents beyond PDF.** `documents.cjs` is structured for more types; `.docx`
   via `mammoth` or similar is the obvious next one. **No OCR path exists** for
   scanned PDFs.

## Tools

7. **Tavily hygiene.** 1,000 free credits/month. `tavily_search` is 1–2 credits;
   **`tavily_crawl` is many requests from one call** and can spend a month's
   allowance on one large site — hence the separate `web-crawl` box. Consider
   leaving it disabled. Be deliberate about enabling `web-search` alongside
   `nextcloud-sharing`: search results are untrusted text and the approval gate is
   the real protection.
8. **`MCP_TOOLBOX_MANIFEST` may be behind upstream.** `nextcloud-mcp-server` now
   advertises 110+ tools plus semantic search across Notes, Files, News, Deck and
   Mail. Worth a re-scan for tools that belong in existing boxes.

## Chat

9. **Chat titles do not update when a message is edited.**
10. **Message editing is destructive, not branching.** Deliberate — it is what makes
    the token saving real — but Claude and ChatGPT keep the old branch behind a
    `< 1/2 >` switcher. A data-model change; decide before users get attached to
    either behaviour.

## UI

11. **"Local MCP Active" indicator.** Achievable from `GET /api/toolboxes`
    (`{ mcp: { configured, error, discovered } }`) but **not wired**. Show a
    degraded state when `mcp.error` is non-null.
12. **The placeholder question — needs an operator decision.** `Scheduled`,
    `Plugins`, `Explore` and the Coding workspace are previews. Hiding them behind a
    flag versus styling them as first-class navigation are opposite calls, and this
    was never settled.

## Usage

13. **Usage page**: cost estimates and an admin-wide aggregated view.

## Testing

14. **Live RAG/embedding smoke test.** The local Node runtime lacks the optional
    `sqlite-vec` dependency, so smoke tests fall back to direct source injection.
    Needs the real deployment.
15. **Container builds and Compose validation** were never run locally — Docker was
    unavailable on the Mac.
