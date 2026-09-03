set -e
cd /mnt/docker/appdata/cowork
BASE=$(grep '^WEBDAV_BASE_URL=' diary-companion.env | cut -d= -f2-)
WUSER=$(grep '^WEBDAV_USERNAME=' diary-companion.env | cut -d= -f2-)
WPASS=$(grep '^WEBDAV_PASSWORD=' diary-companion.env | cut -d= -f2-)

wdav() { curl -s -u "$WUSER:$WPASS" "$@"; }

echo "=== 1. scratch folder listing (Diary-spike-test) ==="
wdav -X PROPFIND -H "Depth: 1" -H "Content-Type: application/xml" \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>' \
  "${BASE}Diary-spike-test/" | grep -oE '<d:href>[^<]+</d:href>|<d:getlastmodified>[^<]+</d:getlastmodified>' | head -12

echo ""
echo "=== 2. scratch month file (format + markers) ==="
wdav "${BASE}Diary-spike-test/2026-09.md" | head -30
echo "..."
echo "--- marker check ---"
wdav "${BASE}Diary-spike-test/2026-09.md" | grep -c 'xid:' | xargs echo "xid markers found:"
wdav "${BASE}Diary-spike-test/2026-09.md" | grep -cF '**Me:**' | xargs echo "Me blocks:"
wdav "${BASE}Diary-spike-test/2026-09.md" | grep -cF '**Claude:**' | xargs echo "Claude blocks:"

echo ""
echo "=== 3. scratch INDEX.md ==="
wdav "${BASE}Diary-spike-test/INDEX.md" | head -12

echo ""
echo "=== 4. sidecar journal state ==="
docker exec cowork-diary-companion python -c "
import os,urllib.request,json
tok=os.environ['DIARY_AUTH_TOKEN']
req=urllib.request.Request('http://127.0.0.1:8010/api/health',headers={'Authorization':'Bearer '+tok})
d=json.load(urllib.request.urlopen(req,timeout=10))
print('ok:',d['ok'],'| journal_pending:',d['journal_pending'],'| chunks:',d['retrieval']['chunks'])"

echo ""
echo "=== 5. REAL Diary/ untouched ==="
wdav -X PROPFIND -H "Depth: 1" -H "Content-Type: application/xml" \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/></d:prop></d:propfind>' \
  "${BASE}Diary/" | grep -oE '<d:href>[^<]+</d:href>|<d:getlastmodified>[^<]+</d:getlastmodified>' | head -14
echo "--- real month file spike-content check (must be 0 matches): ---"
wdav "${BASE}Diary/2026-09.md" | grep -c "Spike verification exchange" || echo "0 (clean)"
