'use strict';
const {detect, deriveFeatures} = require('./lib/rs-capability.cjs');
const cases = require('./fixtures/rs-capability/cases.json');
// Apply the branch-copy mutation classes to each collected protocol literal.
const matrix = cases.filter(c => c.origin === 'new' && !['new:static-lifetime','new:char-lifetime'].includes(c.name));
for (const marker of require('./fixtures/rs-capability/branch-markers.json')) {
  for (const c of matrix) {
    const source = c.source.replaceAll('cap',marker)
      .replaceAll('c\\x61p', '\\x' + marker.charCodeAt(0).toString(16) + marker.slice(1))
      .replaceAll('c\\u{61}p', '\\u{' + marker.charCodeAt(0).toString(16) + '}' + marker.slice(1));
    cases.push({...c,name:`branch-matrix:${marker}:${c.name}`,source,capability:marker});
  }
}
let failures = 0;
for (const c of cases) {
  const got = detect(c.source,c.declaration,c.capability,c.features === undefined || c.features === null ? null : new Set(c.features));
  if (got.split('(')[0] !== c.expected) { console.error(JSON.stringify({name:c.name,expected:c.expected,got,source:c.source})); failures++; }
}
const fs = require('node:fs'), path = require('node:path');
const fixture = name => fs.readFileSync(path.join(__dirname,'fixtures/rs-capability',name),'utf8');
const build = fixture('production.Dockerfile'), cargo = fixture('production-Cargo.toml');
const derived = deriveFeatures(build,cargo);
const featureCases = [
  ['actual production features', derived instanceof Set && derived.has('rust-storage-reads') && derived.has('rust-project-chats') && !derived.has('absent')],
  ['current production build', deriveFeatures(fs.readFileSync(path.join(__dirname,'../../build/web.Dockerfile'),'utf8'),cargo)?.has('rust-storage-reads')],
  ['no default flag excludes default', deriveFeatures(build.replace('cargo build --release','cargo build --no-default-features --release'),cargo) instanceof Set && !deriveFeatures(build.replace('cargo build --release','cargo build --no-default-features --release'),cargo).has('default')],
  ['all features flag refuses', deriveFeatures(build.replace('cargo build --release','cargo build --all-features --release'),cargo) === null],
  ['unknown selector refuses', deriveFeatures(build.replace('features=rust-reasoning-settings','features=$CUSTOM'),cargo) === null],
  ['extra assignment refuses', deriveFeatures(build.replace('cargo build --release','features=other; cargo build --release'),cargo) === null],
  ['extra env refuses', deriveFeatures(build.replaceAll('ENV RUSTUP_TOOLCHAIN','ENV CARGO_ENCODED_RUSTFLAGS=custom\nENV RUSTUP_TOOLCHAIN'),cargo) === null],
  ['unknown build flags refuse', deriveFeatures(build.replace('--locked -p','--locked --config other -p'),cargo) === null],
  ['duplicate features table refuses', deriveFeatures(build,cargo+'\n[features]\ndefault=[]\n') === null],
  ['malformed manifest refuses', deriveFeatures(build,'[features]\ndefault = [broken]') === null],
  ['missing build refuses', deriveFeatures('',cargo) === null],
  ['missing manifest refuses', deriveFeatures(build,'') === null],
];
const graph = '[features]\ndefault = ["via-default"]\nvia-default = ["transitive"]\ntransitive = []\nrust-reasoning-settings=[]\nrust-routing-mode=[]\n';
const transitive = deriveFeatures(build,graph);
featureCases.push(['default feature closure', transitive?.has('transitive')]);
featureCases.push(['disabled default feature', !deriveFeatures(build,graph.replace('["via-default"]','[]'))?.has('transitive')]);
const src = 'pub const FEATURES: &[&str] = &[#[cfg(feature = "transitive")] "cap"];';
featureCases.push(['derived default queried cfg', detect(src,'FEATURES','cap',transitive) === 'v1']);
featureCases.push(['underivable queried cfg', detect(src,'FEATURES','cap',deriveFeatures('',cargo)) === 'invalid(production-features-underivable)']);
const noDefault = deriveFeatures(build.replace('cargo build --release','cargo build --no-default-features --release'),graph);
featureCases.push(['no-default excludes default transitive closure', noDefault instanceof Set && !noDefault.has('default') && !noDefault.has('transitive')]);
const minimal = '[features]\nrust-reasoning-settings=[]\nrust-routing-mode=[]\n';
for (const manifest of [minimal,minimal+'default=[]\n']) {
  const featureSet=deriveFeatures(build,manifest);
  const defaultSrc='pub const FEATURES: &[&str] = &[#[cfg(feature = "default")] "cap"];';
  featureCases.push(['default declaration presence '+manifest.length, featureSet instanceof Set && featureSet.has('default') === manifest.includes('default=')]);
  featureCases.push(['queried default declaration '+manifest.length, detect(defaultSrc,'FEATURES','cap',featureSet) === (manifest.includes('default=')?'v1':'legacy')]);
}
featureCases.push(['undeclared explicit feature refuses', deriveFeatures(build.replace('features=rust-reasoning-settings,','features=undeclared-feature,'),minimal) === null]);
for (const [name,ok] of featureCases) { if (!ok) { console.error('feature derivation: '+name); failures++; } }
if (failures) process.exit(1);
console.log(`Production feature derivation: ${featureCases.length} passed`);
console.log(`Rust capability fixtures: ${cases.length} passed`);
