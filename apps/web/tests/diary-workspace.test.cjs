const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
function load(name, apiFetch = () => {throw Error('unexpected request');}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src',name),'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const exports = {};
  vm.runInNewContext(code,{exports,require:name=>name==='./diary-markdown'?load('diary-markdown.ts'):({apiFetch}),DOMException,File,TextEncoder,window:{},Date,console});
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
  let puts=0; const api=load('diary-workspace.ts',async(_url,init)=>{if(init.method==='PUT')puts++;return {ok:true,json:async()=>({path:'MEMORY.md',content:'different',version:'v2'})};});
  await assert.rejects(api.syncFileChange('MEMORY.md','old','new'),/differs/);assert.equal(puts,0);
  const offline=load('diary-workspace.ts',async()=>{throw Error('offline');});
  await assert.rejects(offline.syncFileChange('MEMORY.md','old','new'),/offline/);
});

test('invalid listings and mismatched reads cannot replace editor state',async()=>{
  const malformed=load('diary-workspace.ts',async()=>({ok:true,json:async()=>({files:{}})}));
  await assert.rejects(malformed.listFiles(),/File list was invalid/);
  const wrong=load('diary-workspace.ts',async()=>({ok:true,json:async()=>({path:'other.md',content:'other',version:'v1'})}));
  await assert.rejects(wrong.readFile('note.md'),/File response was invalid/);
});
test('local byte limit rejects multi-byte content before creating directories or writing',async()=>{
  const api=load('diary-workspace.ts');let calls=0;
  await assert.rejects(api.saveLocal({getDirectoryHandle(){calls++;}},'new/note.md','é'.repeat(262145),null),/512 KiB/);
  assert.equal(calls,0);
});
test('conflict status survives the request boundary for editor comparison',async()=>{
  const api=load('diary-workspace.ts',async()=>({ok:false,status:409,json:async()=>({error:'changed'})}));
  await assert.rejects(api.writeFile({path:'note.md',content:'draft',version:'v1'}),e=>e instanceof api.DiaryRequestError && e.status===409);
});
test('outline preserves source offsets and skips frontmatter and fenced headings',()=>{
  const api=load('diary-markdown.ts');
  const text='---\n# metadata\n---\n# Real\n```md\n# Example\n```\n## Second';
  const rows=api.markdownOutline(text);
  assert.equal(rows.length,2);assert.equal(rows[0].label,'Real');assert.equal(rows[1].offset,text.indexOf('## Second'));
});
test('relative Markdown links stay within the tenant root and reject active or ambiguous URLs',()=>{
  const {resolveMarkdownPath}=load('diary-markdown.ts');
  assert.equal(resolveMarkdownPath('memory/note.md','../Entries/day.md'),'Entries/day.md');
  assert.equal(resolveMarkdownPath('note.md','space%20name.md'),'space name.md');
  for(const href of ['../secret.md','%2e%2e/secret.md','https://host/a.md','javascript:alert.md','//host/a.md','/other/a.md','a\\b.md','%00.md','.hidden/note.md','a.md?download=1','a.md#heading','%invalid'])assert.equal(resolveMarkdownPath('note.md',href),null,href);
});

test('folder search reads only in-scope Markdown and reports inaccessible files as partial',async()=>{
  const {searchMarkdownFolder}=load('diary-file-search.ts');const reads=[];
  const report=await searchMarkdownFolder({path:'notes',query:'target',list:async()=>({files:[
    {path:'other/private.md',name:'private.md',isDir:false},{path:'notes/a.md',name:'a.md',isDir:false},{path:'notes/b.md',name:'b.md',isDir:false}
  ]}),read:async path=>{reads.push(path);if(path.endsWith('b.md'))throw Error('offline');return {path,content:'A target phrase',version:'v1'};}});
  assert.deepEqual(reads,['notes/a.md','notes/b.md']);assert.equal(report.results.length,1);assert.equal(report.partial,true);assert.equal(report.skipped,2);
});
test('folder search enforces file and byte bounds, cancellation, and query length',async()=>{
  const {searchMarkdownFolder}=load('diary-file-search.ts');let reads=0;
  const list=async()=>({files:Array.from({length:70},(_,i)=>({path:`${i}.md`,name:`${i}.md`,isDir:false}))});
  const read=async path=>{reads++;return {path,content:'no matching term',version:'v1'};};
  const report=await searchMarkdownFolder({path:'',query:'absent',list,read});assert.equal(reads,50);assert.equal(report.partial,true);
  await assert.rejects(searchMarkdownFolder({path:'',query:'x',list,read}),/2–200/);
  await assert.rejects(searchMarkdownFolder({path:'',query:'xx',list,read,signal:{aborted:true}}),/cancelled/);
  reads=0;const large=await searchMarkdownFolder({path:'',query:'absent',list,read:async path=>{reads++;return {path,content:'a'.repeat(512*1024),version:'v1'};}});assert.equal(large.partial,true);assert.equal(reads,9);
});

test('backlinks resolve source-relative paths and skip images and fenced code',async()=>{
 const {searchMarkdownFolder}=load('diary-file-search.ts');
 const files={'a.md':'[Real](nested/note.md)','b.md':'```md\n[Example](nested/note.md)\n```\n![Image](nested/note.md)','c.md':'`[Code](nested/note.md)`'};
 const report=await searchMarkdownFolder({path:'',query:'nested/note.md',kind:'backlinks',list:async()=>({files:Object.keys(files).map(path=>({path,name:path,isDir:false}))}),read:async path=>({path,content:files[path],version:'v1'})});
 assert.equal(report.results.length,1);assert.equal(report.results[0].path,'a.md');
});
