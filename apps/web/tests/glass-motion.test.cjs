const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
function fixture(available=true){
 const listeners={},frames=new Map();let id=0,draws=0,mutation;
 const preference={matches:false,addEventListener:(n,f)=>listeners.preference=f};
 const sources=[];const gl=new Proxy({shaderSource:(s,src)=>sources.push(src),getShaderParameter:()=>true,getProgramParameter:()=>true,drawArrays:()=>draws++},{get:(o,k)=>o[k]||(()=>({}))});
 const canvas={setAttribute(){},getContext:(kind,options)=>{canvas.options=options;return available?gl:null;},remove(){this.parent=null;},addEventListener:(n,f)=>listeners[n]=f};
 const body={prepend(n){n.parent=this;},querySelectorAll:()=>[]};
 const modal={...body,getBoundingClientRect:()=>({left:20,top:20,width:600,height:500})};
 const document={body,hidden:false,documentElement:{dataset:{theme:'dark'}},createElement:()=>canvas,querySelector:()=>document.modal||null,addEventListener:(n,f)=>listeners[n]=f};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../public/glass.js'),'utf8'),{document,matchMedia:()=>preference,innerWidth:1440,innerHeight:900,addEventListener:(n,f)=>listeners[n]=f,MutationObserver:class{constructor(f){mutation=f;}observe(){}},requestAnimationFrame:f=>{frames.set(++id,f);return id;},cancelAnimationFrame:i=>frames.delete(i),getComputedStyle:()=>({borderRadius:'16px'})});
 const tick=t=>{const work=[...frames.values()];frames.clear();work.forEach(f=>f(t));};
 return {sources,document,body,modal,canvas,frames,listeners,preference,tick,draws:()=>draws,mutate:()=>mutation([{type:'attributes',target:modal}])};
}
test('one scene moves between workspace and Settings without a second loop',()=>{
 const f=fixture();f.tick(100);assert.equal(f.canvas.parent,f.body);assert.equal(f.frames.size,1);assert.equal(f.canvas.width,900);
 f.document.modal=f.modal;f.mutate();f.tick(140);assert.equal(f.canvas.parent,f.modal);assert.equal(f.frames.size,1);
 f.document.modal=null;f.mutate();f.tick(180);assert.equal(f.canvas.parent,f.body);assert.equal(f.draws(),3);
});
test('hidden and reduced-motion states stop drawing and can resume',()=>{
 const f=fixture();f.tick(100);f.document.hidden=true;f.listeners.visibilitychange();f.tick(140);assert.equal(f.frames.size,0);assert.equal(f.canvas.parent,null);
 f.document.hidden=false;f.listeners.visibilitychange();f.tick(180);assert.equal(f.frames.size,1);
 f.preference.matches=true;f.listeners.preference();f.tick(220);assert.equal(f.frames.size,0);
 f.preference.matches=false;f.listeners.preference();f.tick(260);assert.equal(f.canvas.parent,f.body);
});
test('WebGL unavailable leaves normal interface without animation',()=>{const f=fixture(false);assert.equal(f.frames.size,0);assert.equal(f.draws(),0);});
test('light field is premultiplied, clamped and dithered so engines agree and gradients do not band',()=>{
 const f=fixture();const fragment=f.sources.find(src=>src.includes('gl_FragColor'));
 assert.equal(f.canvas.options.premultipliedAlpha,true);
 assert.match(fragment,/noise\/255\./);
 assert.match(fragment,/gl_FragColor=vec4\(clamp\(lit,0\.,strength\),strength\)/);
});
