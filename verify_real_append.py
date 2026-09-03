import json
import os
import urllib.request
from datetime import date

tok = os.environ["DIARY_AUTH_TOKEN"]
H = {"Authorization": "Bearer " + tok}

from agent.config import load_config
from agent.corpus import parse_diary
from agent.corpus_store import CorpusStore
from agent.journal import Journal
from agent.webdav import WebDAVClient

cfg = load_config()
dav = WebDAVClient(cfg.get("corpus.webdav.base_url"), cfg.get("corpus.webdav.username"),
                   cfg.get("corpus.webdav.password"), timeout_s=60)
store = CorpusStore(cfg, dav, Journal("/tmp/probe4.db"))
post, _ = store.read_month(date.today())
pre = open("/tmp/pre.md").read()

pre_count = pre.count("**Me:**")
post_count = post.count("**Me:**")
days = parse_diary(post)
today_secs = [d for d in days if d.date == date.today()]

print(f"post-state: {len(post)} bytes (pre {len(pre)}), {post_count} Me blocks (pre {pre_count})")
print("checks:")
print("  prior Me blocks intact (n+1):", post_count == pre_count + 1)
print("  prior content preserved verbatim:", pre.rstrip() in post)
print("  new today section exists:", len(today_secs) == 1)
print("  section header:", today_secs[0].header if today_secs else "MISSING")
subs = today_secs[0].subsections if today_secs else []
print("  subsection count:", len(subs), "| first:", subs[0].header if subs else "-")
xids = [e.xid for s in subs for e in s.exchanges if e.xid]
print("  xid marker present in new exchange:", bool(xids))
print("  all existing day sections still parse:", [d.header for d in days])
dav.close()
