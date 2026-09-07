const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
function load(name, apiFetch = () => {throw Error('unexpected request');}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src',name),'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const exports = {};
  vm.runInNewContext(code,{exports,require:()=>({apiFetch}),DOMException,File,window:{},Date,console});
  return exports;
}
const dates = load('diary-data.ts');
test('calendar has leap day and correctly aligned weekday cells',()=>{
  const grid=dates.calendarDays('2024-02');
  assert.equal(grid.length,33); assert.equal(grid[4],'2024-02-01'); assert.equal(grid.at(-1),'2024-02-29');
});
test('days stay separate and standing notes are not a diary day',()=>{
  const parsed=dates.splitDays('## Wednesday, July 8, 2026\nfirst\n## Thursday, July 9, 2026\nsecond\n## Open questions\nquestion');
  assert.match(parsed['2026-07-08'],/first/); assert.doesNotMatch(parsed['2026-07-08'],/second/); assert.doesNotMatch(parsed['2026-07-09'],/question/);
  assert.equal(dates.dateInText('2026-02-30'),null);
});
test('submission timestamp uses current local wall-clock date with offset',()=>{
  const now=new Date(2026,8,7,0,5,4);
  assert.equal(dates.localDay(now),'2026-09-07');
  assert.match(dates.localTimestamp(now),/^2026-09-07T00:05:04[+-]\d{2}:\d{2}$/);
});
function fakeFolder(initial={}) {
  const data={...initial};
  const dir={
    kind:'directory', name:'fixture',
    async *values(){ for(const name of Object.keys(data)) yield await this.getFileHandle(name); },
    async getDirectoryHandle(){ return dir; },
    async getFileHandle(name,opt={}) {
      if(!(name in data)&&!opt.create) throw new DOMException('missing','NotFoundError');
      return {
        kind:'file', name,
        async getFile(){ return new File([data[name]||''],name); },
        async createWritable(){ return { async write(text){data[name]=text;}, async close(){}, async abort(){} }; }
      };
    }
  };
  return {dir,data};
}
test('local-only save makes no server calls and preserves unrelated files',async()=>{
  const api=load('diary-workspace.ts');const f=fakeFolder({'MEMORY.md':'old','notes.md':'keep'});
  await api.saveLocal(f.dir,'MEMORY.md','new','old');
  assert.equal(f.data['MEMORY.md'],'new');assert.equal(f.data['notes.md'],'keep');
});
test('local conflict never overwrites newer file',async()=>{
  const api=load('diary-workspace.ts');const f=fakeFolder({'MEMORY.md':'external edit'});
  await assert.rejects(api.saveLocal(f.dir,'MEMORY.md','new','old'),/changed/);
  assert.equal(f.data['MEMORY.md'],'external edit');
});
test('folder scan only imports Markdown and rejects excess size',async()=>{
  const api=load('diary-workspace.ts');const f=fakeFolder({'MEMORY.md':'words','secret.txt':'not selected'});
  const files=await api.scanLocal(f.dir); assert.equal(files['MEMORY.md'],'words');assert.equal(files['secret.txt'],undefined);
  await assert.rejects(api.scanLocal(fakeFolder({'huge.md':'x'.repeat(512*1024+1)}).dir),/512 KiB/);
});
test('sync uses remote version and retries an already completed write without duplication',async()=>{
  let remote='old', puts=0;
  const api=load('diary-workspace.ts',async(_url,init)=>{
    if(init.method==='PUT'){ const b=JSON.parse(init.body);assert.equal(b.version,'v1');remote=b.content;puts++; }
    return {ok:true,json:async()=>({path:'MEMORY.md',content:remote,version:'v1'})};
  });
  await api.syncFileChange('MEMORY.md','old','new'); await api.syncFileChange('MEMORY.md','old','new');assert.equal(puts,1);
});
test('sync refuses divergent remote contents and remote failure is surfaced',async()=>{
  let puts=0; const api=load('diary-workspace.ts',async(_url,init)=>{if(init.method==='PUT')puts++;return {ok:true,json:async()=>({content:'different',version:'v2'})};});
  await assert.rejects(api.syncFileChange('MEMORY.md','old','new'),/differs/);assert.equal(puts,0);
  const offline=load('diary-workspace.ts',async()=>{throw Error('offline');});
  await assert.rejects(offline.syncFileChange('MEMORY.md','old','new'),/offline/);
});
