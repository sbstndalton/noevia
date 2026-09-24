const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/source-status.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS },
}).outputText, { exports: exportsObject });
const { sourceStatus, sourceRefreshIssues, sourceRefreshEntries, skippedSignature, resolveSkippedToast } = exportsObject;
test('source rows distinguish partial, new failure and stale text', () => {
  assert.match(sourceStatus({ document: { state: 'partial', pages: 2, pageStatus: [{number: 2, status:'ocr-needed'}] } }), /Partially readable.*check pages 2/);
  assert.match(sourceStatus({ document: { state: 'failed', stale: false } }), /Not readable/);
  assert.match(sourceStatus({ document: { state: 'failed', stale: true } }), /using previous text/);
});
test('refresh errors name every affected file and only claim retention when true', () => {
  const text = sourceRefreshIssues([{folder:'f',file:'new.pdf',reason:'OCR needed',retained:false},{folder:'f',file:'old.pdf',reason:'unavailable',retained:true}]);
  assert.match(text, /new.pdf: OCR needed\nold.pdf: unavailable Previous readable text retained/);
});

const a = { folder: 'Notes', file: 'a.pdf', reason: 'Too large' };
const b = { folder: 'Notes', reason: 'Folder unreadable', retained: true };

test('sourceRefreshEntries renders one line per skipped source (for list rendering)', () => {
  assert.deepEqual(sourceRefreshEntries([a, b]), ['a.pdf: Too large', 'Notes: Folder unreadable Previous readable text retained.']);
  assert.equal(sourceRefreshIssues([a, b]), 'a.pdf: Too large\nNotes: Folder unreadable Previous readable text retained.');
});

test('skippedSignature is order-independent and empty for no entries', () => {
  assert.equal(skippedSignature([]), '');
  assert.equal(skippedSignature([a, b]), skippedSignature([b, a]));
  assert.notEqual(skippedSignature([a]), skippedSignature([b]));
});

test('resolveSkippedToast: same skipped set does not re-show the toast', () => {
  const sig = skippedSignature([a, b]);
  const msg = sourceRefreshIssues([a, b]);
  const r = resolveSkippedToast({ signature: sig, message: msg }, [a, b], msg);
  assert.equal(r.signature, sig);
  assert.equal(r.show, undefined);
});

test('resolveSkippedToast: a changed skipped set shows the new message', () => {
  const prevSig = skippedSignature([a]);
  const r = resolveSkippedToast({ signature: prevSig, message: sourceRefreshIssues([a]) }, [a, b], sourceRefreshIssues([a]));
  assert.equal(r.signature, skippedSignature([a, b]));
  assert.equal(r.show, sourceRefreshIssues([a, b]));
});

test('resolveSkippedToast: a clean refresh clears a previously-shown toast that is still the one on screen', () => {
  const prevSig = skippedSignature([a]);
  const prevMsg = sourceRefreshIssues([a]);
  const r = resolveSkippedToast({ signature: prevSig, message: prevMsg }, [], prevMsg);
  assert.equal(r.signature, '');
  assert.equal(r.show, null);
});

test('resolveSkippedToast: a clean refresh does NOT clear an unrelated error currently on screen', () => {
  const prevSig = skippedSignature([a]);
  const prevMsg = sourceRefreshIssues([a]);
  const r = resolveSkippedToast({ signature: prevSig, message: prevMsg }, [], 'Some unrelated project error.');
  assert.equal(r.show, undefined);
});

test('resolveSkippedToast: nothing to show and nothing previously shown is a no-op', () => {
  const r = resolveSkippedToast({ signature: '', message: '' }, [], null);
  assert.equal(r.signature, '');
  assert.equal(r.show, undefined);
});
