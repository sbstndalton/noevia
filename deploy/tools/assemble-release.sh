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
# The exact permanent read-only web-address GETs. Non-GET methods must continue to Node.
web_address_routes_rs() {
  routes_toml "$1" | awk -F'\t' '
    $1 == "/api/instance" || $1 == "/.well-known/webauthn" || $1 == "/api/admin/web-address" {
      if ($2 == "rust") {
        if ($3 != "-" || $4 != "GET") { print "invalid " $1; next }
        print "GET " $1
      }
    }
  ' | sort -u
}
# The core's explicit exported refusal declaration must be wired before its public/auth mounts.
# Parse each path independently, so one missing GET cannot hide behind two paired siblings.
web_address_routes_core() {
  local source="$tree/core/server/rust-web-address.cjs"
  [ -f "$source" ] || return 0
  grep -qxF "const WEB_ADDRESS_READ_OWNER = 'noevia-web-address-read-rust/1';" "$source" || { echo invalid-marker; return; }
  grep -qxF 'module.exports = { WEB_ADDRESS_READ_OWNER, OWNED_GET_PATHS, ROUTE_REFUSAL, ownedRead, refuseOwnedRead };' "$source" || { echo invalid-export; return; }
  grep -qxF "  return method === 'GET' && OWNED_GET_PATHS.includes(pathname);" "$source" || { echo invalid-method; return; }
  grep -qxF "    if (require('./rust-web-address.cjs').refuseOwnedRead(req, res, p, json)) return;" "$tree/core/server/index.cjs" || { echo invalid-wiring; return; }
  sed -n '/^const OWNED_GET_PATHS = /,/]);/p' "$source" | grep -oE "'/(api/instance|api/admin/web-address|\.well-known/webauthn)'" | tr -d "'" | sed 's/^/GET /' | sort -u
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
core_writes_history_via_store() {
  grep -q 'historyAppendIfLast' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
    && grep -q 'transcripts.appendIfLast(' "$tree/core/server/chat-interrupted-turn.cjs" 2>/dev/null \
    && grep -q 'ctx.transcripts.write(' "$tree/core/server/conversation-import.cjs" 2>/dev/null \
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
# Whether the pinned core tails that journal (server/chat-change-journal.cjs carries its marker).
core_tails_change_journal() {
  grep -q "'noevia-chat-change-journal-reader/1'" "$tree/core/server/chat-change-journal.cjs" 2>/dev/null
}
# Whether the pinned core builds a chat's brain only for journal entries with origin "history"
# (sbstndalton/noevia#2153: then it no longer nudges the brain itself while the front journals).
core_needs_journal_origin() {
  grep -q "e.origin === 'history'" "$tree/core/server/chat-change-journal.cjs" 2>/dev/null
}
# Whether the pinned front's journal entries carry that origin (crates/server-projects journal.rs).
rs_journals_origin() {
  grep -qs '"origin"' "$tree/rs/crates/server-projects/src/journal.rs"
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
# Slice7: exact canonical declarations + actual shorthand exports, never comment literals.
# A transitional handler must be a named exported async chatMoveRoute in its actual route module.
move_capability() {
  [ -f "$1" ] || return 1
  awk -v name="$2" -v value="$3" -v kind="$4" '
    function clean(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      line=clean($0)
      if (block) { if (index(line,"*/")) block=0; next }
      if (index(line,"/*")) { if (!index(line,"*/")) block=1; next }
      if (line ~ /^\/\//) next
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
core_move_reader() { move_capability "$tree/core/server/chat-change-journal.cjs" CHAT_MOVE_READER_MARKER noevia-chat-move-reader/1 js; }
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

# Deep research still executes in Node; Rust alone owns its kind-scoped journal. The
# selected pair must contain the exported live client and the compiled internal store routes.
core_research_client() {
  move_capability "$tree/core/server/project-store-client.cjs" RESEARCH_JOBS_CLIENT_MARKER noevia-research-jobs-client/1 js
}
rs_research_store() {
  move_capability "$tree/rs/crates/server-projects/src/research_jobs.rs" RESEARCH_JOBS_STORE_MARKER noevia-research-jobs-store/1 rust || return 1
  move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES server_projects::research_jobs::RESEARCH_JOBS_STORE_MARKER feature_ref || return 1
  grep -qxF 'pub mod research_jobs;' "$tree/rs/crates/server-projects/src/lib.rs" || return 1
  grep -qF 'use server_projects::research_jobs as jobs;' "$tree/rs/bins/noevia-server/src/project_store.rs" || return 1
  local route route_source
  route_source="$(sed '/^[[:space:]]*\/\//d; /\/\*/,/\*\//d' "$tree/rs/bins/noevia-server/src/project_store.rs" | tr '\n' ' ')" || return 1
  for route in recover start abandon event cancel finish report prepare artifact clear read list; do
    grep -Eq "\.route\([[:space:]]*\"/v1/research-jobs/$route\",[[:space:]]*research_route\(ResearchOp::${route^}\)[[:space:]]*,?[[:space:]]*\)" <<<"$route_source" || return 1
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
# A ported core with no Rust route contract cannot be paired at all. Keep this outside the
# routes-file conditional: otherwise removing that file bypasses the GET/refusal pairing.
if [ ! -f "$tree/rs/contracts/http/routes.toml" ]; then
  web_core="$(web_address_routes_core)"
  [ -z "$web_core" ] || die "web-address GET ownership pairing: core refuses GETs but Rust routes.toml is missing"
fi
# A partially ported source journal would either strand a 202 without a reader or give
# source files two owners. Old core/old Rust remains an allowed rollback pair.
if [ -f "$tree/rs/crates/server-projects/src/source_jobs.rs" ] \
   || grep -qE 'SOURCE_JOBS_CLIENT_MARKER|sourceJobsFor\(' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
   || grep -qF 'workspace.sourceJobs' "$tree/core/server/source-jobs.cjs" 2>/dev/null; then
  core_source_client && rs_source_store || die "source job store pairing: core needs an exported source client and Rust needs the compiled source store capability and six internal routes"
fi
if [ -f "$tree/rs/crates/server-projects/src/research_jobs.rs" ] \
   || grep -qE 'RESEARCH_JOBS_CLIENT_MARKER|researchJobsFor\(' "$tree/core/server/project-store-client.cjs" 2>/dev/null \
   || grep -qF 'workspace.researchJobs' "$tree/core/server/research-jobs.cjs" 2>/dev/null; then
  core_research_client && rs_research_store || die "research job store pairing: core needs an exported research client and Rust needs the compiled research store capability and internal routes"
fi
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
  # The three web-address GETs change owner together. A read-only Rust front must be
  # paired with Node's early refusal; an early refusal needs a Rust answer. Other methods
  # (especially HEAD and both POST writers) remain Node's.
  web_rs="$(web_address_routes_rs "$routes_file")"
  web_core="$(web_address_routes_core)"
  web_expected="$(printf 'GET /api/admin/web-address\nGET /api/instance\nGET /.well-known/webauthn' | sort)"
  if [ -n "$web_rs" ] || [ -n "$web_core" ]; then
    [ "$web_rs" = "$web_expected" ] && [ "$web_core" = "$web_expected" ] \
      || die "web-address GET ownership pairing: Rust must own exactly three GETs and Node must refuse those exact GETs before public/auth routing; preserve HEAD/POST fallback"
    move_capability "$tree/rs/bins/noevia-server/src/lib.rs" FEATURES rust-web-address-read features \
      || die "web-address GET ownership pairing: Rust route table lacks a compiled --features declaration"
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
  missing="$(comm -23 <(project_routes_rs "$tree/rs/contracts/http/routes.toml") <(project_routes_core "$tree/core/server/rust-projects.cjs"))"
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
     || core_move_client || core_move_enforcement || core_move_reader; then
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
