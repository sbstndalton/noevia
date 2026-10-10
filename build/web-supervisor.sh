#!/usr/bin/env bash
# The web image's entrypoint (full-Rust migration M1, docs/adr-0001-rust-and-repo-split.md
# "Amendment 2026-10-10"). NOEVIA_FRONT picks who faces the network on UI_PORT:
#
#   node (default)  Node alone, exactly as before: `node server/index.cjs` on UI_HOST:UI_PORT.
#   rust            noevia-server (noevia-rs bins/noevia-server) on UI_HOST:UI_PORT, Node behind
#                   it on UI_PORT+1000 (NOEVIA_LEGACY_UPSTREAM). The front answers the routes
#                   noevia-rs contracts/http/routes.toml gives to Rust and streams the rest to Node.
#
# This is a deployment switch, not an interposer: it is removed once the Rust front is proven.
# If either process exits, the other is stopped and the container exits non-zero, so Docker's
# restart policy brings both back together.
set -uo pipefail

front="${NOEVIA_FRONT:-node}"
case "$front" in
  node) exec node server/index.cjs ;;
  rust) ;;
  *) echo "web-supervisor: NOEVIA_FRONT must be rust or node, got '$front'" >&2; exit 2 ;;
esac

bin="${NOEVIA_SERVER_BIN:-/usr/local/bin/noevia-server}"
if [ ! -x "$bin" ]; then
  echo "web-supervisor: NOEVIA_FRONT=rust but this image has no noevia-server (its NOEVIA_RS_REF predates bins/noevia-server); set NOEVIA_FRONT=node" >&2
  exit 2
fi
port="${UI_PORT:-8021}"
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 64535 ]; then
  echo "web-supervisor: UI_PORT '$port' leaves no room for the legacy port UI_PORT+1000" >&2
  exit 2
fi
legacy=$((port + 1000))

# Node binds UI_HOST for the UI listener AND the Diary file-sharing (DAV) listener. With DAV off
# the legacy port is loopback-only; with DAV on, Node keeps UI_HOST so DAV stays reachable, and
# the legacy port is then reachable from the container's networks too (never published by
# Compose; the same exposure Node's UI port has today) until core splits the two bind hosts.
node_host="127.0.0.1"
if [ -n "${COWORK_DAV_PORT:-}" ] && [ "${COWORK_DAV_PORT}" != 0 ]; then
  node_host="${UI_HOST:-0.0.0.0}"
  echo "web-supervisor: COWORK_DAV_PORT is set; Node's legacy port $legacy listens on $node_host, not loopback only" >&2
fi

node_pid="" front_pid="" signalled=0
stop() {
  local p
  for p in "$node_pid" "$front_pid"; do
    [ -n "$p" ] && kill -TERM "$p" 2>/dev/null
  done
  return 0
}
trap 'signalled=1; stop' TERM INT

UI_HOST="$node_host" UI_PORT="$legacy" node server/index.cjs &
node_pid=$!
NOEVIA_LEGACY_UPSTREAM="http://127.0.0.1:$legacy" "$bin" &
front_pid=$!

# Whichever exits first (or a signal) ends the wait.
wait -n "$node_pid" "$front_pid"
code=$?
if [ "$signalled" = 0 ]; then
  if kill -0 "$node_pid" 2>/dev/null; then which=noevia-server; else which=node; fi
  echo "web-supervisor: $which exited ($code); stopping the other" >&2
fi
stop
wait "$node_pid" 2>/dev/null
wait "$front_pid" 2>/dev/null
# docker stop: a clean exit. Anything else: non-zero, even when the process that left said 0.
[ "$signalled" = 1 ] && exit 0
[ "$code" = 0 ] && code=1
exit "$code"
