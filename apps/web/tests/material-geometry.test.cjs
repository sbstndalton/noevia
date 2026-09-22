'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Material 3 inherits shared geometry and font metrics instead of changing layout', () => {
  const root = path.join(__dirname, '../src/styles');
  const forbidden = /^(?:(?:min-|max-)?(?:width|height)|padding(?:-.+)?|margin(?:-.+)?|gap|font(?:-.+)?|letter-spacing|border(?:-(?:width|top|left|right|bottom))?|--font-ui|--font-display|--row-inset|--row-gap)$/;
  for (const file of fs.readdirSync(root).filter(name => name.endsWith('.css'))) {
    const css = fs.readFileSync(path.join(root, file), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    for (const [, selector, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      if (!/data-material=['"]material['"]/.test(selector)) continue;
      for (const declaration of body.split(';')) {
        const property = declaration.split(':')[0].trim();
        assert.equal(forbidden.test(property), false, `${file}: ${selector.trim()} overrides ${property}`);
      }
    }
  }
});
