'use strict';
// Obsidian-style [[links]] in a Diary kept as plain Markdown. The parser never rewrites the
// file; it reports positions, and resolution offers the placements a real vault uses.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const ts = require('typescript');
const source = fs.readFileSync(path.join(__dirname, '../src/diary-markdown.ts'), 'utf8').replace(/export /g, '');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
const ctx = {}; vm.createContext(ctx); vm.runInContext(js, ctx);
// The module runs in a VM, so its arrays are not reference-equal to ours; compare values.
const plain = (value) => JSON.parse(JSON.stringify(value));
const markdownWikiLinks = (text) => plain(ctx.markdownWikiLinks(text));
const wikiLinkCandidates = (...args) => plain(ctx.wikiLinkCandidates(...args));

test('every form a vault actually uses is recognised', () => {
  const text = [
    'A plain [[Note]] and an aliased [[Projects/Plan|the plan]].',
    'A heading [[Note#Morning]] and a block [[2026-09-20#^a1b2c3]].',
    'An embed ![[Figure 1.png]] and a same-file anchor [[#Later today]].',
  ].join('\n');
  const found = markdownWikiLinks(text);
  assert.deepEqual(found.map((l) => [l.target, l.alias, l.heading, l.embed]), [
    ['Note', null, null, false],
    ['Projects/Plan', 'the plan', null, false],
    ['Note', null, 'Morning', false],
    ['2026-09-20', null, '^a1b2c3', false],
    ['Figure 1.png', null, null, true],
    ['', null, 'Later today', false],
  ]);
  // Positions point at the source, and the embed's "!" belongs to the link.
  for (const link of found) assert.equal(text.slice(link.offset, link.offset + link.length).endsWith(']]'), true);
  assert.equal(text.slice(found[4].offset, found[4].offset + found[4].length), '![[Figure 1.png]]');
});

test('code is code, in a fence or inline, exactly as the tag reader treats it', () => {
  const text = ['```', 'not a link: [[Fenced]]', '```', 'inline `[[Backticked]]` stays text, but [[Real]] does not.'].join('\n');
  assert.deepEqual(markdownWikiLinks(text).map((l) => l.target), ['Real']);
});

test('a link resolves from the Diary folder first, then beside the file that names it', () => {
  // Obsidian prefers the copy nearest the vault root when a bare name is ambiguous.
  assert.deepEqual(wikiLinkCandidates('Diary/2026/09/20.md', 'Diary', 'Note'), ['Diary/Note.md', 'Diary/2026/09/Note.md']);
  assert.deepEqual(wikiLinkCandidates('2026-09-20.md', '', 'Ideas/Plan'), ['Ideas/Plan.md']);
  // An explicit .md is not doubled.
  assert.deepEqual(wikiLinkCandidates('a/b.md', '', 'Note.md'), ['Note.md', 'a/Note.md']);
});

test('a link that could escape the vault, or is not Markdown, resolves to nothing', () => {
  for (const target of ['/etc/passwd', '../../secrets', 'a\\b', 'x:y', '', '.hidden', 'a/../../b']) {
    const candidates = wikiLinkCandidates('Diary/2026/09/20.md', 'Diary', target);
    assert.ok(candidates.every((c) => c.startsWith('Diary/')), `${target} escaped: ${candidates}`);
  }
  assert.deepEqual(wikiLinkCandidates('a.md', '', '/root'), []);
  assert.deepEqual(wikiLinkCandidates('a.md', '', 'x'.repeat(400)), []);
});

test('a file full of brackets cannot make the parser run away', () => {
  const text = Array.from({ length: 900 }, (_, i) => `[[Note ${i}]]`).join('\n');
  assert.equal(markdownWikiLinks(text).length, 500);
});
