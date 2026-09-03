import json, os, urllib.request

body = json.dumps({
    "model": "diary",
    "messages": [
        {"role": "user",
         "content": "Spike verification exchange: what did we set up on the server today, "
                    "and why does the diary pipeline journal every exchange before writing to WebDAV?"}
    ],
    "max_tokens": 400,
}).encode()
req = urllib.request.Request(
    "http://localhost:4000/v1/chat/completions", data=body,
    headers={"Authorization": "Bearer " + os.environ["LITELLM_MASTER_KEY"],
             "Content-Type": "application/json"})
r = json.load(urllib.request.urlopen(req, timeout=300))
print("HTTP OK - model reported:", r.get("model"))
print("reply head:", r["choices"][0]["message"]["content"][:220].strip())
