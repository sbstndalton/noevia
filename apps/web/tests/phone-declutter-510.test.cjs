// #510: the phone declutter stylesheet only works if it loads after the family overrides it
// lightens, and it must never hide anything on a wide screen. Browser proof lives in
// qa/phone-declutter-510.cjs; this guards the two structural facts it depends on.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const src = path.join(__dirname, '../src');
const css = fs.readFileSync(path.join(src, 'styles/phone-declutter.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

test('phone-declutter.css is the last stylesheet main.tsx imports', () => {
  const imports = [...fs.readFileSync(path.join(src, 'main.tsx'), 'utf8').matchAll(/import '\.\/styles\/([\w-]+\.css)';/g)].map(m => m[1]);
  assert.equal(imports.at(-1), 'phone-declutter.css');
  assert.ok(imports.indexOf('families.css') < imports.indexOf('phone-declutter.css'));
});

test('everything it hides is hidden only below 768px, except the phone-only parts', () => {
  // Split top-level blocks: each @media block, or a bare rule.
  const blocks = []; let depth = 0, start = 0;
  for (let i = 0; i < css.length; i++) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}' && --depth === 0) { blocks.push(css.slice(start, i + 1).trim()); start = i + 1; }
  }
  const phoneOnly = /model-pill-short|reasoning-pill-icon|composer-browse-tools/;
  for (const block of blocks) {
    if (!/display:\s*none/.test(block)) continue;
    if (/^@media \(max-width: 767px\)/.test(block)) continue;
    // Outside the phone query, only parts that exist for the phone may be hidden.
    for (const rule of block.matchAll(/([^{}]+)\{[^{}]*display:\s*none[^{}]*\}/g)) {
      for (const selector of rule[1].replace(/@media[^{]*/, '').split(',')) assert.match(selector, phoneOnly, `hidden on wide screens: ${selector.trim()}`);
    }
  }
});
