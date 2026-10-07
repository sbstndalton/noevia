#!/usr/bin/env bash
# Stubs docker with a PATH shim; runs on macOS bash 3.2 and Linux.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/build-web-release.sh"
dockerfile="$here/../../build/web.Dockerfile"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-web-release-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sha=682a45e
# An assembled release tree (deploy/tools/assemble-release.sh) and a monorepo-style context.
mkdir -p "$work/bin" "$work/ctx/noevia/build" "$work/plain"
touch "$work/ctx/noevia/build/web.Dockerfile" "$work/plain/Dockerfile"
printf 'NOEVIA_SHA=%s\nNOEVIA_WEB_SHA=%s\nNOEVIA_CORE_SHA=%s\n' "$sha" \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb > "$work/ctx/release-refs"
log="$work/calls"
cat > "$work/bin/docker" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$log"
if [ "\$1" = run ]; then cat "$work/versionjson"; fi
SHIM
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }

printf '{"version":"%s"}\n' "$sha" > "$work/versionjson"
bash "$script" "$sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "good build exits 0" '[ $rc -eq 0 ]'
check "passes COWORK_VERSION build-arg" 'grep -q -- "--build-arg COWORK_VERSION=$sha" "$log"'
check "enables the Dockerfile guard" 'grep -q -- "--build-arg REQUIRE_RELEASE_VERSION=1" "$log"'
check "tags cowork-web:<sha>" 'grep -q -- "-t cowork-web:$sha" "$log"'
check "builds noevia/build/web.Dockerfile with the tree as context" \
  'grep -q -- "-f $work/ctx/noevia/build/web.Dockerfile" "$log" && grep -q -- " $work/ctx\$" "$log"'

printf '{"version":"0.2.0+abc"}\n' > "$work/versionjson"
bash "$script" "$sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "mis-stamped version.json fails" '[ $rc -ne 0 ]'
printf '{"version":"%s"}\n' "$sha" > "$work/versionjson"

: > "$log"
bash "$script" >/dev/null 2>&1; rc=$?
check "missing sha fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'
bash "$script" "not-a-sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "non-sha argument fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'
bash "$script" "$sha" "$work/plain" >/dev/null 2>&1; rc=$?
check "a monorepo-style context (no assembled tree) fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'
bash "$script" 1234567 "$work/ctx" >/dev/null 2>&1; rc=$?
check "a tree assembled at another sha fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'

: > "$log"
(cd "$work/ctx" && COWORK_SOURCE_DIR= bash "$script" "$sha" >/dev/null 2>&1); rc=$?
check "defaults to the current directory" '[ $rc -eq 0 ] && grep -q -- "-f ./noevia/build/web.Dockerfile" "$log"'
: > "$log"
COWORK_SOURCE_DIR="$work/ctx" bash "$script" "$sha" >/dev/null 2>&1; rc=$?
check "defaults to COWORK_SOURCE_DIR when set" '[ $rc -eq 0 ] && grep -q -- "-f $work/ctx/noevia/build/web.Dockerfile" "$log"'

# Execute build/web.Dockerfile's own release guard (the RUN that sources release-refs) under sh,
# in a directory holding the tree's release-refs, with different build args.
guard="$(awk '/^RUN set -e; \. \.\/release-refs; \\$/ { on = 1 } on { print; if ($0 !~ /\\$/) exit }' "$dockerfile" \
  | sed -e '1s/^RUN //' -e 's/\\$//')"
guard_run() { (cd "$work/ctx" && REQUIRE_RELEASE_VERSION="$1" COWORK_VERSION="$2" sh -c "$guard") >/dev/null 2>&1; }
check "guard extracted from build/web.Dockerfile" '[ -n "$guard" ]'
check "guard fails release build with no COWORK_VERSION" '! guard_run 1 ""'
check "guard fails release build with dev COWORK_VERSION" '! guard_run 1 dev'
check "guard passes release build with the tree's sha" 'guard_run 1 "$sha"'
check "guard fails a build stamped with another sha" '! guard_run 1 1234567'
check "guard leaves plain builds alone" 'guard_run 0 ""'

echo "passed=$passes failed=$fails"
[ "$fails" -eq 0 ]
