#!/usr/bin/env bash
# Assemble one release tarball from pinned sources (#922, docs/adr-0001-rust-and-repo-split.md).
# Runs on the Mac (or CI). Since the repo split cutover (#952) this is THE release source: the
# tarball it writes is what docs/deployment.md ships to releases/<sha>/ on the server, and
# build-web-release.sh / overlay-release.sh consume it.
#
# Usage: assemble-release.sh [--lock <file>] <noevia-sha> [out-dir]
#   <noevia-sha>  7-40 lowercase hex commit in this repo. It becomes COWORK_VERSION / the version.json
#                 `version`, exactly as in today's releases.
#   out-dir       where noevia-release-<sha>.tar.gz is written (default: current directory).
#   --lock <file> CI ONLY (#952): read the component refs from <file> instead of
#                 release/versions.lock at <noevia-sha> (used before the cutover to prove the
#                 split candidate; kept for re-proving a candidate lock).
#
# The tarball holds, at its top level:
#   noevia/        git archive of this repo at <noevia-sha>
#   web/           client tree (noevia-web layout): src, public, index.html, vite.config.ts,
#                  tsconfig.json, package*.json, scripts, contracts, plus tests/client and qa
#                  (the client tests the image build runs)
#   core/          server tree (noevia-core layout): server, contracts, plus tests/server,
#                  tests/fixtures and code-sandbox/ (services/code-sandbox's build context)
#   services/      Python sidecars (noevia-services layout): diary, docling, laya, model-manager,
#                  ocr, one image build context each
#   rs/            noevia-rs at NOEVIA_RS_REF (the whole repo), verified against NOEVIA_RS_SHA256;
#                  build/web.Dockerfile builds the Rust front (bins/noevia-server) from it. Empty
#                  when the lock has no NOEVIA_RS_SHA256 (locks from before M1).
#   release-refs   NOEVIA_SHA / NOEVIA_WEB_SHA / NOEVIA_CORE_SHA / NOEVIA_SERVICES_SHA /
#                  NOEVIA_RS_SHA (build/web.Dockerfile reads the first three)
#   .dockerignore  keeps noevia/ (but build/web-supervisor.sh) and services/ out of the web image
#                  build context
#
# The self-mode path lists match tools/repo-split's map exactly, so a self assembly and one from
# the extracted repos differ only by those repos' README.md and .github/ (CI checks this).
#
# web/, core/ and services/ come from release/versions.lock AS COMMITTED AT <noevia-sha>:
#   NOEVIA_{WEB,CORE,SERVICES}_REF = self      -> exported from apps/web and services/ at <noevia-sha>
#     (only commits from before the cutover have those paths; a lock without NOEVIA_SERVICES_REF,
#     i.e. any commit before #952, means self). This keeps old SHAs assemblable for rollback.
#   NOEVIA_{WEB,CORE,SERVICES}_REF = <40 hex>  -> anonymous https tarball from
#     codeload.github.com/sbstndalton/noevia-web|noevia-core|noevia-services, verified against
#     NOEVIA_{WEB,CORE,SERVICES}_SHA256, which a pinned ref requires (checked before download). The repo root becomes web/, core/
#     or services/. The path map is the one tools/repo-split extracts with.
#
# Build (no push): docker build -f noevia/build/web.Dockerfile --build-arg COWORK_VERSION=<sha> <tree>
set -euo pipefail

die() { echo "assemble-release: $*" >&2; exit 1; }
# Shared strict detector for ownership pairing guards (see lib/rs-capability.md).
rs_capability_lib="$(cd -- "$(dirname -- "$0")" && pwd)/lib/rs-capability.cjs"
. "$(dirname -- "$rs_capability_lib")/rs-capability.sh"
# A source file without its comment lines: a pairing check that reads code must not be satisfied by a
# sentence that mentions the thing (nor end the script silently when a file or a match is absent).
code_lines() { grep -vE '^[[:space:]]*(//|/\*|\*|#)' "$1" 2>/dev/null || true; }

lock_file=""
if [ "${1:-}" = --lock ]; then
  lock_file="${2:-}"; shift 2 || true
  # A release must come from the lock committed at the released sha; an override is CI-only.
  [ "${CI:-}" = true ] || { echo "assemble-release: --lock is for CI dry runs only (CI=true); releases read release/versions.lock" >&2; exit 2; }
  [ -f "$lock_file" ] || { echo "assemble-release: --lock file not found: $lock_file" >&2; exit 2; }
fi
sha="${1:-}"
out_dir="${2:-.}"
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "usage: assemble-release.sh [--lock <file>] <noevia-sha (7-40 lowercase hex)> [out-dir]" >&2; exit 2; }
[ -d "$out_dir" ] || die "out-dir does not exist: $out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"

repo="$(cd -- "$(dirname -- "$0")" && git rev-parse --show-toplevel)" || die "not inside a git checkout"
git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null || die "unknown commit: $sha (fetch it first)"
full_sha="$(git -C "$repo" rev-parse --verify "$sha^{commit}")"
# A short sha must not be ambiguous and must be a prefix of what it resolved to.
[[ "$full_sha" == "$sha"* ]] || die "$sha resolved to $full_sha; pass a commit sha, not a ref"
# The archive is taken from the commit, but a dirty checkout usually means the operator meant to
# release something that is not committed yet. Refuse rather than ship the wrong thing.
if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
  die "checkout $repo has uncommitted changes; commit them or assemble from a clean worktree"
fi

if [ -n "$lock_file" ]; then
  lock="$(cat -- "$lock_file")"
  echo "assemble-release: dry run with component refs from $lock_file, not the committed lock" >&2
else
  lock="$(git -C "$repo" show "$full_sha:release/versions.lock" 2>/dev/null)" \
    || die "release/versions.lock does not exist at $sha"
fi
lock_value() { printf '%s\n' "$lock" | sed -n "s/^$1=//p" | tail -n 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/assemble-release.XXXXXX")"
out_partial=""
# Never leave <out>.partial behind when the final tar (or anything after it) fails.
trap 'rm -rf "$work"; if [ -n "$out_partial" ]; then rm -f "$out_partial"; fi' EXIT
tree="$work/tree"
# Match the Dockerfile that will compile this assembled Rust source snapshot.
rs_capability_build="$tree/noevia/build/web.Dockerfile"
mkdir -p "$tree/noevia" "$tree/web" "$tree/core" "$tree/services"

git -C "$repo" archive --format=tar "$full_sha" | tar -x -C "$tree/noevia"

# Export <prefix>/<paths> at the noevia commit into <dest>, <prefix> stripped.
export_self() {
  local dest="$1" prefix="$2"; shift 2
  local specs=() p strip
  for p in "$@"; do
    git -C "$repo" cat-file -e "$full_sha:$prefix/$p" 2>/dev/null || die "$prefix/$p is missing at $sha"
    specs+=("$prefix/$p")
  done
  strip="$(printf '%s' "$prefix" | tr -cd / | wc -c)"
  git -C "$repo" archive --format=tar "$full_sha" -- "${specs[@]}" | tar -x --strip-components="$((strip + 1))" -C "$dest"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Fetch sbstndalton/<repo_name> at a pinned 40-hex ref into <dest> (repo root -> dest).
fetch_remote() {
  local repo_name="$1" ref="$2" want_sum="$3" dest="$4" tgz
  tgz="$work/$repo_name.tar.gz"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$tgz" \
    "https://codeload.github.com/sbstndalton/$repo_name/tar.gz/$ref" \
    || die "could not download $repo_name at $ref"
  [ "$(sha256_of "$tgz")" = "$want_sum" ] || die "$repo_name tarball checksum mismatch at $ref"
  tar -xzf "$tgz" --strip-components=1 -C "$dest"
}

# Resolve one component; prints the resolved 40-hex sha.
resolve_component() {
  local key="$1" repo_name="$2" dest="$3"; shift 3
  local ref sum
  ref="$(lock_value "${key}_REF")"
  sum="$(lock_value "${key}_SHA256")"
  # Locks from before #952 have no NOEVIA_SERVICES_REF: services were always exported from here.
  if [ -z "$ref" ] && [ "$key" = NOEVIA_SERVICES ] && ! printf '%s\n' "$lock" | grep -q '^NOEVIA_SERVICES_REF='; then
    ref=self
  fi
  if [ "$ref" = self ]; then
    export_self "$dest" "$@"
    printf '%s' "$full_sha"
  elif [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || die "${key}_REF is pinned but ${key}_SHA256 is missing or not 64 lowercase hex"
    fetch_remote "$repo_name" "$ref" "$sum" "$dest"
    printf '%s' "$ref"
  else
    die "${key}_REF in versions.lock at $sha must be 'self' or a 40-char lowercase sha, got: '${ref}'"
  fi
}

web_sha="$(resolve_component NOEVIA_WEB noevia-web "$tree/web" apps/web \
  src public index.html vite.config.ts tsconfig.json package.json package-lock.json scripts contracts tests/client qa \
  tests/hermetic-network.cjs .gitignore .dockerignore)"
core_sha="$(resolve_component NOEVIA_CORE noevia-core "$tree/core" apps/web \
  server contracts tests/server tests/fixtures tests/hermetic-network.cjs)"
if [ "$(lock_value NOEVIA_CORE_REF)" = self ]; then
  # noevia-core also owns services/code-sandbox, at code-sandbox/ (tools/repo-split's map).
  export_self "$tree/core" services code-sandbox
fi
services_sha="$(resolve_component NOEVIA_SERVICES noevia-services "$tree/services" services \
  diary docling laya model-manager ocr)"

# noevia-rs (full-Rust migration M1): the web image builds its Rust front from this tree's rs/.
# Locks from before M1 pin no tarball checksum for noevia-rs; their trees carry an empty rs/.
mkdir -p "$tree/rs"
rs_ref="$(lock_value NOEVIA_RS_REF)"
rs_sum="$(lock_value NOEVIA_RS_SHA256)"
rs_sha=""
if [ -n "$rs_sum" ]; then
  [[ "$rs_ref" =~ ^[0-9a-f]{40}$ ]] || die "NOEVIA_RS_REF in versions.lock at $sha must be a 40-char lowercase sha, got: '${rs_ref}'"
  [[ "$rs_sum" =~ ^[0-9a-f]{64}$ ]] || die "NOEVIA_RS_SHA256 in versions.lock at $sha is not 64 lowercase hex"
  fetch_remote noevia-rs "$rs_ref" "$rs_sum" "$tree/rs"
  [ -f "$tree/rs/Cargo.toml" ] || die "noevia-rs at $rs_ref has no Cargo.toml"
  rs_sha="$rs_ref"
fi

# Full-Rust migration M4: the Rust front and Node share projects.json. Every project route the
# front owns (rs/contracts/http/routes.toml, owner "rust", no switch since sbstndalton/noevia#1071:
# a project, free-chat-list or chat-context path) must be one this release's core knows the front
# owns (core/server/rust-projects.cjs OWNED_ROUTES):
# Node merges what the front writes for those routes per item and refuses its own copies of them.
# A front that saves a project's chat list over a core from before noevia-core#75 would have its
# chats dropped by Node's whole-field merge (sbstndalton/noevia#1409), so that pairing is refused
# here; likewise a front that saves the free-chat list (GET/POST /api/freechats) over a core from
# before noevia-core#76, whose own free-list writers would overwrite free-chats.json whole, and a
# front that answers a chat's DELETE (/api/freechats/{chatId}, /api/projects/{id}/chats/{chatId},
# #1071 slice 6) over a core that still answers it too. Placeholder names ({id}, {projectId}) are compared as one.
# Includes the permanent context slice (#1264). routes.toml is read by routes_toml below, which
# understands the TOML that matters here (indented keys, spaces or tabs around "=", "basic" or
# 'literal' strings, trailing comments, multi-line arrays, quoted keys, [[ route ]] headers) rather
# than one literal spelling; comments never count. Any route that still carries a `switch` is
# refused further down (#2096).
# It fails closed: a line it cannot classify (a quoted [["route"]] header, a top-level route = [ {...} ]
# array, a dotted key inside a route, a """ string, an unterminated value, ...) is an error, never a
# route that reads as unswitched. A leading BOM is skipped. The caller checks it once before any use.
#
# One tab-separated record per [[route]] table: path, owner, switch, methods. An absent or empty
# field is "-", except that a present-but-empty switch is "?" (still switched: fail closed).
routes_toml() {
  LC_ALL=C awk '
    function die(msg) { printf "line %d: %s\n", NR, msg > "/dev/stderr"; bad = 1; exit 2 }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function orDash(s) { return s == "" ? "-" : s }
    function flush() {
      if (seen) print orDash(path) "\t" orDash(owner) "\t" (hasSw ? (sw == "" ? "?" : sw) : "-") "\t" orDash(methods)
      path = ""; owner = ""; sw = ""; methods = ""; hasSw = 0; seen = 0
    }
    function setkey(key, val) {
      if (key == "path" || key == "owner" || key == "switch" || key == "methods") {
        if (index(val, "\\")) die("an escape sequence in " key " is not read")
      }
      if (key == "path") path = val
      else if (key == "owner") owner = val
      else if (key == "switch") { hasSw = 1; sw = val }
      else if (key == "methods") methods = val
    }
    function tailok(t) { t = trim(t); if (t != "" && substr(t, 1, 1) != "#") die("unexpected text after the value: " t) }
    function scalar(rest,   q, e) {
      q = substr(rest, 1, 1)
      if (q == "\"" || q == "\047") {
        rest = substr(rest, 2); e = index(rest, q)
        if (!e) die("unterminated string")
        tailok(substr(rest, e + 1))
        return substr(rest, 1, e - 1)
      }
      sub(/[ \t]*#.*$/, "", rest)
      return trim(rest)
    }
    # One line of an array value: quotes are honoured (a # or ] inside them is text), the rest of
    # the line after a # outside them is a comment. Sets arr = 0 when the array closes.
    function scan(s,   i, c, q) {
      if (index(s, "\"\"\"") || index(s, "\047\047\047")) die("multi-line strings are not read")
      q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == "\\") die("an escape sequence in an array is not read")
          if (c == q) q = ""; else abuf = abuf c
          continue
        }
        if (c == "\"" || c == "\047") { q = c; continue }
        if (c == "#") break
        if (c == "[") { depth++; continue }
        if (c == "]") {
          if (--depth == 0) { tailok(substr(s, i + 1)); arr = 0; return }
          continue
        }
        abuf = abuf c
      }
      if (q != "") die("unterminated string in an array")
      abuf = abuf " "
    }
    NR == 1 && substr($0, 1, 3) == sprintf("%c%c%c", 239, 187, 191) { $0 = substr($0, 4) }
    {
      line = $0; sub(/\r$/, "", line); line = trim(line)
      if (arr) { scan(line); if (!arr && inroute) setkey(arrkey, trim(abuf)); next }
      if (line == "" || line ~ /^#/) next
      if (line ~ /^\[/) {
        flush(); hdr = 1
        if (!match(line, /^\[\[?[ \t]*[A-Za-z0-9_-]+([ \t]*\.[ \t]*[A-Za-z0-9_-]+)*[ \t]*\]\]?/)) die("table header is not a plain bare name, so it cannot be classified: " line)
        head = substr(line, 1, RLENGTH); tailok(substr(line, RLENGTH + 1))
        opens = 0; while (substr(head, opens + 1, 1) == "[") opens++
        closes = 0; while (substr(head, length(head) - closes, 1) == "]") closes++
        name = head; gsub(/[\[\] \t]/, "", name)
        if (opens != closes) die("unbalanced table header: " line)
        if (name == "route") { if (opens != 2) die("route must be an array of tables, [[route]]: " line); inroute = 1; seen = 1 }
        else if (name ~ /^route\./) die("a sub-table of route is not read: " line)
        else inroute = 0
        next
      }
      if (inroute) {
        if (!match(line, /^("[A-Za-z0-9_-]+"|\047[A-Za-z0-9_-]+\047|[A-Za-z0-9_-]+)[ \t]*=/)) die("cannot classify this line inside a [[route]] table (dotted keys and inline tables are not read): " line)
        key = substr(line, 1, RLENGTH - 1); sub(/[ \t]+$/, "", key); gsub(/["\047]/, "", key)
        rest = trim(substr(line, RLENGTH + 1))
      } else {
        eq = index(line, "=")
        if (!eq) next
        key = substr(line, 1, eq - 1); gsub(/[ \t"\047]/, "", key)
        if (!hdr && (key == "route" || key ~ /^route\./)) die("a top-level route key (an inline route array) is not read; use [[route]] tables: " line)
        rest = trim(substr(line, eq + 1))
      }
      if (substr(rest, 1, 3) == "\"\"\"" || substr(rest, 1, 3) == "\047\047\047") die("multi-line strings are not read")
      if (substr(rest, 1, 1) == "[") {
        arrkey = key; arr = 1; depth = 1; abuf = ""
        scan(substr(rest, 2))
        if (!arr && inroute) setkey(key, trim(abuf))
        next
      }
      if (inroute) setkey(key, scalar(rest))
    }
    END {
      if (bad) exit 2
      if (arr) { printf "line %d: unterminated array\n", NR > "/dev/stderr"; exit 2 }
      flush()
    }
  ' "$1"
}
project_routes_rs() {
  routes_toml "$1" | awk -F'\t' '
    $2 == "rust" && $3 == "-" && ($1 ~ /^\/api\/(projects\/|freechats$|freechats\/[^\/]+$)/ || $1 ~ /^\/api\/chats\/[^\/]+\/(context|move)$/) {
      if ($4 == "-") { print "ALL " $1; next }
      n = split($4, m, /[^A-Z]+/)
      for (i = 1; i <= n; i++) if (m[i] != "") print m[i] " " $1
    }
  ' | sed 's/{[^}]*}/{}/g' | sort -u
}
# The three GETs and (when paired) both POST writers. No HEAD or other method moves.
web_address_routes_rs() {
  routes_toml "$1" | awk -F'\t' '
    $1 == "/api/instance" || $1 == "/.well-known/webauthn" || $1 == "/api/admin/web-address" || $1 == "/api/admin/web-address/remove" {
      if ($2 == "rust") {
        if ($3 != "-" || $4 == "-") { print "invalid " $1; next }
        n = split($4, methods, ",")
        for (i = 1; i <= n; i++) {
          gsub(/[ \t]/, "", methods[i])
          if (methods[i] !~ /^(GET|POST)$/) { print "invalid " $1; next }
          print methods[i] " " $1
        }
      }
    }
  ' | sort -u
}
# A writer-capable core must export both markers, both exact POST paths, and refuse the
# methods before public/auth dispatch. Older GET-only pins remain a valid separate pair.
web_address_routes_core() {
  local source="$tree/core/server/rust-web-address.cjs"
  [ -f "$source" ] || return 0
  grep -qxF "const WEB_ADDRESS_READ_OWNER = 'noevia-web-address-read-rust/1';" "$source" || { echo invalid-marker; return; }
  grep -qxF "  return method === 'GET' && OWNED_GET_PATHS.includes(pathname);" "$source" || { echo invalid-method; return; }
  if grep -qxF "const WEB_ADDRESS_WRITE_OWNER = 'noevia-web-address-write-rust/1';" "$source"; then
    grep -qxF 'module.exports = { WEB_ADDRESS_READ_OWNER, WEB_ADDRESS_WRITE_OWNER, OWNED_GET_PATHS, OWNED_POST_PATHS, ROUTE_REFUSAL, WRITE_REFUSAL, ownedRead, ownedWrite, refuseOwnedRead, refuseOwnedWrite, refuseOwned };' "$source" || { echo invalid-export; return; }
    grep -qxF "const OWNED_POST_PATHS = Object.freeze(['/api/admin/web-address', '/api/admin/web-address/remove']);" "$source" || { echo invalid-write-paths; return; }
    grep -qxF "  return method === 'POST' && OWNED_POST_PATHS.includes(pathname);" "$source" || { echo invalid-write-method; return; }
    grep -qxF "  return refuseOwnedRead(req, res, pathname, json) || refuseOwnedWrite(req, res, pathname, json);" "$source" || { echo invalid-write-refusal; return; }
    grep -qxF "    if (require('./rust-web-address.cjs').refuseOwned(req, res, p, json)) return;" "$tree/core/server/index.cjs" || { echo invalid-wiring; return; }
    grep -qxF "  previous_origins: ['Web address changes are owned by the Rust front.', 'RUST_WEB_ADDRESS_WRITE_OWNED']," "$tree/core/server/rust-auth.cjs" || { echo invalid-write-guard; return; }
    sed -n '/^const OWNED_GET_PATHS = /,/]);/p' "$source" | grep -oE "'/(api/instance|api/admin/web-address|\.well-known/webauthn)'" | tr -d "'" | sed 's/^/GET /'
    sed -n '/^const OWNED_POST_PATHS = /,/]);/p' "$source" | grep -oE "'/api/admin/web-address(/remove)?'" | tr -d "'" | sed 's/^/POST /'
  else
    grep -qxF 'module.exports = { WEB_ADDRESS_READ_OWNER, OWNED_GET_PATHS, ROUTE_REFUSAL, ownedRead, refuseOwnedRead };' "$source" || { echo invalid-export; return; }
    grep -qxF "    if (require('./rust-web-address.cjs').refuseOwnedRead(req, res, p, json)) return;" "$tree/core/server/index.cjs" || { echo invalid-wiring; return; }
    sed -n '/^const OWNED_GET_PATHS = /,/]);/p' "$source" | grep -oE "'/(api/instance|api/admin/web-address|\.well-known/webauthn)'" | tr -d "'" | sed 's/^/GET /'
  fi | sort -u
}
# Whether routes.toml gives GET /api/auth/session to Rust with no switch (sign-in is the front's
# permanently, sbstndalton/noevia#1071).
rust_auth_unswitched() {
  routes_toml "$1" | awk -F'\t' '$1 == "/api/auth/session" && $2 == "rust" && $3 == "-" { found = 1 } END { exit(found ? 0 : 1) }'
}
# Whether routes.toml gives GET /api/chats/{chatId}/history to Rust (sbstndalton/noevia#1071
# slice 2): owner rust with GET among its methods, or with all methods.
rust_owns_history_get() {
  routes_toml "$1" | awk -F'\t' '
    $1 ~ /^\/api\/chats\/\{[^}]*\}\/history$/ && $2 == "rust" {
      if ($4 == "-") found = 1
      n = split($4, m, /[^A-Z]+/)
      for (i = 1; i <= n; i++) if (m[i] == "GET") found = 1
    }
    END { exit(found ? 0 : 1) }'
}
# Whether routes.toml gives POST /api/chats/{chatId}/history to Rust (sbstndalton/noevia#1071
# slice 5): owner rust with POST among its methods, or with all methods.
rust_owns_history_post() {
  routes_toml "$1" | awk -F'\t' '
    $1 ~ /^\/api\/chats\/\{[^}]*\}\/history$/ && $2 == "rust" {
      if ($4 == "-") found = 1
      n = split($4, m, /[^A-Z]+/)
      for (i = 1; i <= n; i++) if (m[i] == "POST") found = 1
    }
    END { exit(found ? 0 : 1) }'
}
# Whether the pinned front's internal store serves the transcript ops (sbstndalton/noevia#1071
# slice 4): a Rust source under rs/bins names the append route.
rs_serves_history_ops() {
  grep -rqs --include='*.rs' -e '/v1/history/append-if-last' "$tree/rs/bins"
}
# Whether the pinned core writes transcripts only through the store ops (sbstndalton/noevia#1071
# slice 4): the client has them, the interrupted-reply path and the import use them, and the
# local writer projects.cjs writeHistory is gone.
# Since #2191 round 4 the front owns the conversation import: Core has no conversation-import.cjs and
# refuses the route, so that import cannot write a transcript from Node.
core_refuses_conversation_import() {
  local refusal="if (require('./rust-conversation-import.cjs').refuseOwned(req, res" helper index refuse_at route_at
  helper="$tree/core/server/rust-conversation-import.cjs"; index="$tree/core/server/index.cjs"
  [ ! -e "$tree/core/server/conversation-import.cjs" ] && [ -f "$helper" ] && [ -f "$index" ] || return 1
  code_lines "$helper" | grep -qF "'POST /api/import/conversations'" || return 1
  code_lines "$helper" | grep -qE '^function refuseOwned\(' || return 1
  # The route must not write a transcript itself, and the refusal must run before it.
  ! code_lines "$tree/core/server/routes/import.cjs" | grep -qE 'transcripts\.|writeHistory' || return 1
  refuse_at="$(code_lines "$index" | grep -nF "$refusal" | head -1 | cut -d: -f1)"
  route_at="$(code_lines "$index" | grep -n 'await importRoutes(' | head -1 | cut -d: -f1)"
  [ -n "$refuse_at" ] || return 1
  [ -z "$route_at" ] || [ "$refuse_at" -lt "$route_at" ]
}
core_writes_history_via_store() {
  grep -q 'historyAppendIfLast' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
    && grep -q 'transcripts.appendIfLast(' "$tree/core/server/chat-interrupted-turn.cjs" 2>/dev/null \
    && { grep -q 'ctx.transcripts.write(' "$tree/core/server/conversation-import.cjs" 2>/dev/null \
      || core_refuses_conversation_import; } \
    && ! grep -q 'function writeHistory' "$tree/core/server/projects.cjs" 2>/dev/null
}
# Whether the pinned core calls the transcript ops at all (then the front must serve them).
core_uses_history_ops() {
  grep -q 'historyAppendIfLast' "$tree/core/server/project-store-client.cjs" 2>/dev/null
}
# Whether the pinned front journals transcript changes for Node (sbstndalton/noevia#2153): a Rust
# source under rs/bins names the changes read op.
rs_serves_change_journal() {
  grep -rqs --include='*.rs' -e '/v1/changes/read' "$tree/rs/bins"
}
# Whether the pinned core's own Node reader tails that journal (server/chat-change-journal.cjs carries its marker).
core_tails_change_journal_legacy() {
  grep -q "'noevia-chat-change-journal-reader/1'" "$tree/core/server/chat-change-journal.cjs" 2>/dev/null
}
# Whether the release has a journal consumer: that legacy reader, or the paired front's own
# (rust-chat-mirror-v1: the front tails the journal in process and the core keeps only the executors).
# chat_mirror_paired is set below, once, from the exact declarations of both sides, and starts empty.
chat_mirror_paired=""
core_tails_change_journal() {
  core_tails_change_journal_legacy || [ "$chat_mirror_paired" = rust ]
}
# Whether the pinned core builds a chat's brain only for journal entries with origin "history"
# (sbstndalton/noevia#2153: then it no longer nudges the brain itself while the front journals).
core_needs_journal_origin() {
  # Any variable name (#2161: a rename must not skip the guard), either quote, code lines only. Also `e?.origin`,
  # `e['origin']` / `e?.['origin']`, and the string on the left (#2252): each reads the origin as `history`.
  # #2255: also a destructured bare `origin` (`const { origin } = e`) and the negated tests `!==` / `!=`
  # (`e.origin !== 'history'` returns early for everything else, so the core reads the origin the same way).
  local field="[A-Za-z_][A-Za-z0-9_]*(\\?\\.|\\.)origin|[A-Za-z_][A-Za-z0-9_]*(\\?\\.)?\\[['\"]origin['\"]\\]|(^|[^A-Za-z0-9_\$.'\"-])origin"
  local history="['\"]history['\"]" eq="[[:space:]]*(===?|!==?)[[:space:]]*"
  code_lines "$tree/core/server/chat-change-journal.cjs" | grep -qE "(${field})${eq}${history}|${history}${eq}(${field})"
}
# Whether the pinned front's journal entries carry that origin (crates/server-projects journal.rs).
rs_journals_origin() {
  # The entry's field is built from the origin value in code; a doc comment naming "origin" is not it (#2161).
  code_lines "$tree/rs/crates/server-projects/src/journal.rs" | grep -qF '"origin": origin.as_str()'
}
# Whether routes.toml gives a chat's DELETE to Rust (sbstndalton/noevia#1071 slice 6): either of
# DELETE /api/freechats/{chatId} and DELETE /api/projects/{projectId}/chats/{chatId}.
rust_owns_chat_delete() {
  project_routes_rs "$1" | grep -qx -e 'DELETE /api/freechats/{}' -e 'DELETE /api/projects/{}/chats/{}' \
    -e 'ALL /api/freechats/{}' -e 'ALL /api/projects/{}/chats/{}'
}
# Explicit pairing markers (sbstndalton/noevia#2161), never source shapes: the front's internal
# store answers POST /v1/chat/delete (crates/server-projects chat_delete.rs CHAT_DELETE_STORE_MARKER),
# and the core deletes chats only through it (server/project-store-client.cjs
# CHAT_DELETE_CLIENT_MARKER).
rs_serves_chat_delete() {
  grep -rqsF --include='*.rs' -e '"noevia-chat-delete-store/1"' "$tree/rs/crates/server-projects/src"
}
core_deletes_via_store() {
  grep -qF "'noevia-chat-delete-client/1'" "$tree/core/server/project-store-client.cjs" 2>/dev/null
}
# True when the file has a line of CODE matching the extended regex: comment-only lines (`//` ones and
# `/* ... */` blocks) never count, so a marker or an op name that only a comment mentions is not one.
# Status 1 means only "read and scanned, no match" (or no such file); a failed scan is status 2, so a
# caller that needs a definite "absent" can reject anything other than 1.
# (The text is captured first: `grep -q` closing the pipe early would fail the pipeline under pipefail.)
code_has() {
  [ -f "$1" ] || return 1
  local code
  code="$(awk '
    block { if (index($0, "*/")) block = 0; next }
    { line = $0; sub(/^[ \t]+/, "", line) }
    line ~ /^\/\// { next }
    line ~ /^\/\*/ { if (!index(line, "*/")) block = 1; next }
    { print }
  ' "$1")" || return 2
  grep -qE -e "$2" <<<"$code"
}
# Slice7: exact canonical declarations + actual shorthand exports, never comment literals.
# A transitional handler must be a named exported async chatMoveRoute in its actual route module.
move_capability() {
  [ -f "$1" ] || return 1
  awk -v name="$2" -v value="$3" -v kind="$4" '
    function clean(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      line=clean($0)
      if (block) { if (index(line,"*/")) block=0; next }
      if (line ~ /^\/\//) next
      if (index(line,"/*")) { if (!index(line,"*/")) block=1; next }
      if ((kind=="features" || kind=="feature_ref") && index(line,"pub const FEATURES: &[&str] = &[")==1) { decl++; features=1; line=substr(line,length("pub const FEATURES: &[&str] = &[")+1) }
      if (features) {
        fend=index(line,"];")
        if(fend) line=substr(line,1,fend-1)
        n=split(line,fields,",")
        for(i=1;i<=n;i++) if(clean(fields[i])==(kind=="feature_ref" ? value : sprintf("%c",34) value sprintf("%c",34))) observed++
        if(fend) features=0
      }
      if (kind=="rust" && line == "pub const " name ": &str = \"" value "\";") decl++
      if (kind=="js" && line == "const " name " = " sprintf("%c",39) value sprintf("%c",39) ";") decl++
      if (kind=="function" && line ~ ("^async function " name "\\(")) decl++
      if (index(line,"module.exports = {")==1) { exporting=1; line=substr(line,length("module.exports = {")+1) }
      if (exporting) {
        ending=index(line,"}")
        if (ending) line=substr(line,1,ending-1)
        n=split(line,fields,",")
        for(i=1;i<=n;i++) if(clean(fields[i])==name) exported++
        if(ending) exporting=0
      }
    }
    END { exit !(decl==1 && (kind=="rust" || ((kind=="features" || kind=="feature_ref") && observed==1) || (kind!="features" && exported==1))) }
  ' "$1"
}
rust_owns_chat_move() {
  project_routes_rs "$1" | grep -qxF 'POST /api/chats/{}/move'
}
core_refuses_chat_move() {
  project_routes_core "$tree/core/server/rust-projects.cjs" | grep -qxF 'POST /api/chats/{}/move'
}
rs_move_foundation() { move_capability "$tree/rs/crates/server-projects/src/chat_move.rs" MOVE_MARKER noevia-chat-move-foundation/1 rust; }
rs_move_start() { move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES start-id features; }
rs_move_journal() { move_capability "$tree/rs/crates/server-projects/src/journal.rs" CHAT_MOVE_JOURNAL_MARKER noevia-chat-move-journal/1 rust; }
core_move_client() { move_capability "$tree/core/server/project-store-client.cjs" CHAT_MOVE_CLIENT_MARKER noevia-chat-move-client/1 js; }
core_move_enforcement() { move_capability "$tree/core/server/chat.cjs" CHAT_MOVE_ENFORCEMENT_MARKER noevia-chat-move-enforcement/1 js; }
core_move_reader_legacy() { move_capability "$tree/core/server/chat-change-journal.cjs" CHAT_MOVE_READER_MARKER noevia-chat-move-reader/1 js; }
# The move events are read by that legacy reader or, paired, by the front's consumer (live/recovery delivery, event identity).
core_move_reader() { core_move_reader_legacy || [ "$chat_mirror_paired" = rust ]; }
core_move_owner() { move_capability "$tree/core/server/rust-projects.cjs" CHAT_MOVE_PUBLIC_OWNER "$1" js; }
core_move_handler() { move_capability "$tree/core/server/routes/chat-lists.cjs" chatMoveRoute - function; }
# Source jobs retain the Node executor while Rust alone owns their persisted journals. A
# marker is accepted only when exported from the actual client, referenced by the compiled
# server FEATURES list, and backed by all six authenticated internal store routes.
core_source_client() {
  move_capability "$tree/core/server/project-store-client.cjs" SOURCE_JOBS_CLIENT_MARKER noevia-source-jobs-client/1 js
}
rs_source_store() {
  move_capability "$tree/rs/crates/server-projects/src/source_jobs.rs" SOURCE_JOBS_STORE_MARKER noevia-source-jobs-store/1 rust || return 1
  move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES server_projects::source_jobs::SOURCE_JOBS_STORE_MARKER feature_ref || return 1
  grep -qxF 'pub mod source_jobs;' "$tree/rs/crates/server-projects/src/lib.rs" || return 1
  grep -qF 'use server_projects::source_jobs as jobs;' "$tree/rs/bins/noevia-server/src/project_store.rs" || return 1
  local route
  for route in recover start abandon progress finish read; do
    grep -qF ".route(\"/v1/source-jobs/$route\", source_route(" "$tree/rs/bins/noevia-server/src/project_store.rs" || return 1
  done
}

# Whether the pinned front reads NOEVIA_START_ID: a Rust source under rs/bins names it, or a
# FEATURES list there carries "start-id".
rs_reads_start_id() {
  grep -rqs --include='*.rs' -e 'NOEVIA_START_ID' -e '"start-id"' "$tree/rs/bins"
}
# "<switch> <path>" for every route that carries a switch.
switched_routes() {
  routes_toml "$1" | awk -F'\t' '$3 != "-" { print $3 " " $1 }'
}
project_routes_core() {
  [ -f "$1" ] || return 0
  sed -n "/^const ${2:-OWNED_ROUTES} = /,/]))/p" "$1" | grep -o "'[A-Z]* /[^']*'" | tr -d "'" | sed 's/{[^}]*}/{}/g' | sort -u
}
# Feature authority moves as one three-namespace owner. Historic old/old pins remain
# valid rollback pairs; either mixed generation is refused before producing an archive.

feature_core_owner=""
feature_rs_owner=""
grep -qF '.createReadOnlyFeatures(' "$tree/core/server/index.cjs" 2>/dev/null && feature_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-feature-owner features; then
  feature_rs_owner=rust
fi
[ "$feature_core_owner" = "$feature_rs_owner" ] \
  || die "feature ownership pairing: Core and Rust must move together"
if [ "$feature_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "feature ownership pairing: missing route contract"
  feature_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/features" || $1 == "/api/admin/features" || $1 == "/api/admin/features/{name}" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }' | sort)" || die "feature ownership pairing: all methods must belong to Rust"
  feature_expected="$(printf '%s\n' /api/features /api/admin/features '/api/admin/features/{name}' | sort)"
  [ "$feature_routes" = "$feature_expected" ] || die "feature ownership pairing: incomplete namespace ownership"
fi
# The five proxy-only Diary routes (sbstndalton/noevia#2185) move as one owner: Core's
# rust-diary.cjs refusal and the front's rust-diary capability, all methods of all five in
# routes.toml. Historic old/old pins remain valid rollback pairs.
diary_core_owner=""
diary_rs_owner=""
grep -qF "require('./rust-diary.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && diary_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-diary features; then
  diary_rs_owner=rust
fi
[ "$diary_core_owner" = "$diary_rs_owner" ] \
  || die "Diary ownership pairing: Core and Rust must move together"
if [ "$diary_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "Diary ownership pairing: missing route contract"
  diary_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/diary/source" || $1 == "/api/diary/today" || $1 == "/api/diary/storage-import" ||
    $1 == "/api/diary/workspace-export" || $1 == "/api/diary/workspace-import" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }' | sort)" || die "Diary ownership pairing: all methods must belong to Rust"
  diary_expected="$(printf '%s\n' /api/diary/source /api/diary/today /api/diary/storage-import /api/diary/workspace-export /api/diary/workspace-import | sort)"
  [ "$diary_routes" = "$diary_expected" ] || die "Diary ownership pairing: incomplete route ownership"
fi
# The Diary local exchange moves as one owner: Core's rust-diary-local-exchange.cjs refusal (with the
# admission lease's diaryExchange ask, through which the front holds Node's model throttle and inference
# gate) and the front's rust-diary-local-exchange capability, with every method of the route Rust's in
# routes.toml. Without the pair the route stays Node's. Historic old/old pins remain valid rollback pairs.
lx_core_owner=""
lx_rs_owner=""
grep -qF "require('./rust-diary-local-exchange.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && lx_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-diary-local-exchange features; then
  lx_rs_owner=rust
fi
[ "$lx_core_owner" = "$lx_rs_owner" ] \
  || die "Diary local exchange ownership pairing: Core and Rust must move together"
lx_owner=node
if [ "$lx_rs_owner" = rust ]; then
  lx_owner=rust
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "Diary local exchange ownership pairing: missing route contract"
  lx_route="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/diary/local-exchange" { if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1; print $1 }')" \
    || die "Diary local exchange ownership pairing: every method must belong to Rust"
  [ "$lx_route" = "/api/diary/local-exchange" ] || die "Diary local exchange ownership pairing: missing route ownership"
  grep -qF "diaryExchange" "$tree/core/server/inference-admission-lease.cjs" 2>/dev/null \
    || die "Diary local exchange ownership pairing: Core's admission lease does not take the exchange"
  # The ask alone is not the throttle: index.cjs must hand the lease routes chat's throttle and the backfill pause.
  code_lines "$tree/core/server/index.cjs" | grep -qF "diaryExchange: { rateLimited:" \
    || die "Diary local exchange ownership pairing: Core's admission lease is not given the chat throttle"
fi
# The rest of the Diary routes the web client names (sbstndalton/noevia#2206) move as one owner: Core's
# rust-diary-routes.cjs refusal and the front's rust-diary-routes capability, with the methods Node
# answered Rust's in routes.toml: every method of /api/diary, /api/diary-connector and the storage
# status; GET and POST of the context, the exchanges and the connector credentials; DELETE of one
# credential. /api/diary/local-exchange is Rust's only with its own pair above (lx_owner). Core must refuse exactly those paths and be the one that keeps
# the diary_connectors table out of Node's hands. Historic old/old pins remain valid rollback pairs.
dr_core_owner=""
dr_rs_owner=""
grep -qF "require('./rust-diary-routes.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && dr_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-diary-routes features; then
  dr_rs_owner=rust
fi
[ "$dr_core_owner" = "$dr_rs_owner" ] \
  || die "Diary route ownership pairing: Core and Rust must move together"
if [ "$dr_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "Diary route ownership pairing: missing route contract"
  dr_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' -v lx="$lx_owner" '
    function want(path) {
      if (path == "/api/diary" || path == "/api/diary-connector" || path == "/api/diary/storage-status") return "ALL"
      if (path == "/api/diary/context" || path == "/api/diary/exchanges" || path == "/api/profile/diary-connectors") return "GET,POST"
      if (path == "/api/profile/diary-connectors/{*}") return "DELETE"
      return ""
    }
    $1 == "/api/diary/local-exchange" { if ($2 != lx) exit 1 }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      w = want($1)
      if (w == "ALL") { if ($4 != "-") exit 1; print $1; next }
      ne = split(w, e, ","); delete ok; for (j = 1; j <= ne; j++) ok[e[j]] = 1
      n = split($4, m, /[^A-Z]+/); k = 0; delete seen
      for (i = 1; i <= n; i++) if (m[i] != "") { if (!(m[i] in ok) || (m[i] in seen)) exit 1; seen[m[i]] = 1; k++ }
      if (k != ne) exit 1
      print $1
    }')" || die "Diary route ownership pairing: exactly the methods Node answered must belong to Rust, and the local exchange only with its own pair"
  dr_routes="$(printf '%s\n' "$dr_routes" | sort | tr '\n' ' ')"
  [ "$dr_routes" = "/api/diary /api/diary-connector /api/diary/context /api/diary/exchanges /api/diary/storage-status /api/profile/diary-connectors /api/profile/diary-connectors/{*} " ] \
    || die "Diary route ownership pairing: incomplete route ownership"
  # Core refuses exactly the paths the front answers, and keeps the credential table out of Node's hands.
  for dr_path in /api/diary /api/diary-connector /api/diary/context /api/diary/exchanges /api/diary/storage-status /api/profile/diary-connectors; do
    grep -qF "'$dr_path'" "$tree/core/server/rust-diary-routes.cjs" 2>/dev/null \
      || die "Diary route ownership pairing: Core does not refuse $dr_path"
  done
  grep -qF "rust-diary-routes.cjs" "$tree/core/server/rust-auth.cjs" 2>/dev/null \
    || die "Diary route ownership pairing: Core still lets Node write the connector table"
fi
# The two configuration-only model reads (sbstndalton/noevia#2187) move as one owner: Core's
# rust-models.cjs refusal of their GET and the front's rust-model-reads capability, with exactly
# GET of both routes Rust's in routes.toml (Node keeps every other method). Historic old/old pins
# remain valid rollback pairs.
models_core_owner=""
models_rs_owner=""
grep -qF "require('./rust-models.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && models_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-reads features; then
  models_rs_owner=rust
fi
[ "$models_core_owner" = "$models_rs_owner" ] \
  || die "model read ownership pairing: Core and Rust must move together"
if [ "$models_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "model read ownership pairing: missing route contract"
  model_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/models/capabilities" || $1 == "/api/models/hardware" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "model read ownership pairing: exactly GET of both routes must belong to Rust"
  model_expected="$(printf '%s\n' /api/models/capabilities /api/models/hardware | sort)"
  [ "$model_routes" = "$model_expected" ] || die "model read ownership pairing: incomplete route ownership"
fi
# A project source's stored reads (sbstndalton/noevia#2191) move as one owner: Core's
# rust-project-reads.cjs refusal of their GET and the front's rust-project-reads capability, with
# exactly GET of the three routes Rust's in routes.toml (Node keeps every other method and the page
# reader). Historic old/old pins remain valid rollback pairs.
project_reads_core_owner=""
project_reads_rs_owner=""
grep -qF "require('./rust-project-reads.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && project_reads_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-reads features; then
  project_reads_rs_owner=rust
fi
[ "$project_reads_core_owner" = "$project_reads_rs_owner" ] \
  || die "project source read ownership pairing: Core and Rust must move together"
if [ "$project_reads_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project source read ownership pairing: missing route contract"
  project_read_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/sources/text" || $1 == "/api/projects/{id}/documents/original" || $1 == "/api/projects/{id}/{*}/original" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "project source read ownership pairing: exactly GET of the three routes must belong to Rust"
  project_read_expected="$(printf '%s\n' '/api/projects/{id}/sources/text' '/api/projects/{id}/documents/original' '/api/projects/{id}/{*}/original' | sort)"
  [ "$project_read_routes" = "$project_read_expected" ] || die "project source read ownership pairing: incomplete route ownership"
fi
# A project's create and delete (sbstndalton/noevia#2191 round 2) move as one owner: Core's
# rust-project-lifecycle.cjs refusal and the front's rust-project-lifecycle capability, with exactly POST
# of /api/projects and DELETE of /api/projects/{projectId} Rust's in routes.toml (Node keeps every other
# method of both paths). Historic old/old pins remain valid rollback pairs.
project_lifecycle_core_owner=""
project_lifecycle_rs_owner=""
grep -qF "require('./rust-project-lifecycle.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && project_lifecycle_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-lifecycle features; then
  project_lifecycle_rs_owner=rust
fi
[ "$project_lifecycle_core_owner" = "$project_lifecycle_rs_owner" ] \
  || die "project create/delete ownership pairing: Core and Rust must move together"
if [ "$project_lifecycle_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project create/delete ownership pairing: missing route contract"
  project_lifecycle_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects" || $1 == "/api/projects/{projectId}" {
      if ($2 != "rust" || $3 != "-") exit 1
      want = ($1 == "/api/projects") ? "POST" : "DELETE"
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "project create/delete ownership pairing: exactly POST /api/projects and DELETE /api/projects/{projectId} must belong to Rust"
  project_lifecycle_expected="$(printf '%s\n' '/api/projects' '/api/projects/{projectId}' | sort)"
  [ "$project_lifecycle_routes" = "$project_lifecycle_expected" ] || die "project create/delete ownership pairing: incomplete route ownership"
fi
# A project's storage writes (sbstndalton/noevia#2191 round 3) move as one owner: Core's
# rust-project-storage.cjs job-kind split (required by index.cjs) and the front's rust-project-storage
# capability. No route moves with it; it builds on the create/delete pair, which must be Rust's too.
project_storage_core_owner=""
project_storage_rs_owner=""
grep -qF "require('./rust-project-storage.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && project_storage_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-storage features; then
  project_storage_rs_owner=rust
fi
[ "$project_storage_core_owner" = "$project_storage_rs_owner" ] \
  || die "project storage write ownership pairing: Core and Rust must move together"
if [ "$project_storage_rs_owner" = rust ] && [ "$project_lifecycle_rs_owner" != rust ]; then
  die "project storage write ownership pairing: needs the project create/delete pair"
fi
# A project source file's delete (sbstndalton/noevia#2191 round 3) moves as one owner: Core's
# rust-project-files.cjs refusal and the front's rust-project-files capability, with exactly DELETE of
# /api/projects/{id}/files Rust's in routes.toml. It deletes through the front's storage writes, so it
# needs the project storage pair too.
project_files_core_owner=""
project_files_rs_owner=""
grep -qF "require('./rust-project-files.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && project_files_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-files features; then
  project_files_rs_owner=rust
fi
[ "$project_files_core_owner" = "$project_files_rs_owner" ] \
  || die "project file delete ownership pairing: Core and Rust must move together"
if [ "$project_files_rs_owner" = rust ]; then
  [ "$project_storage_rs_owner" = rust ] || die "project file delete ownership pairing: needs the project storage pair"
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project file delete ownership pairing: missing route contract"
  project_files_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/files" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "DELETE") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "project file delete ownership pairing: exactly DELETE /api/projects/{id}/files must belong to Rust"
  [ "$project_files_routes" = "/api/projects/{id}/files" ] || die "project file delete ownership pairing: incomplete route ownership"
fi
# A project's configuration, its instruction skills and a published skill's install (sbstndalton/noevia#2191
# round 9) move as one owner: Core's rust-project-config.cjs refusal and the front's rust-project-config
# capability, with exactly the methods Node answered Rust's in routes.toml (POST config; GET and PUT
# instruction-skills; GET manifests and a manifest's content; POST install). Who owns the Code and Browser
# reads is the task read pairing's to check, below. Core must refuse exactly those six, keep no
# project route mount (server/routes/projects.cjs is gone), and publish every toolbox it knows for the front's
# manifests. Historic old/old pins remain valid rollback pairs; either mixed generation is refused.
pc_core_owner=""
pc_rs_owner=""
grep -qF "require('./rust-project-config.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && pc_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-config features; then
  pc_rs_owner=rust
fi
[ "$pc_core_owner" = "$pc_rs_owner" ] \
  || die "project configuration ownership pairing: Core and Rust must move together"
if [ "$pc_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project configuration ownership pairing: missing route contract"
  pc_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/projects/{projectId}/config") return "POST"
      if (path == "/api/projects/{projectId}/instruction-skills") return "GET,PUT"
      if (path == "/api/projects/{projectId}/instruction-skills/manifests") return "GET"
      if (path == "/api/projects/{projectId}/instruction-skills/manifests/{skillId}/content") return "GET"
      if (path == "/api/projects/{project}/skills/install") return "POST"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-" || $4 == "-") exit 1
      w = want($1)
      ne = split(w, e, ","); delete ok; for (j = 1; j <= ne; j++) ok[e[j]] = 1
      n = split($4, m, /[^A-Z]+/); k = 0; delete seen
      for (i = 1; i <= n; i++) if (m[i] != "") { if (!(m[i] in ok) || (m[i] in seen)) exit 1; seen[m[i]] = 1; k++ }
      if (k != ne) exit 1
      print $1
    }')" || die "project configuration ownership pairing: exactly the methods Node answered must belong to Rust"
  pc_routes="$(printf '%s\n' "$pc_routes" | sort | tr '\n' ' ')"
  pc_expected="$(printf '%s\n' /api/projects/{project}/skills/install /api/projects/{projectId}/config /api/projects/{projectId}/instruction-skills /api/projects/{projectId}/instruction-skills/manifests '/api/projects/{projectId}/instruction-skills/manifests/{skillId}/content' | sort | tr '\n' ' ')"
  [ "$pc_routes" = "$pc_expected" ] || die "project configuration ownership pairing: incomplete route ownership"
  pc_refused="$( { project_routes_core "$tree/core/server/rust-project-config.cjs" || true; } | sort | tr '\n' ' ')"
  pc_refused_expected="$(printf '%s\n' 'GET /api/projects/{}/instruction-skills' 'GET /api/projects/{}/instruction-skills/manifests' 'GET /api/projects/{}/instruction-skills/manifests/{}/content' 'POST /api/projects/{}/config' 'POST /api/projects/{}/skills/install' 'PUT /api/projects/{}/instruction-skills' | sort | tr '\n' ' ')"
  [ "$pc_refused" = "$pc_refused_expected" ] \
    || die "project configuration ownership pairing: Core must refuse exactly the six routes the front answers"
  { [ ! -e "$tree/core/server/routes/projects.cjs" ] && ! grep -qF "routes/projects.cjs" "$tree/core/server/index.cjs" 2>/dev/null; } \
    || die "project configuration ownership pairing: Core still mounts the project routes"
  grep -qF "known: allToolboxes()" "$tree/core/server/index.cjs" 2>/dev/null \
    || die "project configuration ownership pairing: Core does not publish the toolbox ids the front validates skills against"
fi
# Deep research (sbstndalton/noevia#2218) moves as one owner: Core's rust-research.cjs refusal and the front's
# rust-research capability, with all five paths Rust's for every method, as Node's matcher took them. Core must have
# dropped its handlers and offer the front its admission lease and tool bridge. Historic old/old pins remain valid
# rollback pairs (the journal stays readable by both); either mixed generation is refused.
rr_core_owner=""
rr_rs_owner=""
grep -qF "require('./rust-research.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && rr_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-research features; then
  rr_rs_owner=rust
fi
[ "$rr_core_owner" = "$rr_rs_owner" ] \
  || die "deep research ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # An unreadable table is the route-table check's to report, below.
  rr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || rr_table=""
  rr_routes="$(printf '%s\n' "$rr_table" | awk -F'\t' -v want="$rr_rs_owner" '
    $1 ~ /^\/api\/projects\/\{projectId\}\/research(\/plan|\/\{job\}(\/cancel|\/save)?)?$/ {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "deep research ownership pairing: its routes must be Rust's for every method with the new pair, and Node's with the old"
  if [ "$rr_rs_owner" = rust ]; then
    [ "$(printf '%s\n' "$rr_routes" | sort -u | wc -l | tr -d ' ')" = 5 ] || die "deep research ownership pairing: incomplete route ownership"
    rr_refused="$( { project_routes_core "$tree/core/server/rust-research.cjs" || true; } | sort | tr '\n' ' ')"
    rr_refused_expected="$(printf '%s\n' 'ALL /api/projects/{}/research' 'ALL /api/projects/{}/research/plan' 'ALL /api/projects/{}/research/{}' 'ALL /api/projects/{}/research/{}/cancel' 'ALL /api/projects/{}/research/{}/save' | sort | tr '\n' ' ')"
    [ "$rr_refused" = "$rr_refused_expected" ] \
      || die "deep research ownership pairing: Core must refuse exactly the five paths the front answers"
    { [ ! -e "$tree/core/server/routes/research.cjs" ] && [ ! -e "$tree/core/server/research-service.cjs" ]; } \
      || die "deep research ownership pairing: Core still carries the research handlers"
    { [ -f "$tree/core/server/inference-admission-lease.cjs" ] && [ -f "$tree/core/server/rust-research-bridge.cjs" ]; } \
      || die "deep research ownership pairing: Core does not offer the front its admission lease and tool bridge"
    # The files are not the feature: index.cjs must mount both, and hand both the front's secret. Core's project-store
    # client deletes NOEVIA_PROJECT_STORE_TOKEN from process.env when it is built, so a secret read after that is
    # empty and every call from the front is a 404 (review H1 of #2218). The secret has to be captured in a constant
    # before clientFromEnv runs, never read from the environment after it, and passed to both constructors.
    rr_index="$(code_lines "$tree/core/server/index.cjs")"
    grep -qE 'inferenceAdmission\.handle\(req, res\)' <<<"$rr_index" \
      || die "deep research ownership pairing: Core does not mount the admission lease route"
    grep -qE 'researchBridge\(req, res\)' <<<"$rr_index" \
      || die "deep research ownership pairing: Core does not mount the research bridge"
    rr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$rr_index" | head -1)"
    [ -n "$rr_secret" ] \
      || die "deep research ownership pairing: Core does not capture the front's secret before its project-store client deletes it"
    awk -v c="$rr_secret" '
      /clientFromEnv\(/ && !cut { cut = NR }
      index($0, "const " c " = String(process.env.NOEVIA_PROJECT_STORE_TOKEN") && !cap { cap = NR; next }
      /process\.env\.NOEVIA_PROJECT_STORE_TOKEN/ && cut && NR > cut { late = 1 }
      /createAdmissionRoutes\(\{/ { adm = NR }
      /createResearchBridge\(\{/ { bridge = NR }
      index($0, "secret: " c) {
        if (adm && NR - adm <= 3) admok = 1
        if (bridge && NR - bridge <= 3) bridgeok = 1
      }
      END { exit !(cap && cut && cap < cut && !late && admok && bridgeok) }
    ' <<<"$rr_index" \
      || die "deep research ownership pairing: Core does not hand its admission lease and research bridge the front's secret (captured before clientFromEnv, never read from process.env after it)"
  fi
fi
# The Code and Browser task reads (sbstndalton/noevia#2257) move as one owner: Core's rust-task-reads.cjs refusal and
# the front's rust-task-reads capability, with the active list Rust's for every method and the four project reads
# for GET only (the POSTs and supervision stay Node's). Core must have dropped the read branches and hand the front
# its facts on the loopback check, with the secret captured as for research. Old/old remains a valid rollback pair
# (Node stays the journals' only writer either way); either mixed generation is refused.
tr_core_owner=""
tr_rs_owner=""
grep -qF "require('./rust-task-reads.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && tr_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-task-reads features; then
  tr_rs_owner=rust
fi
[ "$tr_core_owner" = "$tr_rs_owner" ] \
  || die "task read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # An unreadable table is the route-table check's to report, below.
  tr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || tr_table=""
  tr_routes="$(printf '%s\n' "$tr_table" | awk -F'\t' -v want="$tr_rs_owner" '
    $1 == "/api/code/active" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }
    $1 ~ /^\/api\/projects\/\{projectId\}\/(code|browser)(\/\{task\})?$/ {
      if (want == "rust") {
        if ($2 != "rust" || $3 != "-") exit 1
        n = split($4, m, /[^A-Z]+/); k = 0
        for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
        if (k != 1) exit 1
      }
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "task read ownership pairing: the active list must be Rust's whole and the four project reads Rust's for GET alone with the new pair, and Node's with the old"
  if [ "$tr_rs_owner" = rust ]; then
    [ "$(printf '%s\n' "$tr_routes" | sort -u | wc -l | tr -d ' ')" = 5 ] || die "task read ownership pairing: incomplete route ownership"
    tr_refused="$( { project_routes_core "$tree/core/server/rust-task-reads.cjs" || true; } | sort | tr '\n' ' ')"
    tr_refused_expected="$(printf '%s\n' 'ALL /api/code/active' 'GET /api/projects/{}/code' 'GET /api/projects/{}/code/{}' 'GET /api/projects/{}/browser' 'GET /api/projects/{}/browser/{}' | sort | tr '\n' ' ')"
    [ "$tr_refused" = "$tr_refused_expected" ] \
      || die "task read ownership pairing: Core must refuse exactly the five reads the front answers"
    for tr_file in routes/code.cjs routes/browser.cjs; do
      ! grep -qE 'service\.(list|listActive|get)\(' "$tree/core/server/$tr_file" 2>/dev/null \
        || die "task read ownership pairing: Core still carries the task read handlers"
    done
    [ -f "$tree/core/server/rust-task-facts.cjs" ] \
      || die "task read ownership pairing: Core does not offer the front its task facts"
    tr_index="$(code_lines "$tree/core/server/index.cjs")"
    grep -qE 'taskFactsBridge\(req, res\)' <<<"$tr_index" \
      || die "task read ownership pairing: Core does not mount the task facts bridge"
    tr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$tr_index" | head -1)"
    [ -n "$tr_secret" ] && awk -v c="$tr_secret" '
      /createTaskFactsBridge\(\{/ { bridge = NR }
      index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
      END { exit !ok }
    ' <<<"$tr_index" \
      || die "task read ownership pairing: Core does not hand its task facts bridge the front's captured secret"
  fi
fi
# #2304: only the exact GET child moves; all other manager operations remain Node's.
mm_scan_core=""; mm_scan_rs=""
grep -qF "require('./rust-model-manager-scan.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && mm_scan_core=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-manager-scan features; then mm_scan_rs=rust; fi
[ "$mm_scan_core" = "$mm_scan_rs" ] || die "model scan read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  mm_scan_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || mm_scan_table=""
  mm_scan_rows="$(printf '%s\n' "$mm_scan_table" | awk -F'\t' -v want="$mm_scan_rs" '
    $1 == "/api/model-manager/models" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "model scan read ownership pairing: only GET belongs to the paired owner"
fi
if [ "$mm_scan_rs" = rust ]; then
  [ "${mm_scan_rows:-}" = /api/model-manager/models ] || die "model scan read ownership pairing: incomplete route ownership"
  # The pinned Core declares its scan route as 'GET ' plus a file-local PATH.
  # Match that declaration as a whole so extra methods cannot pass as a GET-only marker.
  awk -v quote="'" -v path=/api/model-manager/models '
    block { if (index($0, "*/")) block = 0; next }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*\/\*/ { if (!index($0, "*/")) block = 1; next }
    /^const PATH = / {
      paths++
      correct_path = ($0 == "const PATH = " quote path quote ";")
    }
    /^const OWNED_ROUTES = / {
      markers++
      literal = ($0 == "const OWNED_ROUTES = Object.freeze(new Set([" quote "GET " path quote "]));")
      from_path = ($0 == "const OWNED_ROUTES = Object.freeze(new Set([" quote "GET " quote "+PATH]));")
    }
    END { exit !(markers == 1 && (literal || (from_path && paths == 1 && correct_path))) }
  ' "$tree/core/server/rust-model-manager-scan.cjs" \
    || die "model scan read ownership pairing: Core must refuse exactly this GET"
  ! code_has "$tree/core/server/routes/models.cjs" 'X-Model-Scan|scanGeneration' || die "model scan read ownership pairing: Core still carries the public cache policy"
  for primitive in 'modelScanCache[.]snapshot\(\)' 'modelScanCache[.]publish\(body,token\)' 'modelScanCache[.]refresh\(token\)'; do
    code_has "$tree/core/server/models.cjs" "$primitive" || die "model scan read ownership pairing: existing shared cache primitives required"
  done
  [ -f "$tree/core/server/rust-model-manager-scan-cache.cjs" ] || die "model scan read ownership pairing: missing cache bridge"
  mm_scan_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'modelManagerScanCache(req, res)' <<<"$mm_scan_index" || die "model scan read ownership pairing: missing cache bridge mount"
  mm_scan_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$mm_scan_index" | head -1)"
  [ -n "$mm_scan_secret" ] && awk -v c="$mm_scan_secret" '
    /createModelManagerScanCache\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$mm_scan_index" || die "model scan read ownership pairing: cache bridge needs the front captured secret"
fi
# Row V: the front is the only issuer of the code-sandbox egress proxy's control key and signed task
# grants (rs code_egress.rs, FEATURES "rust-code-egress-issuer"). The paired Core is a fail-closed client of
# it (server/code-egress-client.cjs CODE_EGRESS_CLIENT_MARKER) and carries no Node issuer. A Core that still
# publishes the key and signs grants beside a front that does the same would race over the one key file;
# a client Core beside a front without the issuer could never get a grant. Markers are code lines, never
# comments (a comment-only mention counts for nothing).
ce_core_owner=""; ce_rs_owner=""
code_has "$tree/core/server/code-egress-client.cjs" "^const CODE_EGRESS_CLIENT_MARKER = 'noevia-code-egress-client/1';" && ce_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-code-egress-issuer features; then ce_rs_owner=rust; fi
[ "$ce_core_owner" = "$ce_rs_owner" ] || die "code egress issuer pairing: Core ('noevia-code-egress-client/1') and Rust ('rust-code-egress-issuer') must move together"
if [ "$ce_core_owner" = rust ]; then
  [ ! -e "$tree/core/server/code-egress-control.cjs" ] || die "code egress issuer pairing: Core still carries the Node issuer (server/code-egress-control.cjs)"
  ! code_has "$tree/core/server/code-egress.cjs" 'publishWebKey|createKeyKeeper|createControlClient|mintGrant|secrets[.]derive' \
    || die "code egress issuer pairing: Core still publishes keys or signs grants"
  code_has "$tree/core/server/code-egress.cjs" "require\\('[.]/code-egress-client[.]cjs'\\)" \
    || die "code egress issuer pairing: Core's egress setup does not use the native client"
fi
# #2292: calibration cancellation policy is native, with only facts and the conditional state writer in Core.
cc_core_owner=""; cc_rs_owner=""
grep -qF "require('./rust-calibration-cancel.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && cc_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-calibration-cancel features; then cc_rs_owner=rust; fi
[ "$cc_core_owner" = "$cc_rs_owner" ] || die "calibration cancellation ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  cc_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || cc_table=""
  cc_rows="$(printf '%s\n' "$cc_table" | awk -F'\t' -v want="$cc_rs_owner" '
    $1 == "/api/models/calibration/cancel" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "calibration cancellation ownership pairing: all methods must belong to the paired owner"
fi
if [ "$cc_rs_owner" = rust ]; then
  [ "${cc_rows:-}" = /api/models/calibration/cancel ] || die "calibration cancellation ownership pairing: incomplete route ownership"
  cc_refused="$( { project_routes_core "$tree/core/server/rust-calibration-cancel.cjs" || true; } | tr '\n' ' ')"
  [ "$cc_refused" = 'ALL /api/models/calibration/cancel ' ] || die "calibration cancellation ownership pairing: Core must refuse exactly the cancellation path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/calibration/cancel' \
    || die "calibration cancellation ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-calibration.cjs" '(^|[^A-Za-z0-9_$])function[[:space:]]+cancel[[:space:]]*\(' \
    || die "calibration cancellation ownership pairing: Core still carries the public cancellation policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'cancellationFacts: calibrator.cancellationFacts' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'compareAndAbort: calibrator.compareAndAbort' \
    || die "calibration cancellation ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-calibration-cancel-bridge.cjs" ] || die "calibration cancellation ownership pairing: missing state bridge"
  cc_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'calibrationCancelBridge(req, res)' <<<"$cc_index" || die "calibration cancellation ownership pairing: missing state bridge mount"
  cc_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$cc_index" | head -1)"
  [ -n "$cc_secret" ] && awk -v c="$cc_secret" '
    /createCalibrationCancelBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$cc_index" || die "calibration cancellation ownership pairing: state bridge needs the front captured secret"
fi
# #2303: calibration start/read policy is native, with only facts and the conditional state writer in Core.
cr_core_owner=""; cr_rs_owner=""
grep -qF "require('./rust-calibration-routes.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && cr_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-calibration-routes features; then cr_rs_owner=rust; fi
[ "$cr_core_owner" = "$cr_rs_owner" ] || die "calibration start/read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  cr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || cr_table=""
  cr_rows="$(printf '%s\n' "$cr_table" | awk -F'\t' -v want="$cr_rs_owner" '
    $1 == "/api/models/calibration" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "calibration start/read ownership pairing: all methods must belong to the paired owner"
fi
if [ "$cr_rs_owner" = rust ]; then
  [ "${cr_rows:-}" = /api/models/calibration ] || die "calibration start/read ownership pairing: incomplete route ownership"
  cr_refused="$( { project_routes_core "$tree/core/server/rust-calibration-routes.cjs" || true; } | tr '\n' ' ')"
  [ "$cr_refused" = 'ALL /api/models/calibration ' ] || die "calibration start/read ownership pairing: Core must refuse exactly the calibration path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/calibration' \
    || die "calibration start/read ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-calibration.cjs" '(async[[:space:]]+)?function[[:space:]]+(start|status)[[:space:]]*\(' \
    || die "calibration start/read ownership pairing: Core still carries the public start/status policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'stateFacts:[[:space:]]*calibrator[.]stateFacts[[:space:]]*[,}]' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'listingFacts:[[:space:]]*calibrator[.]listingFacts[[:space:]]*[,}]' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'preparationFacts:[[:space:]]*calibrator[.]preparationFacts[[:space:]]*[,}]' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'compareAndLaunch:[[:space:]]*calibrator[.]compareAndLaunch[[:space:]]*[,}]' \
    || die "calibration start/read ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-calibration-routes-bridge.cjs" ] || die "calibration start/read ownership pairing: missing state bridge"
  cr_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'calibrationRoutesBridge(req, res)' <<<"$cr_index" || die "calibration start/read ownership pairing: missing state bridge mount"
  cr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$cr_index" | head -1)"
  [ -n "$cr_secret" ] && awk -v c="$cr_secret" '
    /createCalibrationRoutesBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$cr_index" || die "calibration start/read ownership pairing: state bridge needs the front captured secret"
fi
# Diary backup must move as a pair: new front + old Core would run two loops.
db_core_owner=""; db_rs_owner=""
move_capability "$tree/core/server/rust-diary.cjs" DIARY_BACKUP_WORKER_OWNER noevia-diary-backup-worker-rust/1 js && db_core_owner=rust
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-diary-backup-worker features && db_rs_owner=rust
[ "$db_core_owner" = "$db_rs_owner" ] || die "diary backup worker pairing: Core and Rust must move together"
if [ "$db_rs_owner" = rust ]; then
  ! code_has "$tree/core/server/index.cjs" 'startDiaryBackupWorker' || die "diary backup worker pairing: Core still starts the worker"
  grep -qF 'DIARY_BACKUP_WORKER_OWNER' "$tree/noevia/build/web-supervisor.sh" && grep -qF 'rust-diary-backup-worker' "$tree/noevia/build/web-supervisor.sh" || die "diary backup worker pairing: supervisor guard missing"
fi

# The memory watchdog moves as one owner; mixed pairs double-run it or leave no watch.
bw_core_owner=""; bw_rs_owner=""
move_capability "$tree/core/server/rust-budget-watch.cjs" BUDGET_WATCH_OWNER noevia-budget-watch-rust/1 js && bw_core_owner=v1
move_capability "$tree/core/server/rust-budget-watch.cjs" BUDGET_WATCH_OWNER noevia-budget-watch-rust/2 js && bw_core_owner=v2
move_capability "$tree/core/server/rust-budget-watch.cjs" BUDGET_WATCH_OWNER noevia-budget-watch-rust/3 js && bw_core_owner=v3
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-budget-watch features && bw_rs_owner=v1
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-budget-watch-v2 features && bw_rs_owner=v2
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-budget-watch-v3 features && bw_rs_owner=v3
[ "$bw_core_owner" = "$bw_rs_owner" ] \
  || die "budget watch pairing: Core and Rust must move the watchdog together"
if [ -n "$bw_rs_owner" ]; then
  grep -qF 'BUDGET_WATCH_OWNER' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
    && grep -qF 'rust-budget-watch' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
    || die "budget watch pairing: web supervisor lacks a prelaunch capability comparison"
fi

# #2303 (worker): the calibration job itself (its state file, boot recovery and hold) moves with explicit
# markers, never source shapes: Core exports CALIBRATION_WORKER_OWNER from rust-calibration-routes.cjs, the
# front lists the worker in --features. A mixed pair recovers one state file twice at a joint restart (new
# front, old Core) or never (old front, new Core), so either half alone is refused. That a marked Core builds
# no public calibrator, recovers nothing at boot and hands the front its load decision is Core CI's to prove,
# by booting index.cjs (noevia-core server/native-calibration-boot-2303.test.cjs), not this script's to guess
# from source text. Generation 2 (noevia-calibration-worker-rust/2, rust-calibration-worker-v2): every load the
# job asks for is first decided by Core's overBudget() (POST /internal/model-maintenance/load-refusal).
# Generations pair only with themselves, and generation 1 (no load decision: quarantined or over-budget
# profiles reached the engine) is refused outright; no release ever shipped it.
cw_core_gen=""; cw_rs_gen=""
move_capability "$tree/core/server/rust-calibration-routes.cjs" CALIBRATION_WORKER_OWNER noevia-calibration-worker-rust/1 js && cw_core_gen=1
move_capability "$tree/core/server/rust-calibration-routes.cjs" CALIBRATION_WORKER_OWNER noevia-calibration-worker-rust/2 js && cw_core_gen=2
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-calibration-worker features && cw_rs_gen=1
move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-calibration-worker-v2 features && cw_rs_gen=2
[ "$cw_core_gen" = "$cw_rs_gen" ] \
  || die "calibration worker pairing: Core (generation ${cw_core_gen:-none}) and Rust (generation ${cw_rs_gen:-none}) must move the calibration job together, at one generation"
[ "$cw_rs_gen" != 1 ] \
  || die "calibration worker pairing: generation 1 sends calibration loads without Core's load decision; pair noevia-calibration-worker-rust/2 with rust-calibration-worker-v2"
if [ -n "$cw_rs_gen" ]; then
  [ "$cr_rs_owner" = rust ] && [ "$cc_rs_owner" = rust ] \
    || die "calibration worker pairing: the native worker needs the native start/read and cancellation routes"
  grep -qF 'noevia-calibration-worker-rust/2' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
    && grep -qF 'rust-calibration-worker-v2' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
    || die "calibration worker pairing: web supervisor lacks a prelaunch capability comparison"
fi
# #2287: auto-tune settings policy is native, with only facts and the conditional state writer in Core.
ats_core_owner=""; ats_rs_owner=""
grep -qF "require('./rust-autotune-settings.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && ats_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-settings features; then ats_rs_owner=rust; fi
[ "$ats_core_owner" = "$ats_rs_owner" ] || die "auto-tune settings ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  ats_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || ats_table=""
  ats_rows="$(printf '%s\n' "$ats_table" | awk -F'\t' -v want="$ats_rs_owner" '
    $1 == "/api/models/autotune/settings" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "auto-tune settings ownership pairing: all methods must belong to the paired owner"
fi
if [ "$ats_rs_owner" = rust ]; then
  [ "${ats_rows:-}" = /api/models/autotune/settings ] || die "auto-tune settings ownership pairing: incomplete route ownership"
  ats_refused="$( { project_routes_core "$tree/core/server/rust-autotune-settings.cjs" || true; } | tr '\n' ' ')"
  [ "$ats_refused" = 'ALL /api/models/autotune/settings ' ] || die "auto-tune settings ownership pairing: Core must refuse exactly the settings path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/autotune/settings' \
    || die "auto-tune settings ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" 'function setSettings' \
    || die "auto-tune settings ownership pairing: Core still carries the public settings policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'settingsFacts: autotuner.settingsFacts' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'commitSettings: autotuner.commitSettings' \
    || die "auto-tune settings ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-autotune-settings-bridge.cjs" ] || die "auto-tune settings ownership pairing: missing state bridge"
  ats_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneSettingsBridge(req, res)' <<<"$ats_index" || die "auto-tune settings ownership pairing: missing state bridge mount"
  ats_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$ats_index" | head -1)"
  [ -n "$ats_secret" ] && awk -v c="$ats_secret" '
    /createAutotuneSettingsBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$ats_index" || die "auto-tune settings ownership pairing: state bridge needs the front captured secret"
fi
# Approval decisions (#2282): Rust owns public policy; Core keeps only the trusted pending-Promise bridge.
ta_core_owner=""
ta_rs_owner=""
grep -qF "require('./rust-tool-approvals.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && ta_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-tool-approvals features; then ta_rs_owner=rust; fi
[ "$ta_core_owner" = "$ta_rs_owner" ] || die "tool approval ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  ta_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || ta_table=""
  ta_rows="$(printf '%s\n' "$ta_table" | awk -F'\t' -v want="$ta_rs_owner" '
    $1 == "/api/tool-approvals/{approvalId}" {
      if (want == "rust") {
        if ($2 != "rust" || $3 != "-") exit 1
        n=split($4,m,/[^A-Z]+/); k=0
        for(i=1;i<=n;i++) if(m[i]!="") { if(m[i]!="POST") exit 1; k++ }
        if(k!=1) exit 1
      } else if ($2 != "node") exit 1
      print $1
    }')" || die "tool approval ownership pairing: POST alone must be Rust's with the new pair and Node's with the old"
  if [ "$ta_rs_owner" = rust ]; then
    [ "$(printf '%s\n' "$ta_rows" | wc -w | tr -d ' ')" = 1 ] || die "tool approval ownership pairing: missing route"
    ta_refused="$( { project_routes_core "$tree/core/server/rust-tool-approvals.cjs" || true; } | sort | tr '\n' ' ')"
    [ "$ta_refused" = 'POST /api/tool-approvals/{} ' ] || die "tool approval ownership pairing: Core must refuse exactly the approval POST"
    [ ! -f "$tree/core/server/routes/approvals.cjs" ] || die "tool approval ownership pairing: Core still carries the public handler"
    [ -f "$tree/core/server/rust-tool-approval-bridge.cjs" ] || die "tool approval ownership pairing: missing pending state bridge"
    ta_index="$(code_lines "$tree/core/server/index.cjs")"
    grep -qE 'toolApprovalBridge\(req, res\)' <<<"$ta_index" || die "tool approval ownership pairing: missing bridge mount"
    ta_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$ta_index" | head -1)"
    [ -n "$ta_secret" ] && awk -v c="$ta_secret" '
      /createToolApprovalBridge\(\{/ { bridge = NR }
      index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
      END { exit !ok }
    ' <<<"$ta_index" || die "tool approval ownership pairing: missing captured front secret"
  fi
fi
# Chat port S4: the framing suggestion. The front owns every method of exactly /api/chat-framing/suggest
# (capability rust-chat-framing-suggest); Core refuses exactly its POST (server/rust-chat-framing-suggest.cjs),
# no longer makes a suggestion in routes/chat-framing.cjs, and serves the front's loopback
# /internal/chat-framing/suggest with the captured front secret. Old/old stays valid; mixed pairs are refused.
fs_core_owner=""; fs_rs_owner=""
grep -qF "require('./rust-chat-framing-suggest.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && fs_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-chat-framing-suggest features; then fs_rs_owner=rust; fi
[ "$fs_core_owner" = "$fs_rs_owner" ] || die "framing suggestion ownership pairing: Core and Rust must move together"
if [ "$fs_rs_owner" != rust ] && [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # The old pair: Node answers the suggestion, so the route table must not give it to Rust.
  fs_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || fs_table=""
  printf '%s\n' "$fs_table" | awk -F'\t' '$1 == "/api/chat-framing/suggest" && $2 == "rust" { bad = 1 } END { exit bad }' \
    || die "framing suggestion ownership pairing: an old pair cannot give the suggestion to Rust"
fi
if [ "$fs_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "framing suggestion ownership pairing: missing route contract"
  fs_rows="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/chat-framing/suggest" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "framing suggestion ownership pairing: every method must belong to Rust"
  [ "$fs_rows" = /api/chat-framing/suggest ] || die "framing suggestion ownership pairing: incomplete route ownership"
  code_has "$tree/core/server/rust-chat-framing-suggest.cjs" "^const OWNED_ROUTES = Object[.]freeze[(]new Set[(][[]'POST /api/chat-framing/suggest'[]][)][)];$" \
    || die "framing suggestion ownership pairing: Core must refuse exactly this POST"
  ! code_has "$tree/core/server/routes/chat-framing.cjs" 'framing[.]suggest[(]' \
    || die "framing suggestion ownership pairing: Core still carries the public suggestion handler"
  fs_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qE 'chatFramingSuggestBridge\(req, res\)' <<<"$fs_index" || die "framing suggestion ownership pairing: missing bridge mount"
  fs_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$fs_index" | head -1)"
  [ -n "$fs_secret" ] && awk -v c="$fs_secret" '
    /createSuggestBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$fs_index" || die "framing suggestion ownership pairing: missing captured front secret"
fi
# #2281: the toolbox picker moves as one owner, with only raw discovery/prefill facts in Core.
tp_core_owner=""; tp_rs_owner=""
grep -qF "require('./rust-toolbox-picker.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && tp_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-toolbox-picker features; then tp_rs_owner=rust; fi
[ "$tp_core_owner" = "$tp_rs_owner" ] || die "toolbox picker ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  tp_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || tp_table=""
  tp_rows="$(printf '%s\n' "$tp_table" | awk -F'\t' -v want="$tp_rs_owner" '
    $1 == "/api/toolboxes" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "toolbox picker ownership pairing: all methods must belong to the paired owner"
fi
if [ "$tp_rs_owner" = rust ]; then
  [ "${tp_rows:-}" = /api/toolboxes ] || die "toolbox picker ownership pairing: incomplete route ownership"
  tp_refused="$( { project_routes_core "$tree/core/server/rust-toolbox-picker.cjs" || true; } | tr '\n' ' ')"
  [ "$tp_refused" = 'ALL /api/toolboxes ' ] || die "toolbox picker ownership pairing: Core must refuse exactly the picker"
  [ ! -f "$tree/core/server/routes/toolboxes.cjs" ] && [ ! -f "$tree/core/server/mcp-status.cjs" ] \
    || die "toolbox picker ownership pairing: Core still carries the public handler or status composition"
  ! code_has "$tree/core/server/toolboxes.cjs" 'function toolboxSummaries' \
    || die "toolbox picker ownership pairing: Core still carries picker summary composition"
  [ -f "$tree/core/server/rust-toolbox-picker-facts.cjs" ] || die "toolbox picker ownership pairing: missing raw facts bridge"
  tp_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'toolboxPickerFacts(req, res)' <<<"$tp_index" || die "toolbox picker ownership pairing: missing facts mount"
  tp_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$tp_index" | head -1)"
  [ -n "$tp_secret" ] && awk -v c="$tp_secret" '
    /createToolboxPickerFacts\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$tp_index" || die "toolbox picker ownership pairing: facts bridge needs the front captured secret"
fi
# #2306: only GET status moves; POST start and all other verbs remain Node-owned.
atr_core_owner=""; atr_rs_owner=""
grep -qF "require('./rust-autotune-read.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && atr_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-read features; then atr_rs_owner=rust; fi
[ "$atr_core_owner" = "$atr_rs_owner" ] || die "auto-tune read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  atr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || atr_table=""
  atr_rows="$(printf '%s\n' "$atr_table" | awk -F'\t' -v want="$atr_rs_owner" '
    $1 == "/api/models/autotune" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "auto-tune read ownership pairing: GET only; POST start and other methods stay Node"
fi
if [ "$atr_rs_owner" = rust ]; then
  [ "${atr_rows:-}" = /api/models/autotune ] || die "auto-tune read ownership pairing: incomplete route ownership"
  atr_refused="$( { project_routes_core "$tree/core/server/rust-autotune-read.cjs" || true; } | tr '\n' ' ')"
  [ "$atr_refused" = 'GET /api/models/autotune ' ] || die "auto-tune read ownership pairing: Core must refuse exactly GET status"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" '(^|[^[:alnum:]_$])const[[:space:]]+status[[:space:]]*=[[:space:]]*(model|[(][[:space:]]*model[[:space:]]*[)])[[:space:]]*=>' \
    || die "auto-tune read ownership pairing: Core still carries the public status formatter"
  ! code_has "$tree/core/server/routes/models.cjs" 'modelManager[.]autotune[.]status[[:space:]]*[(]' \
    || die "auto-tune read ownership pairing: Core still carries the public GET handler"
  code_has "$tree/core/server/routes/models.cjs" 'modelManager[.]autotune[.]start[[:space:]]*[(]' \
    || die "auto-tune read ownership pairing: POST start must stay Node-owned"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'statusFacts: autotuner.statusFacts' \
    || die "auto-tune read ownership pairing: Core does not expose raw status facts"
  [ -f "$tree/core/server/rust-autotune-read-bridge.cjs" ] || die "auto-tune read ownership pairing: missing facts bridge"
  atr_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneReadBridge(req, res)' <<<"$atr_index" || die "auto-tune read ownership pairing: missing facts bridge mount"
  atr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$atr_index" | head -1)"
  [ -n "$atr_secret" ] && awk -v c="$atr_secret" '
    /createAutotuneReadBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$atr_index" || die "auto-tune read ownership pairing: facts bridge needs the front captured secret"
fi
# #1863: only the idle timer GET moves. The setting writer and reload baseline stay in Core.
iur_core_owner=""; iur_rs_owner=""
grep -qF "require('./rust-idle-unload-read.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && iur_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-idle-unload-read features; then iur_rs_owner=rust; fi
[ "$iur_core_owner" = "$iur_rs_owner" ] || die "idle unload read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  iur_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || iur_table=""
  iur_rows="$(printf '%s\n' "$iur_table" | awk -F'\t' -v want="$iur_rs_owner" '
    $1 == "/api/models/idle-unload" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "idle unload read ownership pairing: GET only; PUT and other methods stay Node"
fi
if [ "$iur_rs_owner" = rust ]; then
  [ "${iur_rows:-}" = /api/models/idle-unload ] || die "idle unload read ownership pairing: incomplete route ownership"
  iur_refused="$( { project_routes_core "$tree/core/server/rust-idle-unload-read.cjs" || true; } | tr '\n' ' ')"
  [ "$iur_refused" = 'GET /api/models/idle-unload ' ] || die "idle unload read ownership pairing: Core must refuse exactly GET idle unload"
  ! code_has "$tree/core/server/routes/models.cjs" 'idleUnload[.]get[[:space:]]*[(]' \
    || die "idle unload read ownership pairing: Core still carries the public GET handler"
  code_has "$tree/core/server/routes/models.cjs" 'idleUnload[.]save[[:space:]]*[(]' \
    || die "idle unload read ownership pairing: PUT must stay Node-owned"
  code_has "$tree/core/server/idle-unload-setting.cjs" 'function effectiveSeconds[[:space:]]*[(]' \
    || die "idle unload read ownership pairing: Core does not expose the live timer fact"
  [ -f "$tree/core/server/rust-idle-unload-read-facts.cjs" ] || die "idle unload read ownership pairing: missing facts bridge"
  iur_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'idleUnloadFacts(req, res)' <<<"$iur_index" || die "idle unload read ownership pairing: missing facts bridge mount"
  iur_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$iur_index" | head -1)"
  [ -n "$iur_secret" ] && awk -v c="$iur_secret" '
    /createIdleUnloadFacts\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$iur_index" || die "idle unload read ownership pairing: facts bridge needs the front captured secret"
fi
# Registry persistence and the remote measurement runner transfer together.
machines_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /noevia-inference-machines-client\//.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.MACHINES_CLIENT_MARKER;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^noevia-inference-machines-(client)\/(1)$/.exec(value);
    process.stdout.write(m ? "v" + m[2] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Root-approved source guard contract: prove the direct declared literal with the
# maintained helper. Paths/aliases are ignored, not evaluated runtime absence proof.
# The shipped B marker must remain a direct ordinary literal in real FEATURES.
machines_rs_version() {
  local result
  result="$(rs_capability_version "$1" FEATURES rust-inference-machines)"
  case "$result" in
    v1) echo v1 ;;
    legacy) echo none ;;
    *) echo invalid ;;
  esac
}
check_machines_pair() {
  local core rs
  core="$(machines_core_version "$1")"; rs="$(machines_rs_version "$2")"
  [ "$core" != invalid ] && [ "$rs" != invalid ] && [ "$core" = "$rs" ]
}

check_machines_pair "$tree/core/server/rust-inference-machines.cjs" "$tree/rs/bins/noevia-server/src/lib.rs" \
  || die "inference machines ownership pairing: Core and Rust must move together"
if [ "$(machines_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")" = v1 ]; then
  machines_row="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '$1 == "/api/models/machines" { if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1; print $1 }')" \
    || die "inference machines ownership pairing: all methods must be native"
  [ "$machines_row" = /api/models/machines ] || die "inference machines ownership pairing: missing route"
  code_has "$tree/core/server/inference-machines.cjs" "native-machines-client[.]cjs" \
    && code_has "$tree/core/server/machine-tune.cjs" "native-machines-client[.]cjs" \
    || die "inference machines ownership pairing: missing native owner clients"
  ! code_has "$tree/core/server/inference-machines.cjs" 'function readState|function save' \
    && ! code_has "$tree/core/server/machine-tune.cjs" 'async function script|function save' \
    || die "inference machines ownership pairing: obsolete Node executors remain"
fi
# #2238: only the assignments GET moves. Core retains its shared installed/probe owners.
mas_core_owner=""; mas_rs_owner=""
grep -qF "require('./rust-model-assignments.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && mas_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-assignments features; then mas_rs_owner=rust; fi
[ "$mas_core_owner" = "$mas_rs_owner" ] || die "model assignments read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  mas_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || mas_table=""
  mas_rows="$(printf '%s\n' "$mas_table" | awk -F'\t' -v want="$mas_rs_owner" '
    $1 == "/api/models/assignments" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "model assignments read ownership pairing: GET only; other methods stay Node"
fi
if [ "$mas_rs_owner" = rust ]; then
  [ "${mas_rows:-}" = /api/models/assignments ] || die "model assignments read ownership pairing: incomplete route ownership"
  awk -v quote="'" '
    block { if (index($0, "*/")) block = 0; next }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*\/\*/ { if (!index($0, "*/")) block = 1; next }
    /^const OWNED_ROUTES = / {
      markers++
      exact = ($0 == "const OWNED_ROUTES = Object.freeze(new Set([" quote "GET /api/models/assignments" quote "]));")
    }
    END { exit !(markers == 1 && exact) }
  ' "$tree/core/server/rust-model-assignments.cjs" \
    || die "model assignments read ownership pairing: Core must refuse exactly GET model assignments"
  [ ! -f "$tree/core/server/model-assignments.cjs" ] \
    || die "model assignments read ownership pairing: Core still carries the public GET formatter"
  [ -f "$tree/core/server/rust-model-assignments-facts.cjs" ] || die "model assignments read ownership pairing: missing facts bridge"
  mas_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'modelAssignmentsFacts(req, res)' <<<"$mas_index" || die "model assignments read ownership pairing: missing facts bridge mount"
  mas_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$mas_index" | head -1)"
  [ -n "$mas_secret" ] && awk -v c="$mas_secret" '
    /createModelAssignmentsFacts\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$mas_index" || die "model assignments read ownership pairing: facts bridge needs the front captured secret"
fi
# Download GET moves as a pair; Core retains the tracker and every other method.
mdr_core=""; mdr_rs=""
grep -qF "require('./rust-model-downloads-read.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && mdr_core=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-downloads-read features; then mdr_rs=rust; fi
[ "$mdr_core" = "$mdr_rs" ] || die "model downloads read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  mdr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || mdr_table=""
  mdr_rows="$(printf '%s\n' "$mdr_table" | awk -F'\t' -v want="$mdr_rs" '
    $1 == "/api/models/downloads" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "model downloads read ownership pairing: GET only; other methods stay Node"
fi
if [ "$mdr_rs" = rust ]; then
  [ "${mdr_rows:-}" = /api/models/downloads ] || die "model downloads read ownership pairing: incomplete route ownership"
  code_has "$tree/core/server/rust-model-downloads-read.cjs" "^const OWNED_ROUTES = Object[.]freeze[(]new Set[(][[]'GET /api/models/downloads'[]][)][)];$" \
    || die "model downloads read ownership pairing: Core must refuse exactly this GET"
  code_has "$tree/core/server/routes/models.cjs" "^[[:space:]]*if [(]p === '/api/models/downloads' && req[.]method !== 'GET'[)] [{]$" \
    || die "model downloads read ownership pairing: Core must retain only the legacy methods"
  [ -f "$tree/core/server/rust-model-downloads-read-facts.cjs" ] || die "model downloads read ownership pairing: missing facts bridge"
  mdr_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'modelDownloadsFacts(req, res)' <<<"$mdr_index" || die "model downloads read ownership pairing: missing facts bridge mount"
  mdr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$mdr_index" | head -1)"
  [ -n "$mdr_secret" ] && awk -v c="$mdr_secret" '
    /createModelDownloadsFacts\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$mdr_index" || die "model downloads read ownership pairing: facts bridge needs the front captured secret"
fi
# Preset GET moves as a pair. PUT keeps the same snapshot owner and conditional writer.
pr_core=""; pr_rs=""
grep -qF "require('./rust-preset-read.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && pr_core=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-preset-read features; then pr_rs=rust; fi
[ "$pr_core" = "$pr_rs" ] || die "preset read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  pr_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || pr_table=""
  pr_rows="$(printf '%s\n' "$pr_table" | awk -F'\t' -v want="$pr_rs" '
    $1 == "/api/models/preset" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "GET")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "preset read ownership pairing: GET only; PUT and other methods stay Node"
fi
if [ "$pr_rs" = rust ]; then
  [ "${pr_rows:-}" = /api/models/preset ] || die "preset read ownership pairing: incomplete route ownership"
  code_has "$tree/core/server/rust-preset-read.cjs" "^const OWNED_ROUTES = Object[.]freeze[(]new Set[(][[]'GET /api/models/preset'[]][)][)];$" \
    || die "preset read ownership pairing: Core must refuse exactly this GET"
  ! code_has "$tree/core/server/routes/models.cjs" 'modelManager[.]getPreset[[:space:]]*[(]' \
    || die "preset read ownership pairing: Core still carries the public GET handler"
  code_has "$tree/core/server/routes/models.cjs" 'modelManager[.]applyPreset[[:space:]]*[(]' \
    || die "preset read ownership pairing: PUT must stay Node-owned"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'presetFacts:.*presets[?][.]get[(]' \
    || die "preset read ownership pairing: missing shared preset snapshot"
  [ -f "$tree/core/server/rust-preset-read-bridge.cjs" ] || die "preset read ownership pairing: missing facts bridge"
  pr_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'presetReadBridge(req, res)' <<<"$pr_index" || die "preset read ownership pairing: missing facts bridge mount"
  pr_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$pr_index" | head -1)"
  [ -n "$pr_secret" ] && awk -v c="$pr_secret" '
    /createPresetReadBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$pr_index" || die "preset read ownership pairing: facts bridge needs the front captured secret"
fi
# #2293: autotune dismissal policy is native, with only facts and the conditional state writer in Core.
ac_core_owner=""; ac_rs_owner=""
grep -qF "require('./rust-autotune-clear.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && ac_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-clear features; then ac_rs_owner=rust; fi
[ "$ac_core_owner" = "$ac_rs_owner" ] || die "autotune dismissal ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  ac_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || ac_table=""
  ac_rows="$(printf '%s\n' "$ac_table" | awk -F'\t' -v want="$ac_rs_owner" '
    $1 == "/api/models/autotune/clear" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "autotune dismissal ownership pairing: all methods must belong to the paired owner"
fi
if [ "$ac_rs_owner" = rust ]; then
  [ "${ac_rows:-}" = /api/models/autotune/clear ] || die "autotune dismissal ownership pairing: incomplete route ownership"
  ac_refused="$( { project_routes_core "$tree/core/server/rust-autotune-clear.cjs" || true; } | tr '\n' ' ')"
  [ "$ac_refused" = 'ALL /api/models/autotune/clear ' ] || die "autotune dismissal ownership pairing: Core must refuse exactly the dismissal path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/autotune/clear' \
    || die "autotune dismissal ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" '(^|[^A-Za-z0-9_$])function[[:space:]]+clear[[:space:]]*\(' \
    || die "autotune dismissal ownership pairing: Core still carries the public dismissal policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'clearFacts: autotuner.clearFacts' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'compareAndClear: autotuner.compareAndClear' \
    || die "autotune dismissal ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-autotune-clear-bridge.cjs" ] || die "autotune dismissal ownership pairing: missing state bridge"
  ac_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneClearBridge(req, res)' <<<"$ac_index" || die "autotune dismissal ownership pairing: missing state bridge mount"
  ac_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$ac_index" | head -1)"
  [ -n "$ac_secret" ] && awk -v c="$ac_secret" '
    /createAutotuneClearBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$ac_index" || die "autotune dismissal ownership pairing: state bridge needs the front captured secret"
fi
# #2301: resume policy is native; Core retains staged metadata/reload preparation and conditional launch.
atrm_core_owner=""; atrm_rs_owner=""
grep -qF "require('./rust-autotune-resume.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && atrm_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-resume features; then atrm_rs_owner=rust; fi
[ "$atrm_core_owner" = "$atrm_rs_owner" ] || die "auto-tune resume ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  atrm_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || atrm_table=""
  atrm_rows="$(printf '%s\n' "$atrm_table" | awk -F'\t' -v want="$atrm_rs_owner" '
    $1 == "/api/models/autotune/resume" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "auto-tune resume ownership pairing: all methods must belong to the paired owner"
fi
if [ "$atrm_rs_owner" = rust ]; then
  [ "${atrm_rows:-}" = /api/models/autotune/resume ] || die "auto-tune resume ownership pairing: incomplete route ownership"
  atrm_refused="$( { project_routes_core "$tree/core/server/rust-autotune-resume.cjs" || true; } | tr '\n' ' ')"
  [ "$atrm_refused" = 'ALL /api/models/autotune/resume ' ] || die "auto-tune resume ownership pairing: Core must refuse exactly the dismissal path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/autotune/resume' \
    || die "auto-tune resume ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" '(^|[^[:alnum:]_$])function[[:space:]]+resume[[:space:]]*[(]' \
    || die "auto-tune resume ownership pairing: Core still carries the public resume policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'resumeFacts: autotuner.resumeFacts' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'prepareResume: autotuner.prepareResume' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'compareAndResume: autotuner.compareAndResume' \
    || die "auto-tune resume ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-autotune-resume-bridge.cjs" ] || die "auto-tune resume ownership pairing: missing state bridge"
  atrm_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneResumeBridge(req, res)' <<<"$atrm_index" || die "auto-tune resume ownership pairing: missing state bridge mount"
  atrm_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$atrm_index" | head -1)"
  [ -n "$atrm_secret" ] && awk -v c="$atrm_secret" '
    /createAutotuneResumeBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$atrm_index" || die "auto-tune resume ownership pairing: state bridge needs the front captured secret"
fi
# Retention PUT and the hourly sweep share one native writer. Refuse mixed generations.
retention_core_put=""
if grep -qF "  [/^\\/api\\/account\\/retention$/, ['GET', 'PUT']]," "$tree/core/server/rust-auth.cjs" 2>/dev/null; then
  retention_core_put='PUT /api/account/retention'
fi
retention_rs_put=""
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # An unreadable table is refused further down with its own #2096 error; read it tolerantly here
  # (as the auto-tune cancellation block does) so that error, not this one, is what is reported.
  # With Core moved and the table unreadable, the pairing below still refuses.
  retention_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || retention_table=""
  retention_rs_put="$(printf '%s\n' "$retention_table" | awk -F'\t' '
    $1 == "/api/account/retention" && $2 == "rust" && ($4 == "-" || $4 ~ /(^|,)[ \t]*PUT([ \t]*,|[ \t]*$)/) {print "PUT /api/account/retention"}')"
fi
[ "$retention_core_put" = "$retention_rs_put" ] || die "retention PUT ownership pairing: Core and Rust must move together"
if [ -n "$retention_core_put" ]; then
  code_has "$tree/core/server/routes/account.cjs" "Retention settings are owned by the Rust front." \
    || die "retention PUT ownership pairing: Core must refuse the moved writer"
  if code_has "$tree/core/server/routes/account.cjs" 'retention\.write\('; then
    die "retention PUT ownership pairing: Core still writes retention settings"
  else
    retention_match_status=$?
    [ "$retention_match_status" -eq 1 ] || die "retention PUT ownership pairing: writer matcher failed"
  fi
fi
# #2294: auto-tune cancellation policy is native, with only facts and the conditional state writer in Core.
atc_core_owner=""; atc_rs_owner=""
grep -qF "require('./rust-autotune-cancel.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && atc_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-cancel features; then atc_rs_owner=rust; fi
[ "$atc_core_owner" = "$atc_rs_owner" ] || die "auto-tune cancellation ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  atc_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || atc_table=""
  atc_rows="$(printf '%s\n' "$atc_table" | awk -F'\t' -v want="$atc_rs_owner" '
    $1 == "/api/models/autotune/cancel" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "auto-tune cancellation ownership pairing: all methods must belong to the paired owner"
fi
if [ "$atc_rs_owner" = rust ]; then
  [ "${atc_rows:-}" = /api/models/autotune/cancel ] || die "auto-tune cancellation ownership pairing: incomplete route ownership"
  atc_refused="$( { project_routes_core "$tree/core/server/rust-autotune-cancel.cjs" || true; } | tr '\n' ' ')"
  [ "$atc_refused" = 'ALL /api/models/autotune/cancel ' ] || die "auto-tune cancellation ownership pairing: Core must refuse exactly the cancellation path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/autotune/cancel' \
    || die "auto-tune cancellation ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" 'function cancel()' \
    || die "auto-tune cancellation ownership pairing: Core still carries the public cancellation policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'cancellationFacts: autotuner.cancellationFacts' \
    && code_has "$tree/core/server/llamacpp-manager.cjs" 'compareAndAbort: autotuner.compareAndAbort' \
    || die "auto-tune cancellation ownership pairing: Core does not expose the live actor primitives"
  [ -f "$tree/core/server/rust-autotune-cancel-bridge.cjs" ] || die "auto-tune cancellation ownership pairing: missing state bridge"
  atc_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneCancelBridge(req, res)' <<<"$atc_index" || die "auto-tune cancellation ownership pairing: missing state bridge mount"
  atc_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$atc_index" | head -1)"
  [ -n "$atc_secret" ] && awk -v c="$atc_secret" '
    /createAutotuneCancelBridge\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$atc_index" || die "auto-tune cancellation ownership pairing: state bridge needs the front captured secret"
fi
# #2295: untuned discovery policy is native, with only facts and the conditional state writer in Core.
au_scan_core_owner=""; au_scan_rs_owner=""
grep -qF "require('./rust-autotune-untuned.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && au_scan_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-autotune-untuned features; then au_scan_rs_owner=rust; fi
[ "$au_scan_core_owner" = "$au_scan_rs_owner" ] || die "untuned discovery ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  au_scan_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || au_scan_table=""
  au_scan_rows="$(printf '%s\n' "$au_scan_table" | awk -F'\t' -v want="$au_scan_rs_owner" '
    $1 == "/api/models/autotune/untuned" {
      if (want == "rust" && ($2 != "rust" || $3 != "-" || $4 != "-")) exit 1
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "untuned discovery ownership pairing: all methods must belong to the paired owner"
fi
if [ "$au_scan_rs_owner" = rust ]; then
  [ "${au_scan_rows:-}" = /api/models/autotune/untuned ] || die "untuned discovery ownership pairing: incomplete route ownership"
  au_scan_refused="$( { project_routes_core "$tree/core/server/rust-autotune-untuned.cjs" || true; } | tr '\n' ' ')"
  [ "$au_scan_refused" = 'ALL /api/models/autotune/untuned ' ] || die "untuned discovery ownership pairing: Core must refuse exactly the discovery path"
  ! code_has "$tree/core/server/routes/models.cjs" '/api/models/autotune/untuned' \
    || die "untuned discovery ownership pairing: Core still carries the public handler"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" 'async[[:space:]]+function[[:space:]]+untuned[[:space:]]*\(' \
    || die "untuned discovery ownership pairing: Core still carries the public discovery policy"
  code_has "$tree/core/server/llamacpp-manager.cjs" 'scanFacts: autotuner.scanFacts' \
    && code_has "$tree/core/server/llamacpp-full-autotune.cjs" '[.]autotuneScan[[:space:]]*\(' \
    && code_has "$tree/core/server/dav-parse-wasm.cjs" '[.]autotune_scan[[:space:]]*\(' \
    && code_has "$tree/rs/bins/dav-parse-wasm/src/lib.rs" 'fn[[:space:]]+autotune_scan[[:space:]]*\(' \
    || die "untuned discovery ownership pairing: shared Rust/WASM policy and raw owner facts required"
  ! code_has "$tree/core/server/llamacpp-full-autotune.cjs" 'latest?.version === VERSION' \
    || die "untuned discovery ownership pairing: Core still carries candidate selection policy"
  [ -f "$tree/core/server/rust-autotune-untuned-facts.cjs" ] || die "untuned discovery ownership pairing: missing state bridge"
  au_scan_index="$(code_lines "$tree/core/server/index.cjs")"
  grep -qF 'autotuneUntunedFacts(req, res)' <<<"$au_scan_index" || die "untuned discovery ownership pairing: missing state bridge mount"
  au_scan_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$au_scan_index" | head -1)"
  [ -n "$au_scan_secret" ] && awk -v c="$au_scan_secret" '
    /createAutotuneUntunedFacts\(\{/ { bridge = NR }
    index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
    END { exit !ok }
  ' <<<"$au_scan_index" || die "untuned discovery ownership pairing: state bridge needs the front captured secret"
fi
# An account's deletion (sbstndalton/noevia#2190, #2191 round 9) moves as one owner: Core's rust-admin-users.cjs
# refusal and the front's rust-admin-users capability, with exactly DELETE of /api/admin/users/{id} Rust's in
# routes.toml. Core must have no way left to delete an account: no deleteUser in auth.cjs, and the single-writer
# guard refusing `users` to every statement (rust-auth.cjs), not even inside exempt().
au_core_owner=""
au_rs_owner=""
grep -qF "require('./rust-admin-users.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && au_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-admin-users features; then
  au_rs_owner=rust
fi
[ "$au_core_owner" = "$au_rs_owner" ] \
  || die "account deletion ownership pairing: Core and Rust must move together"
if [ "$au_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "account deletion ownership pairing: missing route contract"
  au_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/admin/users/{id}" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "DELETE") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "account deletion ownership pairing: exactly DELETE /api/admin/users/{id} must belong to Rust"
  [ "$au_routes" = "/api/admin/users/{id}" ] || die "account deletion ownership pairing: incomplete route ownership"
  [ "$(project_routes_core "$tree/core/server/rust-admin-users.cjs")" = "DELETE /api/admin/users/{}" ] \
    || die "account deletion ownership pairing: Core must refuse exactly DELETE /api/admin/users/{id}"
  if grep -qE '^[[:space:]]+deleteUser[[:space:]]*\(' "$tree/core/server/auth.cjs" 2>/dev/null \
     || ! grep -qF "users is written by the Rust front" "$tree/core/server/rust-auth.cjs" 2>/dev/null; then
    die "account deletion ownership pairing: Core can still delete an account (auth.cjs deleteUser, or rust-auth.cjs does not refuse users)"
  fi
fi
# A stored document's page reader (sbstndalton/noevia#2191 round 4) moves as one owner: Core's
# rust-project-document-pages.cjs refusal and the front's rust-project-document-pages capability, with
# exactly GET of /api/projects/{id}/documents/pages Rust's in routes.toml. It reads the results Core's
# extraction writes once per version, so it needs no other pair.
document_pages_core_owner=""
document_pages_rs_owner=""
grep -qF "require('./rust-project-document-pages.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && document_pages_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-document-pages features; then
  document_pages_rs_owner=rust
fi
[ "$document_pages_core_owner" = "$document_pages_rs_owner" ] \
  || die "project document page reader ownership pairing: Core and Rust must move together"
if [ "$document_pages_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project document page reader ownership pairing: missing route contract"
  document_pages_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/documents/pages" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "project document page reader ownership pairing: exactly GET /api/projects/{id}/documents/pages must belong to Rust"
  [ "$document_pages_routes" = "/api/projects/{id}/documents/pages" ] || die "project document page reader ownership pairing: incomplete route ownership"
fi
# The conversation import (sbstndalton/noevia#2191 round 4) moves as one owner: Core's
# rust-conversation-import.cjs refusal and the front's rust-conversation-import capability, with exactly
# POST of /api/import/conversations Rust's in routes.toml. It creates projects through the front's create,
# so it needs the project create/delete pair.
conversation_import_core_owner=""
conversation_import_rs_owner=""
grep -qF "require('./rust-conversation-import.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && conversation_import_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-conversation-import features; then
  conversation_import_rs_owner=rust
fi
[ "$conversation_import_core_owner" = "$conversation_import_rs_owner" ] \
  || die "conversation import ownership pairing: Core and Rust must move together"
if [ "$conversation_import_rs_owner" = rust ]; then
  [ "$project_lifecycle_rs_owner" = rust ] || die "conversation import ownership pairing: needs the project create/delete pair"
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "conversation import ownership pairing: missing route contract"
  conversation_import_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/import/conversations" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "POST") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "conversation import ownership pairing: exactly POST /api/import/conversations must belong to Rust"
  [ "$conversation_import_routes" = "/api/import/conversations" ] || die "conversation import ownership pairing: incomplete route ownership"
fi
# The project document upload (sbstndalton/noevia#2191 round 5) moves as one owner: Core's
# rust-project-documents.cjs refusal and the front's rust-project-documents capability, with exactly POST of
# /api/projects/{id}/documents Rust's in routes.toml. It runs on the front's extraction pipeline, so the
# front must also list rust-document-extraction.
project_documents_core_owner=""
project_documents_rs_owner=""
grep -qF "require('./rust-project-documents.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && project_documents_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-documents features; then
  project_documents_rs_owner=rust
fi
[ "$project_documents_core_owner" = "$project_documents_rs_owner" ] \
  || die "project document upload ownership pairing: Core and Rust must move together"
if [ "$project_documents_rs_owner" = rust ]; then
  move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-document-extraction features \
    || die "project document upload ownership pairing: needs the rust-document-extraction pipeline"
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project document upload ownership pairing: missing route contract"
  project_documents_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/documents" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "POST") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "project document upload ownership pairing: exactly POST /api/projects/{id}/documents must belong to Rust"
  [ "$project_documents_routes" = "/api/projects/{id}/documents" ] || die "project document upload ownership pairing: incomplete route ownership"
fi
# The public pages (sbstndalton/noevia#2190) move as one owner: Core's rust-public-pages.cjs refusal
# and the front's rust-public-pages capability, with exactly GET and HEAD of /about and /privacy and
# every method of /device Rust's in routes.toml (Node keeps the pages' other methods).
pages_core_owner=""
pages_rs_owner=""
grep -qF "require('./rust-public-pages.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && pages_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-public-pages features; then
  pages_rs_owner=rust
fi
[ "$pages_core_owner" = "$pages_rs_owner" ] \
  || die "public page ownership pairing: Core and Rust must move together"
if [ "$pages_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "public page ownership pairing: missing route contract"
  page_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/about" || $1 == "/privacy" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0; g = 0; h = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] == "GET") g++; else if (m[i] == "HEAD") h++; else exit 1; k++ }
      if (k != 2 || g != 1 || h != 1) exit 1
      print $1
    }
    $1 == "/device" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }' | sort)" || die "public page ownership pairing: GET and HEAD of the pages and every method of /device must belong to Rust"
  page_expected="$(printf '%s\n' /about /privacy /device | sort)"
  [ "$page_routes" = "$page_expected" ] || die "public page ownership pairing: incomplete route ownership"
fi
# The plugin directory (sbstndalton/noevia#2190): Core's rust-plugin-directory.cjs refusal and the
# front's rust-plugin-directory capability, every method of the route Rust's in routes.toml.
directory_core_owner=""
directory_rs_owner=""
grep -qF "require('./rust-plugin-directory.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && directory_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-plugin-directory features; then
  directory_rs_owner=rust
fi
[ "$directory_core_owner" = "$directory_rs_owner" ] \
  || die "plugin directory ownership pairing: Core and Rust must move together"
if [ "$directory_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "plugin directory ownership pairing: missing route contract"
  directory_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/plugins/directory" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "plugin directory ownership pairing: all methods must belong to Rust"
  [ "$directory_routes" = /api/plugins/directory ] || die "plugin directory ownership pairing: incomplete route ownership"
fi
# F1: persistence, cleanup and the private boot proof move as one paired writer.
auto_roles_core_owner() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RUST_AUTO_ROLES_WRITE_OWNED;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write("invalid"); process.exit(0); }
    const markers = src.match(/["\x27]rust-auto-roles-write[^"\x27\r\n]*["\x27]/g) || [];
    process.stdout.write(value === "rust-auto-roles-write" && markers.length === 1 ? "rust" : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
auto_roles_rs_owner() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    // No decoded literal (ordinary, raw or byte) mentions auto-roles: this guard has nothing
    // to prove, so other capability guards report their own FEATURES shapes. A split marker
    // still cannot hand PUT to Rust: get_only_pair then requires GET-only ownership.
    if (!strs.some(s => s.v.includes("auto-roles"))) out("none");
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = [];
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-auto-roles-write"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-auto-roles-write")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    out(outbox[0] === "rust-auto-roles-write" ? "rust" : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
auto_roles_write_owner="$(auto_roles_core_owner "$tree/core/server/rust-auto-roles-write.cjs")"
auto_roles_write_front="$(auto_roles_rs_owner "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$auto_roles_write_owner" != invalid ] && [ "$auto_roles_write_front" != invalid ] || die "auto-roles write ownership pairing: ambiguous or unknown capability marker"
[ "$auto_roles_write_owner" = "$auto_roles_write_front" ] || die "auto-roles write ownership pairing: Core and Rust must move together"
if [ "$auto_roles_write_owner" = rust ]; then
  [ -f "$tree/core/server/rust-auto-roles-write.cjs" ] || die "auto-roles write ownership pairing: missing Core bridge"
  code_has "$tree/core/server/index.cjs" 'PROJECT_STORE\.autoRolesReady\(\)' || die "auto-roles write ownership pairing: missing boot proof"
  code_has "$tree/core/server/index.cjs" 'autoRolesWriteBridge\(req, res\)' || die "auto-roles write ownership pairing: missing bridge mount"
  if code_has "$tree/core/server/models.cjs" 'saveAutoRoles[(]' || code_has "$tree/core/server/workspace.cjs" 'saveAutoRoles[(]'; then
    die "auto-roles write ownership pairing: Core still carries a roles writer"
  fi
fi
# The close-out routes: GET /api/health and GET /api/auto-roles (sbstndalton/noevia#2190) and GET
# /api/workspace (#2191). Each is Core's refusal (server/rust-health.cjs, rust-auto-roles.cjs,
# rust-workspace.cjs, which also publish rag-status.json and auto-roles-snapshot.json for the front) beside
# the front's capability of the same name, with exactly the GET of the path Rust's in routes.toml (the
# other methods stay Node's: the auto-roles PUT warms the roles in the engine). Old/old stays valid; a
# mixed pair is refused, so a front never answers from a snapshot nobody publishes and a Core never
# refuses a route nobody answers.
get_only_pair() {
  local marker=$1 capability=$2 label=$3 route=$4 core_owner="" rs_owner="" owned
  grep -qF "require('./$marker')" "$tree/core/server/index.cjs" 2>/dev/null && core_owner=rust
  if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES "$capability" features; then
    rs_owner=rust
  fi
  [ "$core_owner" = "$rs_owner" ] \
    || die "$label ownership pairing: Core and Rust must move together"
  if [ "$rs_owner" = rust ]; then
    [ -f "$tree/rs/contracts/http/routes.toml" ] || die "$label ownership pairing: missing route contract"
    owned="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' -v want="$route" -v put="${auto_roles_write_owner:-}" '
      $1 == want {
        if ($2 != "rust" || $3 != "-") exit 1
        n = split($4, m, /[^A-Z]+/); k = 0; g = 0
        for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] == "GET") g++; k++ }
        if (want == "/api/auto-roles" && put == "rust") {
          p = 0; for (i = 1; i <= n; i++) if (m[i] == "PUT") p++
          if (k != 2 || g != 1 || p != 1) exit 1
        } else if (k != 1 || g != 1) exit 1
        print $1
      }')" || die "$label ownership pairing: exactly GET of $route must belong to Rust"
    [ "$owned" = "$route" ] || die "$label ownership pairing: incomplete route ownership"
  fi
}
get_only_pair rust-health.cjs rust-health "health check" /api/health
get_only_pair rust-auto-roles.cjs rust-auto-roles "auto-roles read" /api/auto-roles
get_only_pair rust-workspace.cjs rust-workspace "workspace list" /api/workspace
# The chat search (#1450) and one chat's Markdown download (#1471), each its own pair of Core refusal
# (server/rust-chat-search.cjs, rust-chat-export.cjs) and front capability, exactly the GET Rust's. A paired
# Core no longer carries the handler in routes/chat-lists.cjs and refuses exactly that GET.
get_only_pair rust-chat-search.cjs rust-chat-search "chat search" /api/chats/search
get_only_pair rust-chat-export.cjs rust-chat-export "chat download" "/api/chats/{chatId}/export"
if grep -qF "require('./rust-chat-search.cjs')" "$tree/core/server/index.cjs" 2>/dev/null; then
  code_has "$tree/core/server/rust-chat-search.cjs" "^const OWNED_ROUTES = Object[.]freeze[(]new Set[(][[]'GET /api/chats/search'[]][)][)];$" \
    || die "chat search ownership pairing: Core must refuse exactly this GET"
  ! code_has "$tree/core/server/routes/chat-lists.cjs" "p === '/api/chats/search'" \
    || die "chat search ownership pairing: Core still carries the public search handler"
fi
if grep -qF "require('./rust-chat-export.cjs')" "$tree/core/server/index.cjs" 2>/dev/null; then
  code_has "$tree/core/server/rust-chat-export.cjs" "^const OWNED_ROUTES = Object[.]freeze[(]new Set[(][[]'GET /api/chats/[{]chatId[}]/export'[]][)][)];$" \
    || die "chat download ownership pairing: Core must refuse exactly this GET"
  ! code_has "$tree/core/server/routes/chat-lists.cjs" 'chatMarkdown[(]' \
    || die "chat download ownership pairing: Core still carries the public download handler"
fi
# The decision settings (sbstndalton/noevia#2190): Core's rust-decision-settings.cjs refusal and the
# front's rust-decision-settings capability (Rust the single writer of decision:configuration), every
# method of both routes Rust's in routes.toml.
decision_core_owner=""
decision_rs_owner=""
grep -qF "require('./rust-decision-settings.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && decision_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-decision-settings features; then
  decision_rs_owner=rust
fi
[ "$decision_core_owner" = "$decision_rs_owner" ] \
  || die "decision settings ownership pairing: Core and Rust must move together"
if [ "$decision_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "decision settings ownership pairing: missing route contract"
  decision_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/admin/decision-settings" || $1 == "/api/admin/decision-settings/test" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }' | sort)" || die "decision settings ownership pairing: all methods must belong to Rust"
  decision_expected="$(printf '%s\n' /api/admin/decision-settings /api/admin/decision-settings/test | sort)"
  [ "$decision_routes" = "$decision_expected" ] || die "decision settings ownership pairing: incomplete route ownership"
fi
# The storage integrations (sbstndalton/noevia#2190, round 3): Core's rust-storage-integrations.cjs
# refusal and the front's rust-storage-integrations capability (the folder write, the connection test
# and the Nextcloud sign-in, whose flows file Rust owns), exactly POST of all five routes Rust's in
# routes.toml (Node answered only POST there; the other methods stay Node's).
storage_core_owner=""
storage_rs_owner=""
grep -qF "require('./rust-storage-integrations.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && storage_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-storage-integrations features; then
  storage_rs_owner=rust
fi
[ "$storage_core_owner" = "$storage_rs_owner" ] \
  || die "storage integration ownership pairing: Core and Rust must move together"
if [ "$storage_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "storage integration ownership pairing: missing route contract"
  storage_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/integrations/storage/folder" || $1 == "/api/integrations/storage/test" ||
    $1 == "/api/integrations/storage/nextcloud/start" || $1 == "/api/integrations/storage/nextcloud/poll" ||
    $1 == "/api/integrations/storage/nextcloud/cancel" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "POST") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "storage integration ownership pairing: exactly POST of all five routes must belong to Rust"
  storage_expected="$(printf '%s\n' /api/integrations/storage/folder /api/integrations/storage/test /api/integrations/storage/nextcloud/start /api/integrations/storage/nextcloud/poll /api/integrations/storage/nextcloud/cancel | sort)"
  [ "$storage_routes" = "$storage_expected" ] || die "storage integration ownership pairing: incomplete route ownership"
fi
# The vault-mirror preferences (#2190, round 3): Core's rust-vault-mirror-preferences.cjs refusal (every
# method; Node's route answered them all, 405 for the others) and the front's
# rust-vault-mirror-preferences capability, with the path Rust's for every method in routes.toml.
mirror_core_owner=""
mirror_rs_owner=""
grep -qF "require('./rust-vault-mirror-preferences.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && mirror_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-vault-mirror-preferences features; then
  mirror_rs_owner=rust
fi
[ "$mirror_core_owner" = "$mirror_rs_owner" ] \
  || die "vault mirror preference ownership pairing: Core and Rust must move together"
if [ "$mirror_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "vault mirror preference ownership pairing: missing route contract"
  mirror_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/chat-vault-mirror/preferences" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "vault mirror preference ownership pairing: every method of the path must belong to Rust"
  [ "$mirror_routes" = /api/chat-vault-mirror/preferences ] || die "vault mirror preference ownership pairing: incomplete route ownership"
fi

# The storage connection save (#2190, round 4): Core's rust-storage-connection.cjs refusal (PUT on the
# exact path; Core's guard then refuses every Node write of storage_connections, and its legacy WebDAV
# setup asks the front's internal store) and the front's rust-storage-connection capability, with
# exactly GET and PUT of /api/integrations/storage Rust's in routes.toml (GET is the metadata worker's).
conn_core_owner=""
conn_rs_owner=""
grep -qF "require('./rust-storage-connection.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && conn_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-storage-connection features; then
  conn_rs_owner=rust
fi
[ "$conn_core_owner" = "$conn_rs_owner" ] \
  || die "storage connection ownership pairing: Core and Rust must move together"
if [ "$conn_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "storage connection ownership pairing: missing route contract"
  conn_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/integrations/storage" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0; get = 0; put = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { k++; if (m[i] == "GET") get = 1; else if (m[i] == "PUT") put = 1; else exit 1 }
      if (k != 2 || !get || !put) exit 1
      print $1
    }')" || die "storage connection ownership pairing: exactly GET and PUT of the path must belong to Rust"
  [ "$conn_routes" = /api/integrations/storage ] || die "storage connection ownership pairing: incomplete route ownership"
fi

# The provider registry (#2190, round 6): Core's rust-providers.cjs refusal and the front's
# rust-providers capability. Detected first because it widens the probe's route below: with it,
# PUT and DELETE of /api/providers/test (a provider id like any other) are Rust's too.
prov_core_owner=""
prov_rs_owner=""
grep -qF "require('./rust-providers.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && prov_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-providers features; then
  prov_rs_owner=rust
fi
[ "$prov_core_owner" = "$prov_rs_owner" ] \
  || die "provider registry ownership pairing: Core and Rust must move together"
if [ "$prov_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "provider registry ownership pairing: missing route contract"
  prov_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/providers") return "GET,POST"
      if (path == "/api/providers/{id}") return "PUT,DELETE"
      if (path == "/api/providers/chatgpt") return "DELETE,GET"
      if (path == "/api/providers/test") return "DELETE,POST,PUT"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      delete seen
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] in seen) exit 1; seen[m[i]] = 1; k++ }
      nw = split(want($1), w, ",")
      if (k != nw) exit 1
      for (i = 1; i <= nw; i++) if (!(w[i] in seen)) exit 1
      print $1
    }' | sort)" || die "provider registry ownership pairing: exactly the registry's methods of the routes must belong to Rust"
  prov_expected="$(printf '%s\n' /api/providers /api/providers/chatgpt /api/providers/test '/api/providers/{id}' | sort)"
  [ "$prov_routes" = "$prov_expected" ] || die "provider registry ownership pairing: incomplete route ownership"
fi

# The provider keys' re-seal (#2190, round 6 review): Core's secrets rotation no longer rewrites the
# provider files, it asks the front's internal store (rust-providers-reseal.cjs in Core,
# rust-providers-reseal in the front's FEATURES, POST /v1/providers/reseal in project_store.rs and
# providersReseal in Core's store client). It moves with the registry: a registry without it would
# leave a second writer of the files (the rotation), and the op alone has no files of its own.
reseal_core_owner=""
reseal_rs_owner=""
grep -qF "require('./rust-providers-reseal.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && reseal_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-providers-reseal features; then
  reseal_rs_owner=rust
fi
[ "$reseal_core_owner" = "$reseal_rs_owner" ] \
  || die "provider key reseal ownership pairing: Core and Rust must move together"
[ "$reseal_rs_owner" = "$prov_rs_owner" ] \
  || die "provider key reseal ownership pairing: it moves with the provider registry (a registry without it leaves a second writer of the provider files)"
if [ "$reseal_rs_owner" = rust ]; then
  grep -qF '"/v1/providers/reseal"' "$tree/rs/bins/noevia-server/src/project_store.rs" 2>/dev/null \
    || die "provider key reseal ownership pairing: the front does not serve /v1/providers/reseal"
  grep -qF 'providersReseal' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
    || die "provider key reseal ownership pairing: Core's store client does not call /v1/providers/reseal"
fi

# The provider probe (#2190, round 4): Core's rust-provider-test.cjs refusal (POST on the exact path;
# Node keeps the other methods, its /api/providers/{id} handler reads `test` as an id) and the front's
# rust-provider-test capability, with exactly POST of /api/providers/test Rust's in routes.toml.
# With the provider registry (round 6) the route is also Rust's for PUT and DELETE, and then those
# three methods exactly.
ptest_core_owner=""
ptest_rs_owner=""
grep -qF "require('./rust-provider-test.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && ptest_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-provider-test features; then
  ptest_rs_owner=rust
fi
[ "$ptest_core_owner" = "$ptest_rs_owner" ] \
  || die "provider test ownership pairing: Core and Rust must move together"
if [ "$ptest_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "provider test ownership pairing: missing route contract"
  ptest_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' -v registry="$prov_rs_owner" '
    $1 == "/api/providers/test" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") {
        if (m[i] != "POST" && !(registry == "rust" && (m[i] == "PUT" || m[i] == "DELETE"))) exit 1
        k++
      }
      if (k != (registry == "rust" ? 3 : 1)) exit 1
      print $1
    }')" || die "provider test ownership pairing: exactly POST of the path must belong to Rust"
  [ "$ptest_routes" = /api/providers/test ] || die "provider test ownership pairing: incomplete route ownership"
fi

# Sign in with ChatGPT's token broker (#2190, round 5): Core's rust-chatgpt-oauth.cjs refusal and
# the front's rust-chatgpt-oauth capability, with exactly POST of the three device routes and GET of
# the model list Rust's in routes.toml (Node keeps DELETE /api/providers/chatgpt, the disconnect).
cgpt_core_owner=""
cgpt_rs_owner=""
grep -qF "require('./rust-chatgpt-oauth.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && cgpt_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-chatgpt-oauth features; then
  cgpt_rs_owner=rust
fi
[ "$cgpt_core_owner" = "$cgpt_rs_owner" ] \
  || die "ChatGPT sign-in ownership pairing: Core and Rust must move together"
if [ "$cgpt_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "ChatGPT sign-in ownership pairing: missing route contract"
  cgpt_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/providers/chatgpt/device" || path == "/api/providers/chatgpt/device/poll" || path == "/api/providers/chatgpt/device/cancel") return "POST"
      if (path == "/api/providers/chatgpt/models") return "GET"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want($1)) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "ChatGPT sign-in ownership pairing: exactly the broker's methods of the routes must belong to Rust"
  cgpt_routes="$(printf '%s\n' "$cgpt_routes" | sort | tr '\n' ' ')"
  [ "$cgpt_routes" = "/api/providers/chatgpt/device /api/providers/chatgpt/device/cancel /api/providers/chatgpt/device/poll /api/providers/chatgpt/models " ] \
    || die "ChatGPT sign-in ownership pairing: incomplete route ownership"
fi

# The MCP server credentials (#2202): Core's rust-mcp-credentials.cjs refusal and the front's
# rust-mcp-credentials capability, with exactly the methods the broker answers Rust's in routes.toml
# (the keys, the sign-in servers, the connect, the disconnect and the sign-in callback). The front is
# the only writer of the three credential tables, and Core's chat asks its internal store
# (/v1/mcp/*; mcpSession, mcpKey and the rotation's mcpReseal in Core's store client) for one call's
# access token or key: a pair without either side would leave a second writer or a chat with no key.
mcp_core_owner=""
mcp_rs_owner=""
code_has "$tree/core/server/index.cjs" "require\\('\\./rust-mcp-credentials\\.cjs'\\)" && mcp_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-mcp-credentials features; then
  mcp_rs_owner=rust
fi
[ "$mcp_core_owner" = "$mcp_rs_owner" ] \
  || die "MCP credential ownership pairing: Core and Rust must move together"
if [ "$mcp_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "MCP credential ownership pairing: missing route contract"
  mcp_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/mcp-keys/servers" || path == "/api/mcp-oauth/servers" || path == "/api/mcp-oauth/callback") return "GET"
      if (path == "/api/mcp-keys/{*}") return "DELETE,PUT"
      if (path == "/api/mcp-oauth/{id}") return "DELETE"
      if (path == "/api/mcp-oauth/{id}/connect") return "POST"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      delete seen
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] in seen) exit 1; seen[m[i]] = 1; k++ }
      nw = split(want($1), w, ",")
      if (k != nw) exit 1
      for (i = 1; i <= nw; i++) if (!(w[i] in seen)) exit 1
      print $1
    }' | LC_ALL=C sort | tr '\n' ' ')" || die "MCP credential ownership pairing: exactly the broker's methods of the routes must belong to Rust"
  [ "$mcp_routes" = "/api/mcp-keys/servers /api/mcp-keys/{*} /api/mcp-oauth/callback /api/mcp-oauth/servers /api/mcp-oauth/{id} /api/mcp-oauth/{id}/connect " ] \
    || die "MCP credential ownership pairing: incomplete route ownership"
  # Code, not comments: a mention of the path or of an op in a comment serves and calls nothing.
  code_has "$tree/rs/bins/noevia-server/src/project_store.rs" '/v1/mcp/' \
    || die "MCP credential ownership pairing: the front does not serve /v1/mcp/*"
  for op in mcpSession mcpKey mcpReseal; do
    code_has "$tree/core/server/project-store-client.cjs" "(^|[^A-Za-z0-9_])$op[[:space:]]*\\(" \
      || die "MCP credential ownership pairing: Core's store client does not call $op"
  done
fi

# The admin MCP directory, the permitted-tools view and the connectors list (#2202 round 2): each is a Core refusal
# (rust-mcp-directory.cjs, rust-toolboxes-permitted.cjs, rust-connectors.cjs) paired with a front capability of the
# same name, with exactly the methods the front answers Rust's in routes.toml. Together they make the front the
# only writer of directory_mcp_servers (Node re-reads it: its directory-mcp.cjs must hold no write of it) and move
# the last two views onto the discovery snapshot Node publishes (mcp-discovery.json): a pair without the Core half
# that publishes it, or the front half that reads it, would answer from nothing.
discovery_pair_ok() {
  code_has "$tree/core/server/index.cjs" "createMcpDiscoveryPublisher[[:space:]]*\\(" \
    && [ -f "$tree/core/server/mcp-discovery-snapshot.cjs" ] \
    && code_has "$tree/rs/bins/noevia-server/src/lib.rs" "pub[[:space:]]+mod[[:space:]]+mcp_discovery"
}
mcpd_core_owner=""
mcpd_rs_owner=""
code_has "$tree/core/server/index.cjs" "require\\('\\./rust-mcp-directory\\.cjs'\\)" && mcpd_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-mcp-directory features; then
  mcpd_rs_owner=rust
fi
[ "$mcpd_core_owner" = "$mcpd_rs_owner" ] \
  || die "MCP directory ownership pairing: Core and Rust must move together"
if [ "$mcpd_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "MCP directory ownership pairing: missing route contract"
  mcpd_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 ~ /^\/api\/admin\/mcp-directory(\/|$)/ {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "MCP directory ownership pairing: every method of the paths must belong to Rust"
  mcpd_routes="$(printf '%s\n' "$mcpd_routes" | LC_ALL=C sort | tr '\n' ' ')"
  [ "$mcpd_routes" = "/api/admin/mcp-directory /api/admin/mcp-directory/custom /api/admin/mcp-directory/custom/preview /api/admin/mcp-directory/{*} /api/admin/mcp-directory/{*}/keys /api/admin/mcp-directory/{id}/oauth-client " ] \
    || die "MCP directory ownership pairing: incomplete route ownership"
  discovery_pair_ok || die "MCP directory ownership pairing: Core does not publish the discovery snapshot the front reads"
  # Node re-reads the table and never writes it: a Core that still writes it beside the front would be a second writer.
  ! code_has "$tree/core/server/directory-mcp.cjs" "(INSERT[[:space:]]+(OR[[:space:]]+[A-Za-z]+[[:space:]]+)?INTO|REPLACE[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM)[[:space:]]+.?directory_mcp_servers" \
    || die "MCP directory ownership pairing: Core still writes directory_mcp_servers"
  # The table is on Core's list of the front's, and the front re-seals the shared key for a rotation.
  code_has "$tree/core/server/rust-mcp-credentials.cjs" "directory_mcp_servers" \
    || die "MCP directory ownership pairing: Core does not treat directory_mcp_servers as the front's"
  code_has "$tree/rs/bins/noevia-server/src/mcp_broker.rs" "directory_mcp_servers" \
    || die "MCP directory ownership pairing: the front does not re-seal the shared keys"
fi

ptb_core_owner=""
ptb_rs_owner=""
code_has "$tree/core/server/index.cjs" "require\\('\\./rust-toolboxes-permitted\\.cjs'\\)" && ptb_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-toolboxes-permitted features; then
  ptb_rs_owner=rust
fi
[ "$ptb_core_owner" = "$ptb_rs_owner" ] \
  || die "permitted tools ownership pairing: Core and Rust must move together"
if [ "$ptb_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "permitted tools ownership pairing: missing route contract"
  ptb_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/toolboxes/permitted" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "permitted tools ownership pairing: every method of the path must belong to Rust"
  [ "$(printf '%s' "$ptb_routes" | tr '\n' ' ')" = "/api/toolboxes/permitted" ] \
    || die "permitted tools ownership pairing: incomplete route ownership"
  discovery_pair_ok || die "permitted tools ownership pairing: Core does not publish the discovery snapshot the front reads"
fi

cnx_core_owner=""
cnx_rs_owner=""
code_has "$tree/core/server/index.cjs" "require\\('\\./rust-connectors\\.cjs'\\)" && cnx_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-connectors features; then
  cnx_rs_owner=rust
fi
[ "$cnx_core_owner" = "$cnx_rs_owner" ] \
  || die "connectors ownership pairing: Core and Rust must move together"
if [ "$cnx_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "connectors ownership pairing: missing route contract"
  cnx_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/connectors") return "GET"
      if (path == "/api/connectors/nextcloud/policy") return "PUT"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want($1)) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "connectors ownership pairing: exactly GET /api/connectors and PUT /api/connectors/nextcloud/policy must belong to Rust"
  cnx_routes="$(printf '%s\n' "$cnx_routes" | LC_ALL=C sort | tr '\n' ' ')"
  [ "$cnx_routes" = "/api/connectors /api/connectors/nextcloud/policy " ] \
    || die "connectors ownership pairing: incomplete route ownership"
  discovery_pair_ok || die "connectors ownership pairing: Core does not publish the discovery snapshot the front reads"
fi

# The provider model lists (#2190, round 5): Core's rust-provider-models.cjs refusal (every method on
# the exact path) and the front's rust-provider-models capability, with the route Rust's for every
# method in routes.toml.
pmod_core_owner=""
pmod_rs_owner=""
grep -qF "require('./rust-provider-models.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && pmod_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-provider-models features; then
  pmod_rs_owner=rust
fi
[ "$pmod_core_owner" = "$pmod_rs_owner" ] \
  || die "provider model list ownership pairing: Core and Rust must move together"
if [ "$pmod_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "provider model list ownership pairing: missing route contract"
  pmod_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/providers/{providerId}/models{*?}" {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "provider model list ownership pairing: the route must belong to Rust for every method"
  [ "$pmod_routes" = "/api/providers/{providerId}/models{*?}" ] || die "provider model list ownership pairing: incomplete route ownership"
fi

# Google Drive's token authority (#2190, round 7): Core's rust-google-drive.cjs refusal and the front's
# rust-google-drive capability, with exactly POST of the connect and disconnect routes and PUT of the policy
# and backup-copy routes Rust's in routes.toml (GET /api/connectors and the Nextcloud policy stay Node's).
gdrv_core_owner=""
gdrv_rs_owner=""
grep -qF "require('./rust-google-drive.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && gdrv_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-google-drive features; then
  gdrv_rs_owner=rust
fi
[ "$gdrv_core_owner" = "$gdrv_rs_owner" ] \
  || die "Google Drive ownership pairing: Core and Rust must move together"
if [ "$gdrv_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "Google Drive ownership pairing: missing route contract"
  gdrv_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    function want(path) {
      if (path == "/api/connectors/gdrive/connect" || path == "/api/connectors/gdrive/disconnect") return "POST"
      if (path == "/api/connectors/gdrive/policy" || path == "/api/connectors/gdrive/backup-copy") return "PUT"
      return ""
    }
    want($1) != "" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want($1)) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }')" || die "Google Drive ownership pairing: exactly the connector writes' methods of the routes must belong to Rust"
  gdrv_routes="$(printf '%s\n' "$gdrv_routes" | sort | tr '\n' ' ')"
  [ "$gdrv_routes" = "/api/connectors/gdrive/backup-copy /api/connectors/gdrive/connect /api/connectors/gdrive/disconnect /api/connectors/gdrive/policy " ] \
    || die "Google Drive ownership pairing: incomplete route ownership"
fi

# The off-site backup (#2190, round 7): Core's rust-offsite-backup.cjs refusal and the front's
# rust-offsite-backup capability, with all eight paths (the seven of the first cut and the review's
# new-store action) Rust's for every method in routes.toml.
offs_core_owner=""
offs_rs_owner=""
grep -qF "require('./rust-offsite-backup.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && offs_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-offsite-backup features; then
  offs_rs_owner=rust
fi
[ "$offs_core_owner" = "$offs_rs_owner" ] \
  || die "off-site backup ownership pairing: Core and Rust must move together"
if [ "$offs_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "off-site backup ownership pairing: missing route contract"
  offs_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 ~ /^\/api\/admin\/offsite-backup(\/|$)/ {
      if ($2 != "rust" || $3 != "-" || $4 != "-") exit 1
      print $1
    }')" || die "off-site backup ownership pairing: every method of the paths must belong to Rust"
  offs_routes="$(printf '%s\n' "$offs_routes" | sort | tr '\n' ' ')"
  [ "$offs_routes" = "/api/admin/offsite-backup /api/admin/offsite-backup/copy /api/admin/offsite-backup/google/connect /api/admin/offsite-backup/google/disconnect /api/admin/offsite-backup/new-store /api/admin/offsite-backup/recovery-key /api/admin/offsite-backup/run /api/admin/offsite-backup/verify " ] \
    || die "off-site backup ownership pairing: incomplete route ownership"
  # Core refuses exactly the paths the front answers: the new-store action included, or a stale Core
  # would route an administrator's "this is a new store" to a Node that has no such path.
  grep -qF "'/api/admin/offsite-backup/new-store'" "$tree/core/server/rust-offsite-backup.cjs" 2>/dev/null \
    || die "off-site backup ownership pairing: Core does not refuse the new-store path"
fi

# The two read-only model sizing reads (sbstndalton/noevia#2189) move as one owner: Core's
# rust-model-sizing.cjs refusal of their GET and the front's rust-model-sizing capability, with
# exactly GET of both routes Rust's in routes.toml (Node keeps every other method). Historic old/old
# pins remain valid rollback pairs.
sizing_core_owner=""
sizing_rs_owner=""
grep -qF "require('./rust-model-sizing.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && sizing_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-sizing features; then
  sizing_rs_owner=rust
fi
[ "$sizing_core_owner" = "$sizing_rs_owner" ] \
  || die "model sizing ownership pairing: Core and Rust must move together"
if [ "$sizing_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "model sizing ownership pairing: missing route contract"
  sizing_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/models/estimate" || $1 == "/api/models/preset/suggest" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "model sizing ownership pairing: exactly GET of both routes must belong to Rust"
  sizing_expected="$(printf '%s\n' /api/models/estimate /api/models/preset/suggest | sort)"
  [ "$sizing_routes" = "$sizing_expected" ] || die "model sizing ownership pairing: incomplete route ownership"
fi

# GET inference-budget and GET installed (sbstndalton/noevia#2262) move as one owner: Core's rust-model-state-reads.cjs
# refusal and the front's rust-model-state-reads capability, with exactly GET of both Rust's in routes.toml (the budget's
# PUT stays Node's). Core must have dropped the handlers and hand the front its facts on the loopback check, with the
# secret captured as for research. Old/old remains a valid rollback pair; either mixed generation is refused.
ms_core_owner=""
ms_rs_owner=""
grep -qF "require('./rust-model-state-reads.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && ms_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-state-reads features; then
  ms_rs_owner=rust
fi
[ "$ms_core_owner" = "$ms_rs_owner" ] \
  || die "model state read ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # An unreadable table is the route-table check's to report, below.
  ms_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || ms_table=""
  ms_routes="$(printf '%s\n' "$ms_table" | awk -F'\t' -v want="$ms_rs_owner" '
    $1 == "/api/models/inference-budget" || $1 == "/api/models/installed" {
      if (want == "rust") {
        if ($2 != "rust" || $3 != "-") exit 1
        n = split($4, m, /[^A-Z]+/); k = 0
        for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "GET") exit 1; k++ }
        if (k != 1) exit 1
      }
      if (want != "rust" && $2 != "node") exit 1
      print $1
    }')" || die "model state read ownership pairing: exactly GET of both routes must be Rust's with the new pair, and Node's with the old"
  if [ "$ms_rs_owner" = rust ]; then
    [ "$(printf '%s\n' "$ms_routes" | sort -u | wc -l | tr -d ' ')" = 2 ] || die "model state read ownership pairing: incomplete route ownership"
    grep -qF "OWNED_PATHS = Object.freeze(['/api/models/inference-budget', '/api/models/installed'])" "$tree/core/server/rust-model-state-reads.cjs" 2>/dev/null \
      || die "model state read ownership pairing: Core must refuse exactly the two reads the front answers"
    ! grep -qE 'inferenceEstimates|await modelsInstalled\(\)\)' "$tree/core/server/routes/models.cjs" 2>/dev/null \
      || die "model state read ownership pairing: Core still carries the read handlers"
    [ -f "$tree/core/server/rust-model-facts.cjs" ] \
      || die "model state read ownership pairing: Core does not offer the front its model facts"
    ms_index="$(code_lines "$tree/core/server/index.cjs")"
    grep -qE 'modelFactsBridge\(req, res\)' <<<"$ms_index" \
      || die "model state read ownership pairing: Core does not mount the model facts bridge"
    ms_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$ms_index" | head -1)"
    [ -n "$ms_secret" ] && awk -v c="$ms_secret" '
      /createModelFactsBridge\(\{/ { bridge = NR }
      index($0, "secret: " c) && bridge && NR - bridge <= 3 { ok = 1 }
      END { exit !ok }
    ' <<<"$ms_index" \
      || die "model state read ownership pairing: Core does not hand its model facts bridge the front's captured secret"
  fi
fi

# The model maintenance routes (sbstndalton/noevia#2210) move as one owner: Core's rust-model-maintenance.cjs
# refusal and the front's rust-model-maintenance capability, with exactly POST /api/models/presets/reload,
# GET /api/models/evidence and POST /api/models/evidence/import Rust's in routes.toml (Node keeps every other
# method; recheck moves separately in #2286). The front is the single writer of the reload guard state file and the evidence
# store; a mixed pair would have two writers or none. Historic old/old pins remain valid rollback pairs.
maint_core_owner=""
maint_rs_owner=""
grep -qF "require('./rust-model-maintenance.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && maint_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-maintenance features; then
  maint_rs_owner=rust
fi
[ "$maint_core_owner" = "$maint_rs_owner" ] \
  || die "model maintenance ownership pairing: Core and Rust must move together"
if [ "$maint_rs_owner" = rust ]; then
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "model maintenance ownership pairing: missing route contract"
  maint_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/models/presets/reload" || $1 == "/api/models/evidence" || $1 == "/api/models/evidence/import" {
      want = ($1 == "/api/models/evidence") ? "GET" : "POST"
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | sort)" || die "model maintenance ownership pairing: exactly the one method of each route must belong to Rust"
  maint_expected="$(printf '%s\n' /api/models/presets/reload /api/models/evidence /api/models/evidence/import | sort)"
  [ "$maint_routes" = "$maint_expected" ] || die "model maintenance ownership pairing: incomplete route ownership"
  # Recheck needs its own native probe/admission pairing, beyond this earlier maintenance group.
  if ! move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-evidence-recheck features && routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '$1 == "/api/models/evidence/recheck" && $2 == "rust" { f = 1 } END { exit !f }'; then
    die "model maintenance ownership pairing: the recheck stays Node's"
  fi
fi

# #2286: the 1x1 recheck probe and evidence filing are native; Node keeps live admission only.
er_core_owner=""
er_rs_owner=""
grep -qF "require('./rust-model-evidence-recheck.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && er_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-model-evidence-recheck features; then er_rs_owner=rust; fi
[ "$er_core_owner" = "$er_rs_owner" ] || die "evidence recheck ownership pairing: Core and Rust must move together"
if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # The common contract parser below reports malformed TOML; preserve its old-pair diagnostic.
  er_table="$(routes_toml "$tree/rs/contracts/http/routes.toml" 2>/dev/null)" || er_table=""
  er_rows="$(printf '%s\n' "$er_table" | awk -F'\t' -v want="$er_rs_owner" '
    $1 == "/api/models/evidence/recheck" {
      if(want=="rust") {
        if($2!="rust" || $3!="-") exit 1
        n=split($4,m,/[^A-Z]+/); k=0
        for(i=1;i<=n;i++) if(m[i]!="") {if(m[i]!="POST") exit 1;k++}
        if(k!=1) exit 1
      } else if($2!="node") exit 1
      print $1
    }')" || die "evidence recheck ownership pairing: POST alone must be native with the new pair and Node's with the old"
  if [ "$er_rs_owner" = rust ]; then
    [ "$maint_rs_owner" = rust ] || die "evidence recheck ownership pairing: native evidence store required"
    [ "$(printf '%s\n' "$er_rows" | wc -w | tr -d ' ')" = 1 ] || die "evidence recheck ownership pairing: missing route"
    er_refused="$( { project_routes_core "$tree/core/server/rust-model-evidence-recheck.cjs" || true; } | sort | tr '\n' ' ')"
    [ "$er_refused" = 'POST /api/models/evidence/recheck ' ] || die "evidence recheck ownership pairing: exact POST refusal required"
    ! grep -qE 'createVisionProbe|source:[[:space:]]*.recheck.' "$tree/core/server/routes/models.cjs" 2>/dev/null || die "evidence recheck ownership pairing: public Node probe still present"
    [ -f "$tree/core/server/inference-admission-lease.cjs" ] || die "evidence recheck ownership pairing: live inference admission required"
    er_index="$(code_lines "$tree/core/server/index.cjs")"
    grep -qE 'inferenceAdmission\.handle\(req, res\)' <<<"$er_index" || die "evidence recheck ownership pairing: inference admission must be mounted"
    er_secret="$(sed -nE "s/^[[:space:]]*const ([A-Za-z_][A-Za-z0-9_]*) = String\(process\.env\.NOEVIA_PROJECT_STORE_TOKEN \|\| ''\);.*/\1/p" <<<"$er_index" | head -1)"
    [ -n "$er_secret" ] && awk -v c="$er_secret" '
      /createAdmissionRoutes\(\{/ {bridge=NR}
      index($0,"secret: " c) && bridge && NR-bridge<=3 {ok=1}
      END {exit !ok}
    ' <<<"$er_index" || die "evidence recheck ownership pairing: captured inference admission secret required"
  fi
fi

# A ported core with no Rust route contract cannot be paired at all. Keep this outside the
# routes-file conditional: otherwise removing that file bypasses the GET/refusal pairing.
if [ ! -f "$tree/rs/contracts/http/routes.toml" ]; then
  web_core="$(web_address_routes_core)"
  [ -z "$web_core" ] || die "web-address GET ownership pairing: core refuses GETs but Rust routes.toml is missing"
fi
# sbstndalton/noevia#2191 round 7 (#697): the large-document lock is the host's. Core's
# large-document-lock.cjs taking large-document-file-lock.cjs and the front's
# rust-large-document-host-lock capability go together, so one large document is held at a time.
large_lock_core_owner=""
large_lock_rs_owner=""
grep -qF "require('./large-document-file-lock.cjs')" "$tree/core/server/large-document-lock.cjs" 2>/dev/null \
  && [ -f "$tree/core/server/large-document-file-lock.cjs" ] && large_lock_core_owner=host
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-large-document-host-lock features; then
  large_lock_rs_owner=host
fi
[ "$large_lock_core_owner" = "$large_lock_rs_owner" ] \
  || die "large-document lock pairing: Core and Rust must share the host lock"
# Both halves must also lock the same thing the same way, or each holds its own "host" lock and two
# large documents run at once again: the lock file's name and the SQLite statement that takes it are
# read from both sources and compared.
if [ "$large_lock_core_owner" = host ]; then
  core_lock_file="$(sed -n "s/^const LOCK_FILE = '\([^']*\)';.*/\1/p" "$tree/core/server/large-document-file-lock.cjs" | head -1)"
  rs_lock_file="$(sed -n 's/^pub const LARGE_LOCK_FILE: &str = "\([^"]*\)";.*/\1/p' "$tree/rs/crates/server-projects/src/extract.rs" | head -1)"
  { [ -n "$core_lock_file" ] && [ "$core_lock_file" = "$rs_lock_file" ]; } \
    || die "large-document lock pairing: Core and Rust must name the same lock file (Core '$core_lock_file', Rust '$rs_lock_file')"
  grep -qF "db.exec('BEGIN IMMEDIATE')" "$tree/core/server/large-document-file-lock.cjs" \
    && grep -qF 'execute_batch("BEGIN IMMEDIATE")' "$tree/rs/crates/server-projects/src/extract.rs" \
    || die "large-document lock pairing: Core and Rust must both take the lock with BEGIN IMMEDIATE"
fi
# sbstndalton/noevia#2191 round 8: the project source operations move as one owner. Core's
# rust-project-source-work.cjs refusal (with its storage latch file and its file-operation reader) and the
# front's rust-project-source-work capability go together. In that generation Core keeps no worker path
# (no source-work.cjs, folder-import.cjs, pdf-reduce.cjs, no `x-noevia-source-work`), the front still runs
# the source jobs (rust-source-jobs), Docling extraction and the host-wide large-document lock, both sides
# name the same storage latch and file-operation files, and routes.toml gives Rust exactly POST of the
# upload, the sync and the folder import's plan.
source_work_core_owner=""
source_work_rs_owner=""
grep -qF "require('./rust-project-source-work.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && source_work_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-project-source-work features; then
  source_work_rs_owner=rust
fi
[ "$source_work_core_owner" = "$source_work_rs_owner" ] \
  || die "project source work ownership pairing: Core and Rust must move together"
if [ "$source_work_rs_owner" = rust ]; then
  for needed in rust-source-jobs rust-document-extraction rust-large-document-host-lock; do
    move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES "$needed" features \
      || die "project source work ownership pairing: needs the $needed capability"
  done
  { [ ! -e "$tree/core/server/source-work.cjs" ] && [ ! -e "$tree/core/server/folder-import.cjs" ] && [ ! -e "$tree/core/server/pdf-reduce.cjs" ] \
    && ! grep -qiF 'x-noevia-source-work' "$tree/core/server/routes/projects.cjs" 2>/dev/null \
    && ! grep -qiF 'x-noevia-source-work' "$tree/core/server/index.cjs" 2>/dev/null; } \
    || die "project source work ownership pairing: Core still carries the worker path"
  [ -f "$tree/core/server/rust-source-ops.cjs" ] && [ -f "$tree/core/server/storage-latch.cjs" ] \
    || die "project source work ownership pairing: Core lacks its readers of the front's file operations and storage latch"
  core_latch="$(code_lines "$tree/core/server/index.cjs" | grep -o "storage-latch\.db" | head -1 || true)"
  rs_latch="$(sed -n 's/^pub const FILE: &str = "\(storage-latch\.db\)";.*/\1/p' "$tree/rs/crates/server-projects/src/storage_latch.rs" 2>/dev/null | head -1)"
  { [ -n "$core_latch" ] && [ "$core_latch" = "$rs_latch" ]; } \
    || die "project source work ownership pairing: Core and Rust must name the same storage latch file (Core '$core_latch', Rust '$rs_latch')"
  core_ops="$(sed -n "s/^const FILE = '\(source-file-ops\.json\)';.*/\1/p" "$tree/core/server/rust-source-ops.cjs" 2>/dev/null | head -1)"
  rs_ops="$(sed -n 's/^pub const FILE: &str = "\(source-file-ops\.json\)";.*/\1/p' "$tree/rs/crates/server-projects/src/source_ops.rs" 2>/dev/null | head -1)"
  { [ -n "$core_ops" ] && [ "$core_ops" = "$rs_ops" ]; } \
    || die "project source work ownership pairing: Core and Rust must name the same file-operation list (Core '$core_ops', Rust '$rs_ops')"
  latch_core_code="$(code_lines "$tree/core/server/storage-latch.cjs")"
  latch_rs_code="$(code_lines "$tree/rs/crates/server-projects/src/storage_latch.rs")"
  { grep -qF "exec('BEGIN IMMEDIATE')" <<<"$latch_core_code" && grep -qF 'execute_batch("BEGIN IMMEDIATE")' <<<"$latch_rs_code"; } \
    || die "project source work ownership pairing: Core and Rust must both change the storage latch with BEGIN IMMEDIATE"
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "project source work ownership pairing: missing route contract"
  source_work_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/upload" || $1 == "/api/projects/{id}/sources/sync" || $1 == "/api/projects/{id}/folder-import/plan" {
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != "POST") exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | LC_ALL=C sort | tr '\n' ' ')" || die "project source work ownership pairing: exactly POST of the upload, the sync and the folder import's plan must belong to Rust"
  [ "$source_work_routes" = "/api/projects/{id}/folder-import/plan /api/projects/{id}/sources/sync /api/projects/{id}/upload " ] \
    || die "project source work ownership pairing: incomplete route ownership"
fi
# A partially ported source journal would either strand a 202 without a reader or give
# source files two owners. Old core/old Rust remains an allowed rollback pair.
# sbstndalton/noevia#2191 round 6: the source jobs move as one owner. Core's rust-source-jobs.cjs
# refusal and the front's rust-source-jobs capability go together; in that generation Core keeps no
# source journal client (no marker, no sourceJobsFor, no source-jobs.cjs), the front serves no
# internal source store (no marker, no /v1/source-jobs/ route), and routes.toml gives Rust exactly
# POST of the upload and the sync (the background start) and GET of the poll.
source_jobs_core_owner=""
source_jobs_rs_owner=""
grep -qF "require('./rust-source-jobs.cjs')" "$tree/core/server/index.cjs" 2>/dev/null && source_jobs_core_owner=rust
if move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-source-jobs features; then
  source_jobs_rs_owner=rust
fi
[ "$source_jobs_core_owner" = "$source_jobs_rs_owner" ] \
  || die "source job ownership pairing: Core and Rust must move together"
if [ "$source_jobs_rs_owner" = rust ]; then
  ! grep -qE 'SOURCE_JOBS_CLIENT_MARKER|sourceJobsFor\(' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
    && [ ! -e "$tree/core/server/source-jobs.cjs" ] \
    || die "source job ownership pairing: Core still carries a source journal client"
  ! grep -qF 'SOURCE_JOBS_STORE_MARKER' "$tree/rs/bins/noevia-server/src/lib.rs" 2>/dev/null \
    && ! grep -qF '/v1/source-jobs/' "$tree/rs/bins/noevia-server/src/project_store.rs" 2>/dev/null \
    || die "source job ownership pairing: the front still serves the internal source store"
  [ -f "$tree/rs/contracts/http/routes.toml" ] || die "source job ownership pairing: missing route contract"
  source_jobs_routes="$(routes_toml "$tree/rs/contracts/http/routes.toml" | awk -F'\t' '
    $1 == "/api/projects/{id}/upload" || $1 == "/api/projects/{id}/sources/sync" || $1 == "/api/projects/{id}/source-jobs/{jobId}" {
      want = ($1 ~ /source-jobs/) ? "GET" : "POST"
      if ($2 != "rust" || $3 != "-") exit 1
      n = split($4, m, /[^A-Z]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") { if (m[i] != want) exit 1; k++ }
      if (k != 1) exit 1
      print $1
    }' | LC_ALL=C sort | tr '\n' ' ')" || die "source job ownership pairing: exactly POST of the upload and the sync and GET of the poll must belong to Rust"
  [ "$source_jobs_routes" = "/api/projects/{id}/source-jobs/{jobId} /api/projects/{id}/sources/sync /api/projects/{id}/upload " ] \
    || die "source job ownership pairing: incomplete route ownership"
elif [ -f "$tree/rs/crates/server-projects/src/source_jobs.rs" ] \
   || grep -qE 'SOURCE_JOBS_CLIENT_MARKER|sourceJobsFor\(' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
   || grep -qF 'workspace.sourceJobs' "$tree/core/server/source-jobs.cjs" 2>/dev/null; then
  core_source_client && rs_source_store || die "source job store pairing: core needs an exported source client and Rust needs the compiled source store capability and six internal routes"
fi
# Port contract row J: the front is the one model-maintenance lease authority, and Core's
# maintenance gate takes every hold there and fails closed without it. Core and Rust must carry the
# same lease generation; legacy/legacy (none/none) stays the rollback pair. Detection follows the
# outbox pairing (f57a4e3): Core's value is what server/model-maintenance-lease.cjs actually exports
# as LEASE_CLIENT_MARKER (evaluated in node:vm under a hard time limit, every require stubbed; a
# marker literal without the export is invalid), and Rust's is the single unconditional ordinary
# string literal "noevia-maintenance-lease-authority/<n>" in lib.rs's one FEATURES array (comment-,
# raw-, byte- and escape-aware tokenizer; attributes, macros, expressions, duplicates, escaped
# duplicates and unknown versions are invalid). Invalid always refuses.
lease_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /noevia-maintenance-lease-client\//.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.LEASE_CLIENT_MARKER;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^noevia-maintenance-lease-(client)\/([12])$/.exec(value);
    process.stdout.write(m ? "v" + m[2] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal or one plain path; macros, expressions,
# raw or byte strings refuse. An outbox entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown outbox entries are invalid; no FEATURES array or no entry is absence.
lease_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // Row J review P2: the declaration itself must be unconditional and at the crate root of lib.rs:
    // no attribute of its own (cfg or any other), not inside a module, function, block or macro body
    // (depth 0), and no crate-level cfg attribute. A scope that cannot be proven this way is invalid.
    if (/#!\s*\[\s*cfg/.test(code)) out("invalid"); // cfg and cfg_attr at crate level
    const before = code.slice(0, decls[0].index);
    let scope = 0;
    for (const ch of before) {
      if (ch === "(" || ch === "[" || ch === "{") scope++;
      else if (ch === ")" || ch === "]" || ch === "}") scope--;
    }
    if (scope !== 0) out("invalid");
    let lead = before.slice(Math.max(before.lastIndexOf(";"), before.lastIndexOf("}")) + 1).trim();
    // Delta review P3: crate inner attributes (#![...], balanced, never cfg/cfg_attr, refused above)
    // apply to the crate, not to the declaration, so they may precede it. An outer #[...] may not.
    while (lead.startsWith("#")) {
      const bang = lead.slice(1).trimStart();
      if (!bang.startsWith("!")) out("invalid");
      const open = bang.slice(1).trimStart();
      if (!open.startsWith("[")) out("invalid");
      let d = 0, end = -1;
      for (let j = 0; j < open.length; j++) {
        if (open[j] === "[" || open[j] === "(" || open[j] === "{") d++;
        else if (open[j] === "]" || open[j] === ")" || open[j] === "}") { d--; if (d === 0) { end = j; break; } }
      }
      if (end < 0) out("invalid");
      if (/^\[\s*cfg/.test(open)) out("invalid");
      lead = open.slice(end + 1).trim();
    }
    if (lead !== "") out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = []; // lease authority entries
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("noevia-maintenance-lease-authority"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("noevia-maintenance-lease-authority")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^noevia-maintenance-lease-authority\/([12])$/.exec(outbox[0]);
    out(m ? "v" + m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
lease_core_owner="$(lease_core_version "$tree/core/server/model-maintenance-lease.cjs")"
lease_rs_owner="$(lease_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$lease_core_owner" != invalid ] && [ "$lease_rs_owner" != invalid ] \
  || die "maintenance lease pairing: ambiguous or unrecognized lease marker (core=$lease_core_owner rust=$lease_rs_owner)"
[ "$lease_core_owner" = "$lease_rs_owner" ] \
  || die "maintenance lease pairing: Core's lease client and the front's lease authority must move together (core=$lease_core_owner rust=$lease_rs_owner)"
reranker_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /reranker-settings-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RERANKER_SETTINGS_OWNER;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^reranker-settings-(v1)$/.exec(value);
    process.stdout.write(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
reranker_core_owner="$(reranker_core_version "$tree/core/server/rerank-settings.cjs")"
reranker_rs_owner="$(rs_capability_version "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES "reranker-settings-v1")"
case "$reranker_rs_owner" in
  invalid\(*\)) die "reranker settings ownership pairing: $reranker_rs_owner" ;;
  legacy) reranker_rs_owner=none ;;
  v1) ;;
  *) die "reranker settings ownership pairing: invalid detector response" ;;
esac
[ "$reranker_core_owner" != invalid ] \
  || die "reranker settings ownership pairing: ambiguous or unrecognized Core capability marker"
[ "$reranker_core_owner" = "$reranker_rs_owner" ] || die "reranker settings ownership pairing: Core and Rust capability versions must match"

# Chat mirror pairing runs after the maintenance lease and reranker guards: its strict whole-FEATURES
# reader refuses any malformed element, so it must not pre-empt their own refusal of their markers. It
# still runs before the history/journal guards below, which read chat_mirror_paired.
# The chat journal tail and the mirror and brain schedules (rust-chat-mirror-v1): the front tails each
# active account's change journal in process and owns the debounce, backoff, idle timers and queue
# (noevia-rs crates/chat-mirror-sched); the core keeps their two work executors (rust-chat-mirror.cjs) and
# nudges the front. Both sides declare it exactly (compiled FEATURES entry; exported RUST_CHAT_MIRROR_OWNED),
# never in a comment. A front without the core's half leaves the journal unread (no mirror or brain follows a
# save); a core without the front's half would run a second schedule beside it. The Node reader must be gone.
chat_mirror_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /rust-chat-mirror-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RUST_CHAT_MIRROR_OWNED;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^rust-chat-mirror-v(1)$/.exec(value);
    process.stdout.write(m ? "v" + m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal or one plain path; macros, expressions,
# raw or byte strings refuse. An outbox entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown outbox entries are invalid; no FEATURES array or no entry is absence.
chat_mirror_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // Row J review P2: the declaration itself must be unconditional and at the crate root of lib.rs:
    // no attribute of its own (cfg or any other), not inside a module, function, block or macro body
    // (depth 0), and no crate-level cfg attribute. A scope that cannot be proven this way is invalid.
    if (/#!\s*\[\s*cfg/.test(code)) out("invalid"); // cfg and cfg_attr at crate level
    const before = code.slice(0, decls[0].index);
    let scope = 0;
    for (const ch of before) {
      if (ch === "(" || ch === "[" || ch === "{") scope++;
      else if (ch === ")" || ch === "]" || ch === "}") scope--;
    }
    if (scope !== 0) out("invalid");
    let lead = before.slice(Math.max(before.lastIndexOf(";"), before.lastIndexOf("}")) + 1).trim();
    // Delta review P3: crate inner attributes (#![...], balanced, never cfg/cfg_attr, refused above)
    // apply to the crate, not to the declaration, so they may precede it. An outer #[...] may not.
    while (lead.startsWith("#")) {
      const bang = lead.slice(1).trimStart();
      if (!bang.startsWith("!")) out("invalid");
      const open = bang.slice(1).trimStart();
      if (!open.startsWith("[")) out("invalid");
      let d = 0, end = -1;
      for (let j = 0; j < open.length; j++) {
        if (open[j] === "[" || open[j] === "(" || open[j] === "{") d++;
        else if (open[j] === "]" || open[j] === ")" || open[j] === "}") { d--; if (d === 0) { end = j; break; } }
      }
      if (end < 0) out("invalid");
      if (/^\[\s*cfg/.test(open)) out("invalid");
      lead = open.slice(end + 1).trim();
    }
    if (lead !== "") out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = []; // lease authority entries
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-chat-mirror-v"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-chat-mirror-v")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^rust-chat-mirror-v(1)$/.exec(outbox[0]);
    out(m ? "v" + m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
chat_mirror_start_enabled() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const target = process.argv[2];
    const matches = [...code.matchAll(new RegExp(target, "g"))];
    if (matches.length !== 1 || /#!\s*\[\s*cfg/.test(code)) out("invalid");
    const before = code.slice(0, matches[0].index);
    const frames = []; let start = 0;
    // Each lexical block inherits the attributes of the item/statement that opens it.
    // Reject a gated ancestor or statement; FEATURES proof separately requires crate root.
    for (let k = 0; k < before.length; k++) {
      const c = before[k];
      if (c === "{") { frames.push(before.slice(start, k)); start = k + 1; }
      else if (c === "}") { frames.pop(); start = k + 1; }
      else if (c === ";") start = k + 1;
    }
    frames.push(before.slice(start));
    if (frames.some(h => /#\s*!?\s*\[\s*cfg/.test(h))) out("invalid");
    out("v1");
  ' "$1" "$2" 2>/dev/null || echo invalid
}
chat_mirror_core_owner=""
chat_mirror_rs_owner=""
if grep -qF "require('./rust-chat-mirror.cjs')" "$tree/core/server/index.cjs" 2>/dev/null; then
  [ "$(chat_mirror_core_version "$tree/core/server/rust-chat-mirror.cjs")" = v1 ] \
    || die "chat mirror ownership pairing: index.cjs requires rust-chat-mirror.cjs, but it does not export RUST_CHAT_MIRROR_OWNED = 'rust-chat-mirror-v1'"
  chat_mirror_core_owner=rust
fi
chat_mirror_version="$(chat_mirror_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$chat_mirror_version" != invalid ] || die "chat mirror schedule ownership pairing: invalid capability scope"
if [ "$chat_mirror_version" = v1 ]; then
  chat_mirror_rs_owner=rust
fi
[ "$chat_mirror_core_owner" = "$chat_mirror_rs_owner" ] \
  || die "chat mirror schedule ownership pairing: Core and Rust must move together (rust-chat-mirror-v1)"
if [ "$chat_mirror_rs_owner" = rust ]; then
  [ ! -e "$tree/core/server/chat-change-journal.cjs" ] \
    || die "chat mirror schedule ownership pairing: the core still carries the Node journal reader (server/chat-change-journal.cjs) beside the front's schedule"
  [ "$(chat_mirror_start_enabled "$tree/rs/bins/noevia-server/src/lib.rs" 'pub\s+mod\s+chat_mirror\s*;')" = v1 ] \
    && move_capability "$tree/rs/crates/chat-mirror-sched/src/lib.rs" MARKER noevia-chat-mirror-scheduler/1 rust \
    && [ "$(chat_mirror_start_enabled "$tree/rs/bins/noevia-server/src/main.rs" 'ChatMirror\s*::\s*start\s*\(')" = v1 ] \
    || die "chat mirror schedule ownership pairing: the front declares rust-chat-mirror-v1 but does not carry and start the schedule (chat_mirror.rs, crate chat-mirror-sched)"
  chat_mirror_paired=rust
fi
# End of chat mirror pairing.

if [ -f "$tree/rs/contracts/http/routes.toml" ]; then
  # The supervisor no longer forwards a context switch. An older switched front
  # paired with permanent core refusal would leave these routes unavailable.
  routes_file="$tree/rs/contracts/http/routes.toml"
  routes_err="$(routes_toml "$routes_file" 2>&1 >/dev/null)" \
    || die "noevia-rs at $rs_ref: routes.toml cannot be read safely, so the switch checks would not be trustworthy (#2096): $routes_err"
  route_switches="$(switched_routes "$routes_file")"
  if printf '%s\n' "$route_switches" | grep -q '^NOEVIA_RUST_PROJECT_WRITES '; then
    die "noevia-rs at $rs_ref still gates chat context on NOEVIA_RUST_PROJECT_WRITES; pin permanent GET/POST context ownership (sbstndalton/noevia#1071)"
  fi
  # The three GETs pair together; the two POST writers transfer together on the
  # dependent pair. HEAD and every other method remain Node's.
  web_rs="$(web_address_routes_rs "$routes_file")"
  web_core="$(web_address_routes_core)"
  web_expected="$(printf 'GET /api/admin/web-address\nGET /api/instance\nGET /.well-known/webauthn' | sort)"
  web_write_expected="$(printf '%s\nPOST /api/admin/web-address\nPOST /api/admin/web-address/remove' "$web_expected" | sort)"
  if [ -n "$web_rs" ] || [ -n "$web_core" ]; then
    { [ "$web_rs" = "$web_expected" ] && [ "$web_core" = "$web_expected" ]; } \
      || { [ "$web_rs" = "$web_write_expected" ] && [ "$web_core" = "$web_write_expected" ]; } \
      || die "web-address ownership pairing: Rust and Node must agree on three GETs and both POST writers together; preserve HEAD/other methods"
    move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-web-address-read features \
      || die "web-address GET ownership pairing: Rust route table lacks a compiled --features declaration"
    if [ "$web_rs" = "$web_write_expected" ]; then
      move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-web-address-write features \
        || die "web-address POST ownership pairing: Rust route table lacks a compiled --features declaration"
      grep -qF "rust-web-address-write" "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
        || die "web-address POST ownership pairing: web supervisor lacks a prelaunch capability comparison"
    fi
    grep -qF 'WEB_ADDRESS_READ_OWNER' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
      && grep -qF "rust-web-address-read" "$tree/noevia/build/web-supervisor.sh" 2>/dev/null \
      || die "web-address GET ownership pairing: web supervisor lacks a prelaunch capability comparison"
  fi
  # sbstndalton/noevia#1071: the project routes are the front's with no switch. The web supervisor
  # no longer passes NOEVIA_RUST_PROJECTS, so a front that still gates them on it (before the
  # noevia-rs retirement) would leave them to a Node that refuses them; and a front that owns them
  # with no switch needs a core whose refusal is unconditional (rust-projects.cjs refuseOwnedRoute)
  # and that always writes through the project store.
  if printf '%s\n' "$route_switches" | grep -q '^NOEVIA_RUST_PROJECTS '; then
    die "noevia-rs at $rs_ref still gates the project routes on NOEVIA_RUST_PROJECTS, which this web supervisor no longer passes; pin a noevia-rs that owns them with no switch (sbstndalton/noevia#1071)"
  fi
  if ! grep -q '^function refuseOwnedRoute' "$tree/core/server/rust-projects.cjs" 2>/dev/null; then
    die "noevia-core at $(lock_value NOEVIA_CORE_REF) still gates its project routes on NOEVIA_RUST_PROJECTS (no unconditional refuseOwnedRoute in server/rust-projects.cjs), which this web supervisor no longer passes; pin a core that refuses them always (sbstndalton/noevia#1071)"
  fi
  # sbstndalton/noevia#2191: a project source's stored reads are listed by core/server/rust-project-reads.cjs,
  # a project's create and delete (round 2) by core/server/rust-project-lifecycle.cjs, a source file's
  # delete (round 3) by core/server/rust-project-files.cjs, a document's page reader (round 4) by
  # core/server/rust-project-document-pages.cjs, a document's upload (round 5) by
  # core/server/rust-project-documents.cjs, the source jobs (round 6) by core/server/rust-source-jobs.cjs, the
  # source operations (round 8) by core/server/rust-project-source-work.cjs, a project's configuration and
  # instruction skills (round 9) by core/server/rust-project-config.cjs, deep research (#2218) by core/server/rust-research.cjs, the task reads (#2257) by core/server/rust-task-reads.cjs.
  missing="$(comm -23 <(project_routes_rs "$tree/rs/contracts/http/routes.toml") <({ project_routes_core "$tree/core/server/rust-projects.cjs"; project_routes_core "$tree/core/server/rust-project-reads.cjs"; project_routes_core "$tree/core/server/rust-project-lifecycle.cjs"; project_routes_core "$tree/core/server/rust-project-files.cjs"; project_routes_core "$tree/core/server/rust-project-document-pages.cjs"; project_routes_core "$tree/core/server/rust-project-documents.cjs"; project_routes_core "$tree/core/server/rust-source-jobs.cjs"; project_routes_core "$tree/core/server/rust-project-source-work.cjs"; project_routes_core "$tree/core/server/rust-project-config.cjs"; project_routes_core "$tree/core/server/rust-research.cjs"; project_routes_core "$tree/core/server/rust-task-reads.cjs"; } | sort -u))"
  [ -z "$missing" ] || die "noevia-rs at $rs_ref owns project routes that noevia-core at $(lock_value NOEVIA_CORE_REF) does not list in server/rust-projects.cjs OWNED_ROUTES (pin a core that does): $(printf '%s' "$missing" | tr '\n' ';')"
  # sbstndalton/noevia#1071: a front that owns sign-in with no switch (routes.toml: GET
  # /api/auth/session owner "rust", no `switch`) needs a core whose rust-auth guard is unconditional
  # (server/rust-auth.cjs refuseOwned). The web supervisor no longer hands Node NOEVIA_RUST_AUTH or
  # its confirmation, so an older core would run as a second writer of the account tables.
  # sbstndalton/noevia#1931: this repo's web supervisor no longer passes NOEVIA_RUST_AUTH, so a
  # front that still gates sign-in on it (before noevia-rs#146) would refuse NOEVIA_RUST_PROJECTS
  # and web would restart-loop. Every pinned rs must own sign-in with no switch.
  rust_auth_unswitched "$tree/rs/contracts/http/routes.toml" \
    || die "noevia-rs at $rs_ref still gates sign-in on NOEVIA_RUST_AUTH (GET /api/auth/session is not Rust-owned without a switch), which this web supervisor no longer passes; pin a noevia-rs with rs#146 (sbstndalton/noevia#1931)"
  if rust_auth_unswitched "$tree/rs/contracts/http/routes.toml" \
     && ! grep -q '^function refuseOwned' "$tree/core/server/rust-auth.cjs" 2>/dev/null; then
    die "noevia-rs at $rs_ref owns sign-in with no switch, but noevia-core at $(lock_value NOEVIA_CORE_REF) still gates its rust-auth guard on NOEVIA_RUST_AUTH (pin a core with an unconditional server/rust-auth.cjs, sbstndalton/noevia#1071)"
  fi
  # sbstndalton/noevia#1071: a front that reads NOEVIA_START_ID (the per-start id in a running
  # reply's partial file) refuses to start beside Node without it, so this release's own web
  # supervisor must make one and hand it to both processes. Keyed on any Rust source of the
  # front's binaries naming the variable, or on its `start-id` --features entry, so a moved or
  # renamed config.rs cannot make the check pass unseen (sbstndalton/noevia#2146).
  if rs_reads_start_id \
     && [ "$(grep -c 'NOEVIA_START_ID="\$start_id"' "$tree/noevia/build/web-supervisor.sh" 2>/dev/null)" -lt 2 ]; then
    die "noevia-rs at $rs_ref needs NOEVIA_START_ID, but this release's build/web-supervisor.sh does not hand it to both processes (sbstndalton/noevia#1071)"
  fi
  # sbstndalton/noevia#1071 slice 2: a front that answers GET /api/chats/{chatId}/history tells a
  # running reply's partial from an interrupted one only by the `running: { start }` marker the
  # pinned core writes into every save (noevia-core#245), and needs that core to take the marker
  # out when a finished reply's partial cannot be removed (endPartial, sbstndalton/noevia#2146).
  # An older core would have the front offer half-streamed replies as interrupted, or hide an
  # ended one until the next start.
  if rust_owns_history_get "$routes_file"; then
    partial_js="$tree/core/server/chat-partial.cjs"
    grep -q 'running: { start: START_ID }' "$partial_js" 2>/dev/null \
      || die "noevia-rs at $rs_ref answers GET /api/chats/{chatId}/history, but noevia-core at $(lock_value NOEVIA_CORE_REF) does not mark a running reply's partial (server/chat-partial.cjs running: { start: START_ID }); pin a core with noevia-core#245 (sbstndalton/noevia#1071)"
    grep -q '^function endPartial' "$partial_js" 2>/dev/null \
      || die "noevia-rs at $rs_ref answers GET /api/chats/{chatId}/history, but noevia-core at $(lock_value NOEVIA_CORE_REF) can leave a finished reply's running marker behind (no endPartial in server/chat-partial.cjs); pin a core with the sbstndalton/noevia#2146 fix"
  fi
  # sbstndalton/noevia#1071 slice 4: a core that saves transcripts through the front's store ops
  # (history-<id>.json written by Rust only) needs a front that serves them, or every transcript
  # save, interrupted reply and import fails (Node has no local fallback, by design).
  if core_uses_history_ops && ! rs_serves_history_ops; then
    die "noevia-core at $(lock_value NOEVIA_CORE_REF) saves transcripts through the project store's history ops, but noevia-rs at $rs_ref does not serve them (no /v1/history/append-if-last under rs/bins); pin a noevia-rs with the #1071 slice 4 store ops"
  fi
  # sbstndalton/noevia#1071 slice 5: a front that answers POST /api/chats/{chatId}/history writes
  # the transcript itself. The core beside it must write it only through the front's store (or
  # two processes write the file, the interrupted-reply path with no lock), and must refuse the
  # POST (rust-projects.cjs OWNED_ROUTES) so there is never a window where both answer it.
  if rust_owns_history_post "$routes_file"; then
    core_writes_history_via_store \
      || die "noevia-rs at $rs_ref answers POST /api/chats/{chatId}/history, but noevia-core at $(lock_value NOEVIA_CORE_REF) still writes transcripts itself (no store ops in server/project-store-client.cjs, chat-interrupted-turn.cjs, conversation-import.cjs, or projects.cjs writeHistory still there); pin a core with the #1071 slice 4 writers"
    project_routes_core "$tree/core/server/rust-projects.cjs" | grep -qx 'POST /api/chats/{}/history' \
      || die "noevia-rs at $rs_ref answers POST /api/chats/{chatId}/history, but noevia-core at $(lock_value NOEVIA_CORE_REF) does not refuse it (not in server/rust-projects.cjs OWNED_ROUTES); pin a core that hands the save to the front (sbstndalton/noevia#1071 slice 5)"
    # sbstndalton/noevia#2153 (slice 5a): Node never sees a save the front answers, so the chat's
    # Diary mirror and brain follow it only through the front's change journal, which the core must
    # tail and the front must write.
    core_tails_change_journal \
      || die "noevia-rs at $rs_ref answers POST /api/chats/{chatId}/history, but noevia-core at $(lock_value NOEVIA_CORE_REF) does not tail the chat change journal (no noevia-chat-change-journal-reader/1 in server/chat-change-journal.cjs), so the chat mirror and brain would stop following saves; pin a core with the sbstndalton/noevia#2153 reader"
    rs_serves_change_journal \
      || die "noevia-rs at $rs_ref answers POST /api/chats/{chatId}/history but does not journal transcript changes (no /v1/changes/read under rs/bins), so the chat mirror and brain would stop following saves; pin a noevia-rs with the sbstndalton/noevia#2153 journal"
  fi
  # sbstndalton/noevia#1071 slice 5, the other way round: a core that refuses the history save
  # (rust-projects.cjs OWNED_ROUTES, noevia-core with the Node handler deleted) beside a front that
  # does not answer it (before noevia-rs#291) would leave every chat save to a Node that answers
  # 503 RUST_PROJECTS_OWNED.
  if ! rust_owns_history_post "$routes_file" \
     && project_routes_core "$tree/core/server/rust-projects.cjs" | grep -qx 'POST /api/chats/{}/history'; then
    die "noevia-core at $(lock_value NOEVIA_CORE_REF) refuses POST /api/chats/{chatId}/history (server/rust-projects.cjs OWNED_ROUTES), but noevia-rs at $rs_ref does not answer it (routes.toml), so every chat save would fail; pin a noevia-rs that owns the history save (noevia-rs#291, sbstndalton/noevia#1071 slice 5)"
  fi
  # sbstndalton/noevia#1071 slice 6: a chat's delete is one store operation in the front. A front
  # that answers the DELETE routes needs a core that refuses them (the generic OWNED_ROUTES check
  # above names any missing one) and whose own deletes (the retention sweep, a project's purge) go
  # through that operation too, or Node removes transcripts and writes tombstones beside it with no
  # lock. A core that deletes through the operation needs a front that serves it, or every one of
  # those deletes fails. And a core that refuses the routes beside a front that does not answer
  # them would leave every chat delete to a 503.
  if rust_owns_chat_delete "$routes_file"; then
    core_deletes_via_store \
      || die "noevia-rs at $rs_ref answers a chat's DELETE, but noevia-core at $(lock_value NOEVIA_CORE_REF) still deletes chats itself (no 'noevia-chat-delete-client/1' in server/project-store-client.cjs); pin a core that deletes through the store (sbstndalton/noevia#1071 slice 6)"
  fi
  if core_deletes_via_store && ! rs_serves_chat_delete; then
    die "noevia-core at $(lock_value NOEVIA_CORE_REF) deletes chats through the project store's chat/delete, but noevia-rs at $rs_ref does not serve it (no \"noevia-chat-delete-store/1\" in crates/server-projects/src); pin a noevia-rs with the #1071 slice 6 store operation"
  fi
  # Check each refused route independently: the other route still being Rust-owned does not
  # make a returned-to-Node route available (#2168).
  for delete_path in '/api/freechats/{}' '/api/projects/{}/chats/{}'; do
    if project_routes_core "$tree/core/server/rust-projects.cjs" | grep -qxF "DELETE $delete_path" \
       && ! project_routes_rs "$routes_file" | grep -qxF -e "DELETE $delete_path" -e "ALL $delete_path"; then
      die "noevia-core at $(lock_value NOEVIA_CORE_REF) refuses a chat's DELETE (DELETE $delete_path in server/rust-projects.cjs OWNED_ROUTES), but noevia-rs at $rs_ref does not answer it (routes.toml), so that chat delete would fail; pin a noevia-rs that owns this chat delete route (sbstndalton/noevia#2168)"
    fi
  done
  # #1071 slice7: an internal move capability is unsafe beside old Node grants too.
  # Refuse partial security/provenance stacks even before switching public ownership.
  if rust_owns_chat_move "$routes_file" || core_refuses_chat_move || rs_move_foundation || rs_move_journal \
     || core_move_client || core_move_enforcement || core_move_reader_legacy; then
    move_other_methods="$( { project_routes_rs "$routes_file"; project_routes_core "$tree/core/server/rust-projects.cjs" || true; } | awk '$2=="/api/chats/{}/move" && $1!="POST"')"
    [ -z "$move_other_methods" ] || die "chat move POST ownership pairing: non-POST move ownership/refusal would remove its existing fallback"
    rs_move_foundation && rs_move_journal && rs_move_start \
      || die "chat move capability pairing: Rust needs canonical foundation, live/recovery journal and shared start support"
    core_move_client && core_move_enforcement && core_move_reader && core_tails_change_journal && rs_serves_change_journal \
      || die "chat move capability pairing: Node needs exported client, final-dispatch enforcement and move journal reader"
    if core_move_owner rust; then
      rust_owns_chat_move "$routes_file" && core_refuses_chat_move \
        || die "chat move POST ownership pairing: declared rust requires exact native POST and Node POST refusal"
      ! core_move_handler \
        || die "chat move owner/handler contradiction: declared rust retains an exported Node move handler"
    elif core_move_owner node; then
      ! rust_owns_chat_move "$routes_file" && ! core_refuses_chat_move && core_move_handler \
        || die "chat move POST ownership pairing: declared node requires a real exported delegation handler and no native/refused POST"
    else
      die "chat move capability pairing: missing, unknown or unexported CHAT_MOVE_PUBLIC_OWNER declaration"
    fi
  fi
  # sbstndalton/noevia#2153: a core that builds brains only for origin "history" entries, beside a
  # front whose journal names no origin, would build no brain at all (every entry is mirror-only
  # and Node stops its own nudge once the journal answers). The origin field itself is safe either
  # way: the front's store ops ignore request fields they do not know.
  if core_tails_change_journal && core_needs_journal_origin && rs_serves_change_journal; then
    rs_journals_origin \
      || die "noevia-core at $(lock_value NOEVIA_CORE_REF) builds a chat's brain only for change-journal entries with origin \"history\", but noevia-rs at $rs_ref journals no origin (none in crates/server-projects/src/journal.rs), so no brain would ever be built; pin a noevia-rs with the journal origin (sbstndalton/noevia#2153)"
  fi
  # #2096: no other switch is accepted either. routes.toml carries none since #1071 (it says so),
  # this supervisor passes none, and a switched route is excluded from the ownership comparison
  # above, so one that slipped in would be silently unchecked: refuse it, fail closed.
  if [ -n "$route_switches" ]; then
    die "noevia-rs at $rs_ref has switched routes in routes.toml ($(printf '%s' "$route_switches" | tr '\n' ';')); deployment ownership switches are retired and this web supervisor passes none (sbstndalton/noevia#1071, #2096)"
  fi
fi

# BEGIN residual fallback pairing
residual_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /rust-residual-fallbacks-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RUST_RESIDUAL_FALLBACKS_OWNED;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^rust-residual-fallbacks-(v1)$/.exec(value);
    process.stdout.write(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal or one plain path; macros, expressions,
# raw or byte strings refuse. An residual entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown residual entries are invalid; no FEATURES array or no entry is absence.
residual_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out(/\bFEATURES\b/.test(code) ? "invalid" : "none");
    // Only the unconditional crate-root declaration is authority. Declaration attributes and
    // crate cfg attributes must not hide it, nor may an enclosing module change its scope.
    const prefix = code.slice(0, decls[0].index);
    let scope = 0;
    for (const ch of prefix) { if (ch === "{") scope++; else if (ch === "}") scope--; if (scope < 0) out("invalid"); }
    if (scope !== 0) out("invalid");
    const item = prefix.slice(Math.max(prefix.lastIndexOf(";"), prefix.lastIndexOf("}")) + 1);
    if (/#\s*\[/.test(item) || /#\s*!\s*\[[^\]]*\bcfg(?:_attr)?\b/.test(prefix)) out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const residual = [];
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-residual-fallbacks"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-residual-fallbacks")) out("invalid");
        residual.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no residual text appears in the element.
      // Existing store markers are the only reviewed nonliteral entries. An arbitrary alias
      // could hide a concatenated capability, so unknown paths fail closed too.
      if (!marked && ["server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER", "server_projects::source_jobs::SOURCE_JOBS_STORE_MARKER"].includes(rest.replace(/\s/g, ""))) continue;
      out("invalid");
    }
    if (!residual.length) out("none");
    if (residual.length > 1) out("invalid");
    const m = /^rust-residual-fallbacks-(v1)$/.exec(residual[0]);
    out(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
residual_core_owner="$(residual_core_version "$tree/core/server/rust-residual-fallbacks.cjs")"
residual_rs_owner="$(residual_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$residual_core_owner" != invalid ] && [ "$residual_rs_owner" != invalid ] \
  || die "residual fallback pairing: ambiguous capability marker"
[ "$residual_core_owner" = "$residual_rs_owner" ] || die "residual fallback pairing: Core and Rust must move together"
# END residual fallback pairing
# Source startup and DAV listener pairing run after every other ownership guard: their strict
# whole-FEATURES readers refuse any malformed element, so they must not pre-empt another guard's
# own refusal of its marker.
source_startup_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /rust-source-startup-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RUST_SOURCE_STARTUP_OWNED;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^rust-source-startup-(v1)$/.exec(value);
    process.stdout.write(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal or one plain path; macros, expressions,
# raw or byte strings refuse. An outbox entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown outbox entries are invalid; no FEATURES array or no entry is absence.
source_startup_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // FEATURES must be a top-level, unconditional declaration. Unknown attributes
    // can transform declarations too: only inert doc/allow attributes are accepted.
    const before = code.slice(0, decls[0].index);
    let braces = 0;
    for (const ch of before) { if (ch === "{") braces++; if (ch === "}") braces--; }
    if (braces !== 0 || /#!\s*\[\s*cfg(?:_attr)?\b/.test(code)) out("invalid");
    const tail = before.slice(Math.max(before.lastIndexOf(";"), before.lastIndexOf("}")) + 1).trim();
    // Crate inner attributes (#![...], never cfg/cfg_attr, refused above) apply to the crate, not to
    // the declaration, so they may precede it, as in the maintenance lease reader.
    if (tail && !/^(?:#\s*\[\s*(?:doc\s*=\s*\u0000\d+\u0000|allow\s*\([^\[\]]*\))\s*\]\s*|#!\s*\[[^\[\]]*\]\s*)+$/.test(tail)) out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = [];
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-source-startup"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-source-startup")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^rust-source-startup-(v1)$/.exec(outbox[0]);
    out(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
source_startup_core_owner="$(source_startup_core_version "$tree/core/server/rust-source-startup.cjs")"
source_startup_rs_owner="$(source_startup_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$source_startup_core_owner" != invalid ] && [ "$source_startup_rs_owner" != invalid ] \
  || die "source startup ownership pairing: ambiguous capability marker"
[ "$source_startup_core_owner" = "$source_startup_rs_owner" ] \
  || die "source startup ownership pairing: Core and Rust must move together"

dav_listener_core_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const fs = require("node:fs"), vm = require("node:vm");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const literal = /rust-dav-listener-v/.test(src);
    let value;
    try {
      // Invocation and export access both run inside the timed evaluation.
      value = vm.runInNewContext(
        "(function () {" +
        "  const stub = new Proxy(function () {}, { get: () => stub, apply: () => stub, construct: () => stub });" +
        "  const module = { exports: {} };" +
        "  (function (require, module, exports) {" + src + "\n})(() => stub, module, module.exports);" +
        "  const v = module.exports.RUST_DAV_LISTENER_OWNED;" +
        "  return v === undefined ? undefined : typeof v === \"string\" ? v : null;" +
        "})()", {}, { timeout: 2000 });
    } catch { process.stdout.write("invalid"); process.exit(0); }
    if (value === undefined) { process.stdout.write(literal ? "invalid" : "none"); process.exit(0); }
    const m = typeof value === "string" && /^rust-dav-listener-(v1)$/.exec(value);
    process.stdout.write(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}
# Rust: tokenize lib.rs (nested block comments, line comments, escaped, raw and byte strings, char
# literals vs lifetimes) and read the entries of the single FEATURES array. Every element must be
# optional attributes followed by one ordinary string literal or one plain path; macros, expressions,
# raw or byte strings refuse. An outbox entry must be an unconditional ordinary literal. Duplicate,
# several, malformed or unknown outbox entries are invalid; no FEATURES array or no entry is absence.
dav_listener_rs_version() {
  [ -f "$1" ] || { echo none; return; }
  command -v node >/dev/null 2>&1 || { echo invalid; return; }
  timeout -k 2 10 node -e '
    const src = require("node:fs").readFileSync(process.argv[1], "utf8");
    const strs = []; let code = ""; let i = 0; const n = src.length;
    const ident = c => /[A-Za-z0-9_]/.test(c || "");
    const out = r => { process.stdout.write(r); process.exit(0); };
    while (i < n) {
      const c = src[i], d = src[i + 1];
      if (c === "/" && d === "/") { while (i < n && src[i] !== "\n") i++; continue; }
      if (c === "/" && d === "*") {
        let depth = 1; i += 2;
        while (i < n && depth) {
          if (src[i] === "/" && src[i + 1] === "*") { depth++; i += 2; }
          else if (src[i] === "*" && src[i + 1] === "/") { depth--; i += 2; }
          else i++;
        }
        if (depth) out("invalid");
        code += " "; continue;
      }
      const raw = /^b?r(#*)"/.exec(src.slice(i, i + 260));
      if (raw && !ident(src[i - 1])) {
        const close = "\"" + raw[1]; const s0 = i + raw[0].length; const e = src.indexOf(close, s0);
        if (e < 0) out("invalid");
        strs.push({ kind: "other", v: src.slice(s0, e) }); code += "\u0000" + (strs.length - 1) + "\u0000"; i = e + close.length; continue;
      }
      if (c === "\"" || (c === "b" && d === "\"" && !ident(src[i - 1]))) {
        const bytes = c === "b"; i += bytes ? 2 : 1; let v = "";
        while (i < n && src[i] !== "\"") {
          if (src[i] !== "\\") { v += src[i++]; continue; }
          const e = src[i + 1];
          const simple = { n: "\n", r: "\r", t: "\t", "\\": "\\", "0": "\0", "\x27": "\x27", "\"": "\"" };
          if (e in simple) { v += simple[e]; i += 2; }
          else if (e === "x" && (bytes ? /^[0-9A-Fa-f]{2}$/ : /^[0-7][0-9A-Fa-f]$/).test(src.slice(i + 2, i + 4))) { v += String.fromCharCode(parseInt(src.slice(i + 2, i + 4), 16)); i += 4; }
          else if (!bytes && e === "u" && src[i + 2] === "{") {
            const close = src.indexOf("}", i + 3); const hex = src.slice(i + 3, close).replace(/_/g, "");
            if (close < 0 || !/^[0-9A-Fa-f]{1,6}$/.test(hex)) out("invalid");
            v += String.fromCodePoint(parseInt(hex, 16)); i = close + 1;
          }
          else if (e === "\n" || e === "\r") { i += 2; while (i < n && /[ \t\r\n]/.test(src[i])) i++; }
          else out("invalid");
        }
        if (i >= n) out("invalid");
        i++; strs.push({ kind: bytes ? "other" : "str", v }); code += "\u0000" + (strs.length - 1) + "\u0000"; continue;
      }
      if (c === "\x27") {
        if (d === "\\") { const e = src.indexOf("\x27", i + 3); if (e < 0) out("invalid"); i = e + 1; code += " "; continue; }
        if (src[i + 2] === "\x27") { i += 3; code += " "; continue; }
      }
      code += c; i++;
    }
    const head = /pub\s+const\s+FEATURES\s*:\s*&\s*\[\s*&\s*str\s*\]\s*=\s*&\s*\[/g;
    const decls = [...code.matchAll(head)];
    if (decls.length > 1) out("invalid");
    if (!decls.length) out("none");
    // FEATURES must be a top-level, unconditional declaration. Unknown attributes
    // can transform declarations too: only inert doc/allow attributes are accepted.
    const before = code.slice(0, decls[0].index);
    let braces = 0;
    for (const ch of before) { if (ch === "{") braces++; if (ch === "}") braces--; }
    if (braces !== 0 || /#!\s*\[\s*cfg(?:_attr)?\b/.test(code)) out("invalid");
    const tail = before.slice(Math.max(before.lastIndexOf(";"), before.lastIndexOf("}")) + 1).trim();
    // Crate inner attributes (#![...], never cfg/cfg_attr, refused above) apply to the crate, not to
    // the declaration, so they may precede it, as in the maintenance lease reader.
    if (tail && !/^(?:#\s*\[\s*(?:doc\s*=\s*\u0000\d+\u0000|allow\s*\([^\[\]]*\))\s*\]\s*|#!\s*\[[^\[\]]*\]\s*)+$/.test(tail)) out("invalid");
    const body = code.slice(decls[0].index + decls[0][0].length);
    // Split the array at depth-0 commas, balancing (), [] and {} so attributes and nested
    // expressions stay inside their element.
    const elements = []; let depth = 0, cur = "", closed = false;
    for (const ch of body) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") depth--;
      else if (ch === "]") { if (depth === 0) { closed = true; break; } depth--; }
      if (depth < 0) out("invalid");
      if (ch === "," && depth === 0) { elements.push(cur); cur = ""; } else cur += ch;
    }
    if (!closed) out("invalid");
    elements.push(cur);
    const outbox = [];
    for (let k = 0; k < elements.length; k++) {
      let rest = elements[k].trim(), gated = false;
      if (!rest && k === elements.length - 1) continue; // trailing comma
      // Strip leading attributes (#[...], balanced); they gate but never name an entry.
      while (rest.startsWith("#")) {
        const open = rest.slice(1).trimStart();
        if (!open.startsWith("[")) out("invalid");
        let j = rest.length - open.length, dep = 0;
        for (; j < rest.length; j++) {
          if (rest[j] === "[") dep++;
          else if (rest[j] === "]" && --dep === 0) break;
        }
        if (dep) out("invalid");
        gated = true; rest = rest.slice(j + 1).trim();
      }
      const lit = /^\u0000(\d+)\u0000$/.exec(rest);
      const marked = [...elements[k].matchAll(/\u0000(\d+)\u0000/g)].some(m => strs[+m[1]].v.includes("rust-dav-listener"));
      if (lit && strs[+lit[1]].kind === "str") {
        if (!marked) continue;
        if (gated || !strs[+lit[1]].v.includes("rust-dav-listener")) out("invalid");
        outbox.push(strs[+lit[1]].v); continue;
      }
      // A plain path (a named constant) is allowed only when no outbox text appears in the element.
      if (!marked && /^(::)?[A-Za-z_][A-Za-z0-9_]*(\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*$/.test(rest)) continue;
      out("invalid");
    }
    if (!outbox.length) out("none");
    if (outbox.length > 1) out("invalid");
    const m = /^rust-dav-listener-(v1)$/.exec(outbox[0]);
    out(m ? m[1] : "invalid");
  ' "$1" 2>/dev/null || echo invalid
}

dav_listener_core_owner="$(dav_listener_core_version "$tree/core/server/rust-dav-listener.cjs")"
dav_listener_rs_owner="$(dav_listener_rs_version "$tree/rs/bins/noevia-server/src/lib.rs")"
[ "$dav_listener_core_owner" != invalid ] && [ "$dav_listener_rs_owner" != invalid ] \
  || die "DAV listener ownership pairing: ambiguous capability marker"
[ "$dav_listener_core_owner" = "$dav_listener_rs_owner" ] \
  || die "DAV listener ownership pairing: Core and Rust must move together"
if [ "$dav_listener_core_owner" = v1 ]; then
  ! code_lines "$tree/core/server/index.cjs" | grep -qE 'davServer|createDavHandler|davConfig\.available' \
    || die "DAV listener ownership pairing: Node listener remains"
  [ ! -f "$tree/core/server/dav.cjs" ] && [ ! -f "$tree/core/server/dav-ops.cjs" ] \
    || die "DAV listener ownership pairing: live Node handlers remain"
  code_lines "$tree/rs/bins/noevia-server/src/main.rs" | grep -qF 'dav::start(' \
    || die "DAV listener ownership pairing: native startup hook absent"
  code_lines "$tree/noevia/build/web-supervisor.sh" | grep -qF rust-dav-listener-v1 \
    || die "DAV listener ownership pairing: supervisor comparison absent"
fi
# End of source startup and DAV listener pairing.

for need in web/package.json web/package-lock.json web/src web/index.html core/server/package.json core/server/index.cjs core/contracts \
            core/code-sandbox/Dockerfile services/diary/Dockerfile services/docling/Dockerfile services/laya/Dockerfile \
            services/model-manager/Dockerfile services/ocr/Dockerfile; do
  [ -e "$tree/$need" ] || die "assembled tree lacks $need"
done

printf 'NOEVIA_SHA=%s\nNOEVIA_WEB_SHA=%s\nNOEVIA_CORE_SHA=%s\nNOEVIA_SERVICES_SHA=%s\nNOEVIA_RS_SHA=%s\n' \
  "$sha" "$web_sha" "$core_sha" "$services_sha" "$rs_sha" > "$tree/release-refs"
# The web image's entrypoint is the one file of noevia/ its build needs.
printf 'noevia\n!noevia/build/web-supervisor.sh\nservices\n' > "$tree/.dockerignore"

out="$out_dir/noevia-release-$sha.tar.gz"
out_partial="$out.partial"
COPYFILE_DISABLE=1 tar -czf "$out_partial" -C "$tree" .dockerignore release-refs noevia web core services rs
mv -f "$out_partial" "$out"
echo "ok: $out (noevia $full_sha, web $web_sha, core $core_sha, services $services_sha, rs ${rs_sha:-none})"
