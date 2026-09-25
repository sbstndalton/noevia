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
// One entry per lazy-view segment: its constant suffix, the chunk that registers its English part
// (settings/index.ts etc., what the real view's chunk does), and the component(s) allowed to pull
// its strings into their own chunk.
const SEGMENT_DEFS={
  settings:{suffix:'SETTINGS',owners:/^components\/(SettingsShell|ProviderForm|connectors\/)/},
  // Diary's and Projects' child components rely on their lazy entry (DiaryView, ProjectsView)
  // having already registered the segment, rather than each importing it themselves.
  projects:{suffix:'PROJECTS',owners:/^components\/ProjectsView$/},
  diary:{suffix:'DIARY',owners:/^components\/DiaryView$/},
};
const SEGMENT_NAMES=Object.keys(SEGMENT_DEFS);
assert.equal(Object.keys(core.CATALOGUES).join(),'en-GB,en-US','only English is bundled eagerly');
for(const s of SEGMENT_NAMES)assert.equal(Object.keys(core.SEGMENTS[s]).length,0,`the ${s} segment is not loaded with the core`);
const ENSEG={};// segment => its EN_GB_<SUFFIX> object
for(const s of SEGMENT_NAMES){
  ENSEG[s]=load(`${s}/en-GB`)[`EN_GB_${SEGMENT_DEFS[s].suffix}`];
  load(`${s}/index`);// what the view's chunk does: registers the English part of that segment
}
for(const [l,name] of Object.entries(FILES)){
  core.registerCatalogue(l,load(l)[name]);
  for(const s of SEGMENT_NAMES){
    const suffix=SEGMENT_DEFS[s].suffix;
    const mod=load(`${s}/${l}`);
    if(mod[`${name}_${suffix}`])core.registerSegment(s,l,mod[`${name}_${suffix}`]);
  }
}
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
  const segTotal=SEGMENT_NAMES.reduce((n,s)=>n+Object.keys(ENSEG[s]).length,0);
  for(const locale of NON_BASE){
    for(const part of ['base',...SEGMENT_NAMES])same(core.coverage(locale,part).extra,[],`${locale} ${part} segment has keys its English segment does not`);
    const c=core.coverage(locale);
    assert.equal(c.total,Object.keys(EN).length+segTotal,'coverage spans the base and every segment');
    same(c.extra,[],`${locale} has keys English does not: ${c.extra.join(', ')}`);
    same(c.placeholderMismatch,[],`${locale} placeholders differ: ${c.placeholderMismatch.join(', ')}`);
    lines.push(`${locale} ${c.translated}/${c.total} (${Math.round(100*c.translated/c.total)}%)`);
    // en-US is spelling only; every real translation is complete.
    if(locale!=='en-US')same(c.missing,[],`${locale} is missing: ${c.missing.join(', ')}`);
  }
  console.log('i18n coverage: '+lines.join(' · '));
  const us={...load('en-US').EN_US};
  for(const s of SEGMENT_NAMES){const mod=load(`${s}/en-US`);if(mod)Object.assign(us,mod[`EN_US_${SEGMENT_DEFS[s].suffix}`]||{});}
  const englishAll={...EN,...Object.assign({},...SEGMENT_NAMES.map(s=>ENSEG[s]))};
  for(const [k,v] of Object.entries(us))assert.notEqual(v,englishAll[k],`en-US repeats British text for ${k}`);
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
  const ALL={...EN,...Object.assign({},...SEGMENT_NAMES.map(s=>ENSEG[s]))};
  const plural=Object.keys(ALL).filter(k=>/\.(one|other)$/.test(k)).map(k=>k.replace(/\.(one|other)$/,''));
  for(const base of new Set(plural))assert.ok(ALL[base+'.one']&&ALL[base+'.other'],base);
  const files=fs.readdirSync(dir).flatMap(f=>fs.statSync(path.join(dir,f)).isDirectory()?fs.readdirSync(path.join(dir,f)).map(g=>f+'/'+g):[f]);
  for(const s of SEGMENT_NAMES)assert.ok(files.includes(`${s}/de-DE.ts`));
  const LOCALE_RE='(de-DE|es-ES|fr-FR|it-IT|nb-NO|nl-NL|pt-BR|sv-SE)';
  for(const f of files){
    const src=fs.readFileSync(path.join(dir,f),'utf8');
    assert.doesNotMatch(src,/\bfetch\(/,`${f} fetches at runtime`);
    // Dynamic imports only in loaders.ts, and only literal paths to a supported catalogue.
    const imports=[...src.matchAll(/import\(([^)]*)\)/g)].map(m=>m[1]);
    if(f!=='loaders.ts'){assert.equal(imports.length,0,`${f} imports at runtime`);continue;}
    for(const arg of imports)assert.match(arg,new RegExp(`^'\\./(?:(?:${SEGMENT_NAMES.join('|')})/)?${LOCALE_RE}'$`),`non-literal import ${arg}`);
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
  same(Object.keys(loaders.PROJECTS_LOADERS).sort(),core.SUPPORTED.filter(l=>!l.startsWith('en-')).sort());
  same(Object.keys(loaders.DIARY_LOADERS).sort(),core.SUPPORTED.filter(l=>!l.startsWith('en-')).sort());
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

// Shell strings the first screen shows before any Settings/Projects/Diary code has loaded.
const SHELL_ALLOW=/^(settings\.title|capabilities\.unavailable|keyboard\.(searchShortcuts|noMatch|action\..+|group\..+))$/;
// Prefixes owned by each lazy segment, checked against the base catalogue below. account.* stays
// in the base on purpose: the account menu renders on the first screen.
const SEGMENT_PREFIX={
  settings:/^(settings|appearance|profile|capabilities|language|notifications|keyboard|style|models|connectors|data|memory|usage|security|users|providers|appPasswords)\./,
  projects:/^projects\./,
  diary:/^diary\./,
};
test('the base English catalogue holds no Settings-screen string beyond the shell allowlist',()=>{
  const settingsInBase=Object.keys(EN).filter(k=>k.startsWith('settings.'));
  same(settingsInBase,['settings.title'],'settings.* in the base catalogue');
  const stray=Object.keys(EN).filter(k=>SEGMENT_PREFIX.settings.test(k)&&!SHELL_ALLOW.test(k));
  same(stray,[],'Settings-only keys in the base catalogue');
});

test('the base English catalogue holds no Projects- or Diary-only string (ProjectView/EditProjectModal/ProjectIdentity are not lazy, so their own keys stay in the base)',()=>{
  const strayProjects=Object.keys(EN).filter(k=>SEGMENT_PREFIX.projects.test(k)&&Object.prototype.hasOwnProperty.call(ENSEG.projects,k));
  same(strayProjects,[],'a projects.* key exists in both the base and the projects segment');
  const strayDiary=Object.keys(EN).filter(k=>SEGMENT_PREFIX.diary.test(k)&&Object.prototype.hasOwnProperty.call(ENSEG.diary,k));
  same(strayDiary,[],'a diary.* key exists in both the base and the diary segment');
  // diary.markdown.* used by MarkdownPreview (shared with the eager ChatView) stays in the base;
  // everything else diary.* that IS lazy-only lives in the diary segment, not the base.
  const diaryInBase=Object.keys(EN).filter(k=>SEGMENT_PREFIX.diary.test(k));
  assert.ok(diaryInBase.every(k=>k.startsWith('diary.markdown.')),`unexpected diary.* key in the base: ${diaryInBase.filter(k=>!k.startsWith('diary.markdown.')).join(', ')}`);
});

test('no key is defined in more than one segment, and the base catalogue module never imports a segment at runtime',()=>{
  for(const s of SEGMENT_NAMES)same(Object.keys(ENSEG[s]).filter(k=>k in EN),[],`${s} segment repeats a base key`);
  for(let i=0;i<SEGMENT_NAMES.length;i++)for(let j=i+1;j<SEGMENT_NAMES.length;j++){
    const [a,b]=[SEGMENT_NAMES[i],SEGMENT_NAMES[j]];
    same(Object.keys(ENSEG[a]).filter(k=>k in ENSEG[b]),[],`${a} and ${b} both define`);
  }
  const coreSrc=fs.readFileSync(path.join(dir,'core.ts'),'utf8');
  for(const s of SEGMENT_NAMES)assert.doesNotMatch(coreSrc,new RegExp(`^import \\{[^}]*\\} from '\\./${s}`,'m'),`core imports the ${s} segment's strings at runtime`);
  // Only each segment's own lazy view(s) register its English part.
  for(const s of SEGMENT_NAMES){
    const users=[];(function walk(d){for(const f of fs.readdirSync(d)){const p=path.join(d,f);if(fs.statSync(p).isDirectory()){if(f!=='i18n')walk(p);}else if(/\.tsx?$/.test(f)&&new RegExp(`i18n/${s}['"/]`).test(fs.readFileSync(p,'utf8')))users.push(path.relative(path.join(__dirname,'../src'),p).replace(/\.tsx?$/,'').replace(/\\/g,'/'));}})(path.join(__dirname,'../src'));
    for(const u of users)assert.match(u,SEGMENT_DEFS[s].owners,`${u} pulls the ${s} strings into its chunk`);
  }
});

// Generic version of the Settings-specific lifecycle test below, run once per lazy segment with a
// representative key from each (settings.backToApp / projects.title / diary.title).
const REP_KEY={settings:'settings.backToApp',projects:'projects.title',diary:'diary.title'};
for(const s of SEGMENT_NAMES){
  test(`${s} keys: English until the segment arrives, key by key, and the key itself if unregistered`,async()=>{
    const key=REP_KEY[s];
    assert.equal(core.translate('de-DE',key),core.SEGMENTS[s]['de-DE'][key]);
    const savedDe=core.SEGMENTS[s]['de-DE'];delete core.SEGMENTS[s]['de-DE'];
    try{
      assert.equal(core.translate('de-DE',key),ENSEG[s][key],'absent segment falls back to English');
      assert.equal(core.translate('de-DE','common.cancel'),'Abbrechen','the base still translates');
    }finally{core.SEGMENTS[s]['de-DE']=savedDe;}
    const savedEn=core.SEGMENTS[s]['en-GB'];delete core.SEGMENTS[s]['en-GB'];
    try{
      assert.ok(!core.activeSegments().includes(s));
      assert.equal(core.translate('en-GB',key),key,'without the view code an unknown key renders as the key');
    }finally{core.SEGMENTS[s]['en-GB']=savedEn;}
    core.registerSegment(s,'xx-XX',{});assert.ok(!('xx-XX' in core.SEGMENTS[s]));
    // A failed segment chunk logs once, is not retried, and leaves the base catalogue alone.
    const loaders=load('loaders');
    const savedPt=core.SEGMENTS[s]['pt-BR'];delete core.SEGMENTS[s]['pt-BR'];
    let tries=0;const bad={'pt-BR':()=>{tries++;return Promise.reject(Error('chunk 404'));}};
    try{
      warnings.length=0;
      assert.equal(loaders.catalogueSettled('pt-BR'),false);
      assert.equal(await loaders.loadSegment(s,'pt-BR',bad),false);
      assert.equal(await loaders.loadSegment(s,'pt-BR',bad),false);
      assert.equal(tries,1);assert.equal(warnings.length,1);
      assert.equal(loaders.catalogueSettled('pt-BR'),true,'a failed segment does not keep useT waiting');
      assert.equal(core.translate('pt-BR',key),ENSEG[s][key]);
      assert.equal(core.translate('pt-BR','common.cancel'),core.CATALOGUES['pt-BR']['common.cancel']);
    }finally{core.SEGMENTS[s]['pt-BR']=savedPt;}
    let ok=0;const good={'nb-NO':()=>{ok++;return Promise.resolve({[key]:'Test-NB'});}};
    const savedNb=core.SEGMENTS[s]['nb-NO'];delete core.SEGMENTS[s]['nb-NO'];
    try{
      const [a,b]=await Promise.all([loaders.loadSegment(s,'nb-NO',good),loaders.loadSegment(s,'nb-NO',good)]);
      assert.equal(a&&b,true);assert.equal(ok,1);assert.equal(core.translate('nb-NO',key),'Test-NB');
    }finally{core.SEGMENTS[s]['nb-NO']=savedNb;}
  });
}

test('Settings keys: partial segment falls back per key, and shell keys never depend on the segment',()=>{
  const savedDe=core.SEGMENTS.settings['de-DE'];
  try{
    core.registerSegment('settings','de-DE',{'settings.search':'Einstellungen durchsuchen'});
    assert.equal(core.translate('de-DE','settings.backToApp'),'Back to app','a partial segment falls back per key');
    assert.equal(core.translate('de-DE','settings.search'),'Einstellungen durchsuchen');
  }finally{core.SEGMENTS.settings['de-DE']=savedDe;}
  assert.equal(core.translate('fr-FR','settings.title'),core.CATALOGUES['fr-FR']['settings.title'],'shell keys never depend on the segment');
});

test('Settings search matches English keywords as well as the translated ones',()=>{
  const shell=fs.readFileSync(path.join(__dirname,'../src/components/SettingsShell.tsx'),'utf8');
  assert.match(shell,/\['connectors', 'Connected apps', '[^']*\bplugins\b[^']*'\]/,'English connector keywords include plugins');
  // The haystack joins the English keywords, the translated ones and the English label.
  assert.match(shell,/\[keywords, ownKeywords\.startsWith\('settings\.'\) \? '' : ownKeywords, own === label \? '' : label\.toLowerCase\(\)\]/);
  assert.doesNotMatch(core.translate('de-DE','settings.keywords.connectors'),/^settings\./);
});
