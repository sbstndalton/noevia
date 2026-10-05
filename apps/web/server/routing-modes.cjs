'use strict';
// Routing modes (#778, features.routingModes, off by default). An account chooses where Auto sends
// its chats: `local` (local roles only), `cloud` (a cloud provider the account names), or `hybrid`
// (cloud, unless the turn looks sensitive). Only Auto chats are routed; a model picked by hand is
// respected, and the existing hard bans (provider-egress.cjs) always win.
//
// In hybrid, a flagged turn is never sent to cloud silently. Cheap deterministic rules run first
// (Diary content, obvious secrets and account numbers); otherwise the router role is asked through
// decide() with `cloud: 'forbidden'`. Every failure of that call is treated as "flagged". A flagged
// turn either stays local (the account's "always local" choice) or the person is asked, through the
// same pending-card mechanism as the write approvals, and nothing reaches the cloud provider until
// they pick "Send to cloud". A timeout, a cancel or a lost connection keeps it local.
//
// Logs and the decision log carry codes only (mode, route, reason, flag), never message text.

const fs = require('node:fs');
const path = require('node:path');

const MODES = Object.freeze(['local', 'cloud', 'hybrid']);
const WHEN_SENSITIVE = Object.freeze(['ask', 'local']);
/** Why a reply went where it did. */
const REASONS = Object.freeze(['mode', 'user-choice', 'force-local', 'sensitive-rule', 'fail-closed', 'remembered']);
/** Why a turn was flagged, as shown on the card. */
const FLAGS = Object.freeze(['diary', 'secret', 'iban', 'card', 'router', 'unavailable']);
const ROLE_KEYS = Object.freeze(['fast', 'smart', 'code']);
const MODEL_RE = /^[A-Za-z0-9._:/@+-]{1,200}$/;
const PROVIDER_RE = /^[A-Za-z0-9_-]{1,80}$/;
const FILE = 'routing-mode.json';
const ALLOWED_KEY = 'routing_modes_allowed';

// ── Account settings ────────────────────────────────────────────────────────

/** The stored setting, normalized. `mode: null` means "not chosen": routing behaves as before. */
function normalize(raw) {
  const value = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const mode = MODES.includes(value.mode) ? value.mode : null;
  const whenSensitive = WHEN_SENSITIVE.includes(value.whenSensitive) ? value.whenSensitive : 'ask';
  const c = value.cloud && typeof value.cloud === 'object' ? value.cloud : {};
  const cloud = { providerId: typeof c.providerId === 'string' && PROVIDER_RE.test(c.providerId) ? c.providerId : '' };
  for (const role of ROLE_KEYS) cloud[role] = typeof c[role] === 'string' && MODEL_RE.test(c[role].trim()) ? c[role].trim() : '';
  return { mode, whenSensitive, cloud };
}

function read(dir) {
  try { return normalize(JSON.parse(fs.readFileSync(path.join(dir, FILE), 'utf8'))); } catch { return normalize(null); }
}

/** Validates a PUT body; throws { status: 400 } on anything it cannot store. */
function validate(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw Object.assign(Error('request body must be a JSON object'), { status: 400 });
  if (body.mode !== null && !MODES.includes(body.mode)) throw Object.assign(Error("mode must be 'local', 'cloud', 'hybrid' or null"), { status: 400 });
  if (body.mode && !allowed.includes(body.mode)) throw Object.assign(Error('An administrator has not allowed this routing mode.'), { status: 403 });
  if (body.whenSensitive !== undefined && !WHEN_SENSITIVE.includes(body.whenSensitive)) throw Object.assign(Error("whenSensitive must be 'ask' or 'local'"), { status: 400 });
  const c = body.cloud === undefined ? {} : body.cloud;
  if (!c || typeof c !== 'object' || Array.isArray(c)) throw Object.assign(Error('cloud must be an object'), { status: 400 });
  if (c.providerId !== undefined && c.providerId !== '' && !(typeof c.providerId === 'string' && PROVIDER_RE.test(c.providerId))) throw Object.assign(Error('cloud.providerId is not a provider id'), { status: 400 });
  for (const role of ROLE_KEYS) {
    const v = c[role];
    if (v !== undefined && v !== '' && !(typeof v === 'string' && MODEL_RE.test(v.trim()))) throw Object.assign(Error(`cloud.${role} must be a model id`), { status: 400 });
  }
  return normalize(body);
}

function write(dir, value) {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, FILE), tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(normalize(value)));
  fs.renameSync(tmp, file);
}

/** The modes an administrator allows (all three unless restricted). */
function allowedModes(store) {
  try {
    const list = JSON.parse(store.get(ALLOWED_KEY) || 'null');
    if (Array.isArray(list)) { const out = MODES.filter((m) => list.includes(m)); return out; }
  } catch { /* fall through */ }
  return [...MODES];
}

function setAllowedModes(store, list) {
  if (!Array.isArray(list) || list.some((m) => !MODES.includes(m))) throw Object.assign(Error("allowed must list 'local', 'cloud' and/or 'hybrid'"), { status: 400 });
  const out = MODES.filter((m) => list.includes(m));
  store.set(ALLOWED_KEY, JSON.stringify(out));
  return out;
}

/** The mode in force. A mode an administrator later disallowed falls back to local, the one
 *  direction that never sends more data out. */
function effectiveMode(settings, allowed) {
  if (!settings.mode) return null;
  return allowed.includes(settings.mode) ? settings.mode : 'local';
}

// ── Deterministic pre-rules ─────────────────────────────────────────────────

function ibanValid(raw) {
  const s = raw.replace(/\s+/g, '').toUpperCase();
  if (s.length < 15 || s.length > 34) return false;
  const moved = s.slice(4) + s.slice(0, 4);
  let rem = 0;
  for (const ch of moved) {
    const code = ch >= 'A' && ch <= 'Z' ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of code) rem = (rem * 10 + Number(d)) % 97;
  }
  return rem === 1;
}

function luhn(digits) {
  let sum = 0, dbl = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48;
    if (dbl) { d *= 2; if (d > 9) d -= 9; }
    sum += d; dbl = !dbl;
  }
  return sum % 10 === 0;
}

const SECRET_PATTERNS = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\b(?:password|passwort|passwd|pwd|passcode|pin|api[ _-]?key|secret|access[ _-]?token|auth[ _-]?token|token)\s*[:=]\s*\S{4,}/i,
  /\bBearer\s+[A-Za-z0-9._~+/-]{16,}/,
  /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/,
  // A long key-shaped token: a prefix, then 24+ characters mixing letters and digits.
  /\b[a-z]{2,8}[-_](?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{24,}\b/,
];
const SCAN_LIMIT = 400_000;

/** The first rule a text trips, as a flag code, or null. Pure; bounded. */
function preRule(text) {
  const s = String(text || '').slice(0, SCAN_LIMIT);
  if (SECRET_PATTERNS.some((re) => re.test(s))) return 'secret';
  for (const m of s.matchAll(/\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\b/g)) if (ibanValid(m[0])) return 'iban';
  for (const m of s.matchAll(/\b\d(?:[ -]?\d){12,18}\b/g)) {
    const digits = m[0].replace(/\D/g, '');
    if (digits.length >= 13 && digits.length <= 19 && luhn(digits)) return 'card';
  }
  return null;
}

/** Diary content in what would be sent: a Diary tool's result in the history. */
function hasDiaryContent(history) {
  return (Array.isArray(history) ? history : []).some((h) => h && (h.role === 'tool' || h.role === 'function') && /^diary[_-]/i.test(String(h.name || '')));
}

// ── The digest the router role reads ────────────────────────────────────────

const DIGEST_MAX = 6000;
const textOf = (content) => (typeof content === 'string' ? content : Array.isArray(content) ? content.map((p) => (p && typeof p.text === 'string' ? p.text : '')).join(' ') : '');
/** Everything that would be sent, bounded: the message, then context (memory, RAG, project excerpts),
 *  attachment names and the most recent history, each with its own share. */
function digest({ message, system, history, attachments }) {
  const part = (label, text, max) => (text ? `${label}:\n${String(text).slice(0, max)}` : '');
  const recent = (Array.isArray(history) ? history : []).slice(-6).map((h) => `${h.role}: ${textOf(h.content)}`).join('\n');
  const tail = recent.length > 1500 ? recent.slice(-1500) : recent;
  return [
    part('Message', message, 2400),
    part('Context', system, 1600),
    part('Attachments', (Array.isArray(attachments) ? attachments : []).join(', '), 300),
    part('Recent history', tail, 1500),
  ].filter(Boolean).join('\n\n').slice(0, DIGEST_MAX);
}

// ── The router role ─────────────────────────────────────────────────────────

const OPTIONS = Object.freeze([
  { id: 'sensitive', label: 'Contains private or confidential information: health, finances, identity numbers, passwords, private relationships, legal or work secrets' },
  { id: 'not_sensitive', label: 'General, public or harmless content that is fine to send to an external service' },
]);

/** async (digestText) => { flagged, flag }. Never throws; every failure is flagged ('unavailable'). */
function createSensitivity({ decide, deadlineMs = () => 1500, minConfidence = 0.6, log = () => {} }) {
  return async function check(text) {
    let result;
    try {
      if (typeof decide !== 'function') throw Error('no decision service');
      result = await decide({ kind: 'choice', purpose: 'routing.sensitivity',
        question: 'Does this content contain sensitive personal or confidential information?',
        context: { cloud: 'forbidden', stateText: String(text || '').slice(0, DIGEST_MAX) }, options: OPTIONS.map((o) => ({ ...o })),
        constraints: { deadlineMs: Math.max(100, Number(deadlineMs()) || 1500), minConfidence }, fallback: { selected: null, scores: {} } });
    } catch { result = null; }
    const answered = result && result.source !== 'fallback' && OPTIONS.some((o) => o.id === result.selected);
    const confident = answered && (typeof result.confidence !== 'number' || result.confidence >= minConfidence);
    const out = !confident ? { flagged: true, flag: 'unavailable' } : result.selected === 'sensitive' ? { flagged: true, flag: 'router' } : { flagged: false, flag: null };
    try { log({ verdict: out.flag || 'clear', fellBack: !confident }); } catch { /* codes only, never breaks routing */ }
    return out;
  };
}

/**
 * Where an Auto turn goes. Pure apart from the injected `check` and `ask`.
 * @returns {Promise<{ route:'local'|'cloud', reason:string, flag?:string, remember?:'local'|'cloud' } | { cancel:true, reason:string }>}
 */
async function resolveRoute({ mode, whenSensitive = 'ask', hasCloud, hasLocal = true, hardLocal = false, forceLocal = false, allowCloud = false,
  preFlag = null, check = async () => ({ flagged: true, flag: 'unavailable' }), ask = async () => ({ choice: 'timeout' }) }) {
  const local = (reason, extra = {}) => (hasLocal ? { route: 'local', reason, ...extra } : { cancel: true, reason });
  if (hardLocal) return local('sensitive-rule', { flag: 'diary' });
  if (forceLocal) return local('force-local');
  if (mode === 'local' || !hasCloud) return local('mode');
  if (mode === 'cloud') return { route: 'cloud', reason: 'mode' };
  // hybrid
  let flag = preFlag;
  if (!flag) { const verdict = await check(); if (!verdict || verdict.flagged !== false) flag = verdict?.flag || 'unavailable'; }
  if (!flag) return { route: 'cloud', reason: 'mode' };
  const flagReason = flag === 'unavailable' ? 'fail-closed' : 'sensitive-rule';
  if (allowCloud) return { route: 'cloud', reason: 'remembered', flag };
  if (whenSensitive === 'local') return local(flagReason, { flag });
  let answer;
  try { answer = await ask(flag); } catch { answer = null; }
  if (answer?.choice === 'cloud') return { route: 'cloud', reason: 'user-choice', flag, ...(answer.remember ? { remember: 'cloud' } : {}) };
  if (answer?.choice === 'local') return local('user-choice', { flag, ...(answer.remember ? { remember: 'local' } : {}) });
  // Timed out, cancelled or unanswered: never cloud.
  return local('fail-closed', { flag });
}

/** The chat's stored routing flags, from the requesting user's own lists only. */
function chatFlags({ chatId, list }) {
  const meta = (Array.isArray(list) ? list : []).find((c) => c && c.id === chatId);
  return { forceLocal: meta?.forceLocal === true, allowCloud: meta?.allowCloud === true };
}

/** The cloud model for a role, falling back smart → fast → code. */
function cloudModel(cloud, role) {
  return cloud[role] || cloud.smart || cloud.fast || cloud.code || '';
}

module.exports = { MODES, WHEN_SENSITIVE, REASONS, FLAGS, OPTIONS, FILE, ALLOWED_KEY, normalize, read, write, validate, allowedModes, setAllowedModes,
  effectiveMode, preRule, hasDiaryContent, digest, createSensitivity, resolveRoute, chatFlags, cloudModel, ibanValid, luhn };
