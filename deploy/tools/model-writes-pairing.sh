#!/usr/bin/env bash
# Derived from the hardened generation detector in f57a4e3; no source evaluation outside its VM.
# Keep the Linux timeout contract on macOS without requiring a tool installation.
model_writes_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout -k 2 10 "$@"; return; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 2 10 "$@"; return; fi
  python3 - "$@" <<'PY_TIMEOUT'
import os, signal, subprocess, sys
child = subprocess.Popen(sys.argv[1:], start_new_session=True)
try:
    code = child.wait(timeout=10)
except subprocess.TimeoutExpired:
    os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
    code = 124
sys.exit(code)
PY_TIMEOUT
}

model_writes_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  model_writes_timeout node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /rust-model-writes-d-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.MODEL_WRITES_OWNER;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^rust-model-writes-d-(v1)$/.exec(value);
    process.stdout.write(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal; macros, expressions,
# raw or byte strings refuse. An outbox entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown outbox entries are invalid; no FEATURES array or no entry is absence.
model_writes_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  model_writes_timeout node -e '
    const fs = require("node:fs"), path = require("node:path");
    const out = r => { process.stdout.write(r); process.exit(0); };
    function tokens(src) {
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
      return {code, strs};
    }
    function topLevel(prefix) {
      let depth = 0;
      for (const ch of prefix) { if (ch === "{") depth++; else if (ch === "}") depth--; }
      return depth === 0 && !/#\s*!\s*\[\s*(?:cfg|cfg_attr)\b/.test(prefix) && /(?:^|[;}])\s*$/.test(prefix);
    }
    const {code, strs} = tokens(fs.readFileSync(process.argv[1], "utf8"));
    // Two existing capability references predate this move. Resolve their actual
    // unconditional literal and module declaration; never trust an arbitrary path.
    function legacyLiteral(ref) {
      const known = {
        "server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER": ["research_jobs", "RESEARCH_JOBS_STORE_MARKER", "noevia-research-jobs-store/1"],
        "server_projects::source_jobs::SOURCE_JOBS_STORE_MARKER": ["source_jobs", "SOURCE_JOBS_STORE_MARKER", "noevia-source-jobs-store/1"],
      };
      const entry = known[ref.replace(/\s/g, "")];
      if (!entry) return false;
      try {
        const root = path.resolve(path.dirname(process.argv[1]), "../../..");
        const file = tokens(fs.readFileSync(path.join(root, "crates/server-projects/src", entry[0] + ".rs"), "utf8"));
        const lib = tokens(fs.readFileSync(path.join(root, "crates/server-projects/src/lib.rs"), "utf8"));
        const mods = [...lib.code.matchAll(new RegExp("pub\\s+mod\\s+" + entry[0] + "\\s*;", "g"))];
        const decls = [...file.code.matchAll(new RegExp("pub\\s+const\\s+" + entry[1] + "\\s*:\\s*&\\s*str\\s*=\\s*\u0000(\\d+)\u0000\\s*;", "g"))];
        if (mods.length !== 1 || decls.length !== 1 || !topLevel(lib.code.slice(0, mods[0].index)) || !topLevel(file.code.slice(0, decls[0].index))) return false;
        const literal = file.strs[+decls[0][1]];
        return literal.kind === "str" && literal.v === entry[2];
      } catch { return false; }
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // Only a top-level declaration with no item attributes is provable here. Reject
    // nested/cfg-wrapped declarations rather than infer compile-time reachability.
    const prefix = code.slice(0, decls[0].index);
    let scope = 0;
    for (const ch of prefix) { if (ch === "{") scope++; else if (ch === "}") scope--; }
    if (!topLevel(prefix)) out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = [];
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-model-writes-d"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-model-writes-d")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      if (!marked && legacyLiteral(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^rust-model-writes-d-(v1)$/.exec(outbox[0]);
    out(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}

model_writes_pair() {
  local core rust
  core="$(model_writes_core_version "$1/server/rust-model-write-effects.cjs")"
  rust="$(model_writes_rs_version "$2/bins/noevia-server/src/lib.rs")"
  [ "$core" != invalid ] && [ "$rust" != invalid ] && [ "$core" = "$rust" ]
}
