#!/usr/bin/env bash
# Source-only release guard. The strict FEATURES detector is copied from row J c6e0b79d.
gate_settlement_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
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
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // Row J review P2: the declaration itself must be unconditional and at the crate root of lib.rs:
    // no attribute of its own (cfg or any other), not inside a module, function, block or macro body
    // (depth 0), and no crate-level cfg attribute. A scope that cannot be proven this way is invalid.
    if (/#!\s*\[\s*cfg/.test(code)) out("invalid"); // cfg and cfg_attr at crate level
    const before = code.slice(0, decls[0].index);
    let scope = 0;
    for (const ch of before) {
      if (ch === "(" || ch === "[" || ch === "{") scope++;
      else if (ch === ")" || ch === "]" || ch === "}") scope--;
    }
    if (scope !== 0) out("invalid");
    let lead = before.slice(Math.max(before.lastIndexOf(";"), before.lastIndexOf("}")) + 1).trim();
    // Delta review P3: crate inner attributes (#![...], balanced, never cfg/cfg_attr, refused above)
    // apply to the crate, not to the declaration, so they may precede it. An outer #[...] may not.
    while (lead.startsWith("#")) {
      const bang = lead.slice(1).trimStart();
      if (!bang.startsWith("!")) out("invalid");
      const open = bang.slice(1).trimStart();
      if (!open.startsWith("[")) out("invalid");
      let d = 0, end = -1;
      for (let j = 0; j < open.length; j++) {
        if (open[j] === "[" || open[j] === "(" || open[j] === "{") d++;
        else if (open[j] === "]" || open[j] === ")" || open[j] === "}") { d--; if (d === 0) { end = j; break; } }
      }
      if (end < 0) out("invalid");
      if (/^\[\s*cfg/.test(open)) out("invalid");
      lead = open.slice(end + 1).trim();
    }
    if (lead !== "") out("invalid");
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
    const outbox = []; // lease authority entries
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
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("noevia-model-load-settlement"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("noevia-model-load-settlement")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^noevia-model-load-settlement\/(1)$/.exec(outbox[0]);
    out(m ? "v" + m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}

model_load_gate_pairing() {
  local tree="$1" front_ref="$2" docker="$1/services/model-manager/Dockerfile" gate_ref
  [ -f "$docker" ] || { echo "model load gate pairing: missing model-manager Dockerfile" >&2; return 1; }
  # Same immutable Rust input as the front (also required by release CI). Multiple ARG definitions,
  # indirection and nonliteral defaults cannot prove which gate the image builds.
  gate_ref="$(sed -n 's/^ARG NOEVIA_RS_REF=\([0-9a-f]\{40\}\)$/\1/p' "$docker")"
  [ "$(grep -c '^[[:space:]]*ARG[[:space:]]\+NOEVIA_RS_REF\b' "$docker")" = 1 ] &&
    [ "$gate_ref" = "$front_ref" ] || {
      echo "model load gate pairing: model-manager must build the front immutable Rust revision" >&2; return 1;
    }
  [ "$(gate_settlement_version "$tree/rs/bins/noevia-inference-gate/src/lib.rs")" = v1 ] || {
    echo "model load gate pairing: missing or ambiguous gate settlement capability" >&2; return 1;
  }
}
