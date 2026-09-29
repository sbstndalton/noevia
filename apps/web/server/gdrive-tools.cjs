'use strict';
// The Google Drive toolbox: seven tools over the calling account's own Drive connection
// (drive-accounts.cjs). Offered to a chat only when that account is connected, and each tool
// is further gated by the account's tool policy (tool-policy.cjs). Descriptions stay short
// because every tool definition is re-sent on every turn.
const { driveFiles } = require('./gdrive-files.cjs');

const fn = (name, description, properties = {}, required = []) => ({ type: 'function', function: { name, description, parameters: { type: 'object', properties, required } } });
const ID = { fileId: { type: 'string', description: 'Drive file id from a search or list result' } };

// #659: the tools that read or write a file's content say they are for Google Drive, by Drive
// file id, and not for the files uploaded to a project. A request about a project's own file
// then goes to the project tools, which edit in place, conditionally, with the file named on
// the approval card.
const NOT_PROJECT = 'Not for files uploaded to this project; use the project file tools for those.';
const TOOLS = [
  fn('drive_search_files', 'Search the user\'s Google Drive (files noevia created or was given) by name or text.', { query: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 25 } }, ['query']),
  fn('drive_read_file', `Read a text file, Google Doc, Sheet (as CSV) or Slides deck from Google Drive, by Drive file id. ${NOT_PROJECT}`, ID, ['fileId']),
  fn('drive_get_metadata', 'Get a Google Drive file\'s name, type, size, dates and link.', ID, ['fileId']),
  fn('drive_list_recent', 'List the most recently changed files in Google Drive.', { limit: { type: 'integer', minimum: 1, maximum: 25 } }),
  fn('drive_create_file', `Create a new text file in the user's Google Drive. ${NOT_PROJECT}`, { name: { type: 'string' }, content: { type: 'string' }, mimeType: { type: 'string', description: 'text/plain (default), text/markdown, text/csv or application/json' } }, ['name', 'content']),
  fn('drive_update_file', `Replace the whole content of a text file in Google Drive, by Drive file id. Read it with drive_read_file in this chat first. ${NOT_PROJECT}`, { ...ID, content: { type: 'string' } }, ['fileId', 'content']),
  fn('drive_trash_file', 'Move a Google Drive file to the trash (recoverable for 30 days).', ID, ['fileId']),
];
const READS = ['drive_search_files', 'drive_read_file', 'drive_get_metadata', 'drive_list_recent'];
// How Settings names each tool, in the order it lists them.
const LABELS = {
  drive_search_files: 'Search files', drive_read_file: 'Read file content', drive_get_metadata: 'Get file metadata', drive_list_recent: 'List recent files',
  drive_create_file: 'Create file', drive_update_file: 'Update file', drive_trash_file: 'Trash file',
};

// Drive's own id alphabet. Anything else (a project path such as "noevia projects/…/notes.md")
// is not a Drive file, and is refused before an approval card is shown.
const DRIVE_ID = /^[\w-]{1,200}$/;
// The writes that change an existing file, whose card names that file.
const EXISTING_FILE_WRITES = new Set(['drive_update_file', 'drive_trash_file']);
const READ_TTL_MS = 6 * 60 * 60 * 1000;
const READ_MAX = 2000;

const line = (f) => `- ${f.name} (id ${f.id}) · ${f.mimeType || 'file'}${f.size ? ` · ${f.size} bytes` : ''}${f.modifiedTime ? ` · changed ${f.modifiedTime}` : ''}`;

function createDriveTools({ accounts, cap = 8000, now = Date.now }) {
  // The box description is what the toolbox picker shows (worded from the catalogue, #615); the
  // model is steered by the tool descriptions above (#659).
  const box = {
    id: 'gdrive', label: 'Google Drive', source: 'builtin',
    description: 'Search, read and write files in your connected Google Drive (only files noevia created or was given).',
    tools: TOOLS, reads: READS,
  };
  const names = new Set(TOOLS.map((t) => t.function.name));
  const connected = (user) => { try { return accounts.forUser(user).drive.state().state === 'connected'; } catch { return false; } };

  // #659: the Drive version each chat read, per account, chat and file. drive_update_file
  // replaces a whole file, so it runs only against the version this chat read in full: a file
  // changed elsewhere since, read only in part, or never read here is refused, nothing written.
  const reads = new Map(); // key -> { version, complete, at }
  const readKey = (user, chatKey, id) => `${(user && user.id) || ''}\u0000${chatKey || ''}\u0000${id}`;
  function remember(user, chatKey, id, version, complete) {
    if (version === undefined || version === null || !id) return;
    const key = readKey(user, chatKey, id);
    reads.delete(key);
    reads.set(key, { version: String(version), complete, at: now() });
    while (reads.size > READ_MAX) reads.delete(reads.keys().next().value);
  }
  function lastRead(user, chatKey, id) {
    const hit = reads.get(readKey(user, chatKey, id));
    return hit && now() - hit.at <= READ_TTL_MS ? hit : null;
  }

  /** The Drive file a write would change, for its approval card (#659): `{ target, kind }`;
   *  `{ error }` when it names no Drive file (refused before the card, nothing written); or null
   *  for a tool with no target. `kind` is 'drive' for an existing file, 'drive-new' for a new one. */
  async function describeTarget(user, name, rawArgs) {
    if (!names.has(name) || READS.includes(name)) return null;
    let args;
    try { args = typeof rawArgs === 'string' ? JSON.parse(rawArgs || '{}') : rawArgs; } catch { return null; }
    if (!args || typeof args !== 'object' || Array.isArray(args)) return null;
    if (name === 'drive_create_file') {
      return typeof args.name === 'string' && args.name.trim() ? { target: args.name.trim().slice(0, 255), kind: 'drive-new' } : null;
    }
    if (!EXISTING_FILE_WRITES.has(name)) return null;
    const id = typeof args.fileId === 'string' ? args.fileId.trim() : '';
    if (!DRIVE_ID.test(id)) {
      return { error: `${JSON.stringify(id.slice(0, 200))} is not a Google Drive file id. The Google Drive tools only change files in the connected Google Drive; to change a file uploaded to this project, use the project file tools (project_append_file or project_replace_text)` };
    }
    try {
      const { drive } = accounts.forUser(user);
      if (drive.state().state !== 'connected') return { error: 'Google Drive is not connected for this account' };
      const meta = await driveFiles(drive).metadata({ fileId: id });
      return { target: `${meta.name} (id ${meta.id})`, kind: 'drive' };
    } catch (error) {
      return { error: error.publicMessage || 'Google Drive could not be reached' };
    }
  }

  async function execute(user, name, args, { chatKey = null } = {}) {
    let files;
    try {
      const { drive } = accounts.forUser(user);
      if (drive.state().state !== 'connected') return 'ERROR: Google Drive is not connected for this account. Connect it in Settings → Connectors.';
      files = driveFiles(drive);
      switch (name) {
        case 'drive_search_files': { const r = await files.search(args); return r.length ? `Found ${r.length}:\n${r.map(line).join('\n')}` : 'No matching files. noevia only sees files it created or was given in this Drive.'; }
        case 'drive_list_recent': { const r = await files.recent(args); return r.length ? r.map(line).join('\n') : 'No files yet. noevia only sees files it created or was given in this Drive.'; }
        case 'drive_get_metadata': { const f = await files.metadata(args); return `${line(f)}${f.webViewLink ? `\nLink: ${f.webViewLink}` : ''}`; }
        case 'drive_read_file': {
          const r = await files.read(args);
          const text = r.text.slice(0, cap);
          const partial = r.truncated || r.text.length > cap;
          remember(user, chatKey, r.meta.id, r.meta.version, !partial);
          return `${r.meta.name}:\n${text}${partial ? '\n[truncated]' : ''}`;
        }
        case 'drive_create_file': { const f = await files.create(args); remember(user, chatKey, f.id, f.version, true); return `Created ${f.name} (id ${f.id})${f.webViewLink ? `: ${f.webViewLink}` : ''}`; }
        case 'drive_update_file': {
          const id = typeof args.fileId === 'string' ? args.fileId.trim() : '';
          const seen = DRIVE_ID.test(id) ? lastRead(user, chatKey, id) : null;
          // An id that is not a Drive id falls through to files.update, which refuses it by name.
          if (DRIVE_ID.test(id) && !seen) return 'ERROR: drive_update_file replaces the whole file, so it only runs on a file read in full with drive_read_file in this chat. Read it first. Nothing was changed.';
          if (seen && !seen.complete) return 'ERROR: only part of this file was read in this chat, so replacing it would drop the rest. Nothing was changed.';
          const f = await files.update(args, seen ? { expectVersion: seen.version } : {});
          // What this chat wrote is what it now knows, so a further edit here is checked against it.
          remember(user, chatKey, f.id, f.version, true);
          return `Updated ${f.name} (id ${f.id}).`;
        }
        case 'drive_trash_file': { const f = await files.trash(args); return `Moved ${f.name} to the Drive trash.`; }
        default: return `ERROR: unknown Drive tool ${name}`;
      }
    } catch (error) {
      return `ERROR: ${error.publicMessage || 'Google Drive could not be reached.'}`;
    }
  }

  return { box, names, reads: new Set(READS), labels: LABELS, connected, execute, describeTarget };
}

module.exports = { createDriveTools, LABELS, READS };
