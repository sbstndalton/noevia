const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const code=ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/components/notifications/notify.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
function load({permission='granted',hidden=true,stored=null}={}){
 const made=[];const store=new Map(stored?[[ 'noevia:notify',stored]]:[]);
 class N{constructor(t,o){made.push({t,o});}static get permission(){return permission;}close(){}}
 const window={Notification:N,focus(){}};
 const ex={};vm.runInNewContext(code,{exports:ex,window,Notification:N,document:{get visibilityState(){return hidden?'hidden':'visible';}},localStorage:{getItem:k=>store.get(k)??null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)}});
 return {ex,made};
}
test('notifies only when opted in, permitted and the page is hidden',()=>{
 const {ex}=load();
 assert.equal(ex.shouldNotify({enabled:true,permission:'granted',hidden:true}),true);
 for(const env of [{enabled:false,permission:'granted',hidden:true},{enabled:true,permission:'default',hidden:true},{enabled:true,permission:'denied',hidden:true},{enabled:true,permission:'granted',hidden:false}])assert.equal(ex.shouldNotify(env),false,JSON.stringify(env));
});
test('notifyIfAway respects the stored choice and visibility',()=>{
 let r=load({stored:'1'});r.ex.notifyIfAway('Reply ready','Battery notes','c-1');assert.equal(r.made.length,1);assert.equal(r.made[0].o.tag,'c-1');
 r=load({stored:null});r.ex.notifyIfAway('Reply ready','x','c-1');assert.equal(r.made.length,0);
 r=load({stored:'1',hidden:false});r.ex.notifyIfAway('Reply ready','x','c-1');assert.equal(r.made.length,0);
 r=load();r.ex.setNotificationsEnabled(true);assert.equal(r.ex.notificationsEnabled(),true);r.ex.setNotificationsEnabled(false);assert.equal(r.ex.notificationsEnabled(),false);
});
