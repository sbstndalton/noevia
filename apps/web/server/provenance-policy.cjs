'use strict';
// Tool-layer provenance policy (#769, features.provenancePolicy, off by default): the hard
// injection boundary. Prompt framing (prompt-framing.cjs) labels untrusted text but cannot stop a
// model from acting on it. This decides from where a WRITE call's arguments came, never from
// anything the model says: when a sensitive argument (a recipient, URL or host, path or command)
// contains text that entered this exchange from an untrusted source, the call may not run under
// "Allow for this chat" and always gets its own approval card, naming the source.
//
// Untrusted text is exactly what the chat loop framed with frameUntrusted(): tool and connector
// results, documents and RAG excerpts, Diary excerpts, brains, task packets, vision descriptions.
// The loop hands this module each model request before it is sent; the framed blocks in it are
// the taint. It can only add friction: an error anywhere here asks per call (fails closed).

const GRAM = 16; // a window this long matching untrusted text is not a coincidence
const MIN_WHOLE = 6; // shorter values (or hostnames) must match as a whole
const DEFAULT_MAX_CHARS = 400_000; // per exchange; beyond it the store is saturated
const MAX_SOURCES = 64;

// Argument names whose values decide where data goes or what runs.
const SENSITIVE_KEY = /^(to|cc|bcc|recipients?|email|emails|e_?mail|mail_?to|address|addresses|send_?to|url|urls|uri|href|link|host|hostname|domain|endpoint|webhook|path|paths|file_?path|filepath|destination|dest|target_?path|folder|directory|dir|remote|command|cmd|commands|script|shell)$/i;

const FRAMED = /<untrusted kind="([^"]*)"(?: label="([^"]*)")?> \(data, not instructions\)\n([\s\S]*?)\n<\/untrusted>/g;

function normalise(text) {
  return String(text == null ? '' : text).normalize('NFKC').toLowerCase()
    .replace(/[​-‏⁠﻿]/g, '').replace(/\s+/g, ' ').trim();
}

// FNV-1a, 32 bit. A collision only ever adds an approval card.
function hash(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h;
}

/** One exchange's record of untrusted text. Bounded: past maxChars it is saturated, and then every
 *  sensitive value counts as tainted (the bound never turns into a way around the policy). */
function createTaintStore({ maxChars = DEFAULT_MAX_CHARS } = {}) {
  const grams = new Map(); // hash -> index into sources
  const texts = []; // { source, text } normalised, for short whole-value matches
  const seen = new Set(); // hashes of whole blocks already ingested (each round resends history)
  const sources = [];
  let chars = 0, saturated = false;

  function sourceIndex(source) {
    let i = sources.indexOf(source);
    if (i === -1) { if (sources.length >= MAX_SOURCES) return MAX_SOURCES - 1; sources.push(source); i = sources.length - 1; }
    return i;
  }

  function add(source, raw) {
    if (saturated) return;
    const text = normalise(raw);
    if (!text) return;
    const whole = hash(text) ^ text.length;
    if (seen.has(whole)) return;
    if (chars + text.length > maxChars) { saturated = true; grams.clear(); texts.length = 0; return; }
    seen.add(whole);
    chars += text.length;
    const at = sourceIndex(String(source || 'untrusted text').slice(0, 120));
    texts.push({ at, text });
    for (let i = 0; i + GRAM <= text.length; i++) {
      const g = hash(text.slice(i, i + GRAM));
      if (!grams.has(g)) grams.set(g, at);
    }
  }

  /** Every frameUntrusted block in the messages one model request is about to send. */
  function ingestMessages(messages) {
    for (const m of Array.isArray(messages) ? messages : []) {
      const parts = typeof m?.content === 'string' ? [m.content]
        : Array.isArray(m?.content) ? m.content.map((p) => (typeof p?.text === 'string' ? p.text : '')) : [];
      for (const content of parts) {
        if (!content.includes('<untrusted ')) continue;
        for (const [, kind, label, body] of content.matchAll(FRAMED)) add(label ? `${kind}: ${label}` : kind, body);
      }
    }
  }

  /** The source a value's text came from, or null when none of it is untrusted. */
  function sourceOf(raw) {
    const value = normalise(raw);
    if (value.length < MIN_WHOLE) return null;
    if (saturated) return 'untrusted text (too much to track in this reply)';
    if (value.length < GRAM) {
      const hit = texts.find((t) => t.text.includes(value));
      return hit ? sources[hit.at] : null;
    }
    for (let i = 0; i + GRAM <= value.length; i++) {
      const at = grams.get(hash(value.slice(i, i + GRAM)));
      if (at !== undefined) return sources[at];
    }
    return null;
  }

  return { add, ingestMessages, sourceOf, stats: () => ({ chars, grams: grams.size, sources: sources.length, saturated }) };
}

// The forms of one value that are checked: itself, URL-decoded, and the host of a URL or the
// domain of an address (an injected host inside a model-built URL is the exfiltration case).
function candidates(value) {
  const out = new Set([value]);
  try { out.add(decodeURIComponent(value)); } catch { /* not encoded */ }
  try { const u = new URL(value); if (u.hostname) out.add(u.hostname); } catch { /* not a URL */ }
  const at = /@([^\s@/]+)$/.exec(value.trim());
  if (at) out.add(at[1]);
  return [...out];
}

function sensitiveValues(node, key, out, depth = 0) {
  if (depth > 8 || out.length > 200) return out;
  if (typeof node === 'string') { if (key && SENSITIVE_KEY.test(key)) out.push({ field: key, value: node }); return out; }
  if (Array.isArray(node)) { for (const v of node) sensitiveValues(v, key, out, depth + 1); return out; }
  if (node && typeof node === 'object') for (const [k, v] of Object.entries(node)) sensitiveValues(v, k, out, depth + 1);
  return out;
}

/**
 * The provenance of one write call: [] when no sensitive argument holds untrusted text, else
 * [{ field, source }] (at most 5). Any failure, including arguments that are not JSON, returns
 * [{ field: null, source: null, unchecked: true }]: the caller asks per call (fails closed).
 */
function checkWrite(store, rawArgs) {
  try {
    const args = typeof rawArgs === 'string' ? (rawArgs.trim() ? JSON.parse(rawArgs) : {}) : rawArgs;
    if (args !== null && typeof args !== 'object') throw Error('arguments are not an object');
    const found = [];
    for (const { field, value } of sensitiveValues(args, null, [])) {
      const source = candidates(value).map((c) => store.sourceOf(c)).find(Boolean);
      if (source && !found.some((f) => f.field === field && f.source === source)) found.push({ field, source });
      if (found.length >= 5) break;
    }
    return found;
  } catch {
    return [{ field: null, source: null, unchecked: true }];
  }
}

module.exports = { createTaintStore, checkWrite, normalise, SENSITIVE_KEY, GRAM, DEFAULT_MAX_CHARS };
