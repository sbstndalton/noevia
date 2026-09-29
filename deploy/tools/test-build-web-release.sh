#!/usr/bin/env bash
# Stubs docker with a PATH shim; runs on macOS bash 3.2 and Linux.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/build-web-release.sh"
dockerfile="$here/../../apps/web/Dockerfile"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-web-release-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/ctx"
touch "$work/ctx/Dockerfile"
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

sha=682a45e
printf '{"version":"%s"}\n' "$sha" > "$work/versionjson"
bash "$script" "$sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "good build exits 0" '[ $rc -eq 0 ]'
check "passes COWORK_VERSION build-arg" 'grep -q -- "--build-arg COWORK_VERSION=$sha" "$log"'
check "enables the Dockerfile guard" 'grep -q -- "--build-arg REQUIRE_RELEASE_VERSION=1" "$log"'
check "tags cowork-web:<sha>" 'grep -q -- "-t cowork-web:$sha" "$log"'

printf '{"version":"0.2.0+abc"}\n' > "$work/versionjson"
bash "$script" "$sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "mis-stamped version.json fails" '[ $rc -ne 0 ]'

: > "$log"
bash "$script" >/dev/null 2>&1; rc=$?
check "missing sha fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'
bash "$script" "not-a-sha" "$work/ctx" >/dev/null 2>&1; rc=$?
check "non-sha argument fails without building" '[ $rc -ne 0 ] && [ ! -s "$log" ]'

# Execute the Dockerfile's own guard command under sh with different build args.
guard="$(grep -A1 '^RUN if \[ "\$REQUIRE_RELEASE_VERSION"' "$dockerfile" | sed -e 's/^RUN //' -e 's/ \\$//')"
guard_run() { REQUIRE_RELEASE_VERSION="$1" COWORK_VERSION="$2" sh -c "$guard" >/dev/null 2>&1; }
check "guard extracted from Dockerfile" '[ -n "$guard" ]'
check "guard fails release build with no COWORK_VERSION" '! guard_run 1 ""'
check "guard fails release build with dev COWORK_VERSION" '! guard_run 1 dev'
check "guard passes release build with a sha" 'guard_run 1 682a45e'
check "guard leaves plain builds alone" 'guard_run 0 ""'

echo "passed=$passes failed=$fails"
[ "$fails" -eq 0 ]
