'use strict';
// Revoked Skills in earlier turns (#546). #543 stops a reply the moment a Skill it loaded is disabled
// or changed, but the chat history the client sends with the NEXT message can still carry that
// Skill's instructions: a read_project_file / project_read_file result replayed as a tool message,
// or an assistant reply that repeated the body. This module removes them server-side, before the
// history reaches the model. The client's history is never trusted to say what came from a Skill.
//
// What counts as Skill content is decided only from server-held records:
//   - a tenant-scoped ledger (one file in the account's own workspace directory, keyed by project)
//     of every Skill version an exchange put in front of the model, with SHA-256 fingerprints of
//     its lines. Fingerprints, not text: the ledger keeps no copy of a Skill body.
//   - the project as stored now: a Skill that is disabled still has its reviewed body there.
// A version is revoked when its (file, SHA-256) is no longer an enabled Skill of the project. For a
// revoked version, three things in the history are replaced with a short neutral placeholder:
//   - a tool/function message that is the Skill reader's output for it (its heading names the
//     SHA-256): the whole message;
//   - any other line that names its SHA-256;
//   - runs of lines whose normalised text matches its fingerprints (a verbatim echo of the body).
// Lines that also belong to a Skill that is still enabled are left alone, and user messages are
// never changed: the person may have typed or pasted that text themselves.
//
// Limits (documented, deliberate): a paraphrase or an inline quotation inside a longer line is not
// recognised; only verbatim lines are. Text that merely claims to be from a Skill but matches no
// server record is ordinary history. A server-side compaction summary built over the old text no
// longer applies once the covered history changes (chat-context.cjs fingerprints that prefix), so
// it is rebuilt from the scrubbed history rather than reused.
const crypto = require('node:crypto');
const instructionSkills = require('./instruction-skills.cjs');

const FILE = 'skill-history.json';
const MAX_VERSIONS = 64; // per project, oldest dropped first
const MAX_LINES = 2000; // per version; a Skill body is at most 32 KiB
const STRONG = 16; // a normalised line this long identifies a Skill on its own; shorter ones only extend a match
const SHA = /\b[a-f0-9]{64}\b/g;
const READER = /^(?:Loaded instruction skill |Loaded part of instruction skill )/;

const normalise = (line) => String(line).replace(/^\s*(?:[-*+>]|#{1,6}|\d+[.)])\s+/, '').replace(/\s+/g, ' ').trim().toLowerCase();
const fingerprint = (text) => crypto.createHash('sha256').update(text).digest('hex').slice(0, 16);
function fingerprints(content) {
  const out = new Set();
  for (const line of String(content || '').split(/\r?\n/)) {
    const n = normalise(line);
    if (n && n !== '---') out.add(fingerprint(n));
    if (out.size >= MAX_LINES) break;
  }
  return out;
}
const placeholder = (names) => `[Skill ${[...names].map((n) => JSON.stringify(n)).join(', ')} was disabled or changed, and its instructions were removed]`;

function createSkillHistory({ fs, path, cacheMax = 256 }) {
  // dir -> { projects: { [projectId]: [{ file, name, hash, lines: [fingerprint], at }] } }. Read from
  // disk once per account directory, then served from memory, so a chat without Skills costs a map
  // lookup. Every write goes to memory and disk together.
  const cache = new Map();
  function load(dir) {
    if (cache.has(dir)) { const v = cache.get(dir); cache.delete(dir); cache.set(dir, v); return v; }
    let state = { v: 1, projects: Object.create(null) };
    try {
      const parsed = JSON.parse(fs.readFileSync(path.join(dir, FILE), 'utf8'));
      if (parsed && typeof parsed.projects === 'object' && parsed.projects) state = { v: 1, projects: Object.assign(Object.create(null), parsed.projects) };
    } catch { /* absent or unreadable: nothing recorded yet */ }
    cache.set(dir, state);
    while (cache.size > cacheMax) cache.delete(cache.keys().next().value);
    return state;
  }
  function persist(dir, state) {
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, FILE), tmp = `${file}.${crypto.randomUUID()}`;
    fs.writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
    fs.renameSync(tmp, file);
  }
  const entries = (dir, projectId) => {
    const list = load(dir).projects[projectId];
    return Array.isArray(list) ? list : [];
  };

  /** Records one Skill version an exchange loaded. Idempotent per (project, file, SHA-256). */
  function record(dir, projectId, { file, name, hash, content }) {
    if (!dir || !projectId || typeof file !== 'string' || !/^[a-f0-9]{64}$/.test(String(hash || ''))) return false;
    const state = load(dir);
    const list = entries(dir, projectId);
    if (list.some((e) => e.file === file && e.hash === hash)) return false;
    const next = [...list, { file, name: String(name || file).slice(0, 160), hash, lines: [...fingerprints(content)], at: Date.now() }].slice(-MAX_VERSIONS);
    state.projects[projectId] = next;
    try { persist(dir, state); } catch (error) { console.warn(`[skills] could not record a loaded skill: ${error.message}`); }
    return true;
  }

  /** The versions of this project's Skills that were in front of a model once and are not enabled now. */
  function revokedVersions(dir, project) {
    const recorded = dir ? entries(dir, project.id) : [];
    const tracked = project.instructionSkills && Object.keys(project.instructionSkills).length > 0;
    if (!recorded.length && !tracked) return { revoked: new Map(), enabled: [] };
    const now = tracked ? instructionSkills.list(project) : [];
    const enabled = now.filter((s) => s.status === 'enabled');
    const enabledHashes = new Set(enabled.map((s) => s.hash));
    const active = new Set(enabled.map((s) => `${s.file}\0${s.hash}`));
    const revoked = new Map(); // SHA-256 -> { name, lines: Set }
    for (const e of recorded) {
      if (active.has(`${e.file}\0${e.hash}`) || enabledHashes.has(e.hash)) continue;
      const known = revoked.get(e.hash);
      if (known) for (const l of e.lines || []) known.lines.add(l);
      else revoked.set(e.hash, { name: e.name || e.file, lines: new Set(e.lines || []) });
    }
    // A disabled Skill still holds its reviewed body in the project, so one loaded before the ledger
    // existed is recognised too. Never-reviewed or merely changed files were never offered to a model.
    for (const s of now) if (s.status === 'disabled' && !enabledHashes.has(s.hash) && !revoked.has(s.hash)) revoked.set(s.hash, { name: s.name || s.file, lines: fingerprints(s.content) });
    return { revoked, enabled };
  }

  function scrubText(content, revoked, byLine, keep) {
    const lines = String(content).split('\n');
    // S: identifies a revoked Skill; W: matches one but is too short to decide alone; B: blank; N: other.
    const marks = lines.map((line) => {
      const hashes = String(line).match(SHA) || [];
      const named = hashes.filter((h) => revoked.has(h));
      if (named.length) return { kind: 'S', names: named.map((h) => revoked.get(h).name) };
      const n = normalise(line.replace(/\r$/, ''));
      if (!n) return { kind: 'B' };
      const fp = fingerprint(n);
      if (keep.has(fp) || !byLine.has(fp)) return { kind: 'N' };
      return { kind: n.length >= STRONG ? 'S' : 'W', names: byLine.get(fp) };
    });
    const out = [], removed = new Set();
    for (let i = 0; i < lines.length;) {
      if (marks[i].kind === 'N') { out.push(lines[i]); i++; continue; }
      let j = i;
      while (j < lines.length && marks[j].kind !== 'N') j++;
      let a = i, b = j - 1;
      // Trim the run to its outermost strong lines, then take in short matching lines directly next to
      // them. Blank lines and short lines further out stay as they were.
      while (a <= b && marks[a].kind !== 'S') a++;
      while (b >= a && marks[b].kind !== 'S') b--;
      if (a > b) { out.push(...lines.slice(i, j)); i = j; continue; }
      while (a > i && marks[a - 1].kind === 'W') a--;
      while (b < j - 1 && marks[b + 1].kind === 'W') b++;
      const names = new Set();
      for (let k = a; k <= b; k++) for (const name of marks[k].names || []) names.add(name);
      for (const name of names) removed.add(name);
      out.push(...lines.slice(i, a), placeholder(names), ...lines.slice(b + 1, j));
      i = j;
    }
    return { text: removed.size ? out.join('\n') : content, removed };
  }

  /**
   * Returns the history with revoked Skill content replaced, and the Skill names that were removed.
   * `messages` is the mapped client history ({ role, content[, name] }); it is never mutated, and when
   * nothing is revoked the same array comes back.
   */
  function scrub({ dir, project, messages }) {
    const none = { messages, removed: [] };
    if (!project || !Array.isArray(messages) || !messages.length) return none;
    const { revoked, enabled } = revokedVersions(dir, project);
    if (!revoked.size) return none;
    const byLine = new Map(); // fingerprint -> [names]
    for (const { name, lines } of revoked.values()) for (const l of lines) byLine.set(l, [...(byLine.get(l) || []), name]);
    const keep = new Set(); // lines of Skills that are still enabled are not revoked instructions
    for (const s of enabled) for (const l of fingerprints(s.content)) keep.add(l);
    const removed = new Set();
    let changed = false;
    const next = messages.map((m) => {
      if (!m || m.role === 'user' || typeof m.content !== 'string') return m;
      const hashes = m.content.match(SHA) || [];
      const named = [...new Set(hashes.filter((h) => revoked.has(h)))];
      if ((m.role === 'tool' || m.role === 'function') && named.length && READER.test(m.content.trimStart())) {
        const names = named.map((h) => revoked.get(h).name);
        for (const name of names) removed.add(name);
        changed = true;
        return { ...m, content: placeholder(names) };
      }
      const { text, removed: here } = scrubText(m.content, revoked, byLine, keep);
      if (!here.size) return m;
      for (const name of here) removed.add(name);
      changed = true;
      return { ...m, content: text };
    });
    return changed ? { messages: next, removed: [...removed] } : none;
  }

  return { record, scrub, revokedVersions };
}

module.exports = { createSkillHistory, fingerprints, normalise, placeholder, FILE };
