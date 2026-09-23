# Google Drive read tools are treated as writes

Status: plan only; implementation pending. Found in live testing on release `aa5132b`, 2026-09-23.

## What happens

Settings → Connectors → Google Drive shows **"Read-only tools (0)"**, and all seven tools under "Write and delete tools", including Search files, Read file content, Get file metadata and List recent files. Those four are reads (`READS` in `server/gdrive-tools.cjs`). Every Drive search or read in chat therefore stops for approval, and the page misreports which tools write. It fails safe, but it adds friction and mislabels things.

## Cause

- `routes/connectors.cjs` (and chat approvals) decide with `isWriteTool(name)`, which in `server/toolboxes.cjs` returns true for anything outside `readOnlyToolNames()`.
- `readOnlyToolNames()` collects `reads` only from `allToolboxes()`, and that list is filtered by `offered(id)` (the `ENABLED_TOOLBOXES` env).
- The live `ENABLED_TOOLBOXES` doesn't include `gdrive`: Drive is a per-user connector box that reaches chats through `connectedBoxes(user)`, not through `ENABLED_TOOLBOXES`. So the Drive box's `reads` are never collected, and every Drive tool counts as a write.

## Fix

- Build the read-only set from every box noevia knows, including connector boxes (`CONNECTOR_BOXES`), independent of `offered()`. `offered()` decides what a chat gets, not whether a tool writes.
- Keep "unknown ⇒ write" and the MCP `readOnly === false` override exactly as they are.
- Tests:
  - with `offered` excluding `gdrive`, `isWriteTool('drive_search_files')` is false and `isWriteTool('drive_trash_file')` is true;
  - the connectors route lists 4 read-only and 3 write tools;
  - a chat that calls `drive_read_file` doesn't produce an approval card.
- After deploying, check Settings → Connectors → Google Drive shows "Read-only tools (4)", and check where each user's saved per-tool modes (`policy.mode`) land for those four tools.

## Also seen (minor, same session)

With Settings open, clicking "New chat" leaves Settings on top. The chat underneath has focus, so typing goes into an input the user can't see. Consider closing Settings when "New chat" is chosen.
