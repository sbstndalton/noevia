#!/usr/bin/env bash
# Snapshot/restore the preset-authority named volume's journal without losing WAL records.
# Backup:  preset-authority-backup.sh backup <volume-mount>/authority.sqlite <private-destination>
# Restore: preset-authority-backup.sh restore <snapshot> <volume-mount>/authority.sqlite --services-stopped
set -euo pipefail
mode=${1:?backup or restore}; source_file=${2:?source}; destination=${3:?destination}
if [ "$mode" = restore ] && [ "${4:-}" != --services-stopped ]; then
  echo 'Stop web, loader and gate before restoring the authority journal.' >&2; exit 2
fi
[ "$mode" = backup ] || [ "$mode" = restore ] || { echo 'Expected backup or restore.' >&2; exit 2; }
python3 - "$mode" "$source_file" "$destination" <<'PY'
import os, pathlib, sqlite3, sys, tempfile
mode, source, destination = sys.argv[1:]
source = pathlib.Path(source).resolve()
destination = pathlib.Path(destination).resolve()
if source == destination:
    raise SystemExit('Source and destination must differ.')
if destination.exists() and mode == 'backup':
    raise SystemExit('Backup destination already exists.')
# mode=ro with immutable=0 includes committed WAL frames in SQLite's consistent snapshot.
reader = sqlite3.connect(source.as_uri() + '?mode=ro&immutable=0', uri=True, timeout=5)
reader.execute('PRAGMA busy_timeout=5000')
if reader.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
    raise SystemExit('Source journal failed integrity validation.')
fd, temporary = tempfile.mkstemp(prefix='.preset-authority-', dir=destination.parent)
os.close(fd)
try:
    writer = sqlite3.connect(temporary, timeout=5)
    try:
        reader.backup(writer)
        writer.commit()
    finally:
        writer.close()
        reader.close()
    os.chmod(temporary, 0o644 if mode == 'restore' else 0o600)
    with open(temporary, 'rb') as f:
        os.fsync(f.fileno())
    if mode == 'restore':
        # Only after the operator explicitly confirms web, loader and gate are stopped.
        for suffix in ('-wal', '-shm'):
            pathlib.Path(str(destination) + suffix).unlink(missing_ok=True)
    os.replace(temporary, destination)
    fd = os.open(destination.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
finally:
    pathlib.Path(temporary).unlink(missing_ok=True)
PY
