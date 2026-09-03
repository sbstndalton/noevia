from datetime import date

from agent.config import load_config
from agent.corpus import parse_diary
from agent.corpus_store import CorpusStore
from agent.journal import Journal
from agent.webdav import WebDAVClient

cfg = load_config()
dav = WebDAVClient(cfg.get("corpus.webdav.base_url"), cfg.get("corpus.webdav.username"),
                   cfg.get("corpus.webdav.password"), timeout_s=60)
store = CorpusStore(cfg, dav, Journal("/tmp/probe5.db"))
post, _ = store.read_month(date.today())
days = parse_diary(post)
today_secs = [d for d in days if d.date == date.today()]
subs = today_secs[0].subsections if today_secs else []
exs = [e for s in subs for e in s.exchanges]
xids = [e.xid for e in exs]

print(f"post-state: {len(post)} bytes, {post.count('**Me:**')} Me blocks (pre was 71)")
print("checks:")
print("  Me blocks == 72:", post.count("**Me:**") == 72)
print("  Claude blocks == 72:", post.count("**Claude:**") == 72)
print("  today section exists:", len(today_secs) == 1)
print("  today section header:", today_secs[0].header if today_secs else "MISSING")
print("  subsections today:", len(subs), "| first:", subs[0].header if subs else "-")
print("  xid marker present:", bool(xids))
print("  xid == journal xid 7a5c7e04...:", bool(xids) and xids[0].startswith("7a5c7e04"))
print("  user message near-verbatim:", any("teach the machine my naming" in (e.me or "") for e in exs))
print("  claude third-person prose:", all("**" not in (e.claude or "") for e in exs))
print("  all day sections intact:", [d.header for d in days])
dav.close()
