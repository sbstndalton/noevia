// Actual app, synthetic API only. No model, credentials, disk corpus or live service.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {createFixture}=require('../../apps/web/qa/diary-fixture.cjs');
const base=createFixture(31289),port=31287;
const projects=[['room','A room of my own','Plans, possibilities, and a desk by the window.','work','#a75438'],['adventures','Small adventures','Places nearby. A few plans further away.','globe','#436aab'],['making','Learning by making','Notes, experiments, and the occasional wrong turn.','plant','#5a793c']].map(([id,name,goal,icon,color])=>({id,name,goal,icon,color,instructions:'',memories:[],files:[],chats:[],createdAt:Date.now()-86400000,updatedAt:Date.now(),model:'synthetic'}));
const server=http.createServer((req,res)=>{
const url=new URL(req.url,'http://localhost');const json=data=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(data))};
if(url.pathname==='/api/workspace')return json({projects,freeChats:[]});
if(url.pathname==='/study.css'){res.setHeader('Content-Type','text/css');return res.end(fs.readFileSync(path.join(__dirname,'playful.css')))}
if(url.pathname==='/api/diary/source')return json({source:'synthetic',months:[{id:'2026-09',label:'September 2026'}]});
if(url.pathname==='/api/diary/today')return json({todayLog:'## 2026-09-13\n\nI took the longer way home. The light was good, and I wasn’t trying to get somewhere faster.\n\n## 2026-09-12\n\nA good kind of quiet.',standingSections:{},memoryFiles:[]});
const proxy=http.request({hostname:'127.0.0.1',port:31289,path:req.url,method:req.method,headers:req.headers},up=>{if(url.pathname==='/'){let html='';up.setEncoding('utf8');up.on('data',c=>html+=c);up.on('end',()=>{res.writeHead(up.statusCode,{'Content-Type':'text/html'});res.end(html.replace('</head>','<link rel="stylesheet" href="/study.css"></head>').replace('<title>noevia</title>','<title>noevia — synthetic design preview</title>'))})}else{res.writeHead(up.statusCode,up.headers);up.pipe(res)}});proxy.on('error',()=>{res.writeHead(502);res.end('Synthetic fixture unavailable')});req.pipe(proxy);
});base.listen().then(()=>server.listen(port,'127.0.0.1',()=>console.log('Synthetic design preview http://localhost:'+port)));
process.on('SIGTERM',()=>server.close(()=>base.close().then(()=>process.exit())));
