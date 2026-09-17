const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
const code=ts.transpileModule(fs.readFileSync(require('node:path').join(__dirname,'../src/model-guidance.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const exports_={};vm.runInNewContext(code,{exports:exports_});
const {memoryAssessment:assess,matchesModelUse:matches,modelChoiceLabel:label}=exports_;
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
test('a model deleted from the local catalogue reads as No model selected',()=>{
 const installed=[{name:'Kept',loaded:false},{name:'Hot',loaded:true}];
 assert.equal(label({model:'Gone'},installed),'No model selected');
 assert.equal(label({model:'Kept'},installed),'Kept');
 assert.equal(label({routing:'auto',model:'Gone'},installed),'Auto (Fast/Smart)');
 assert.equal(label({},installed),'Hot');
 assert.equal(label(null,[]),'local model');
});
test('an unknown catalogue or another provider never declares a model missing',()=>{
 assert.equal(label({model:'Gone'},null),'Gone');
 assert.equal(label({model:'claude-x',provider:'anthropic'},[]),'claude-x');
});
test('warns when a unified-memory GPU may borrow nearly all host RAM',()=>{
 const {sharedMemoryRisk:risk}=exports_;
 // DaServer 2026-09-17: 29 GiB host, GTT allowed ~27 GiB.
 const r=risk({unified:true,sharedTotalGB:27,hostTotalGB:29});
 assert.equal(r.risky,true);assert.equal(r.leftGB,2);assert.match(r.message,/29 GiB/);assert.match(r.message,/27 GiB/);
 assert.equal(risk({unified:true,sharedTotalGB:16,hostTotalGB:64}).risky,false);
 assert.equal(risk({unified:false,sharedTotalGB:27,hostTotalGB:29}).risky,false);
 for(const host of [0,null,NaN])assert.equal(risk({unified:true,sharedTotalGB:27,hostTotalGB:host}).risky,false);
});
