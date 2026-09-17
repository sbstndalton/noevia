'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const { lint } = require('../scripts/lint-design.cjs');

test('flags one-sided accent borders but not blockquotes, hairlines or allowed cases', () => {
  const rules = (css) => lint(css).map((f) => `${f.rule}@${f.line}`);
  assert.deepEqual(rules('.card {\n  border-left: 3px solid var(--accent);\n}'), ['side-tab@2']);
  assert.deepEqual(rules('.card { border: 1px solid red; border-left-width: 4px; }'), ['side-tab@1']);
  assert.deepEqual(rules('.panel { border-left: 1px solid var(--border); }'), []);
  assert.deepEqual(rules('.markdown blockquote { border-left: 3px solid var(--accent); }'), []);
  assert.deepEqual(rules('/* design-lint: allow side-tab — miniature sidebar */\n.preview { border-left: 25px solid var(--chrome); }'), []);
});

test('flags overshooting easing and gradient text only', () => {
  assert.deepEqual(lint('a { transition: transform .2s cubic-bezier(0.16, 1, 0.3, 1); }'), []);
  assert.equal(lint('a { transition: transform .2s cubic-bezier(.34,1.56,.64,1); }')[0].rule, 'overshoot-ease');
  assert.equal(lint('h1 { -webkit-background-clip: text; background-clip: text; }').length, 2);
});

test('font sizes come from the type scale and weights from four steps', () => {
  // HIG typography: a small hierarchy of text styles, no in-between weights.
  const rules = (css) => lint(css).map((f) => f.rule);
  assert.deepEqual(rules('p { font-size: var(--text-body); font-weight: 600; }'), []);
  assert.deepEqual(rules('p { font-size: 13px; }'), []);
  assert.deepEqual(rules('p { font-size: 12.5px; }'), ['type-scale']);
  assert.deepEqual(rules('p { font-size: 14.5px; }'), ['type-scale']);
  assert.deepEqual(rules('p { font-size: 18px; }'), ['type-scale']);
  assert.deepEqual(rules('p { font-size: 0.75rem; }'), ['type-scale']);
  assert.deepEqual(rules('p { font-size: inherit; font-size: 1em; }'), []);
  assert.deepEqual(rules('b { font-weight: 550; }'), ['font-weight']);
  assert.deepEqual(rules('b { font-weight: 650 }'), ['font-weight']);
  assert.deepEqual(rules('b { font-weight: bold; font-weight: 700; }'), []);
  assert.deepEqual(rules('--text-body: 13px;'), []);
});

test('the app stylesheets pass', () => {
  const fs = require('node:fs'), path = require('node:path');
  const dir = path.join(__dirname, '../src');
  const findings = fs.readdirSync(dir, { recursive: true }).filter((f) => /\.(css|tsx)$/.test(f)).flatMap((f) => lint(fs.readFileSync(path.join(dir, f), 'utf8'), f));
  assert.deepEqual(findings, []);
});
