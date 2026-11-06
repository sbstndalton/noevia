'use strict';

// A conservative Rust token-tree reader, not a Rust evaluator. No source is executed.
// Only a single crate-root public const/static &[&str] declaration is supported.
// Unknown attributes/expressions fail closed; callers must refuse invalid results.
function detect(source, declaration, capability, enabledFeatures = null) {
  const fail = reason => { throw new Error(reason); };
  try {
    if (typeof source !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(declaration) ||
        typeof capability !== 'string' || !capability || source.length > 8 * 1024 * 1024) fail('input');
    const tokens = [];
    let i = 0;
    const push = (kind, value) => tokens.push({kind, value});
    const quoted = (quote, kind) => {
      i++; let value = '';
      while (i < source.length && source[i] !== quote) {
        if (source[i] !== '\\') { value += source[i++]; continue; }
        i++;
        const e = source[i++];
        const simple = {n:'\n', r:'\r', t:'\t', '0':'\0', '\\':'\\', '"':'"', "'":"'"};
        if (Object.hasOwn(simple, e)) value += simple[e];
        else if (e === 'x') {
          const hex = source.slice(i, i + 2);
          if (!/^[0-9a-fA-F]{2}$/.test(hex) || (kind === 'str' && parseInt(hex,16) > 127)) fail('escape');
          value += String.fromCharCode(parseInt(hex,16)); i += 2;
        } else if (e === 'u' && source[i] === '{' && kind !== 'byte') {
          const end = source.indexOf('}', ++i), hex = source.slice(i,end).replace(/_/g,'');
          if (end < 0 || !/^[0-9a-fA-F]{1,6}$/.test(hex)) fail('escape');
          const cp = parseInt(hex,16);
          if (cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) fail('escape');
          value += String.fromCodePoint(cp); i = end + 1;
        } else if (quote === '"' && /[\r\n]/.test(e || '')) {
          while (/\s/.test(source[i] || '') && i < source.length) i++;
        } else fail('escape');
      }
      if (source[i++] !== quote) fail('unterminated-literal');
      if (quote === "'" && [...value].length !== 1) fail('character');
      push(kind,value);
    };
    while (i < source.length) {
      const rest = source.slice(i), c = source[i];
      if (/\s/.test(c)) { i++; continue; }
      if (rest.startsWith('//')) { const end = source.indexOf('\n',i); i = end < 0 ? source.length : end; continue; }
      if (rest.startsWith('/*')) {
        i += 2; let depth = 1;
        while (i < source.length && depth) {
          if (source.startsWith('/*',i)) { depth++; i += 2; }
          else if (source.startsWith('*/',i)) { depth--; i += 2; }
          else i++;
        }
        if (depth) fail('unterminated-comment');
        continue;
      }
      const raw = /^(?:br|cr|r)(#{0,255})"/.exec(rest);
      if (raw) {
        const close = '"' + raw[1], start = i + raw[0].length, end = source.indexOf(close,start);
        if (end < 0) fail('unterminated-raw');
        push('raw',source.slice(start,end)); i = end + close.length; continue;
      }
      if (/^[bc]"/.test(rest)) { i++; quoted('"','byte'); continue; }
      if (c === '"') { quoted('"','str'); continue; }
      if (rest.startsWith("b'")) { i++; quoted("'",'byte'); continue; }
      if (c === "'") {
        // An identifier after apostrophe without a closing apostrophe is a lifetime/label.
        const lifetime = /^'[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
        if (lifetime && rest[lifetime[0].length] !== "'") { push('lifetime',lifetime[0]); i += lifetime[0].length; }
        else quoted("'",'char');
        continue;
      }
      const id = /^(?:r#)?[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
      if (id) { push('id',id[0].replace(/^r#/,'')); i += id[0].length; continue; }
      if (/[\x00-\x1f\x7f-\uffff]/.test(c)) fail('unsupported-token');
      push('punct',c); i++;
      if (tokens.length > 1000000) fail('token-limit');
    }
    // Balance every token tree first, including irrelevant function/macro bodies.
    const stack = [], pairs = new Map(), closes = {')':'(',']':'[','}':'{'};
    for (let k = 0; k < tokens.length; k++) {
      const t = tokens[k]; if (t.kind !== 'punct') continue;
      if ('([{'.includes(t.value)) stack.push(k);
      else if (Object.hasOwn(closes,t.value)) {
        const open = stack.pop();
        if (open === undefined || tokens[open].value !== closes[t.value]) fail('unbalanced');
        pairs.set(open,k);
      }
    }
    if (stack.length) fail('unbalanced');
    const v = k => ['id','punct','lifetime'].includes(tokens[k]?.kind) ? tokens[k].value : undefined;
    const harmless = new Set(['allow','warn','deny','forbid','doc','deprecated','must_use']);
    let found = null;
    // We deliberately support only crate-root declarations. Nested targets are refused,
    // even in unconditional modules: reachability/export semantics are not inferred.
    function scope(start,end,root) {
      let attrs = [], crateUnsafe = false;
      for (let k = start; k < end;) {
        if (v(k) === '#') {
          const inner = v(k+1) === '!', open = k + (inner ? 2 : 1);
          if (v(open) !== '[' || !pairs.has(open)) fail('attribute');
          const name = v(open+1), unsafe = !harmless.has(name);
          if (inner) { if (unsafe) crateUnsafe = true; }
          else attrs.push(unsafe);
          k = pairs.get(open) + 1; continue;
        }
        const begin = k;
        // An item ends at its semicolon or first top-level braced body.
        let stop = k, body = -1;
        while (stop < end && v(stop) !== ';') {
          if (v(stop) === '{') { body = stop; break; }
          if (pairs.has(stop)) stop = pairs.get(stop) + 1;
          else stop++;
        }
        let target = -1;
        for (let j = begin; j < stop; j++) {
          if ((v(j) === 'const' || v(j) === 'static') &&
              (v(j+1) === declaration || (v(j+1) === 'mut' && v(j+2) === declaration))) target = j;
        }
        if (target >= 0) {
          if (found) fail('multiple-declarations');
          if (!root || crateUnsafe || attrs.some(Boolean)) fail('conditional-or-nested-declaration');
          if (target !== begin + 1 || v(begin) !== 'pub') fail('visibility');
          let p = target + 2;
          const take = x => { if (v(p++) !== x) fail('declaration-shape'); };
          take(':'); take('&');
          if (tokens[p]?.kind === 'lifetime' && v(p) === "'static") p++;
          take('['); take('&');
          if (tokens[p]?.kind === 'lifetime' && v(p) === "'static") p++;
          take('str'); take(']'); take('='); take('&'); take('[');
          let matches = 0, present = false;
          while (v(p) !== ']') {
            if (p >= stop) fail('array');
            const attributes = [];
            while (v(p) === '#') {
              const open = p + 1;
              if (v(open) !== '[' || !pairs.has(open)) fail('element-attribute');
              attributes.push(tokens.slice(open+1,pairs.get(open)));
              p = pairs.get(open) + 1;
            }
            if (tokens[p]?.kind === 'str') {
              const value = tokens[p++].value;
              if (value === capability) {
                if (++matches > 1) fail('duplicate-queried-literal');
                let cfgFeature = null;
                for (const attr of attributes) {
                  const name = attr[0]?.value;
                  if (attr[0]?.kind === 'id' && harmless.has(name)) continue;
                  if (attr[0]?.kind !== 'id' || name !== 'cfg' || cfgFeature !== null || attr.length !== 6 ||
                      attr[1].kind !== 'punct' || attr[1].value !== '(' || attr[2].kind !== 'id' || attr[2].value !== 'feature' ||
                      attr[3].kind !== 'punct' || attr[3].value !== '=' || attr[4].kind !== 'str' || attr[5].kind !== 'punct' || attr[5].value !== ')') fail('queried-element-cfg');
                  cfgFeature = attr[4].value;
                }
                if (cfgFeature !== null && !(enabledFeatures instanceof Set)) fail('production-features-underivable');
                present = cfgFeature === null || enabledFeatures.has(cfgFeature);
              }
            } else {
              // Unresolved paths cannot satisfy a literal query. Never inspect their values.
              if (v(p) === ':' && v(p+1) === ':') p += 2;
              if (tokens[p]?.kind !== 'id') fail('nonliteral-element');
              p++;
              while (v(p) === ':' && v(p+1) === ':') {
                p += 2;
                if (tokens[p]?.kind !== 'id') fail('nonliteral-element');
                p++;
              }
            }
            if (v(p) === ',') { p++; if (v(p) === ']') break; }
            else if (v(p) !== ']') fail('element-shape');
          }
          p++; if (p !== stop || v(stop) !== ';') fail('declaration-tail');
          found = {present};
        }
        if (body >= 0) { scope(body+1,pairs.get(body),false); k = pairs.get(body)+1; }
        else k = stop + 1;
        attrs = [];
      }
      if (root && found && crateUnsafe) fail('conditional-crate');
    }
    scope(0,tokens.length,true);
    return found?.present ? 'v1' : 'legacy';
  } catch (error) { return `invalid(${error.message})`; }
}
// Recognize the production build's restricted feature-selection program, without
// executing shell code. Any changed/unsupported build or manifest syntax is unknown.
function deriveFeatures(build, cargo) {
  try {
    if (typeof build !== 'string' || typeof cargo !== 'string') return null;
    const tables = [...cargo.matchAll(/^\[features\]\s*$/gm)];
    if (tables.length !== 1) return null;
    const tail = cargo.slice(tables[0].index + tables[0][0].length);
    const table = tail.split(/^\[/m)[0];
    // TOML comments outside basic strings only. Feature arrays use basic strings.
    const clean = table.replace(/"(?:\\.|[^"\\])*"|#[^\n]*/g, x => x.startsWith('#') ? '' : x);
    const graph = new Map(); let rest = clean;
    while (rest.trim()) {
      const m = /^\s*([A-Za-z0-9_-]+)\s*=\s*\[([^\]]*)\]\s*/.exec(rest);
      if (!m || graph.has(m[1])) return null;
      let values;
      try { values = JSON.parse('[' + m[2].replace(/,\s*$/, '') + ']'); } catch { return null; }
      if (!values.every(x => typeof x === 'string')) return null;
      graph.set(m[1],values); rest = rest.slice(m[0].length);
    }
    // Isolate the front stage and insist on the known build command and selector
    // grammar. Different flags, inherited feature env, or multiple builds refuse.
    const stage = /FROM [^\n]+ AS front\n([\s\S]*?)(?=\nFROM |$)/.exec(build)?.[1];
    if (!stage || /(?:CARGO_ENCODED_RUSTFLAGS|RUSTFLAGS|CARGO_FEATURE|--no-default-features|--all-features)/.test(stage)) return null;
    if ((stage.match(/cargo build/g) || []).length !== 1) return null;
    const program = /features=([a-zA-Z0-9_,-]+);\s*\\\n([\s\S]*?)cargo build --release --locked -p noevia-server --features "\$features";/.exec(stage);
    if (!program) return null;
    const enabled = new Set(['default', ...program[1].split(',')]);
    let selectors = program[2].replace(/\\\n/g,' ').trim();
    while (selectors) {
      const m = /^if grep -(qx|q) '([^']+)' bins\/noevia-server\/Cargo\.toml; then features="\$features,([A-Za-z0-9_-]+)"; fi;\s*/.exec(selectors);
      if (!m) return null;
      const exact = m[2] === m[3] + ' = \\[\\]';
      const prefix = m[2] === '^' + m[3] + ' = ';
      if ((m[1] === 'qx' && !exact) || (m[1] === 'q' && !prefix)) return null;
      // Reproduce grep against the original snapshot, not reformatted TOML.
      if (cargo.split('\n').some(line => exact ? line === m[3] + ' = []' : line.startsWith(m[3] + ' = '))) enabled.add(m[3]);
      selectors = selectors.slice(m[0].length).trim();
    }
    // Everything between the stage header and selector must be the known setup;
    // no alternate features assignment or extra cargo flags may be hidden there.
    const prefix = stage.slice(0,program.index).replace(/\\\n/g,' ').replace(/\s+/g,' ').trim();
    if (!/^ENV RUSTUP_TOOLCHAIN=[^ ]+ CARGO_TERM_COLOR=never COPY rs\/ \/src\/ WORKDIR \/src RUN set -e; mkdir -p \/out; if \[ -f bins\/noevia-server\/Cargo.toml \]; then$/.test(prefix)) return null;
    const visited = new Set();
    function visit(name) {
      if (visited.has(name)) return;
      visited.add(name);
      if (!graph.has(name)) {
        if (name === 'default') return;
        throw new Error('unknown-feature');
      }
      enabled.add(name);
      for (const dep of graph.get(name)) {
        if (dep.startsWith('dep:') || dep.includes('/')) continue;
        visit(dep);
      }
    }
    for (const name of [...enabled]) visit(name);
    return enabled;
  } catch { return null; }
}
module.exports = {detect, deriveFeatures};
if (require.main === module) {
  try {
    const fs = require('node:fs'), path = require('node:path');
    const [file,name,capability,buildFile,cargoFile] = process.argv.slice(2);
    let features = null;
    try {
      features = deriveFeatures(fs.readFileSync(buildFile || path.join(__dirname,'../../../build/web.Dockerfile'),'utf8'),
        fs.readFileSync(cargoFile || path.join(path.dirname(file),'../Cargo.toml'),'utf8'));
    } catch { /* Only a queried cfg element requires a derivable build. */ }
    process.stdout.write(detect(fs.readFileSync(file,'utf8'),name,capability,features) + '\n');
  } catch { process.stdout.write('invalid(read)\n'); }
}
