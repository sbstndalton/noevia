# Writable boot-storage preflight

Run this on the Docker host before deployment. Unraid already provides PHP;
other hosts need PHP 8 or later if using this helper. No model, account or storage
configuration is changed by the check. It inspects resolved Compose JSON and does
not print environment values, credentials or volume driver options.

```sh
# From the repository root, using its Compose file and .env:
bash deploy/preflight/up.sh -- -d --build

# DaServer, from the existing Cowork Compose Manager project directory:
bash /mnt/docker/appdata/cowork/tools/preflight/up.sh \
  --env-file /mnt/docker/appdata/cowork/config/.env -- \
  -d --no-build --wait --wait-timeout 120
```

Global Compose options go before `--`; `up` options go after it. The wrapper
resolves the same files/environment, runs the check, and starts services only
if both Compose resolution and validation succeed. It preserves all supplied
Compose options and does not select different volumes.

For a read-only check:

```sh
docker compose config --format json | php deploy/preflight/check.php --config-json -
```

Rejects writable binds inside `/boot`, ancestor mounts exposing `/boot`, symlink
aliases (including missing descendants), and alternate mountpoints on a separate
boot device. Read-only mounts and normal Docker managed volumes are allowed.
Named volumes with driver options need separate verification and are refused by
this helper; use ordinary binds for local paths so they can be inspected.

This is a deployment preflight, not a Docker daemon policy. Starting directly
through Compose Manager's GUI or plain `docker compose up` bypasses it. Do not
claim the web container can resolve host symlinks correctly. Keep existing state
bindings; this does not migrate to managed volumes or change the real Diary mount.

Verification: synthetic PHP path tests run on Unraid, wrapper failure/argument tests
run locally, and the resolved live Cowork configuration passes without changes.
