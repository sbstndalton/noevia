const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const result={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/tool-call-state.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:result});
test('a reply that ended leaves no pending or running calls, and no approval ids', () => {
  const settled = result.settleToolCalls([
    { name: 'read', args: '{}', status: 'done', result: 'ok' },
    { name: 'write', args: '{"a":1}', status: 'pending', approvalId: 'ap-1' },
    { name: 'search', args: '{}', status: 'running' },
    { name: 'legacy', args: '{}' },
    { name: 'no', args: '{}', status: 'denied', result: 'ERROR: the user declined' },
  ]);
  assert.deepEqual(settled.map((c) => c.status), ['done', 'stopped', 'stopped', 'stopped', 'denied']);
  assert.ok(settled.every((c) => c.approvalId === undefined));
  assert.equal(settled[1].args, '{"a":1}', 'arguments are kept for the record');
  assert.equal(result.settleToolCalls(undefined), undefined);
});
