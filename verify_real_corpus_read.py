import json
import os
import urllib.request
from datetime import date

tok = os.environ["DIARY_AUTH_TOKEN"]
H = {"Authorization": "Bearer " + tok}

# 1. health
req = urllib.request.Request("http://127.0.0.1:8010/api/health", headers=H)
d = json.load(urllib.request.urlopen(req, timeout=15))
print("health ok:", d["ok"], "| journal_pending:", d["journal_pending"])

# 2. read the real month file through the app's own store (adapted naming)
from agent.config import load_config
from agent.corpus import parse_diary
from agent.corpus_store import CorpusStore
from agent.journal import Journal
from agent.webdav import WebDAVClient

cfg = load_config()
dav = WebDAVClient(cfg.get("corpus.webdav.base_url"), cfg.get("corpus.webdav.username"),
                   cfg.get("corpus.webdav.password"), timeout_s=60)
journal = Journal("/tmp/probe.db")  # throwaway, read-only usage
store = CorpusStore(cfg, dav, journal)
today = date.today()
print("month file resolved:", store.month_path(today))
text, etag = store.read_month(today)
print("read ok:", text is not None, "| bytes:", len(text or "") )
if text:
    days = parse_diary(text)
    print("parsed day sections:", len(days), "| day headers:", [d2.header for d2 in days][:5])
    total_ex = sum(len(s.exchanges) for day_ in days for s in day_.subsections)
    print("total parsed exchanges:", total_ex)
    print("today's section present:", any(d2.date == today for d2 in days))
dav.close()
