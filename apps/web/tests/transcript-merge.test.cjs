const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const m={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/transcript-merge.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:m});
const u=(c)=>({role:'user',content:c}),a=(c)=>({role:'assistant',content:c});
test('a newer copy that extends the other wins without duplication',()=>{
 assert.deepEqual([...m.mergeTranscripts([u('q')],[u('q'),a('x')]).map(x=>x.content)],['q','x']);
 assert.deepEqual([...m.mergeTranscripts([u('q'),a('x')],[u('q')]).map(x=>x.content)],['q','x']);
});
test('diverged copies keep the shared start, then the other device’s turns, then ours',()=>{
 const theirs=[u('q'),a('laptop answer'),u('laptop follow-up')];
 const ours=[u('q'),a('phone answer')];
 assert.deepEqual([...m.mergeTranscripts(theirs,ours).map(x=>x.content)],['q','laptop answer','laptop follow-up','phone answer']);
});
test('identical copies merge to themselves',()=>{
 const same=[u('q'),a('x')];assert.equal(m.mergeTranscripts(same,same.map(x=>({...x}))).length,2);
});
