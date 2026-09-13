// Actual app, synthetic API only. No model, credentials, disk corpus or live service.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {createFixture}=require('../../apps/web/qa/diary-fixture.cjs');
const base=createFixture(31289),port=31287;
const now=Date.now();
const projects=[
 ['infrastructure','Server infrastructure','Deployment notes, backup verification and service configuration.','terminal',4,2],
 ['research','Model evaluation','Context limits, inference measurements and backend comparisons.','chart',3,5],
 ['interface','Interface design','Navigation references, screen studies and interaction decisions.','pencil',2,24],
 ['diary-system','Diary integration','Storage architecture, recovery behavior and client access.','book',2,48],
 ['documents','Document processing','Extraction quality, source handling and OCR test cases.','folder',3,72],
 ['planning','Release planning','Scope, validation results and the next deployment.','work',1,96],
].map(([id,name,goal,icon,count,hours],i)=>({id,name,goal,icon,color:'default',instructions:'Synthetic design-preview workspace.',memories:[],files:Array.from({length:count},(_,n)=>({name:['Notes.md','Test results.md','Reference.md','Decisions.md'][n],content:'Synthetic preview document.'})),chats:[{id:id+'-review',title:['Backup verification','Context allocation results','Navigation review','Storage migration plan','OCR comparison','Deployment checklist'][i],projectId:id,updatedAt:now-hours*3600000}],createdAt:now-86400000*14,updatedAt:now-hours*3600000,model:'synthetic'}));
const server=http.createServer((req,res)=>{
const url=new URL(req.url,'http://localhost');const json=data=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(data))};
if(url.pathname==='/api/workspace')return json({projects,freeChats:[]});
if(url.pathname==='/study.css'){res.setHeader('Content-Type','text/css');return res.end(fs.readFileSync(path.join(__dirname,'playful.css')))}
if(url.pathname==='/api/diary/source')return json({source:'synthetic',months:[{id:'2026-09',label:'September 2026'}]});
if(url.pathname==='/api/diary/today')return json({todayLog:'## 2026-09-13\n\nReviewed the deployment plan this morning. The restore test is complete, but I want to check the client workflow before changing storage. It helped to separate what is verified from what still needs a decision.\n\n## 2026-09-12\n\nSpent the afternoon testing the interface. The layout is useful; the presentation still needs work.',standingSections:{},memoryFiles:[]});
const proxy=http.request({hostname:'127.0.0.1',port:31289,path:req.url,method:req.method,headers:req.headers},up=>{if(url.pathname==='/'){let html='';up.setEncoding('utf8');up.on('data',c=>html+=c);up.on('end',()=>{res.writeHead(up.statusCode,{'Content-Type':'text/html'});res.end(html.replace('</head>','<link rel="stylesheet" href="/study.css"></head>').replace('<title>noevia</title>','<title>noevia — synthetic design preview</title>'))})}else{res.writeHead(up.statusCode,up.headers);up.pipe(res)}});proxy.on('error',()=>{res.writeHead(502);res.end('Synthetic fixture unavailable')});req.pipe(proxy);
});base.listen().then(()=>server.listen(port,'127.0.0.1',()=>console.log('Synthetic design preview http://localhost:'+port)));
process.on('SIGTERM',()=>server.close(()=>base.close().then(()=>process.exit())));
