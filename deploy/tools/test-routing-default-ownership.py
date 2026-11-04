"""Exercise the assembler's actual parser and code matcher on synthetic generations of the routing default's PUT (#2384)."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'deploy/tools/assemble-release.sh').read_text()
def function(name):
    start = source.index(name + '() {')
    return source[start:source.index('\n}', start) + 2]
helpers = 'die() { echo "$*" >&2; exit 1; };\n' + function('code_has') + '\n' + function('routes_toml')
guard = source[source.index('# #2384: the routing default'):source.index('# #2384: only GET /api/reasoning-settings')]
AUTH_MOVED = r"  [/^\/api\/routing-default$/, ['PUT']]," + '\n'
AUTH_OLD = r"  [/^\/api\/account\/retention$/, ['GET', 'PUT']]," + '\n'

def run(tree, extra=''):
    return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + helpers + '\n' + extra + '\ntree=' + repr(str(tree)) + '\n' + guard], capture_output=True, text=True)

with tempfile.TemporaryDirectory(dir=repo) as tmp:
    tree = Path(tmp)
    (tree / 'core/server/routes').mkdir(parents=True)
    (tree / 'rs/contracts/http').mkdir(parents=True)
    def write(core, rust, models='const R = "Routing default is owned by the Rust front.";\n', workspace='const dir = 1;\n'):
        (tree / 'core/server/rust-auth.cjs').write_text(AUTH_OLD + (AUTH_MOVED if core else ''))
        (tree / 'core/server/routes/models.cjs').write_text(models)
        (tree / 'core/server/workspace.cjs').write_text(workspace)
        methods = '["GET", "PUT"]' if rust else '["GET"]'
        (tree / 'rs/contracts/http/routes.toml').write_text(
            '[[route]]\npath = "/api/routing-default"\nowner = "rust"\nmethods = ' + methods + '\n')
    # old/old, new/new, and both mixed generations.
    for core, rust, expected in [(False, False, True), (True, True, True), (False, True, False), (True, False, False)]:
        write(core, rust)
        result = run(tree)
        assert (result.returncode == 0) == expected, (core, rust, result.stderr)
        if not expected:
            assert 'routing default PUT ownership pairing' in result.stderr, result.stderr
        print('PASS generation', core, rust)
    # A moved pair whose Core does not refuse the moved writer.
    write(True, True, models='// nothing\n')
    result = run(tree)
    assert result.returncode != 0 and 'must refuse the moved writer' in result.stderr, result.stderr
    print('PASS a moved pair without the refusal is refused')
    # A moved pair whose Core still writes the preferences, from either file or by the raw file write.
    for models, workspace in [
        ('const R = "Routing default is owned by the Rust front.";\nws.savePreferences();\n', 'const x = 1;\n'),
        ('const R = "Routing default is owned by the Rust front.";\n', 'savePreferences() { atomicJson(f, p); },\n'),
        ('const R = "Routing default is owned by the Rust front.";\n', "atomicJson(path.join(dir, 'preferences.json'), prefs);\n"),
    ]:
        write(True, True, models=models, workspace=workspace)
        result = run(tree)
        assert result.returncode != 0 and 'still writes the preferences' in result.stderr, (models, workspace, result.stderr)
    print('PASS a retained preferences writer is refused')
    # A comment that names the writer is not a writer.
    write(True, True, models='const R = "Routing default is owned by the Rust front.";\n// ws.savePreferences() was here\n')
    assert run(tree).returncode == 0
    print('PASS a comment is not a writer')
    # An operational grep failure at a writer matcher fails closed, not as "no writer".
    write(True, True, models='const R = "Routing default is owned by the Rust front.";\nws.savePreferences();\n')
    broken_grep = r"""grep() { if [ "${3:-}" = 'savePreferences[[:space:]]*[(]' ]; then return 2; fi; command grep "$@"; };"""
    result = run(tree, broken_grep)
    assert result.returncode != 0 and ('writer matcher failed' in result.stderr or 'still writes' in result.stderr), result.stderr
    write(True, True)
    result = run(tree, broken_grep)
    assert result.returncode != 0 and 'writer matcher failed' in result.stderr, result.stderr
    print('PASS matcher error fails closed')
    # A route table that is unreadable still refuses a Core that moved (Rust cannot be shown to match).
    write(True, True)
    (tree / 'rs/contracts/http/routes.toml').write_text('[[route]\npath = broken\n')
    result = run(tree)
    assert result.returncode != 0 and 'must move together' in result.stderr, result.stderr
    print('PASS an unreadable route table refuses a moved Core')
