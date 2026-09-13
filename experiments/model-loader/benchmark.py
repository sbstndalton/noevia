import json,time,urllib.request,sys,pathlib
base,model,out=sys.argv[1:4]
rows=[]
for i in range(3):
    payload={'model':model,'messages':[{'role':'user','content':'Write a practical checklist for testing a local software service. Cover startup, error handling, performance, and recovery. Use numbered items and concrete checks.'}], 'max_tokens':256,'temperature':0,'stream':True,'stream_options':{'include_usage':True},'chat_template_kwargs':{'enable_thinking':False},'cache_prompt':False}
    start=time.monotonic(); first=None; answer=''; usage={}; timings={}
    try:
        req=urllib.request.Request(base+'/chat/completions',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=240) as r:
            for line in r:
                if not line.startswith(b'data: '): continue
                raw=line[6:].strip()
                if raw==b'[DONE]':break
                d=json.loads(raw)
                if d.get('usage'):usage=d['usage']
                if d.get('timings'):timings=d['timings']
                for c in d.get('choices',[]):
                    delta=c.get('delta',{}); text=delta.get('content') or delta.get('reasoning_content') or ''
                    if text and first is None:first=time.monotonic()-start
                    answer+=text
        elapsed=time.monotonic()-start
        rows.append({'run':i+1,'ttft_s':first,'elapsed_s':elapsed,'usage':usage,'timings':timings,'output':answer})
    except Exception as e: rows.append({'run':i+1,'error':str(e),'elapsed_s':time.monotonic()-start})
    pathlib.Path(out).write_text(json.dumps(rows,indent=2))
    print(json.dumps({k:v for k,v in rows[-1].items() if k!='output'}),flush=True)
