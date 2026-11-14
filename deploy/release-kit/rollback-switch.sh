#!/bin/bash
# rollback-switch.sh KEY : rolls one web switch back from its live value to absent (both files back to their pre-flip
# bytes). To step back to an earlier value instead, run switch.sh forward with its DRY. Replaces the hand-made per-release rollback-<KEY>.sh files: the live value is read from
# .env at run time, so the same command works after any later flip and after a web image rollback. See switch.sh.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd); . "$HERE/lib.sh"
KEY=${1:?KEY}; [ $# = 1 ] || { echo "switch_error=rollback_only_removes (step back to a value with a forward switch.sh run and its DRY)"; exit 64; }
kit_conf "${KIT_CONF:-$HERE/kit.conf}" || exit 1
ENV=${CONF_APPDATA:-/mnt/docker/appdata/cowork}/config/.env
cur=$(env_get "$ENV" "$KEY")
[ "$cur" != - ] || { echo "switch_error=${KEY}_not_set (nothing to roll back)"; exit 64; }
ROLLBACK=1 exec bash "$HERE/switch.sh" "$KEY" - "$cur"
