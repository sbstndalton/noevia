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
const { sourceStatus, sourceRefreshIssues } = exportsObject;
test('source rows distinguish partial, new failure and stale text', () => {
  assert.match(sourceStatus({ document: { state: 'partial', pages: 2, pageStatus: [{number: 2, status:'ocr-needed'}] } }), /Partially readable.*check pages 2/);
  assert.match(sourceStatus({ document: { state: 'failed', stale: false } }), /Not readable/);
  assert.match(sourceStatus({ document: { state: 'failed', stale: true } }), /using previous text/);
});
test('refresh errors name every affected file and only claim retention when true', () => {
  const text = sourceRefreshIssues([{folder:'f',file:'new.pdf',reason:'OCR needed',retained:false},{folder:'f',file:'old.pdf',reason:'unavailable',retained:true}]);
  assert.match(text, /new.pdf: OCR needed\nold.pdf: unavailable Previous readable text retained/);
});
