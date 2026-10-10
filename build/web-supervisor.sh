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

# Only this script may confirm rust-auth to Node (below); never trust a value from the environment.
unset NOEVIA_RUST_AUTH_CONFIRMED
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
# The code-network guard (sbstndalton/noevia#1246): with COWORK_CODE_NET_ADDR set, Node behind
# the front sees every request arrive on loopback, so only the front can refuse code-network
# requests. A front that does not report the guard must not face the network.
# (Captured first: with pipefail, grep -q exiting early could fail the pipeline via SIGPIPE.)
if [ -n "${COWORK_CODE_NET_ADDR:-}" ]; then
  features="$("$bin" --features 2>/dev/null || true)"
else
  features=code-net-guard
fi
if ! grep -qx 'code-net-guard' <<<"$features"; then
  echo "web-supervisor: COWORK_CODE_NET_ADDR is set but this noevia-server has no code-net-guard; set NOEVIA_FRONT=node or update the image" >&2
  exit 2
fi
# Rust-owned sign-in (noevia-core server/rust-auth.cjs): with NOEVIA_RUST_AUTH=1 Node refuses to
# write the account tables, so the front facing the network must answer those routes. Only a front
# whose --features lists rust-auth may do that; Node is told so with NOEVIA_RUST_AUTH_CONFIRMED=1
# and stays a full writer without it.
rust_auth_confirmed=""
if [ "${NOEVIA_RUST_AUTH:-}" = 1 ]; then
  rust_features="$("$bin" --features 2>/dev/null || true)"
  if ! grep -qx 'rust-auth' <<<"$rust_features"; then
    echo "web-supervisor: NOEVIA_RUST_AUTH=1 but this noevia-server has no rust-auth; unset NOEVIA_RUST_AUTH, set NOEVIA_FRONT=node or update the image" >&2
    exit 2
  fi
  rust_auth_confirmed=1
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

UI_HOST="$node_host" UI_PORT="$legacy" NOEVIA_RUST_AUTH_CONFIRMED="$rust_auth_confirmed" node server/index.cjs &
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
