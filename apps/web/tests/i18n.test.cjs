// Interface translations (#231): the catalogue core, loaded from source the same way the other
// src tests are (transpiled, run in a fresh context), with relative imports resolved to src/i18n.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const dir=path.join(__dirname,'../src/i18n');
const cache={},warnings=[];
function load(name){
  if(cache[name])return cache[name];
  const exports={};cache[name]=exports;
  const code=ts.transpileModule(fs.readFileSync(path.join(dir,name+'.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  vm.runInNewContext(code,{exports,Intl,console:{warn:(...a)=>warnings.push(a)},Promise,require:(m)=>{if(!m.startsWith('./'))throw Error('unexpected import '+m);return load(m.slice(2));}});
  return exports;
}
const core=load('core');
// Arrays built inside the vm context have another Array prototype; compare them as JSON.
const same=(a,b,m)=>assert.equal(JSON.stringify(a),JSON.stringify(b),m);
const EN=load('en-GB').EN_GB;
// The app loads non-English catalogues as chunks; node registers them directly for the checks below.
const FILES={'de-DE':'DE_DE','es-ES':'ES_ES','fr-FR':'FR_FR','it-IT':'IT_IT','nb-NO':'NB_NO','nl-NL':'NL_NL','pt-BR':'PT_BR','sv-SE':'SV_SE'};
assert.equal(Object.keys(core.CATALOGUES).join(),'en-GB,en-US','only English is bundled eagerly');
for(const [l,name] of Object.entries(FILES))core.registerCatalogue(l,load(l)[name]);
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
    assert.doesNotMatch(src,/\bfetch\(/,`${f} fetches at runtime`);
    // Dynamic imports only in loaders.ts, and only literal paths to a supported catalogue.
    const imports=[...src.matchAll(/import\(([^)]*)\)/g)].map(m=>m[1]);
    if(f!=='loaders.ts'){assert.equal(imports.length,0,`${f} imports at runtime`);continue;}
    for(const arg of imports)assert.match(arg,/^'\.\/(de-DE|es-ES|fr-FR|it-IT|nb-NO|nl-NL|pt-BR|sv-SE)'$/,`non-literal import ${arg}`);
  }
});

test('every appearance sync status useAppearance can report has a translation in Settings',()=>{
  const hook=fs.readFileSync(path.join(__dirname,'../src/useAppearance.ts'),'utf8');
  const settings=fs.readFileSync(path.join(__dirname,'../src/components/GeneralSettings.tsx'),'utf8');
  const statuses=[...new Set([...hook.matchAll(/setStatus\('([^']+)'\)/g)].map(m=>m[1]))];
  assert.ok(statuses.length>=4);
  for(const s of statuses)assert.ok(settings.includes(`'${s}': 'appearance.status.`),`untranslated appearance status: ${s}`);
});

test('the chunk loader map holds only supported non-English ids; anything else never imports',async()=>{
  const loaders=load('loaders');
  same(Object.keys(loaders.LOADERS).sort(),core.SUPPORTED.filter(l=>!l.startsWith('en-')).sort());
  let calls=0;const spy={'de-DE':()=>{calls++;return Promise.resolve({});}};
  for(const bad of ['xx-XX','../en-GB','__proto__','constructor','toString','',"de-DE'"])assert.equal(await loaders.loadCatalogue(bad,spy),false,bad);
  assert.equal(calls,0,'an unsupported id called a loader');
  assert.equal(await loaders.loadCatalogue('xx-XX'),false);
  assert.equal(await loaders.loadCatalogue('en-GB',spy),true,'English is already there');
  assert.equal(calls,0);
});

test('a chunk loads once and is cached; a failed one stays English, logs once and is not retried',async()=>{
  const loaders=load('loaders');
  const saved=core.CATALOGUES['it-IT'];delete core.CATALOGUES['it-IT'];
  let ok=0;const good={'it-IT':()=>{ok++;return Promise.resolve({'common.cancel':'Annulla'});}};
  try{
    const [a,b]=await Promise.all([loaders.loadCatalogue('it-IT',good),loaders.loadCatalogue('it-IT',good)]);
    assert.equal(a&&b,true);assert.equal(ok,1,'concurrent requests share one load');
    assert.equal(await loaders.loadCatalogue('it-IT',good),true);assert.equal(ok,1,'cached');
    assert.equal(core.translate('it-IT','common.cancel'),'Annulla');
  }finally{core.CATALOGUES['it-IT']=saved;}
  const savedSv=core.CATALOGUES['sv-SE'];delete core.CATALOGUES['sv-SE'];
  let tries=0;const bad={'sv-SE':()=>{tries++;return Promise.reject(Error('chunk 404'));}};
  try{
    warnings.length=0;
    assert.equal(await loaders.loadCatalogue('sv-SE',bad),false);
    assert.equal(await loaders.loadCatalogue('sv-SE',bad),false);
    assert.equal(tries,1,'no retry loop');assert.equal(warnings.length,1,'logged once');
    assert.equal(core.translate('sv-SE','common.save'),'Save','stays English');
  }finally{core.CATALOGUES['sv-SE']=savedSv;}
});

test('every Cowork fallback reason has a message key', () => {
  const src = fs.readFileSync(path.join(__dirname, '../src/chat-mode.ts'), 'utf8');
  const codes = src.match(/export type FallbackReason = ([^;]+);/)[1].match(/'(\w+)'/g).map((c) => c.slice(1, -1));
  assert.equal(codes.length, 4);
  for (const c of codes) assert.ok(EN[`mode.reason.${c}`], c);
});

test('key names follow the locale: Strg in German, Maj in French, Ctrl in English', () => {
  for (const [l, ctrl, shift] of [['en-GB', 'Ctrl', 'Shift'], ['de-DE', 'Strg', 'Umschalt'], ['fr-FR', 'Ctrl', 'Maj']]) {
    assert.equal(core.translate(l, 'keys.ctrl'), ctrl); assert.equal(core.translate(l, 'keys.shift'), shift);
  }
  // The German shortcut note and the key name agree.
  assert.match(core.translate('de-DE', 'keyboard.otherNote'), /Strg/);
});
