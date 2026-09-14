const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
const code=ts.transpileModule(fs.readFileSync(require('node:path').join(__dirname,'../src/model-guidance.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const exports_={};vm.runInNewContext(code,{exports:exports_});
const {memoryAssessment:assess,matchesModelUse:matches}=exports_;
const plan={capacityGB:'16',reserveGB:'4',kind:'gpu'};
test('memory guidance never adds system RAM to GPU or double-counts unified memory',()=>{
 assert.equal(assess(8,plan).remainingGB,4);
 for(const kind of ['gpu','unified','cpu'])assert.equal(assess(8,{...plan,kind}).remainingGB,4);
 assert.equal(assess(13,plan).state,'over');assert.equal(assess(11.5,plan).state,'tight');assert.equal(assess(8,plan).state,'room');
});
test('unknown sizes, invalid budgets and absent capacity never become recommended fit',()=>{
 for(const size of [null,undefined,0,-1,NaN,Infinity])assert.equal(assess(size,plan).state,'unknown');
 for(const capacityGB of ['', ' ', '-4','Infinity','hello','5000'])assert.equal(assess(8,{...plan,capacityGB}).state,'unknown');
 for(const reserveGB of ['', ' ', '-1','16','17','Infinity'])assert.equal(assess(8,{...plan,reserveGB}).state,'unknown');
 assert.match(assess(8,plan).detail,/needs verification/);
});
test('capability guidance uses explicit labels, not model-size or name guesses',()=>{
 assert.equal(matches([], 'vision'),false);assert.equal(matches(['vision'],'vision'),true);
 assert.equal(matches(['thinking'],'reasoning'),true);assert.equal(matches(['tool_use'],'tools'),true);
 assert.equal(matches(['embeddings'],'all'),false);assert.equal(matches(['vision'],'all'),true);
});
