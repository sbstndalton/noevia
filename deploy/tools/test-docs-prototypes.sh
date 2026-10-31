#!/usr/bin/env bash
# #2241: the synthetic Settings preview fixture (docs/prototypes/settings-fixture.cjs) must work without
# any module that has left the tree (it required the deleted apps/web/server/appearance.cjs, so every valid
# appearance save answered 400 "Cannot find module"), and the relative links in the research notes and
# the archived run plans must resolve. Needs node.
set -u
here="$(cd -- "$(dirname -- "$0")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
fails=0; passes=0
check() { if eval "$2"; then passes=$((passes+1)); echo "ok - $1"; else fails=$((fails+1)); echo "FAIL - $1"; fi; }

out="$(cd "$root" && node - <<'JS' 2>&1
const { createSettingsFixture } = require('./docs/prototypes/settings-fixture.cjs');
const handler = createSettingsFixture();
const call = async (method, path, payload) => {
  const req = (async function* () { if (payload !== undefined) yield Buffer.from(JSON.stringify(payload)); })();
  req.method = method;
  const res = { head: 0, body: '', writeHead(s) { this.head = s; }, setHeader() {}, end(b) { this.body = b; } };
  const handled = await handler(req, res, new URL(`http://localhost${path}`));
  return { handled, status: res.head, body: res.body ? JSON.parse(res.body) : null };
};
(async () => {
  const good = { theme: 'dark', light: 'sage', dark: 'iris' };
  const saved = await call('PUT', '/api/profile/appearance', good);
  console.log(`put-good ${saved.status} ${JSON.stringify(saved.body)}`);
  const read = await call('GET', '/api/profile/appearance');
  console.log(`get ${read.status} ${JSON.stringify(read.body)}`);
  const bad = await call('PUT', '/api/profile/appearance', { theme: 'dark', light: 'nope', dark: 'iris' });
  console.log(`put-bad ${bad.status} ${bad.body && bad.body.error}`);
  const extra = await call('PUT', '/api/profile/appearance', { ...good, light: 'warm', extra: 1 });
  console.log(`put-extra ${extra.status} ${JSON.stringify(extra.body)}`);
})().catch((e) => { console.log(`crash ${e.message}`); process.exit(1); });
JS
)"
check "a valid appearance save answers 200 with the three fields" 'printf "%s\n" "$out" | grep -qx "put-good 200 {\"theme\":\"dark\",\"light\":\"sage\",\"dark\":\"iris\"}"'
check "the saved appearance reads back" 'printf "%s\n" "$out" | grep -qx "get 200 {\"theme\":\"dark\",\"light\":\"sage\",\"dark\":\"iris\"}"'
check "an unknown palette is refused with the Settings message" 'printf "%s\n" "$out" | grep -qx "put-bad 400 Choose a valid mode and a palette for both light and dark."'
check "unknown fields are dropped" 'printf "%s\n" "$out" | grep -qx "put-extra 200 {\"theme\":\"dark\",\"light\":\"warm\",\"dark\":\"iris\"}"'

# Relative markdown links (not http/https/mailto/anchors) must point at a file that exists.
dead_links() { # dead_links <file>
  local f="$1" d link target
  d="$(dirname "$f")"
  grep -o ']([^)]*)' "$f" | sed -e 's/^](//' -e 's/)$//' | while IFS= read -r link; do
    case "$link" in http://*|https://*|mailto:*|'#'*|'') continue ;; esac
    target="${link%%#*}"
    [ -e "$d/$target" ] || echo "$f -> $link"
  done
}
for f in "$root/docs/research-skills-mcp-loading.md" "$root"/docs/handoffs/2026-09-25-run-plan-26[45].md; do
  dead="$(dead_links "$f")"
  check "no dead relative link in ${f#"$root"/}" '[ -z "$dead" ]'
  [ -z "$dead" ] || printf '%s\n' "$dead"
done
for n in 264 265; do
  check "run plan $n says where its archived experiment files are" 'grep -q "archived at\|last tree is commit 9ee4b821" "$root/docs/handoffs/2026-09-25-run-plan-$n.md" && grep -q "Archived experiment files" "$root/docs/handoffs/2026-09-25-run-plan-$n.md"'
done

# #2252: this test runs in the deploy-tests job, which the change filter in ci.yml starts only for the paths listed under
# `deploy:`. A change to the fixture or to the notes the test reads must be among them, or it merges without this test.
ci="$root/.github/workflows/ci.yml"
deploy_filter="$(awk '/^            deploy:/{on=1; next} on && /^            [a-z]+:/{on=0} on' "$ci")"
for pattern in 'docs/prototypes/**' 'docs/research-skills-mcp-loading.md' 'docs/handoffs/2026-09-25-run-plan-26*.md'; do
  check "ci.yml's deploy filter runs this test for $pattern" 'printf "%s\n" "$deploy_filter" | grep -qxF "              - '"'"'$pattern'"'"'"'
done

echo "$passes passed, $fails failed"
[ $fails -eq 0 ]
