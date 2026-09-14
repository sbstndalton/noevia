// Explicit, process-local synthetic settings. No credentials, storage or live APIs.
function createSettingsFixture() {
  const user={id:'synthetic-diary-only',username:'fixture',displayName:'Synthetic settings QA',role:'admin',diaryEnabled:true,onboarded:true,disabled:false};
  let fail = '';
  let appearance = null;
  return async (req,res,url) => {
    const json=(value,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
    if(url.pathname==='/__qa') {
      if(url.searchParams.has('fail'))fail=url.searchParams.get('fail');
      res.setHeader('Content-Type','text/html');
      res.end('<h1>Synthetic Settings controls</h1><p>Process memory only; resets on preview restart. Never contacts real services.</p><form><label>Fail next request <select name="fail"><option value="">None</option><option value="/api/profile">Profile</option><option value="/api/profile/features">Diary preference</option><option value="/api/providers">Connections</option><option value="/api/profile/appearance">Appearance</option></select></label><button>Apply fixture fault</button></form>');return true;
    }
    const paths=['/api/profile/appearance','/api/auth/session','/api/profile','/api/profile/features','/api/providers','/api/profile/app-passwords','/api/profile/sharing','/api/admin/users','/api/usage','/api/usage/rates','/api/integrations/storage'];
    if(!paths.includes(url.pathname)) {
      if(req.method!=='GET' && /^\/api\/(profile|admin|auth|providers|integrations|reasoning-settings)(\/|$)/.test(url.pathname)) {json({error:'This action is not implemented in the synthetic preview.'},501);return true;}
      return false;
    }
    await new Promise(resolve=>setTimeout(resolve,350));
    if(fail===url.pathname){fail='';json({error:'Synthetic temporary failure'},503);return true;}
    let raw='';for await(const c of req)raw+=c;
    let body;try {body=raw?JSON.parse(raw):{};}catch {json({error:'Invalid JSON'},400);return true;}
    if(url.pathname==='/api/profile/appearance') {
      if(req.method==='GET'){json(appearance);return true;}
      if(req.method==='PUT'){try{appearance=require('../../apps/web/server/appearance.cjs').validateAppearance(body);json(appearance);}catch(e){json({error:e.message},400);}return true;}
    }
    if(req.method==='GET') {
      const values={
        '/api/auth/session':{user},'/api/profile':{user,passkeys:[],sessions:[]},
        '/api/providers':{providers:[]},'/api/integrations/storage':{kind:'local',baseUrl:'',username:'',corpusRoot:''},'/api/profile/app-passwords':{appPasswords:[]},
        '/api/profile/sharing':{available:false,reason:'Synthetic preview: file sharing is not configured.',scope:'off',cleartext:false,url:'',eligible:false},
        '/api/admin/users':{users:[user]},
        '/api/usage':{allTime:{input:0,output:0,replies:0},last7:{input:0,output:0,replies:0},last30:{input:0,output:0,replies:0},activeDays:0,currentStreak:0,longestStreak:0,retentionDays:365,timeZone:'UTC',days:[],models:[]},
        '/api/usage/rates':{currency:'USD',models:{},admin:false},
      };
      if(values[url.pathname]){json(values[url.pathname]);return true;}
    }
    if(url.pathname==='/api/profile'&&req.method==='PATCH') {
      if(typeof body.displayName!=='string'||!body.displayName.trim()){json({error:'Display name required'},400);return true;}
      user.displayName=body.displayName.trim().slice(0,80);json({ok:true});return true;
    }
    if(url.pathname==='/api/profile/features'&&req.method==='PUT'&&typeof body.diaryEnabled==='boolean') {user.diaryEnabled=body.diaryEnabled;json({diaryEnabled:user.diaryEnabled});return true;}
    json({error:'This action is not implemented in the synthetic preview.'},501);return true;
  };
}
module.exports={createSettingsFixture};
