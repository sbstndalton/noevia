'use strict';
// Port of the active-instruction, stage-chain, shell and copy proof used by the
// model-manager generator. Kept local to release tooling; no cross-repo imports.
const path = require('node:path');

const BIN = '/usr/local/bin/noevia-server';
const PKG = 'noevia-server';
const PRODUCING = new Set(['build', 'b', 'install', 'rustc', 'run', 'r', 'test', 't', 'bench']);
const NONPRODUCING = new Set(['fetch', 'metadata', 'fmt', 'check', 'c', 'clippy', 'doc', 'd', 'tree', 'vendor', 'version', 'help']);
const fail = (m) => { throw new Error(`Dockerfile: ${m}`); };

// ---- instructions ------------------------------------------------------------------------------

function instructions(text) {
  const physical = text.split(/\r?\n/);
  for (const l of physical) if (/^\s*#\s*(escape|syntax)\s*=/i.test(l) && /escape/i.test(l)) fail('a parser directive changes the escape character');
  const out = [];
  let cur = null;
  for (const raw of physical) {
    const line = raw.replace(/\s+$/, '');
    if (/^\s*#/.test(line)) continue; // comment lines vanish, also inside a continuation
    if (cur === null && line.trim() === '') continue;
    const cont = line.endsWith('\\');
    const body = cont ? line.slice(0, -1) : line;
    cur = (cur === null ? '' : cur) + body;
    if (cont) continue;
    out.push(cur.trim()); cur = null;
  }
  if (cur !== null) fail('the file ends inside a continued instruction');
  return out.filter(Boolean).map((s) => {
    const m = /^(\S+)\s*([\s\S]*)$/.exec(s);
    return { kw: m[1].toUpperCase(), args: m[2] };
  });
}

function stages(text) {
  const list = [];
  for (const ins of instructions(text)) {
    if (ins.kw === 'FROM') {
      if (ins.args.startsWith('--')) fail('unsupported FROM options');
      const m = /^(?:--\S+\s+)*(\S+)(?:\s+AS\s+(\S+))?\s*$/i.exec(ins.args);
      if (!m) fail(`unreadable FROM ${ins.args}`);
      list.push({ base: m[1], name: m[2] ? m[2].toLowerCase() : null, ins: [] });
    } else if (list.length) list[list.length - 1].ins.push(ins);
    else if (ins.kw !== 'ARG') fail(`${ins.kw} before the first FROM`);
  }
  if (!list.length) fail('no FROM');
  const seen = new Set();
  list.forEach((s, i) => { s.index = i; if (s.name) { if (seen.has(s.name)) fail(`stage ${s.name} is defined twice`); seen.add(s.name); } });
  return list;
}

// The stage plus the stages it inherits from, root first. A base that is not an earlier stage name is an
// external image and ends the chain.
function chainOf(all, stage) {
  const chain = [stage];
  let cur = stage;
  for (;;) {
    if (/[$]/.test(cur.base)) fail(`stage ${cur.name || cur.index} has an unresolved base image ${cur.base}`);
    const parent = all.find((s) => s.name && s.name === cur.base.toLowerCase());
    if (!parent) break;
    if (parent.index >= cur.index) fail(`stage ${cur.name || cur.index} inherits from a stage defined later`);
    chain.unshift(parent); cur = parent;
  }
  return chain;
}

// ---- shell -------------------------------------------------------------------------------------

// Words and operators of one RUN command. Quotes are honoured; `$`, backticks and globs are flagged on
// the word so callers can refuse them; $(...) and `...` bodies are kept for a "cargo hidden inside" test.
function shell(src) {
  const toks = [];
  let i = 0, w = null;
  const n = src.length;
  const open = () => (w === null ? (w = { v: '', raw: '', dollar: false, glob: false, subst: [] }) : w);
  const flush = () => { if (w) { toks.push({ t: 'w', ...w }); w = null; } };
  const op = (v) => { flush(); toks.push({ t: 'op', v }); };
  while (i < n) {
    const c = src[i];
    if (c === ' ' || c === '\t' || c === '\n') { flush(); i++; continue; }
    if (c === '#' && w === null) fail('shell comment inside a RUN command');
    if (c === '&' && src[i + 1] === '&') { op('&&'); i += 2; continue; }
    if (c === '|' && src[i + 1] === '|') { op('||'); i += 2; continue; }
    if (c === '|' || c === ';' || c === '(' || c === ')' || (c === '&' && !/[<>]/.test(src[i - 1] || ''))) { op(c); i++; continue; }
    if (c === '>' || c === '<') {
      let pre = '';
      if (w && /^\d+$/.test(w.v)) { pre = w.v; w = null; } else flush();
      let j = i + 1; if (src[j] === c) j++;
      let target = null;
      if (src[j] === '&') { const m = /^&(\d+|-)/.exec(src.slice(j)); if (!m) fail('unreadable redirection'); j += m[0].length; target = m[0]; }
      toks.push({ t: 'redir', v: pre + src.slice(i, j).replace(/&.*/, '') + (target || ''), needsTarget: target === null });
      i = j; continue;
    }
    const word = open();
    if (c === "'") {
      const e = src.indexOf("'", i + 1); if (e < 0) fail('unterminated quote in a RUN command');
      const lit = src.slice(i + 1, e); word.v += lit; word.raw += src.slice(i, e + 1); if (/[$`]/.test(lit)) word.dollar = true; i = e + 1; continue;
    }
    if (c === '"') {
      let j = i + 1, lit = '';
      for (;;) {
        if (j >= n) fail('unterminated quote in a RUN command');
        if (src[j] === '\\' && j + 1 < n) { lit += src[j + 1]; j += 2; continue; }
        if (src[j] === '"') break;
        if (src[j] === '$' || src[j] === '`') word.dollar = true;
        lit += src[j]; j++;
      }
      word.v += lit; word.raw += src.slice(i, j + 1); i = j + 1; continue;
    }
    if (c === '\\') { word.v += src[i + 1] || ''; word.raw += src.slice(i, i + 2); i += 2; continue; }
    if (c === '`') {
      const e = src.indexOf('`', i + 1); if (e < 0) fail('unterminated backtick');
      word.dollar = true; word.subst.push(src.slice(i + 1, e)); word.v += src.slice(i, e + 1); word.raw += src.slice(i, e + 1); i = e + 1; continue;
    }
    if (c === '$') {
      word.dollar = true;
      if (src[i + 1] === '(') {
        let depth = 0, j = i + 1;
        for (; j < n; j++) { if (src[j] === '(') depth++; else if (src[j] === ')' && --depth === 0) break; }
        if (j >= n) fail('unterminated $(');
        word.subst.push(src.slice(i + 2, j)); word.v += src.slice(i, j + 1); word.raw += src.slice(i, j + 1); i = j + 1; continue;
      }
      if (src[i + 1] === '{') {
        const e = src.indexOf('}', i); if (e < 0) fail('unterminated ${');
        word.v += src.slice(i, e + 1); word.raw += src.slice(i, e + 1); i = e + 1; continue;
      }
    }
    if (c === '*' || c === '?' || c === '[') word.glob = true;
    word.v += c; word.raw += c; i++;
  }
  flush();
  // Segments: command groups between operators.
  const segs = [];
  let cur = { words: [], redirs: [], before: null, after: null };
  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    if (t.t === 'op') { cur.after = t.v; segs.push(cur); cur = { words: [], redirs: [], before: t.v, after: null }; continue; }
    if (t.t === 'redir') {
      if (t.needsTarget) { const tgt = toks[++k]; if (!tgt || tgt.t !== 'w') fail('redirection without a target'); cur.redirs.push({ v: t.v, target: tgt.v }); }
      else cur.redirs.push({ v: t.v, target: null });
      continue;
    }
    cur.words.push(t);
  }
  segs.push(cur);
  return segs.filter((s) => s.words.length || s.redirs.length || s.before || s.after);
}

// ---- cargo -------------------------------------------------------------------------------------

function parseCargo(seg, at) {
  const w = seg.words.slice(at + 1);
  for (const x of seg.words) if (x.dollar || x.glob) fail(`a cargo command contains an expansion or glob (${x.raw}); refusing`);
  let k = 0;
  if (!w[k] || w[k].v.startsWith('-') || w[k].v.startsWith('+')) fail(`cargo is called with an unsupported global option (${w[k] ? w[k].v : 'none'})`);
  const sub = w[k++].v;
  if (NONPRODUCING.has(sub)) return { kind: 'other', sub };
  if (!PRODUCING.has(sub)) fail(`cargo subcommand "${sub}" may build the binary and is not understood`);
  const info = { kind: 'build', sub, packages: [], bins: [], features: [], noDefault: false, options: [] };
  const val = (opt, inline) => { if (inline !== undefined) return inline; const v = w[k++]; if (!v || v.v.startsWith('-')) fail(`cargo ${opt} has no value`); return v.v; };
  while (k < w.length) {
    const a = w[k++].v, eq = a.indexOf('=');
    const name = a.startsWith('--') && eq > 0 ? a.slice(0, eq) : a, inline = a.startsWith('--') && eq > 0 ? a.slice(eq + 1) : undefined;
    if (name === '--release' || name === '--locked') { if (inline !== undefined) fail('boolean cargo option has a value'); info.options.push(name); continue; }
    if (name === '--no-default-features') { if (inline !== undefined) fail('boolean cargo option has a value'); info.noDefault = true; continue; }
    if (name === '-p' || name === '--package') { info.packages.push(val(name, inline)); continue; }
    if (name === '--bin') { info.bins.push(val(name, inline)); continue; }
    if (name === '--features' || name === '-F') { info.features.push(...val(name, inline).split(',')); continue; }
    fail(`cargo ${sub} uses an option outside the supported set: ${a}`);
  }
  if (sub !== 'build' && sub !== 'b') fail(`cargo ${sub} could produce ${PKG} and is not a supported build command`);
  return info;
}

// ---- paths -------------------------------------------------------------------------------------

function resolveDir(workdir, p, what) {
  if (/[$]/.test(p)) fail(`${what} uses an unresolved variable (${p})`);
  return path.posix.normalize(p.startsWith('/') ? p : path.posix.join(workdir, p));
}
// Does a COPY/ADD (sources, dest) possibly write `target`?
function writes(srcs, dest, target) {
  const dir = dest.endsWith('/') || dest === '.' || dest.endsWith('/.') || srcs.length > 1 || srcs.some((s) => /[*?[]|\/$|\/\.$/.test(s) || s === '.');
  const d = dest.replace(/\/+$/, '') || '/';
  if (d === target) return true;
  if (target.startsWith(d === '/' ? '/' : d + '/')) return true; // a directory copy can place it
  return dir && srcs.some((s) => path.posix.join(d, path.posix.basename(s)) === target);
}

function copyOf(ins, workdir) {
  if (/^\s*\[/.test(ins.args)) fail(`${ins.kw} in JSON form cannot be checked`);
  const words = ins.args.split(/\s+/).filter(Boolean);
  let from = null;
  while (words.length && words[0].startsWith('--')) {
    const m = /^--from=(.+)$/.exec(words[0]);
    if (m && ins.kw === 'COPY') from = m[1]; else fail(`${ins.kw} uses an option other than --from (${words[0]})`);
    words.shift();
  }
  if (words.length < 2) fail(`unreadable ${ins.kw}`);
  for (const x of words) if (/[$]/.test(x)) fail(`${ins.kw} uses an unresolved variable (${x})`);
  const dest = words.pop();
  let d = path.posix.normalize(dest.startsWith('/') ? dest : path.posix.join(workdir, dest));
  if (dest === '.' && !d.endsWith('/')) d += '/';
  return { from, srcs: words, dest: d };
}

// The complete supported front RUN grammar. The fixed selector language is
// evaluated against the same Cargo snapshot, never by invoking a shell. Only its
// proven literal result may replace the one known "$features" argument.
function frontRun(text, cargo) {
  if (/^\s*(--|\[)/.test(text) || /<</.test(text)) fail('unsupported RUN form');
  let command;
  const prefix = /^set -e;\s*mkdir -p \/out;\s*if \[ -f bins\/noevia-server\/Cargo.toml \]; then\s*features=([A-Za-z0-9_,-]+);\s*/.exec(text);
  if (prefix) {
    const features = new Set(prefix[1].split(','));
    let tail = text.slice(prefix[0].length);
    while (tail.startsWith('if grep ')) {
      const m = /^if grep -(qx|q) '([^']+)' bins\/noevia-server\/Cargo\.toml; then features="\$features,([A-Za-z0-9_-]+)"; fi;\s*/.exec(tail);
      if (!m) fail('unsupported feature selector');
      const exact = m[2] === m[3] + ' = \\[\\]';
      const head = m[2] === '^' + m[3] + ' = ';
      if ((m[1] === 'qx' && !exact) || (m[1] === 'q' && !head)) fail('unsupported feature predicate');
      if (cargo.split('\n').some(line => exact ? line === m[3] + ' = []' : line.startsWith(m[3] + ' = '))) features.add(m[3]);
      tail = tail.slice(m[0].length);
    }
    const m = /^(cargo[\s\S]*?);\s*cp target\/release\/noevia-server \/out\/noevia-server;\s*\/out\/noevia-server 2>&1 \| grep -q NOEVIA_LEGACY_UPSTREAM;\s*else\s*echo "noevia-rs in this tree has no bins\/noevia-server: the image ships without the Rust front";\s*fi$/.exec(tail);
    if (!m) fail('unsupported complete front build/output program');
    command = m[1].replace('"$features"', [...features].join(','));
  } else {
    // Literal unconditional build form, also used for the adversarial probe suite.
    const m = /^(?:mkdir -p \/out && )?(cargo[\s\S]*?) && cp target\/release\/noevia-server \/out\/noevia-server$/.exec(text);
    if (!m) fail('unsupported unconditional front build/output program');
    command = m[1];
  }
  const segments = shell(command);
  if (segments.length !== 1 || segments[0].redirs.length || segments[0].before || segments[0].after ||
      segments[0].words[0]?.v !== 'cargo') fail('exactly one plain producing cargo command is required');
  const build = parseCargo(segments[0],0);
  if (build.kind !== 'build' || !['build','b'].includes(build.sub) || build.packages.length !== 1 || build.packages[0] !== PKG ||
      build.bins.some(x => x !== PKG) || !build.options.includes('--release')) fail('unsupported binary/package build');
  const features = [];
  for (const item of build.features) {
    const m = /^(?:noevia-server\/)?([A-Za-z0-9_-]+)$/.exec(item);
    if (!m) fail('feature must be a literal local/package feature');
    features.push(m[1]);
  }
  return {features,noDefault:build.noDefault};
}

function proveBuild(all, source, cargo) {
  const chain = chainOf(all,source);
  // Restrict the external toolchain/setup, including every instruction in all
  // ancestors. An inherited stage cannot hide a second build or output overwrite.
  if (!/^rust:[0-9]+(?:\.[0-9]+)*-slim-bookworm$/.test(chain[0].base)) fail('unsupported front base');
  const ins = chain.flatMap(st => st.ins);
  if (ins.length !== 4 || ins[0].kw !== 'ENV' ||
      !/^RUSTUP_TOOLCHAIN=[0-9]+(?:\.[0-9]+)* CARGO_TERM_COLOR=never$/.test(ins[0].args) ||
      ins[1].kw !== 'COPY' || ins[1].args !== 'rs/ /src/' ||
      ins[2].kw !== 'WORKDIR' || ins[2].args !== '/src' || ins[3].kw !== 'RUN') fail('unsupported complete front stage chain');
  return frontRun(ins[3].args,cargo);
}

function proveFeatures(text,cargo) {
  const all = stages(text), final = all[all.length-1], chain = chainOf(all,final);
  if (chain[0].base !== 'node:22-bookworm') fail('unsupported runtime base');
  let workdir = '/', hit = null, count = 0;
  for (const st of chain) {
    for (const ins of st.ins) {
      if (ins.kw === 'ONBUILD' || ins.kw === 'SHELL') fail(ins.kw+' in runtime chain');
      if (ins.kw === 'WORKDIR') { workdir = resolveDir(workdir,ins.args.trim(),'WORKDIR'); continue; }
      if (ins.kw === 'RUN' && /noevia-server|\/usr\/local\/bin|\/usr\/local\b/.test(ins.args)) fail('runtime RUN may overwrite binary');
      if (ins.kw !== 'COPY' && ins.kw !== 'ADD') continue;
      const c = copyOf(ins,workdir);
      if (writes(c.srcs,c.dest,BIN)) { count++; hit = {ins,c,stage:st}; }
    }
  }
  if (count !== 1) fail('runtime binary must be written exactly once');
  const {ins,c,stage} = hit;
  const outputDir = c.srcs.length === 1 && c.srcs[0] === '/out/' && c.dest === '/usr/local/bin/';
  const outputFile = c.srcs.length === 1 && c.srcs[0] === '/out/noevia-server' && c.dest === BIN;
  if (ins.kw !== 'COPY' || !c.from || !(outputDir || outputFile)) fail('runtime must COPY the proven output from one stage');
  const source = all.find(s => s.name === c.from.toLowerCase());
  if (!source || source.index >= stage.index) fail('runtime copy must name an earlier local stage');
  return {...proveBuild(all,source,cargo),buildStage:source.name};
}
module.exports = {proveFeatures,instructions};
