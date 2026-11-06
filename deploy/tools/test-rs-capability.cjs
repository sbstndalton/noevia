'use strict';
const {detect} = require('./lib/rs-capability.cjs');
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
  const got = detect(c.source,c.declaration,c.capability);
  if (got.split('(')[0] !== c.expected) { console.error(JSON.stringify({name:c.name,expected:c.expected,got,source:c.source})); failures++; }
}
if (failures) process.exit(1);
console.log(`Rust capability fixtures: ${cases.length} passed`);
