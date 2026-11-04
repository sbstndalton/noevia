"""Exercise the assembler's actual parser and code matcher on synthetic generations."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'deploy/tools/assemble-release.sh').read_text()
def function(name):
    start = source.index(name + '() {')
    return source[start:source.index('\n}', start) + 2]
helpers = 'die() { echo "$*" >&2; exit 1; };\n' + function('code_has') + '\n' + function('routes_toml')
guard = source[source.index('# Retention PUT and'):source.index('# #2384: the routing default')]
with tempfile.TemporaryDirectory(dir=repo) as tmp:
    tree = Path(tmp)
    (tree / 'core/server/routes').mkdir(parents=True)
    (tree / 'rs/contracts/http').mkdir(parents=True)
    for core, rust, writer, expected in [
        (False, False, False, True), (True, True, False, True),
        (False, True, False, False), (True, False, False, False),
        (True, True, True, False),
    ]:
        methods = "['GET', 'PUT']" if core else "['GET']"
        (tree / 'core/server/rust-auth.cjs').write_text(r'  [/^\/api\/account\/retention$/, ' + methods + '],\n')
        (tree / 'core/server/routes/account.cjs').write_text(
            "const refusal = 'Retention settings are owned by the Rust front.';\n" +
            ('retention.write(dir, days);\n' if writer else ''))
        methods = '["GET", "PUT"]' if rust else '["GET"]'
        (tree / 'rs/contracts/http/routes.toml').write_text(
            '[[route]]\npath = "/api/account/retention"\nowner = "rust"\nmethods = ' + methods + '\n')
        result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + helpers + '\ntree=' + repr(str(tree)) + '\n' + guard], capture_output=True, text=True)
        assert (result.returncode == 0) == expected, (core, rust, writer, result.stderr)
        print('PASS', core, rust, writer)
    # Preserve the real matcher and inject an operational grep failure only for its writer check.
    broken_grep = r"""grep() { if [ "${3:-}" = 'retention\.write\(' ]; then return 2; fi; command grep "$@"; };"""
    result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + helpers + '\n' + broken_grep + '\ntree=' + repr(str(tree)) + '\n' + guard], capture_output=True, text=True)
    assert result.returncode != 0 and 'writer matcher failed' in result.stderr, result.stderr
    print('PASS matcher error fails closed')
    # Inject an operational awk failure on the second scan of account.cjs (the writer check), with the
    # retained writer still present: the guard must reject rather than read the failure as "no writer".
    counter = tree / 'awk-calls'
    broken_awk = (r"""awk() { case "${!#}" in */account.cjs) n=$(( $(cat """ + repr(str(counter)) +
                  r""" 2>/dev/null || echo 0) + 1 )); echo "$n" > """ + repr(str(counter)) +
                  r"""; if [ "$n" -ge 2 ]; then return 2; fi;; esac; command awk "$@"; };""")
    result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + helpers + '\n' + broken_awk + '\ntree=' + repr(str(tree)) + '\n' + guard], capture_output=True, text=True)
    assert counter.read_text().strip() == '2', counter.read_text()
    assert result.returncode != 0 and 'writer matcher failed' in result.stderr, (result.returncode, result.stderr)
    print('PASS awk scan error fails closed')
