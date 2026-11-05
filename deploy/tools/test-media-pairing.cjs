'use strict';
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), cp = require('node:child_process'), assert = require('node:assert/strict');
const source = fs.readFileSync(process.env.ASSEMBLE_SOURCE || path.join(__dirname, 'assemble-release.sh'), 'utf8');
const begin = source.indexOf('media_core_version()');
const end = source.indexOf('\nfor need in web/package.json', begin);
assert.ok(begin >= 0 && end > begin, 'native media pair guard must exist');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'media-pair-'));
const marker = 'rust-media-background-v1';
const core = `module.exports.RUST_MEDIA_BACKGROUND_OWNED = '${marker}';`;
const rust = `pub const FEATURES: &[&str] = &["${marker}"];`;
const cases = [
  ['paired', core, rust, true], ['legacy', '', 'pub const FEATURES: &[&str] = &[];', true],
  ['core half', core, '', false], ['rust half', '', rust, false],
  ['unexported literal', `const marker = '${marker}';`, rust, false],
  ['nonstring export', 'module.exports.RUST_MEDIA_BACKGROUND_OWNED = 1;', rust, false],
  ['comment only', '', `// "${marker}"\npub const FEATURES: &[&str] = &[];`, true],
  ['constant alias cannot hide ownership', '', `const HIDDEN: &str = "${marker}"; pub const FEATURES: &[&str] = &[HIDDEN];`, false],
  ['gated element', core, `pub const FEATURES: &[&str] = &[#[cfg(any())] "${marker}"];`, false],
  ['gated declaration', core, `#[cfg(any())]\n${rust}`, false],
  ['gated enclosing module', core, `#[cfg(any())] mod hidden { ${rust} }`, false],
  ['duplicate', core, `pub const FEATURES: &[&str] = &["${marker}","${marker}"];`, false],
  ['escaped duplicate', core, `pub const FEATURES: &[&str] = &["${marker}","rust-media-background-v\\x31"];`, false],
  ['byte string', core, `pub const FEATURES: &[&str] = &[b"${marker}"];`, false],
  ['raw string', core, `pub const FEATURES: &[&str] = &[r#"${marker}"#];`, false],
  ['macro', core, 'pub const FEATURES: &[&str] = &[concat!("rust-media-background-", "v1")];', false],
  ['timed getter', `Object.defineProperty(module.exports,'RUST_MEDIA_BACKGROUND_OWNED',{get(){while(true){}}});`, rust, false],
];
try {
  const script = path.join(dir, 'guard.sh');
  fs.writeFileSync(script, 'tree="$1"\ndie(){ echo "$*" >&2; exit 19; }\n' + source.slice(begin, end));
  const cf = path.join(dir, 'core/server/rust-media-background.cjs'), rf = path.join(dir, 'rs/bins/noevia-server/src/lib.rs');
  fs.mkdirSync(path.dirname(cf), { recursive: true }); fs.mkdirSync(path.dirname(rf), { recursive: true });
  for (const [name, c, r, pass] of cases) {
    fs.writeFileSync(cf, c); fs.writeFileSync(rf, r);
    const result = cp.spawnSync('bash', [script, dir], { encoding: 'utf8', timeout: 15000 });
    assert.equal(result.status === 0, pass, `${name}: ${result.stderr}`);
  }
  console.log(`${cases.length} media pairing fixtures passed`);
} finally { fs.rmSync(dir, { recursive: true, force: true }); }
