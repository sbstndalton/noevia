"""Reproduce the 412: copy the real month file to a probe path with the same
space/encoding shape, then run GET -> If-Match PUT cycles and print status codes."""
from agent.config import load_config
from agent.webdav import WebDAVClient
from datetime import date
from urllib.parse import quote

cfg = load_config()
dav = WebDAVClient(cfg.get("corpus.webdav.base_url"), cfg.get("corpus.webdav.username"),
                   cfg.get("corpus.webdav.password"), timeout_s=60)

real_path = "Documents/Important Documents/Diary/Diary - September 2026.md"
probe_path = "Diary-spike-test/etag probe.md"

text, etag = dav.get_text(real_path)
print("GET real file: bytes:", len(text or ""), "| raw etag repr:", repr(etag))

# copy bytes to probe path
ok, new_etag, status = dav.put(probe_path, (text or "").encode("utf-8"), if_match=None)
print("create probe copy:", ok, "status:", status, "etag:", repr(new_etag))

# cycle 1: GET probe -> If-Match PUT identical content
t2, e2 = dav.get_text(probe_path)
print("GET probe etag:", repr(e2))
ok, e3, st = dav.put(probe_path, t2.encode("utf-8"), if_match=e2)
print("If-Match PUT (same content):", ok, "status:", st, "new etag:", repr(e3))

# cycle 2: If-Match with a STALE etag -> expect 412
ok, e4, st = dav.put(probe_path, t2.encode("utf-8"), if_match='"stale-etag"')
print("If-Match PUT (stale etag):", ok, "status:", st)

# cycle 3: the REAL file — GET then If-Match PUT of IDENTICAL bytes.
# Net effect on content: none (same bytes), only a version bump if it succeeds.
t_real, et_real = dav.get_text(real_path)
print("GET real again etag:", repr(et_real))
ok, e_new, st = dav.put(real_path, t_real.encode("utf-8"), if_match=et_real)
print("If-Match PUT real (identical bytes):", ok, "status:", st)

dav.close()
