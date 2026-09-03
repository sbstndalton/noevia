import os
import urllib.request
from datetime import date

from agent.config import load_config
from agent.corpus_store import CorpusStore
from agent.journal import Journal
from agent.webdav import WebDAVClient

cfg = load_config()
dav = WebDAVClient(cfg.get("corpus.webdav.base_url"), cfg.get("corpus.webdav.username"),
                   cfg.get("corpus.webdav.password"), timeout_s=60)
store = CorpusStore(cfg, dav, Journal("/tmp/probe3.db"))
pre, _ = store.read_month(date.today())
with open("/tmp/pre.md", "w") as f:
    f.write(pre)
print(f"pre-state saved: {len(pre)} bytes, {pre.count('**Me:**')} Me blocks")
dav.close()
