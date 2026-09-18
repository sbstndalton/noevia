# Off-site backups to Google Drive

noevia already backs itself up every night — encrypted — into
`/mnt/user/noevia-backups/offsite` on DaServer. The script here copies that folder to your
Google Drive at 02:45 each night, so that a dead server does not take everything with it.

**Google never sees anything readable.** Every file is sealed with AES-256-GCM before it leaves
noevia, and the file names are random hashes. On Drive you will see a folder called
`noevia-offsite` full of meaningless names. That is correct.

**noevia never holds your Google password or token.** Only rclone on the server does, and it is
limited to `drive.file`: it can see the files it created itself and nothing else in your Drive.

Status on 2026-09-18: everything is set up and running except the one step that needs you — signing
rclone in to Google, once.

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

The server has no browser, so this borrows your Mac's. Open a terminal on your Mac and connect to
the server with a tunnel:

```bash
ssh -L 53682:127.0.0.1:53682 daserver
```

Then, **in that same window** (you are now on the server):

```bash
RCLONE_CONFIG=/boot/config/rclone/rclone.conf rclone config
```

Answer the questions like this:

| rclone asks | You answer |
|---|---|
| New remote? | `n` |
| name | `gdrive` — exactly this; the nightly script looks for it |
| Storage | `drive` (Google Drive) |
| client_id / client_secret | press Enter (leave blank) |
| scope | the one that says **"Access to files created by rclone only"** (`drive.file`) — not full access |
| service_account_file | press Enter |
| Edit advanced config? | `n` |
| Use web browser to automatically authenticate? | `y` |

rclone prints a link starting with `http://127.0.0.1:53682/`. **Open it in your Mac's browser**,
sign in to the Google account you want the backups in, and allow access. The tunnel carries the
answer back to the server. Then:

| rclone asks | You answer |
|---|---|
| Configure this as a Shared Drive? | `n` |
| Keep this remote? | `y` |
| (menu) | `q` to quit |

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
