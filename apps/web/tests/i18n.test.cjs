// Interface translations (#231): the catalogue core, loaded from source the same way the other
// src tests are (transpiled, run in a fresh context), with relative imports resolved to src/i18n.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const dir=path.join(__dirname,'../src/i18n');
const cache={},warnings=[];
// name is relative to src/i18n ('core', 'settings/de-DE'); imports resolve from the importing file.
function load(name){
  name=path.posix.normalize(name);
  if(cache[name])return cache[name];
  const exports={};cache[name]=exports;
  const code=ts.transpileModule(fs.readFileSync(path.join(dir,name+'.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const here=path.posix.dirname(name);
  vm.runInNewContext(code,{exports,Intl,console:{warn:(...a)=>warnings.push(a)},Promise,require:(m)=>{if(!/^\.\.?\//.test(m))throw Error('unexpected import '+m);const target=path.posix.join(here,m);if(target.startsWith('..'))throw Error('import outside src/i18n '+m);return load(target);}});
  return exports;
}
const core=load('core');
// Arrays built inside the vm context have another Array prototype; compare them as JSON.
const same=(a,b,m)=>assert.equal(JSON.stringify(a),JSON.stringify(b),m);
const EN=load('en-GB').EN_GB;
// The app loads non-English catalogues as chunks; node registers them directly for the checks below.
const FILES={'de-DE':'DE_DE','es-ES':'ES_ES','fr-FR':'FR_FR','it-IT':'IT_IT','nb-NO':'NB_NO','nl-NL':'NL_NL','pt-BR':'PT_BR','sv-SE':'SV_SE'};
assert.equal(Object.keys(core.CATALOGUES).join(),'en-GB,en-US','only English is bundled eagerly');
assert.equal(Object.keys(core.SEGMENTS.settings).length,0,'the Settings segment is not loaded with the core');
const ENS=load('settings/en-GB').EN_GB_SETTINGS;
load('settings/index');// what the Settings chunk does: registers the English Settings segment
for(const [l,name] of Object.entries(FILES)){core.registerCatalogue(l,load(l)[name]);core.registerSegment('settings',l,load('settings/'+l)[name+'_SETTINGS']);}
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
    for(const part of ['base','settings'])same(core.coverage(locale,part).extra,[],`${locale} ${part} segment has keys its English segment does not`);
    const c=core.coverage(locale);
    assert.equal(c.total,Object.keys(EN).length+Object.keys(ENS).length,'coverage spans both segments');
    same(c.extra,[],`${locale} has keys English does not: ${c.extra.join(', ')}`);
    same(c.placeholderMismatch,[],`${locale} placeholders differ: ${c.placeholderMismatch.join(', ')}`);
    lines.push(`${locale} ${c.translated}/${c.total} (${Math.round(100*c.translated/c.total)}%)`);
    // en-US is spelling only; every real translation is complete.
    if(locale!=='en-US')same(c.missing,[],`${locale} is missing: ${c.missing.join(', ')}`);
  }
  console.log('i18n coverage: '+lines.join(' · '));
  const us={...load('en-US').EN_US,...load('settings/en-US').EN_US_SETTINGS};
  for(const [k,v] of Object.entries(us))assert.notEqual(v,EN[k]??ENS[k],`en-US repeats British text for ${k}`);
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
  const ALL={...EN,...ENS};
  const plural=Object.keys(ALL).filter(k=>/\.(one|other)$/.test(k)).map(k=>k.replace(/\.(one|other)$/,''));
  for(const base of new Set(plural))assert.ok(ALL[base+'.one']&&ALL[base+'.other'],base);
  const files=fs.readdirSync(dir).flatMap(f=>fs.statSync(path.join(dir,f)).isDirectory()?fs.readdirSync(path.join(dir,f)).map(g=>f+'/'+g):[f]);
  assert.ok(files.includes('settings/de-DE.ts'));
  for(const f of files){
    const src=fs.readFileSync(path.join(dir,f),'utf8');
    assert.doesNotMatch(src,/\bfetch\(/,`${f} fetches at runtime`);
    // Dynamic imports only in loaders.ts, and only literal paths to a supported catalogue.
    const imports=[...src.matchAll(/import\(([^)]*)\)/g)].map(m=>m[1]);
    if(f!=='loaders.ts'){assert.equal(imports.length,0,`${f} imports at runtime`);continue;}
    for(const arg of imports)assert.match(arg,/^'\.\/(settings\/)?(de-DE|es-ES|fr-FR|it-IT|nb-NO|nl-NL|pt-BR|sv-SE)'$/,`non-literal import ${arg}`);
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
  same(Object.keys(loaders.SETTINGS_LOADERS).sort(),core.SUPPORTED.filter(l=>!l.startsWith('en-')).sort());
  for(const bad of ['xx-XX','../en-GB','__proto__','constructor','']){assert.equal(await loaders.loadSegment('settings',bad,{}),false,bad);}
  assert.equal(await loaders.loadSegment('__proto__','de-DE'),false,'an unknown segment loads nothing');
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

// Shell strings the first screen shows before any Settings code has loaded.
const SHELL_ALLOW=/^(settings\.title|capabilities\.unavailable|keyboard\.(searchShortcuts|noMatch|action\..+|group\..+))$/;
test('the base English catalogue holds no Settings-screen string beyond the shell allowlist',()=>{
  const settingsInBase=Object.keys(EN).filter(k=>k.startsWith('settings.'));
  same(settingsInBase,['settings.title'],'settings.* in the base catalogue');
  const stray=Object.keys(EN).filter(k=>/^(settings|appearance|profile|capabilities|language|notifications|keyboard|style|models|connectors|data|memory|usage|security|users|providers|appPasswords)\./.test(k)&&!SHELL_ALLOW.test(k));
  same(stray,[],'Settings-only keys in the base catalogue');
  // No key is defined in both segments, and the base catalogue module never imports the segment.
  same(Object.keys(ENS).filter(k=>k in EN),[]);
  assert.doesNotMatch(fs.readFileSync(path.join(dir,'core.ts'),'utf8'),/^import \{[^}]*\} from '\.\/settings/m,'core imports Settings strings at runtime');
  // Only the Settings and Customise code registers the English segment.
  const users=[];(function walk(d){for(const f of fs.readdirSync(d)){const p=path.join(d,f);if(fs.statSync(p).isDirectory()){if(f!=='i18n')walk(p);}else if(/\.tsx?$/.test(f)&&/i18n\/settings['\/]/.test(fs.readFileSync(p,'utf8')))users.push(path.relative(path.join(__dirname,'../src'),p));}})(path.join(__dirname,'../src'));
  for(const u of users)assert.match(u,/^components\/(SettingsShell|ProviderForm|connectors\/)/,`${u} pulls the Settings strings into its chunk`);
});

test('Settings keys: English until the segment arrives, key by key, and the key itself if unregistered',async()=>{
  assert.equal(core.translate('de-DE','settings.backToApp'),'Zurück zur App');
  const savedDe=core.SEGMENTS.settings['de-DE'];delete core.SEGMENTS.settings['de-DE'];
  try{
    assert.equal(core.translate('de-DE','settings.backToApp'),'Back to app','absent segment falls back to English');
    assert.equal(core.translate('de-DE','common.cancel'),'Abbrechen','the base still translates');
    core.registerSegment('settings','de-DE',{'settings.search':'Einstellungen durchsuchen'});
    assert.equal(core.translate('de-DE','settings.backToApp'),'Back to app','a partial segment falls back per key');
    assert.equal(core.translate('de-DE','settings.search'),'Einstellungen durchsuchen');
  }finally{core.SEGMENTS.settings['de-DE']=savedDe;}
  const savedEn=core.SEGMENTS.settings['en-GB'];delete core.SEGMENTS.settings['en-GB'];
  try{
    same(core.activeSegments(),[]);
    assert.equal(core.translate('fr-FR','settings.title'),core.CATALOGUES['fr-FR']['settings.title'],'shell keys never depend on the segment');
    assert.equal(core.translate('en-GB','settings.backToApp'),'settings.backToApp','without the Settings code an unknown key renders as the key');
  }finally{core.SEGMENTS.settings['en-GB']=savedEn;}
  core.registerSegment('settings','xx-XX',{});assert.ok(!('xx-XX' in core.SEGMENTS.settings));
  // A failed segment chunk logs once, is not retried, and leaves the base catalogue alone.
  const loaders=load('loaders');
  const savedPt=core.SEGMENTS.settings['pt-BR'];delete core.SEGMENTS.settings['pt-BR'];
  let tries=0;const bad={'pt-BR':()=>{tries++;return Promise.reject(Error('chunk 404'));}};
  try{
    warnings.length=0;
    assert.equal(loaders.catalogueSettled('pt-BR'),false);
    assert.equal(await loaders.loadSegment('settings','pt-BR',bad),false);
    assert.equal(await loaders.loadSegment('settings','pt-BR',bad),false);
    assert.equal(tries,1);assert.equal(warnings.length,1);
    assert.equal(loaders.catalogueSettled('pt-BR'),true,'a failed segment does not keep useT waiting');
    assert.equal(core.translate('pt-BR','settings.backToApp'),'Back to app');
    assert.equal(core.translate('pt-BR','common.cancel'),core.CATALOGUES['pt-BR']['common.cancel']);
  }finally{core.SEGMENTS.settings['pt-BR']=savedPt;}
  let ok=0;const good={'nb-NO':()=>{ok++;return Promise.resolve({'settings.search':'Søk'});}};
  const savedNb=core.SEGMENTS.settings['nb-NO'];delete core.SEGMENTS.settings['nb-NO'];
  try{
    const [a,b]=await Promise.all([loaders.loadSegment('settings','nb-NO',good),loaders.loadSegment('settings','nb-NO',good)]);
    assert.equal(a&&b,true);assert.equal(ok,1);assert.equal(core.translate('nb-NO','settings.search'),'Søk');
  }finally{core.SEGMENTS.settings['nb-NO']=savedNb;}
});

test('Settings search matches English keywords as well as the translated ones',()=>{
  const shell=fs.readFileSync(path.join(__dirname,'../src/components/SettingsShell.tsx'),'utf8');
  assert.match(shell,/\['connectors', 'Connected apps', '[^']*\bplugins\b[^']*'\]/,'English connector keywords include plugins');
  // The haystack joins the English keywords, the translated ones and the English label.
  assert.match(shell,/\[keywords, ownKeywords\.startsWith\('settings\.'\) \? '' : ownKeywords, own === label \? '' : label\.toLowerCase\(\)\]/);
  assert.doesNotMatch(core.translate('de-DE','settings.keywords.connectors'),/^settings\./);
});
