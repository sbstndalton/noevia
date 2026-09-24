// Interface translations (#231): the catalogue core, loaded from source the same way the other
// src tests are (transpiled, run in a fresh context), with relative imports resolved to src/i18n.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const dir=path.join(__dirname,'../src/i18n');
const cache={};
function load(name){
  if(cache[name])return cache[name];
  const exports={};cache[name]=exports;
  const code=ts.transpileModule(fs.readFileSync(path.join(dir,name+'.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  vm.runInNewContext(code,{exports,Intl,require:(m)=>{if(!m.startsWith('./'))throw Error('unexpected import '+m);return load(m.slice(2));}});
  return exports;
}
const core=load('core');
// Arrays built inside the vm context have another Array prototype; compare them as JSON.
const same=(a,b,m)=>assert.equal(JSON.stringify(a),JSON.stringify(b),m);
const EN=load('en-GB').EN_GB;
const NON_BASE=Object.keys(core.CATALOGUES).filter(l=>l!=='en-GB');

test('every supported account locale has a catalogue, and nothing else does',()=>{
  const server=require('../server/account-preferences.cjs');
  const locales=(server.LOCALES||[]).filter(l=>l!=='system');
  assert.ok(locales.length>0,'server LOCALES not exported');
  same([...core.SUPPORTED].sort(),[...locales].sort());
});

test('a missing key falls back to English, and an unknown one to the key itself',()=>{
  const saved=core.CATALOGUES['de-DE']['common.cancel'];
  delete core.CATALOGUES['de-DE']['common.cancel'];
  try{assert.equal(core.translate('de-DE','common.cancel'),'Cancel');}
  finally{core.CATALOGUES['de-DE']['common.cancel']=saved;}
  assert.equal(core.translate('de-DE','common.cancel'),'Abbrechen');
  assert.equal(core.translate('en-US','common.cancel'),'Cancel','en-US only overrides spellings');
  assert.equal(core.translate('en-US','sidebar.customise'),'Customize');
  assert.equal(core.translate('xx-XX','common.save'),'Save','an unknown locale is English');
  assert.equal(core.translate('de-DE','no.such.key'),'no.such.key');
  // An empty string is a missing translation, not a blank label.
  core.CATALOGUES['sv-SE']['common.save']='';
  try{assert.equal(core.translate('sv-SE','common.save'),'Save');}finally{core.CATALOGUES['sv-SE']['common.save']='Spara';}
});

test('parameters are interpolated; unknown placeholders stay visible; values are not re-parsed',()=>{
  assert.equal(core.translate('en-GB','sidebar.openNamed',{name:'Garden plan'}),'Open Garden plan');
  assert.equal(core.translate('de-DE','sidebar.openNamed',{name:'Garden plan'}),'Garden plan öffnen');
  assert.equal(core.translate('en-GB','sidebar.openNamed'),'Open {name}');
  assert.equal(core.interpolate('{a} and {b}',{a:'{b}',b:'x'}),'{b} and x');
  assert.equal(core.interpolate('{n}',{n:0}),'0');
  assert.equal(core.translate('fr-FR','sidebar.confirmDeleteChatTitle',{name:'Notes'}),'Supprimer « Notes » ?');
});

test('plurals follow the locale’s rules',()=>{
  assert.equal(core.translatePlural('en-GB','sidebar.count.chats',1),'1 chat');
  assert.equal(core.translatePlural('en-GB','sidebar.count.chats',3),'3 chats');
  assert.equal(core.translatePlural('de-DE','sidebar.count.files',1),'1 Datei');
  assert.equal(core.translatePlural('de-DE','sidebar.count.files',0),'0 Dateien');
  // French treats 0 as singular.
  assert.equal(core.translatePlural('fr-FR','sidebar.count.files',0),'0 fichier');
});

test('system locale: browser languages in order, bare languages and regions, English otherwise',()=>{
  const r=core.resolveInterfaceLocale;
  assert.equal(r('system',['de']),'de-DE');
  assert.equal(r('system',['de-AT','en']),'de-DE');
  assert.equal(r('system',['en-US']),'en-US');
  assert.equal(r('system',['en']),'en-GB');
  assert.equal(r('system',['en-AU']),'en-GB');
  assert.equal(r('system',['en_us']),'en-US');
  assert.equal(r('system',['no']),'nb-NO');
  assert.equal(r('system',['nn-NO']),'nb-NO');
  assert.equal(r('system',['pt-PT']),'pt-BR');
  assert.equal(r('system',['sv-FI']),'sv-SE');
  assert.equal(r('system',['zh-CN','ja','fr-CA']),'fr-FR','first supported language wins');
  assert.equal(r('system',['zh-CN']),'en-GB');
  assert.equal(r('system',[]),'en-GB');
  assert.equal(r('system',['', 'x']),'en-GB');
  assert.equal(r('it-IT',['de']),'it-IT','a saved choice beats the browser');
  assert.equal(r('xx-XX',['de']),'de-DE','an unknown saved value is treated as system');
  assert.equal(r(undefined,undefined),'en-GB');
});

test('catalogues: no keys outside English, matching placeholders, and coverage reported',()=>{
  const lines=[];
  for(const locale of NON_BASE){
    const c=core.coverage(locale);
    same(c.extra,[],`${locale} has keys English does not: ${c.extra.join(', ')}`);
    same(c.placeholderMismatch,[],`${locale} placeholders differ: ${c.placeholderMismatch.join(', ')}`);
    lines.push(`${locale} ${c.translated}/${c.total} (${Math.round(100*c.translated/c.total)}%)`);
    // en-US is spelling only; every real translation is complete.
    if(locale!=='en-US')same(c.missing,[],`${locale} is missing: ${c.missing.join(', ')}`);
  }
  console.log('i18n coverage: '+lines.join(' · '));
  const us=load('en-US').EN_US;
  for(const [k,v] of Object.entries(us))assert.notEqual(v,EN[k],`en-US repeats British text for ${k}`);
});

test('the completeness check really fails on an extra key and a broken placeholder',()=>{
  core.CATALOGUES['nl-NL']['sidebar.bogus']='x';
  const saved=core.CATALOGUES['nl-NL']['sidebar.openNamed'];
  core.CATALOGUES['nl-NL']['sidebar.openNamed']='{naam} openen';
  try{
    const c=core.coverage('nl-NL');
    same(c.extra,['sidebar.bogus']);
    same(c.placeholderMismatch,['sidebar.openNamed']);
  }finally{delete core.CATALOGUES['nl-NL']['sidebar.bogus'];core.CATALOGUES['nl-NL']['sidebar.openNamed']=saved;}
});

test('plural keys come in pairs, and catalogues are bundled, not fetched',()=>{
  const plural=Object.keys(EN).filter(k=>/\.(one|other)$/.test(k)).map(k=>k.replace(/\.(one|other)$/,''));
  for(const base of new Set(plural))assert.ok(EN[base+'.one']&&EN[base+'.other'],base);
  for(const f of fs.readdirSync(dir)){
    const src=fs.readFileSync(path.join(dir,f),'utf8');
    assert.doesNotMatch(src,/\bfetch\(|import\(/,`${f} loads something at runtime`);
  }
});

test('every appearance sync status useAppearance can report has a translation in Settings',()=>{
  const hook=fs.readFileSync(path.join(__dirname,'../src/useAppearance.ts'),'utf8');
  const settings=fs.readFileSync(path.join(__dirname,'../src/components/GeneralSettings.tsx'),'utf8');
  const statuses=[...new Set([...hook.matchAll(/setStatus\('([^']+)'\)/g)].map(m=>m[1]))];
  assert.ok(statuses.length>=4);
  for(const s of statuses)assert.ok(settings.includes(`'${s}': 'appearance.status.`),`untranslated appearance status: ${s}`);
});
