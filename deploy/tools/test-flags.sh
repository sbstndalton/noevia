#!/usr/bin/env bash
# flags.sh must never print a secret: fake `docker inspect` carries tokens under non-allow-listed keys
# (and inside the VALUE of an allow-listed-looking neighbour), and every output is scanned for them.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/flags.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/flags-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# A new LITERAL allow-list name in flags.sh also needs a value in this shim's Env, or its "accept" case below
# fails (loudly, as "FAIL - accept NAME"). Wildcard names are probed with the sample instance named in the loop.
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
 "STREAM_GUARD_IMPL=wasm",
 "S3_SIGN_IMPL=js",
 "NOEVIA_FEATURE_DEEP_RESEARCH=false",
 "NOEVIA_FEATURE_=SECRET-empty-suffix-ok-or-not",
 "LAYA_LOAD_ADVISOR=on",
 "DECISION_LOAD_ADVISOR=on",
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
check "allow-listed values printed" 'printf "%s" "$out" | grep -qx "STREAM_GUARD_IMPL=wasm" && printf "%s" "$out" | grep -qx "COWORK_VERSION=abc123" && printf "%s" "$out" | grep -qx "NOEVIA_FEATURE_DEEP_RESEARCH=false" && printf "%s" "$out" | grep -qx "COWORK_CODE_NET_ADDR=10.0.0.5:9000" && printf "%s" "$out" | grep -qx "DECISION_LOAD_ADVISOR=on" && printf "%s" "$out" | grep -qx "LAYA_LOAD_ADVISOR=on"'
check "exactly the 11 allow-listed entries (incl. generic *_IMPL and both advisor names)" '[ "$(printf "%s\n" "$out" | grep -c .)" -eq 11 ]'

keys="$(bash "$script" --keys cowork-web-1 2>&1)"; rc=$?
check "--keys exits 0" '[ $rc -eq 0 ]'
check "--keys prints no value and no =" '! printf "%s" "$keys" | grep -q "=" && ! printf "%s" "$keys" | grep -Eqi "SECRET|wasm|abc123"'
check "--keys lists names" 'printf "%s" "$keys" | grep -qx STREAM_GUARD_IMPL && printf "%s" "$keys" | grep -qx COWORK_VERSION && printf "%s" "$keys" | grep -qx DECISION_LOAD_ADVISOR'
check "--keys omits secret key names" '! printf "%s" "$keys" | grep -Eq "TOKEN|API_KEY|SECRET"'

one="$(bash "$script" cowork-web-1 GGUF_PARSER 2>&1)"
check "explicit allowed key prints just it" '[ "$one" = "GGUF_PARSER=rust" ]'
one_decision="$(bash "$script" cowork-web-1 DECISION_LOAD_ADVISOR 2>&1)"; rc=$?
check "new DECISION_LOAD_ADVISOR name prints just it" '[ $rc -eq 0 ] && [ "$one_decision" = "DECISION_LOAD_ADVISOR=on" ]'
one_laya="$(bash "$script" cowork-web-1 LAYA_LOAD_ADVISOR 2>&1)"; rc=$?
check "old LAYA_LOAD_ADVISOR alias still prints just it" '[ $rc -eq 0 ] && [ "$one_laya" = "LAYA_LOAD_ADVISOR=on" ]'
bash "$script" cowork-web-1 DECISION_LOAD >/dev/null 2>&1; rc=$?
check "near-miss advisor name refused (exit 2)" '[ $rc -eq 2 ]'
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

# #2101: generated from the allow-list in flags.sh, so a newly allowed name is covered automatically.
# A literal name must be accepted exactly; NAME_X, X_NAME, NAMEX, XNAME, lowercase and a leading or
# trailing newline must be refused. A wildcard entry is covered by one sample instance and only refused on
# the side its regex anchors: *_IMPL is open at the start (X_STREAM_GUARD_IMPL is an allowed *_IMPL name),
# NOEVIA_FEATURE_* is open at the end (NOEVIA_FEATURE_X_Y is an allowed NOEVIA_FEATURE_ name).
try() { # try accept|refuse <argument>
  local want="$1" arg="$2" out rc ok=0
  if [ "$want" = accept ]; then
    out="$(bash "$script" cowork-web-1 "$arg" 2>&1)"; rc=$?
    [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] && [[ $out == "$arg="?* ]] && ok=1
  else
    # Container "missing" makes docker inspect exit 1, so exit 2 proves the name was refused before docker ran.
    out="$(bash "$script" missing "$arg" 2>&1)"; rc=$?
    [ $rc -eq 2 ] && printf '%s' "$out" | grep -q 'refusing key not on the allow-list' && ok=1
  fi
  if [ $ok -eq 1 ]; then passes=$((passes+1)); echo "ok - $want $(printf '%q' "$arg")"
  else fails=$((fails+1)); echo "FAIL - $want $(printf '%q' "$arg")"; fi
}
cover() { # cover <sample> <anchored refusals...>: exact sample accepted; each refusal, lowercase and newline-bounded form refused
  local n="$1" v; shift
  try accept "$n"
  for v in "$@" "${n,,}" "$n"$'\n' $'\n'"$n"; do try refuse "$v"; done
}
# Exactly one allow= line must match: read -a would use only the first, so a second one would go unprobed.
allow_lines="$(sed -n -E 's/^allow=.\^?\((.*)\)\$?.$/\1/p' "$script")"
allow_count="$(printf '%s\n' "$allow_lines" | grep -c .)"
allow_body="$(printf '%s\n' "$allow_lines" | head -n1)"
if [ "$allow_count" -ne 1 ]; then fails=$((fails+1)); echo "FAIL - expected exactly one allow= line in flags.sh, found $allow_count"; fi
IFS='|' read -r -a allow_alts <<< "$allow_body"
echo "covering ${#allow_alts[@]} allow-list entries from flags.sh"
for alt in "${allow_alts[@]}"; do
  case "$alt" in
    # The open side is probed directly too: the class must refuse a bad character, an empty prefix and an empty suffix,
    # so a drift to `.*_IMPL` or `NOEVIA_FEATURE_.*` is caught here and not only by the secret-leak checks.
    '[A-Z0-9_]+_IMPL') s=STREAM_GUARD_IMPL; cover "$s" "${s}_X" "${s}X" 'bad-name_IMPL' '_IMPL' 'bad name_IMPL' 'a.b_IMPL' ;;
    'NOEVIA_FEATURE_[A-Z0-9_]+') s=NOEVIA_FEATURE_DEEP_RESEARCH; cover "$s" "X_${s}" "X${s}" 'NOEVIA_FEATURE_' 'NOEVIA_FEATURE_a-b' 'NOEVIA_FEATURE_A-B' 'NOEVIA_FEATURE_A B' ;;
    *'['*) fails=$((fails+1)); echo "FAIL - no sample instance for new wildcard allow-list entry: $alt" ;;
    *) cover "$alt" "${alt}_X" "X_${alt}" "${alt}X" "X${alt}" ;;
  esac
done

echo "$passes passed, $fails failed"
[ $fails -eq 0 ]
