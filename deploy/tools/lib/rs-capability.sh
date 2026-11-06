# POSIX shell adapter. Caller sets rs_capability_lib to the absolute .cjs path.
# Missing input is legacy; missing runtime/helper or timeout is invalid, never absence.
rs_capability_version() {
  if [ ! -e "$1" ]; then printf '%s\n' legacy; return; fi
  if ! rs_capability_result=$(timeout -k 2 10 node "$rs_capability_lib" "$1" "$2" "$3" "${rs_capability_build:-}" "${rs_capability_cargo:-}" 2>/dev/null); then
    printf '%s\n' 'invalid(runtime)'; return
  fi
  case "$rs_capability_result" in
    v1|legacy|invalid\(*\)) printf '%s\n' "$rs_capability_result" ;;
    *) printf '%s\n' 'invalid(protocol)' ;;
  esac
}
