# Google Drive read tools are treated as writes

Found in live testing on release `aa5132b`, 2026-09-23.

Settings → Connectors → Google Drive listed "Read-only tools (0)", and chat gated every Drive search and read behind approval. `isWriteTool` treats anything outside `readOnlyToolNames()`, and that set was collected only from `allToolboxes()`, which is filtered by `ENABLED_TOOLBOXES`. Drive is a per-user connector box (reached through `connectedBoxes`) and isn't in that list live, so its `READS` were never counted.

Implemented: `readOnlyToolNames()` now collects `reads` from every known box (built-in, connector and MCP) whether or not it is offered. What a chat is offered is unchanged. "Unknown ⇒ write" and the MCP `readOnly === false` override are unchanged.

## Verification

- New test in `server/toolboxes.test.cjs`: with `gdrive` excluded from `offered`, the four Drive reads are reads, the three writes and an unknown Drive tool are writes, and `allToolboxes()` still omits `gdrive`. It fails on `main` and passes here.
- Full `npm test`, typecheck and build: see the PR.

Not done here: the minor "New chat doesn't close Settings" note from the live session.
