set -e
cd /mnt/docker/appdata/diary-companion
BASE=$(grep '^WEBDAV_BASE_URL=' .env | cut -d= -f2-)
WUSER=$(grep '^WEBDAV_USERNAME=' .env | cut -d= -f2-)
WPASS=$(grep '^WEBDAV_PASSWORD=' .env | cut -d= -f2-)

TRASH=$(echo "$BASE" | sed 's#/remote.php/dav/files/[^/]*/#/remote.php/dav/trashbin/#')
echo "trash endpoint root: ${TRASH}trash/"

echo "--- trashbin listing (names + dates only) ---"
curl -s -u "$WUSER:$WPASS" -X PROPFIND -H "Depth: 1" -H "Content-Type: application/xml" \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:trashbin:original-location xmlns:d="DAV:"/><d:trashbin:deletion-time xmlns:d="DAV:"/></d:prop></d:propfind>' \
  "${TRASH}trash/" | python3 -c "
import sys, re
xml = sys.stdin.read()
names = re.findall(r'<d:displayname>([^<]*)</d:displayname>', xml)
locs  = re.findall(r'<d:trashbin:original-location[^>]*>([^<]*)</d:trashbin:original-location>', xml)
times = re.findall(r'<d:trashbin:deletion-time[^>]*>([^<]*)</d:trashbin:deletion-time>', xml)
import datetime
for n, l, t in zip(names, locs + ['?']*(len(names)-len(locs)), times + ['?']*(len(names)-len(times))):
    try:
        ts = datetime.datetime.fromtimestamp(int(t), datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    except Exception:
        ts = t
    print(f'  {n!r}  original-location={l!r}  deleted={ts}')
if not names:
    print('  (trashbin empty or listing failed)')
"
