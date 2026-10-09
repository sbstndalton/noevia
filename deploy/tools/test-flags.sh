#!/usr/bin/env bash
# flags.sh must never print a secret: fake `docker inspect` carries tokens under non-allow-listed keys
# (and inside the VALUE of an allow-listed-looking neighbour), and every output is scanned for them.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/flags.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/flags-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = inspect ] || exit 1
[ "$2" = missing ] && exit 1
cat <<'JSON'
[{"Config":{"Env":[
 "PATH=/usr/bin",
 "MODEL_LOADER_TOKEN=SECRET-tok-0123456789abcdef",
 "DIARY_API_KEY=SECRET-diary-key",
 "S3_SECRET_KEY=SECRET-s3",
 "MODEL_LOADER_TOKEN_IMPL_NOT=SECRET-lookalike",
 "X_IMPL_EXTRA=SECRET-suffix-lookalike",
 "lowercase_IMPL=SECRET-lower",
 "GGUF_META_IMPL=wasm",
 "S3_SIGN_IMPL=js",
 "NOEVIA_FEATURE_DEEP_RESEARCH=false",
 "NOEVIA_FEATURE_=SECRET-empty-suffix-ok-or-not",
 "LAYA_LOAD_ADVISOR=on",
 "MODEL_AUTOCONFIG=rust",
 "GGUF_PARSER=rust",
 "COWORK_CODE_NET_ADDR=10.0.0.5:9000",
 "COWORK_VERSION=abc123",
 "DIARY_VERSION=def456",
 "MODEL_MANAGER_VERSION=789",
 "NOEQUALS"
]}}]
JSON
SHIM
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }

out="$(bash "$script" cowork-web-1 2>&1)"; rc=$?
check "values mode exits 0" '[ $rc -eq 0 ]'
check "no secret in values mode" '! printf "%s" "$out" | grep -qi "SECRET"'
check "no non-allow-listed key name in values mode" '! printf "%s" "$out" | grep -Eq "TOKEN|API_KEY|S3_SECRET|PATH|lowercase|X_IMPL_EXTRA_NOT"'
check "allow-listed values printed" 'printf "%s" "$out" | grep -qx "GGUF_META_IMPL=wasm" && printf "%s" "$out" | grep -qx "COWORK_VERSION=abc123" && printf "%s" "$out" | grep -qx "NOEVIA_FEATURE_DEEP_RESEARCH=false" && printf "%s" "$out" | grep -qx "COWORK_CODE_NET_ADDR=10.0.0.5:9000"'
check "exactly the 10 allow-listed entries (incl. generic *_IMPL)" '[ "$(printf "%s\n" "$out" | grep -c .)" -eq 10 ]'

keys="$(bash "$script" --keys cowork-web-1 2>&1)"; rc=$?
check "--keys exits 0" '[ $rc -eq 0 ]'
check "--keys prints no value and no =" '! printf "%s" "$keys" | grep -q "=" && ! printf "%s" "$keys" | grep -Eqi "SECRET|wasm|abc123"'
check "--keys lists names" 'printf "%s" "$keys" | grep -qx GGUF_META_IMPL && printf "%s" "$keys" | grep -qx COWORK_VERSION'
check "--keys omits secret key names" '! printf "%s" "$keys" | grep -Eq "TOKEN|API_KEY|SECRET"'

one="$(bash "$script" cowork-web-1 GGUF_PARSER 2>&1)"
check "explicit allowed key prints just it" '[ "$one" = "GGUF_PARSER=rust" ]'
ref="$(bash "$script" cowork-web-1 MODEL_LOADER_TOKEN 2>&1)"; rc=$?
check "explicit secret key refused (exit 2)" '[ $rc -eq 2 ]'
check "refusal leaks no value" '! printf "%s" "$ref" | grep -qi "SECRET"'
ref="$(bash "$script" cowork-web-1 GGUF_PARSER DIARY_API_KEY 2>&1)"; rc=$?
check "one bad key among good ones refuses all" '[ $rc -eq 2 ] && ! printf "%s" "$ref" | grep -q "GGUF_PARSER=rust"'
bash "$script" missing >/dev/null 2>&1; rc=$?
check "docker failure exits 1" '[ $rc -eq 1 ]'
bash "$script" >/dev/null 2>&1; rc=$?
check "no args is usage (2)" '[ $rc -eq 2 ]'
bash "$script" --keys '$(id)' >/dev/null 2>&1; rc=$?
check "bad container name refused" '[ $rc -eq 2 ]'

echo "$passes passed, $fails failed"
[ $fails -eq 0 ]
