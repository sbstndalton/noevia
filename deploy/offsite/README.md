# Off-site backups to Google Drive

noevia already backs itself up every night — encrypted — into
`/mnt/user/noevia-backups/offsite` on DaServer. The script here copies that folder to your
Google Drive at 02:45 each night, so that a dead server does not take everything with it.

**Google never sees anything readable.** Every file is sealed with AES-256-GCM before it leaves
noevia, and the file names are random hashes. On Drive you will see a folder called
`noevia-offsite` full of meaningless names. That is correct.

**noevia never holds your Google password or token.** Only rclone on the server does, and it is
limited to `drive.file`: it can see the files it created itself and nothing else in your Drive.

Status: **live since 2026-09-18.** The first copy put all 124 objects on Drive and `rclone check`
found 0 differences. Settings → Off-site backups shows the mirror's state.

---

## 1. Keep a copy of the backup key somewhere safe — do this first

The backups are encrypted with a key that lives on the server. **If the server dies and you do not
have a copy of that key, the backups on Google Drive are unreadable noise — to you as much as to
anyone.** So put a copy somewhere that is not the server: a password manager is ideal.

On your Mac:

```bash
ssh daserver cat /mnt/docker/appdata/cowork/config/offsite-backup.key
```

Copy the 64-character line it prints into your password manager as "noevia off-site backup key".
Then clear your terminal. Don't email it, don't put it in Google Drive next to the backups, and
don't put it in a note that syncs to the same account.

## 2. Connect Google Drive (once)

Done on 2026-09-18. To redo it (a new Google account, or a revoked token), run this **on your
Mac**, in a terminal that is *not* an SSH tunnel to the server — an open `ssh -L 53682:…` holds
the very port Google sends you back to, and the sign-in then fails with "No code returned":

```bash
brew install rclone
```

```bash
F=$(mktemp); rclone authorize "drive" "eyJzY29wZSI6ImRyaXZlLmZpbGUifQ" >"$F"; TOKEN=$(python3 -c "import sys,json,base64;t=open(sys.argv[1]).read();b=t.split('--->')[-1].split('<---')[0].strip();d=None if b.startswith('{') else json.loads(base64.urlsafe_b64decode(b+'='*(-len(b)%4)));tok=b if d is None else d.get('token',d);tok=tok if isinstance(tok,str) else json.dumps(tok);json.loads(tok)['access_token'];print(tok)" "$F" 2>/dev/null); if [ -n "$TOKEN" ]; then ssh daserver "export RCLONE_CONFIG=/boot/config/rclone/rclone.conf; rclone config update gdrive token '$TOKEN' config_refresh_token=false --non-interactive >/dev/null && bash /mnt/docker/appdata/cowork/tools/offsite/rclone-sync.sh"; else echo "Could not read the token."; fi; rm -f "$F"; unset TOKEN F
```

Your browser opens; sign in and click Allow. The token goes straight from your Mac to the
server's rclone config — it is never shown on screen or saved in shell history — and the first copy
runs. (The server needs a `gdrive` remote to update; create an empty one first with
`RCLONE_CONFIG=/boot/config/rclone/rclone.conf rclone config create gdrive drive scope=drive.file --non-interactive`.)

Two details that cost time the first time: the scope argument is base64 **without** `=` padding
(rclone rejects it otherwise), and `rclone authorize` hands the token back base64-wrapped rather
than as plain JSON, which the one-liner above unwraps.

## 3. Check it works

Still on the server:

```bash
bash /mnt/docker/appdata/cowork/tools/offsite/rclone-sync.sh
```

It should end with `OK mirrored N snapshots to gdrive:noevia-offsite`, and a `noevia-offsite`
folder should appear in your Google Drive. From then on it runs by itself every night. Type `exit`
to close the tunnel.

What it said, every night, is kept in `/mnt/user/noevia-backups/offsite-sync.log`.

---

## What protects the backup from the mirror itself

A mirror is the one tool that can destroy a backup: if it faithfully copies an empty folder, it
deletes everything on the other side. So the script
([`rclone-sync.sh`](rclone-sync.sh), tested in
[`deploy/tests/test_rclone_sync.py`](../tests/test_rclone_sync.py)):

- **refuses to run** if the local folder does not look like a healthy backup (no `config`, or no
  snapshot) — a wiped or unmounted disk never wipes Google Drive;
- **copies first, prunes second**, and never deletes more than 500 files in one night;
- **never overwrites** a file already on Drive with different content — chunk names are content
  hashes, so a difference can only mean corruption;
- compares by **content, not date**, so restoring the local folder from a backup does not make
  every later sync fail.

## Restoring

Everything needed is: rclone signed in to Google, and the key from step 1.

```bash
# 1. Bring the encrypted store back from Google Drive (to any empty folder).
RCLONE_CONFIG=/boot/config/rclone/rclone.conf rclone copy gdrive:noevia-offsite /mnt/user/restore/offsite

# 2. Point noevia at it and at the key, then use Settings -> Off-site backups -> Restore,
#    which restores into a new, empty directory and checks every file against its hash.
```

noevia's own restore test runs after every backup and checks that the latest snapshot comes back
byte for byte. On 2026-09-18 the first real snapshot (139 files, including the Diary) restored in
full, and all 12 SQLite databases in it — accounts, projects, and `managed-diary.db` — passed
SQLite's own integrity check.
