'use strict';
// #355, #360, #362: sidebar search Escape / inline rename / quick-archive undo. Sidebar.tsx wires
// live DOM refs and timers that aren't worth a headless-DOM harness for; the pure pieces
// (normalizeRenameDraft, placeCatalogue-style helpers) have their own unit tests, and this file
// pins the wiring in the markup so a regression that drops a fix is still caught.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const src = fs.readFileSync(path.join(__dirname, '../src/components/Sidebar.tsx'), 'utf8');

test('startRename normalises the prefill before it reaches renameDraft state (#360)', () => {
  assert.match(src, /setRenameDraft\(normalizeRenameDraft\(current\)\)/);
});
test('the list rename input has an accessible label (#360)', () => {
  const input = src.slice(src.indexOf("renameSource==='list' ?"), src.indexOf("renameSource==='list' ?") + 400);
  assert.match(input, /aria-label=\{t\('sidebar\.renameChatLabel'\)\}/);
});
test('Escape in the sidebar search returns focus to a search trigger instead of <body> (#355)', () => {
  const handler = src.slice(src.indexOf('shell-search'), src.indexOf('shell-search') + 500);
  assert.match(handler, /searchTrigger\.current\|\|railSearchButton\.current\)\?\.focus\(\)/);
});
test('committing or cancelling a list rename returns focus to that row (#355)', () => {
  const start = src.indexOf("renameSource==='list' ?");
  const input = src.slice(start, src.indexOf('/>', start) + 2);
  // Both Enter (commit) and Escape (cancel) must return focus, not just one of them.
  assert.equal((input.match(/returnFocusToRow\(c\.id\)/g) || []).length, 2);
});
test('quick-archive goes through the undo-toast path, not a bare patch call (#362)', () => {
  const archiveButton = src.slice(src.indexOf('sidebar.archiveNamed'), src.indexOf('sidebar.archiveNamed') + 300);
  assert.match(archiveButton, /onClick=\{\(\)=>archiveChat\(c,projectId\)\}/);
});
test('the archive-undo toast offers Undo and is announced politely, not as an alert (#362)', () => {
  const toast = src.slice(src.indexOf('archiveUndo &&'), src.indexOf('archiveUndo &&') + 400);
  assert.match(toast, /role="status"/);
  assert.match(toast, /onClick=\{undoArchive\}/);
  assert.match(toast, /common\.undo/);
});
test('undo restores the same chat without touching its position-determining fields (#362)', () => {
  const undo = src.slice(src.indexOf('const undoArchive'), src.indexOf('const undoArchive') + 300);
  assert.match(undo, /onPatchChat\(archiveUndo\.projectId, ?archiveUndo\.chat\.id, ?\{ ?archived: ?false ?\}\)/);
});
