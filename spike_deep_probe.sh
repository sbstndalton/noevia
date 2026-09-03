set -e
cd /mnt/docker/appdata/diary-companion
BASE=$(grep '^WEBDAV_BASE_URL=' .env | cut -d= -f2-)
WUSER=$(grep '^WEBDAV_USERNAME=' .env | cut -d= -f2-)
WPASS=$(grep '^WEBDAV_PASSWORD=' .env | cut -d= -f2-)

echo "=== A. deep sweep: any .md files or diary-named dirs anywhere in the DAV tree ==="
curl -s -u "$WUSER:$WPASS" -X PROPFIND -H "Depth: 3" -H "Content-Type: application/xml" \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>' \
  "$BASE" > /tmp/dav-sweep.xml
grep -oE '<d:href>[^<]+</d:href>' /tmp/dav-sweep.xml | sed 's/<[^>]*>//g' | grep -iE '\.md|diary' || echo "  (no .md files or diary-named paths found in tree, depth 3)"
echo "  total paths scanned: $(grep -c '<d:href>' /tmp/dav-sweep.xml)"

echo ""
echo "=== B. Nextcloud DB (read-only): file cache for Diary paths + trashbin + recent delete activity ==="
docker exec nextcloud-aio-database sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -F" | " <<SQL
SELECT '\''oc_filecache'\'';
SELECT fileid, path, path_hash FROM oc_filecache WHERE path ILIKE '\''%diary%'\'';
SELECT '\''--- trash table ---'\'';
SELECT autoid, id, name, origpath, deleted_at FROM oc_files_trash WHERE name ILIKE '\''%diary%\'' OR origpath ILIKE '\''%diary%'\'';
SELECT '\''--- activity: delete/share/untrash events mentioning Diary (last 40) ---'\'';
SELECT activity_id, user_id, timestamp, type, object_name FROM oc_activity WHERE object_name ILIKE '\''%Diary%'\'' ORDER BY activity_id DESC LIMIT 40;
SQL' 2>&1 | head -80

echo ""
echo "=== C. sharelink / external changes check (was folder maybe renamed?) ==="
docker exec nextcloud-aio-database sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -F" | " -c "SELECT activity_id, user_id, to_timestamp(timestamp), type, object_name FROM oc_activity WHERE object_name ILIKE '\''%diary%'\'' OR object_name ILIKE '\''%2026-09%'\'' ORDER BY activity_id DESC LIMIT 25;"' 2>&1 | head -30
