# AIO notify-push internal callbacks

`repair-push.py` changes only the notify-push callback URL and adds the exact
internal Apache hostname to Nextcloud's trusted domains. It preserves the current
image ID, mounts, restart policy and other container settings. The public endpoint
and trusted-proxy list are unchanged. Run without `--apply` to inspect status.

DaServer has no host Python. Use its existing noevia worker image as a temporary
runtime, with the Docker socket and CLI mounted for this administrator operation:

```sh
scp deploy/nextcloud/repair-push.py root@10.69.0.130:/tmp/noevia-repair-push.py
ssh root@10.69.0.130 'docker run --rm --network none --user 0 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/local/bin/docker:ro \
  -v /mnt/docker/appdata/cowork/backups:/mnt/docker/appdata/cowork/backups \
  -v /tmp/noevia-repair-push.py:/repair.py:ro \
  --entrypoint python cowork-ocr:ddbe852 /repair.py --apply'
```

The script verifies the real self-test and automatically rolls back on failure.
It retains a stopped rollback container and root-only configuration backup.
The setting survives container/host restarts. **AIO updates can recreate the
container from their default definition**: rerun this script after an AIO update.
It detects an already-correct setting and only verifies it. Do not commit backups;
container configuration may contain credentials.

Verified live on 2026-09-10: all six self-test checks pass before and after a
notify-push restart. This removes the public Cloudflare round trip for internal
callbacks; it does not make desktop file sync transactional.
