const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const code=ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/components/shortcuts/shortcuts.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const ex={};vm.runInNewContext(code,{exports:ex});
const k=(key,o={})=>({key,metaKey:false,ctrlKey:false,altKey:false,shiftKey:false,...o});
test('⌘ on Apple and Ctrl elsewhere; the other modifier never triggers',()=>{
 assert.equal(ex.matchShortcut(k('k',{metaKey:true}),true),'search');
 assert.equal(ex.matchShortcut(k('k',{ctrlKey:true}),true),null);
 assert.equal(ex.matchShortcut(k('K',{ctrlKey:true}),false),'search');
 assert.equal(ex.matchShortcut(k('k',{metaKey:true}),false),null);
});
test('shift must match exactly, alt and IME composition never trigger, plain keys never trigger',()=>{
 assert.equal(ex.matchShortcut(k('O',{metaKey:true,shiftKey:true}),true),'newChat');
 assert.equal(ex.matchShortcut(k('o',{metaKey:true}),true),null);
 assert.equal(ex.matchShortcut(k('k',{metaKey:true,altKey:true}),true),null);
 assert.equal(ex.matchShortcut(k('k',{metaKey:true,isComposing:true}),true),null);
 assert.equal(ex.matchShortcut(k('k'),true),null);
 assert.equal(ex.matchShortcut(k(',',{ctrlKey:true}),false),'settings');
 assert.equal(ex.matchShortcut(k('/',{metaKey:true}),true),'help');
});
test('labels follow the platform',()=>{
 const newChat=ex.SHORTCUTS.find(s=>s.id==='newChat');
 assert.equal(ex.describe(newChat,true),'⌘⇧O');assert.equal(ex.describe(newChat,false),'Ctrl+Shift+O');
 assert.equal(ex.isApple('MacIntel'),true);assert.equal(ex.isApple('Win32'),false);
});
