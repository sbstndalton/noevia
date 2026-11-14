#!/bin/bash
# rollback-switch.sh KEY [TO] : rolls one web switch back from its live value to TO (default '-', absent: both files
# back to their pre-flip bytes). Replaces the hand-made per-release rollback-<KEY>.sh files: the live value is read from
# .env at run time, so the same command works after any later flip and after a web image rollback. See switch.sh.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
KEY=${1:?KEY}; TO=${2:--}
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
ENV=${CONF_APPDATA:-/mnt/docker/appdata/cowork}/config/.env
cur=$(env_get "$ENV" "$KEY")
[ "$cur" != - ] || { echo "switch_error=${KEY}_not_set (nothing to roll back)"; exit 64; }
ROLLBACK=1 exec bash "$HERE/switch.sh" "$KEY" "$TO" "$cur"
