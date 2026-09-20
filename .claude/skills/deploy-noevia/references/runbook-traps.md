# DaServer deployment: the five traps

Distilled from `docs/deployment.md`, which stays authoritative. Read that file for the
full history; this is the part that bites if you skip it.

## Contents

1. There are no git credentials on the server
2. Three copies of the compose config, none of which auto-sync
3. The preflight wrapper, not the GUI
4. Verify the candidate before flipping the symlink
5. Rollback

---

## 1. There are no git credentials on the server

`git fetch` in `/mnt/docker/appdata/cowork` fails with "could not read Username" — that
directory is a stale checkout, far behind. Only release `a576ecf` was a real
`git worktree`; everything since is a plain directory.

**Deploy by shipping a tarball.** There is no pull-based path.

```sh
SHA=$(git rev-parse --short HEAD)
git archive --format=tar.gz -o "/tmp/$SHA.tar.gz" HEAD
scp "/tmp/$SHA.tar.gz" root@100.70.173.74:/mnt/docker/appdata/cowork/releases/
ssh root@100.70.173.74 "set -e
cd /mnt/docker/appdata/cowork/releases && mkdir -p $SHA && tar -xzf $SHA.tar.gz -C $SHA && rm -f $SHA.tar.gz
cd /mnt/docker/appdata/cowork && cp config/.env config/.env.bak.\$(date +%Y%m%d%H%M%S)
cd /boot/config/plugins/compose.manager/projects/Cowork
COWORK_SOURCE_DIR=/mnt/docker/appdata/cowork/releases/$SHA COWORK_VERSION=$SHA docker compose --env-file /mnt/docker/appdata/cowork/config/.env build
# STOP HERE if candidate verification fails — see trap 4.
ln -sfn /mnt/docker/appdata/cowork/releases/$SHA /mnt/docker/appdata/cowork/current
sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=$SHA/' /mnt/docker/appdata/cowork/config/.env
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --wait --wait-timeout 120"
```

Layout: `/mnt/docker/appdata/cowork/releases/<git-sha>/` holds a full source checkout;
`current` is a symlink to the active one. `COWORK_SOURCE_DIR` in `.env` points the
compose file's `build: context:` at `current`, and `COWORK_VERSION` sets the image tag.
`config/.env` is chmod 600 — back it up before editing, the `.env.bak.<timestamp>`
convention is already established.

A build takes ~10 min over the Tailscale relay. Run it in the background and poll for
`docker ps | grep cowork-web`. An image that downloads models at build time (the Docling
sidecar) takes considerably longer — and needs outbound access from the box at that
moment, which is worth confirming with a single `curl` before starting rather than
discovering 10 minutes in.

## 2. Three copies of the compose config, none of which auto-sync

A new service or env var must be added to **all three** by hand:

1. repo `compose.yaml`
2. `deploy/examples/unraid-compose-manager.yml`
3. `/boot/config/plugins/compose.manager/projects/Cowork/docker-compose.yml` — **the live
   one**, plus its `docker-compose.override.yml` for the `lemonade_default` external
   network

Editing only the repo file does nothing. Back the live one up first:

```sh
cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
```

**Compose overlays do not work here.** The Unraid Compose Manager plugin drives project
"Cowork" from that single `docker-compose.yml` plus the one override. A
`docker compose -f a.yaml -f b.yaml` pattern is fine on a dev box and cannot be deployed
— the plugin will not read a second `-f`. An optional service shipped as an overlay in
the repo has to be hand-merged into the live file to go live.

## 3. The preflight wrapper, not the GUI

Before any Compose `up` on Unraid, validate resolved writable mounts with the host-side
preflight — `deploy/preflight/README.md`, installed at
`/mnt/docker/appdata/cowork/tools/preflight/up.sh`. Call it from the Compose Manager
project directory with `--env-file … --` followed by the usual `up` options. It rejects
writable `/boot` paths and device aliases without changing state bindings.

**Starting the project from the Compose Manager GUI bypasses this helper entirely.**

## 4. Verify the candidate before flipping the symlink

The build step and the symlink flip are deliberately separate. Between them is the point
where a bad candidate can still be abandoned at zero cost — once `current` moves and
`COWORK_VERSION` is rewritten, recovery is a rollback rather than a no-op.

If candidate verification fails, stop. Do not flip.

## 5. Rollback

Repoint `current` and `COWORK_VERSION` at the previous SHA and re-run Compose up with
`--no-build --wait`. The previous release directory is still there — releases are not
pruned on deploy.

```sh
ssh root@100.70.173.74 "set -e
ln -sfn /mnt/docker/appdata/cowork/releases/<previous-sha> /mnt/docker/appdata/cowork/current
sed -i 's/^COWORK_VERSION=.*/COWORK_VERSION=<previous-sha>/' /mnt/docker/appdata/cowork/config/.env
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh --env-file /mnt/docker/appdata/cowork/config/.env -- -d --no-build --wait --wait-timeout 120"
```

---

## Other things that have wasted time

- **`UPGRADES.md` on the server is stale.** It describes a retired AnythingLLM + LiteLLM
  stack. Ignore it.
- **`/mnt/docker` has no redundancy.** Single-device pool, with daily state and config
  backups to a separate array disk (`deploy/backups/README.md`). That does not cover
  unrelated appdata or the remote Nextcloud corpus.
- **Containers are `cowork-web-1`, `cowork-diary-1`, `cowork-ocr-1`**, plus
  `cowork-embed-1`, native llama.cpp, the model loader and Kiwix. The `cowork-` prefix is
  deliberate and load-bearing.
