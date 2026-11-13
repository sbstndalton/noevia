"""Guards in the live-server overlay scripts that can be exercised without Docker or the server.

The release SHA becomes a path component, an image tag and a sed replacement, so both scripts
refuse anything but a hex SHA before touching anything. The Diary overlay archives its own state
(#1487) and may stop or recreate only the Diary container; it never runs the Appdata Backup plugin.
Synthetic Dockerfiles exercise the final-stage COPY/ADD contract in both parsers.
The requirements probe's argv and hash refusals are checked with a recording docker stub.
"""
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OVERLAY = ROOT / 'deploy/examples/overlay-release.sh'
DIARY = ROOT / 'deploy/examples/diary-overlay.sh'
RCLONE = ROOT / 'deploy/offsite/rclone-sync.sh'

BAD_SHAS = ['', 'ABCDEF1', 'abc12', 'abc123g', '../../etc', 'abc1234;touch x', 'abc1234 x', '$(id)', 'a' * 41]


# Generated overlay shape: binary bundle plus the one replaced app directory (agent/); config/ and scripts/ stay the
# running image's, so the overlay's own Dockerfile copies only agent/. The release's Dockerfile still copies all three.
# Real release Dockerfiles copy the two binaries individually; both shapes are checked below.
DIARY_DOCKERFILE = """FROM rust:slim AS tenant-assertion
ADD https://example.invalid/source.tar.gz /tmp/source.tar.gz
COPY tools/ ./tools/
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
COPY --from=tenant-assertion /out/ /usr/local/bin/
COPY agent/ ./agent/
COPY config/ ./config/
COPY scripts/ ./scripts/
CMD ["uvicorn", "agent.app:app"]
"""
OVERLAY_TAIL = 'RUN rm -rf ./agent\nCOPY agent/ ./agent/\n'


def run(script, *args, **env):
    return subprocess.run(['bash', str(script), *args], env=dict(os.environ, **env),
                          capture_output=True, text=True, timeout=30)


class ShaValidation(unittest.TestCase):
    def test_overlay_release_rejects_non_sha_arguments_before_any_work(self):
        for bad in BAD_SHAS:
            for args in [('abc1234', bad), (bad, 'abc1234')]:
                with self.subTest(args=args):
                    result = run(OVERLAY, *args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue('hex characters' in result.stderr or 'release sha' in result.stderr, result.stderr)

    def test_diary_overlay_rejects_non_sha_argument_before_any_work(self):
        for bad in BAD_SHAS:
            with self.subTest(sha=bad):
                result = run(DIARY, bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue('hex characters' in result.stderr or 'source release sha' in result.stderr, result.stderr)

    def test_a_valid_sha_gets_past_validation(self):
        # Fails later (no server layout here), but never with the validation message.
        for script, args in [(OVERLAY, ('abc1234', 'def5678')), (DIARY, ('def5678',))]:
            self.assertNotIn('hex characters', run(script, *args).stderr)

    def test_overlay_release_tolerates_missing_engine_and_model_loader(self):
        text = OVERLAY.read_text()
        # No bare inspect of the optional containers: the engine goes through container_id, which
        # treats only "No such object" as absent (tested below).
        for line in text.splitlines():
            if 'docker inspect cowork-llama-1' in line:
                self.fail(f'bare inspect of the optional engine: {line}')
        self.assertIn('old_native=$(container_id cowork-llama-1) || exit 1', text)
        self.assertNotIn('cowork-model-loader-1 \\', text)

    def test_engine_probe_runs_before_the_release_changes_anything(self):
        text = OVERLAY.read_text()
        probe = text.index('old_native=$(container_id')
        for change in ['mkdir -p "$base/releases/$NEW"', 'docker build', 'ln -sfn', 'sed -i']:
            self.assertLess(probe, text.index(change), change)


class AssembledSource(unittest.TestCase):
    """#952: the release folder comes from the assembled tarball, checked before it is unpacked."""

    def test_overlay_takes_the_assembled_tarball_not_a_git_archive(self):
        text = OVERLAY.read_text()
        self.assertNotIn('src-$NEW', text)
        self.assertIn('src="/tmp/noevia-release-$NEW.tar.gz"', text)

    def test_release_refs_sha_is_checked_before_the_release_folder_exists(self):
        text = OVERLAY.read_text()
        check = text.index('[ "$src_sha" = "$NEW" ]')
        self.assertLess(text.index('tar -xzOf "$src" release-refs'), check)
        self.assertLess(check, text.index('mkdir -p "$base/releases/$NEW"'))
        self.assertLess(check, text.index('docker build'))

    def test_release_refs_check_rejects_a_tree_for_another_sha(self):
        # Run the overlay's own release-refs lines against synthetic tarballs.
        lines = OVERLAY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('src="/tmp/noevia-release-$NEW.tar.gz"'))
        block = '\n'.join(lines[start:start + 4]).replace('/tmp/noevia-release-$NEW.tar.gz', '$TARBALL')
        with tempfile.TemporaryDirectory(prefix='noevia-overlay-src-') as temp:
            tree = pathlib.Path(temp) / 'tree'
            tree.mkdir()
            for sha, expect_ok in [('def5678', True), ('abc1234', False)]:
                (tree / 'release-refs').write_text(f'NOEVIA_SHA={sha}\nNOEVIA_WEB_SHA={"a" * 40}\n')
                tarball = pathlib.Path(temp) / f'{sha}.tar.gz'
                subprocess.run(['tar', '-czf', str(tarball), '-C', str(tree), 'release-refs'], check=True)
                result = subprocess.run(['bash', '-c', 'set -euo pipefail\nNEW=def5678\n' + block + '\necho CHECKED'],
                                        env=dict(os.environ, TARBALL=str(tarball)), capture_output=True, text=True, timeout=30)
                with self.subTest(sha=sha):
                    self.assertEqual('CHECKED' in result.stdout, expect_ok, result.stderr)
                    if not expect_ok:
                        self.assertIn('not deploying', result.stderr)


ID = 'a1b2c3d4e5f60718293a4b5c6d7e8f90' * 2


class ContainerId(unittest.TestCase):
    """Run the `container-id` block of overlay-release.sh against a fake `docker` on PATH."""

    def block(self):
        lines = OVERLAY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('# BEGIN container-id'))
        end = next(i for i, l in enumerate(lines) if l.startswith('# END container-id'))
        return '\n'.join(lines[start + 1:end])

    def probe(self, docker_body):
        with tempfile.TemporaryDirectory(prefix='noevia-fake-docker-') as temp:
            fake = pathlib.Path(temp) / 'docker'
            fake.write_text('#!/bin/bash\n' + docker_body + '\n')
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            script = 'set -euo pipefail\n' + self.block() + '\nold=$(container_id cowork-llama-1) || exit 1\necho "ID=[$old]"'
            return subprocess.run(['bash', '-c', script], env=dict(os.environ, PATH=f'{temp}:{os.environ["PATH"]}'),
                                  capture_output=True, text=True, timeout=30)

    def test_returns_the_id_of_an_existing_container(self):
        result = self.probe(f'echo {ID}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'ID=[{ID}]', result.stdout)

    def test_a_cli_warning_next_to_the_id_is_not_part_of_the_id(self):
        result = self.probe(f'echo "WARNING: a deprecated flag" >&2; echo {ID}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'ID=[{ID}]', result.stdout)

    def test_unexpected_success_output_stops_the_release_and_is_reported(self):
        for body in ['echo sha256:abc123', 'echo "WARNING: only a warning"', 'echo ' + ID.upper(), 'echo ' + ID[:-1],
                     f'echo {ID}; echo {ID[::-1]}', 'true']:
            with self.subTest(body=body):
                result = self.probe(body)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('unexpected output', result.stderr)
                self.assertIn('not deploying', result.stderr)
                self.assertNotIn('ID=[', result.stdout)

    def test_a_missing_container_is_absent_not_an_error(self):
        for message in ['Error: No such object: cowork-llama-1', 'Error response from daemon: No such container: cowork-llama-1']:
            with self.subTest(message=message):
                result = self.probe(f'echo "{message}" >&2; exit 1')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('ID=[]', result.stdout)

    def test_any_other_inspect_failure_stops_with_the_docker_error(self):
        for message in ['Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?',
                        'permission denied while trying to connect to the Docker daemon socket', 'context deadline exceeded']:
            with self.subTest(message=message):
                result = self.probe(f'echo "{message}" >&2; exit 1')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertIn('not deploying', result.stderr)
                self.assertNotIn('ID=[', result.stdout)

    def test_a_failure_without_any_output_is_still_an_error(self):
        result = self.probe('exit 1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('ID=[', result.stdout)


class RcloneJsonEscape(unittest.TestCase):
    def escape(self, value):
        text = RCLONE.read_text()
        start = text.index('json_escape() {')
        func = text[start:text.index('\n}\n', start) + 3]
        out = subprocess.run(['bash', '-c', func + '\njson_escape "$1"', 'x', value], capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout

    def test_every_c0_control_quote_and_backslash_round_trips_through_json(self):
        value = 'a"b\\c' + ''.join(chr(i) for i in range(1, 32)) + 'z\x7f'
        escaped = self.escape(value)
        self.assertFalse(any(ord(c) < 32 for c in escaped), repr(escaped))
        self.assertEqual(json.loads('"' + escaped + '"'), value)

    def test_plain_text_is_unchanged(self):
        self.assertEqual(self.escape('gdrive:noevia backups'), 'gdrive:noevia backups')


class ScopedDiaryOverlay(unittest.TestCase):
    """#1487: diary-overlay.sh runs end to end against a synthetic appdata tree.

    Paths are pointed at a temp tree; docker, php and gzip are stubs on PATH that record their argv
    (gzip can be told to fail `-t`). The real preflight up.sh runs and reaches the stubbed docker
    compose. Only cowork-diary-1 may be stopped, restarted or recreated, and the Appdata Backup plugin
    never runs. Every value is synthetic.
    """

    NEW = 'abc1234'
    OLD = 'def5678'
    OLD_ID = 'sha256:' + 'a' * 64
    LIFECYCLE = {'stop', 'start', 'restart', 'kill', 'rm', 'down', 'pause', 'unpause', 'update'}

    DOCKER_STUB = r"""
# Runs the overlay's own inventory script (the argument after -c) the way the image would, on the emulated /app.
manifest_in() {
  root=$1; shift
  while [ "$1" != -c ]; do shift; done; shift
  script=$1; shift; shift   # the script, then argv0
  dir=$1; shift             # /app/<dir>, then the skipped name
  sub="${dir#/app/}"
  [ "${MISSING_LISTING_DIR:-}" != "$sub" ] || exit 1
  [ "${MISSING_RUNNING_DIR:-}" != "$sub" ] || [ "$root" != "$RUNNING_APP" ] || exit 1
  if [ "$root" = "$CAND_APP" ]; then case "${STALE_FILE:-}" in "$sub/"*) mkdir -p "$(dirname "$root/$STALE_FILE")"; printf x > "$root/$STALE_FILE" ;; esac; fi
  if [ "${TRUNCATED_MANIFEST:-}" = "$sub" ]; then echo "F 0 ./partial"; exit 0; fi
  sh -c "$script" sh "$root/$sub" "$@"
}
logargs=(); for a in "$@"; do case "$a" in *diary-overlay-manifest*) a='<manifest>' ;; esac; logargs+=("$a"); done
printf 'docker %s\n' "${logargs[*]}" >> "$CALL_LOG"
case "$*" in
  "image inspect cowork-diary:@NEW@") [ -e "$CALL_LOG.tagged" ] || exit 1 ;;
  "tag @OLD_ID@ "*) ;;
  "tag cowork-diary:@NEW@-candidate cowork-diary:@NEW@") : > "$CALL_LOG.tagged" ;;
  "image rm cowork-diary:@NEW@") rm -f "$CALL_LOG.tagged" ;;
  "image rm cowork-diary:@NEW@-candidate") [ -z "${FAIL_CANDIDATE_RM:-}" ] || exit 1 ;;
  "image inspect cowork-diary:@OLD@ --format {{.Id}}") echo "@OLD_ID@" ;;
  "inspect cowork-diary-1 --format {{.Image}}")
    if [ -n "${LATER_IMAGE:-}" ] && [ -e "$CALL_LOG.inspected" ]; then echo "$LATER_IMAGE"; else : > "$CALL_LOG.inspected"; echo "@OLD_ID@"; fi ;;
  "inspect cowork-diary-1 --format diary"*) echo "diary healthy restarts=0" ;;
  "exec cowork-diary-1 python -c"*) exit 1 ;;
  "run --rm "*"--entrypoint sh cowork-diary:@OLD@ -c"*)
    all="$*"
    case "$all" in
      *diary-overlay-manifest*)
        # The running image's preserved directory (config/, scripts/): the overlay replaces neither.
        manifest_in "$RUNNING_APP" "$@" ;;
      *)
        # The running image's /app/requirements.txt (#2112) or /app/constraints.txt (#2523): the file the probe names.
        f=$(printf '%s' "$all" | grep -oE '/app/(requirements|constraints)\.txt' | tail -1)
        [ -n "$f" ] && [ -f "$RUNNING_APP/${f#/app/}" ] && sha256sum "$RUNNING_APP/${f#/app/}" ;;
    esac ;;
  "run --rm --entrypoint python"*) [ -z "${FAIL_CANDIDATE_IMPORT:-}" ] || exit 1; echo "candidate imports ok" ;;
  "build -q -t cowork-diary:@NEW@-candidate "*)
    # Emulate the build of the generated overlay Dockerfile on top of the running image's /app (#2112): `RUN rm -rf`
    # removes, `COPY <dir>/ ./<dir>/` copies from the build context. Anything else is the running image's.
    ctx="${!#}"; cp "$ctx/Dockerfile" "$CALL_LOG.dockerfile"
    (cd "$ctx" && find . -type f | LC_ALL=C sort | sed 's|^\./||') > "$CALL_LOG.context"
    rm -rf "$CAND_APP"; cp -R "$RUNNING_APP" "$CAND_APP"
    while IFS= read -r line; do
      case "$line" in
        "RUN rm -rf "*) for t in ${line#RUN rm -rf }; do rm -rf "$CAND_APP/${t#./}"; done ;;
        "COPY --from"*) ;;
        "COPY entrypoint.sh /usr/local/bin/diary-entrypoint") cp "$ctx/entrypoint.sh" "$CAND_APP/entrypoint.sh"; stat -c '%a' "$ctx/entrypoint.sh" > "$CALL_LOG.entrypoint_mode" ;;
        "COPY "*) src="${line#COPY }"; src="${src%% *}"; mkdir -p "$CAND_APP/$src"; cp -R "$ctx/$src/." "$CAND_APP/$src/" ;;
      esac
    done < "$ctx/Dockerfile" ;;
  "run --rm --network none --entrypoint sh cowork-diary:@NEW@-candidate -c"*)
    # The candidate's /app/<dir> as the emulated build left it, plus a stale file when the test asks (#1624).
    manifest_in "$CAND_APP" "$@" ;;
  "compose "*" config --format json") echo "{}" ;;
  "compose "*" up "*) [ -z "${FAIL_UP:-}" ] || exit 1 ;;
esac
exit 0
"""
    # A tool that fails (FAIL_MODE=fail: no output; partial: its first output line) when it is run by the inventory in a
    # directory matching FAIL_PWD (the inventory cd's into the tree it lists first), for the tool named in FAIL_TOOL.
    TOOL_SHIM = r"""
if [ "${FAIL_TOOL:-}" = "@NAME@" ]; then
  case "$PWD" in ${FAIL_PWD:-__no_such_directory__})
    if [ "${FAIL_MODE:-fail}" = partial ]; then "@REAL@" "$@" | head -n 1; fi
    echo "@NAME@: injected failure" >&2; exit 1 ;;
  esac
fi
exec "@REAL@" "$@"
"""
    PHP_STUB = r"""
printf 'php %s\n' "$*" >> "$CALL_LOG"
cat >/dev/null
exit 0
"""
    GZIP_STUB = r"""
for arg in "$@"; do
  if [ "$arg" = -t ] && [ -n "${INJECT_GZIP_FAILURE:-}" ]; then echo "gzip: injected failure" >&2; exit 1; fi
done
exec "@REAL_GZIP@" "$@"
"""

    # The script's `sed -i EXPR FILE` is GNU syntax (DaServer, CI). BSD sed (macOS) needs `-i ''`, so the
    # test shim adds it only when the real sed is BSD; the script text is never changed for the test.
    SED_STUB = r"""
if [ "$1" = -i ] && ! "@REAL_SED@" --version >/dev/null 2>&1; then shift; exec "@REAL_SED@" -i '' "$@"; fi
exec "@REAL_SED@" "$@"
"""

    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp(prefix='noevia-diary-overlay-'))
        self.addCleanup(shutil.rmtree, self.temp, ignore_errors=True)
        self.base = self.temp / 'appdata'
        self.manager = self.temp / 'manager'
        self.backups = self.temp / 'backups'
        self.bin = self.temp / 'bin'
        self.log = self.temp / 'calls.log'
        for d in [self.base / 'config', self.base / 'state/diary/users/u1', self.base / 'state/web',
                  self.base / 'tools/preflight', self.base / f'releases/{self.NEW}/services/diary/agent',
                  self.manager, self.backups, self.bin]:
            d.mkdir(parents=True)
        self.config = self.base / 'config/.env'
        self.config.write_text(f'COWORK_VERSION=0000000\nDIARY_VERSION={self.OLD}\nDIARY_AUTH_TOKEN=synthetic-token\n')
        (self.base / 'state/diary/users/u1/managed-diary.db').write_bytes(b'synthetic diary state')
        (self.base / 'state/web/cowork.db').write_bytes(b'synthetic web state')
        # The release tree: what the Diary Dockerfile copies into /app (agent/, config/, scripts/). Only agent/ differs
        # from the running image; config/ and scripts/ are the running image's, as the companion overlay requires.
        self.release = self.base / f'releases/{self.NEW}/services/diary'
        for rel, text in {'agent/app.py': 'x = 1\n', 'config/config.yaml': 'prompt: kept\n',
                          'config/prompts/system.md': 'kept system prompt\n', 'scripts/tool.py': 'y = 2\n'}.items():
            (self.release / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.release / rel).write_text(text)
        self.dockerfile(DIARY_DOCKERFILE)
        # The running image's /app: older agent code (with a file the release dropped), config and prompt.
        self.running_app = self.temp / 'running-app'
        self.cand_app = self.temp / 'candidate-app'
        (self.release / 'requirements.txt').write_text('synthetic-dependency==1.0\n')
        self.running_app.mkdir(parents=True, exist_ok=True)
        (self.running_app / 'requirements.txt').write_text('synthetic-dependency==1.0\n')
        for rel, text in {'agent/app.py': 'x = 0\n', 'agent/static/old.js': 'gone\n', 'config/config.yaml': 'prompt: kept\n',
                          'config/prompts/system.md': 'kept system prompt\n', 'scripts/tool.py': 'y = 2\n'}.items():
            (self.running_app / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.running_app / rel).write_text(text)
        (self.manager / 'compose.yaml').write_text('services: {}\n')
        # up.sh sources diary-image-guard.sh from its own directory and fails closed without it (#1148),
        # so the installed preflight directory is staged whole, with the installer the runbook names (#1597).
        installed = subprocess.run(['bash', str(ROOT / 'deploy/preflight/install.sh'), str(self.base / 'tools/preflight')],
                                   capture_output=True, text=True, timeout=30)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        # #2105: the installed model check is a stub here (test_diary_models_check_2105.py runs the real one);
        # it records the .env it was given in its own log, so the docker call log stays unchanged.
        models_check = self.base / 'tools/preflight/diary-models-check.sh'
        models_check.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALL_LOG.modelcheck"\n'
                                '[ -z "${FAIL_MODELS_CHECK:-}" ] || { echo "REFUSED stub" >&2; exit 1; }\nexit 0\n')
        models_check.chmod(0o755)
        subst = {'@NEW@': self.NEW, '@OLD@': self.OLD, '@OLD_ID@': self.OLD_ID,
                 '@AGENT_DIR@': str(self.base / f'releases/{self.NEW}/services/diary/agent'),
                 '@REAL_GZIP@': shutil.which('gzip') or '/usr/bin/gzip', '@REAL_SED@': shutil.which('sed') or '/usr/bin/sed'}
        self.stub('docker', self.DOCKER_STUB, subst)
        self.stub('php', self.PHP_STUB, subst)
        self.stub('gzip', self.GZIP_STUB, subst)
        self.stub('sed', self.SED_STUB, subst)
        for tool in ('find', 'sort', 'sha256sum', 'readlink'):
            self.stub(tool, self.TOOL_SHIM, {'@NAME@': tool, '@REAL@': shutil.which(tool) or f'/usr/bin/{tool}'})
        text = DIARY.read_text()
        for old, new in [('base=/mnt/docker/appdata/cowork;', f"base='{self.base}';"),
                         ('cd /boot/config/plugins/compose.manager/projects/Cowork', f"cd '{self.manager}'")]:
            self.assertEqual(text.count(old), 1, old)
            text = text.replace(old, new)
        self.script = self.temp / 'diary-overlay.sh'
        self.script.write_text(text)

    def dockerfile(self, text):
        (self.release / 'Dockerfile').write_text(text)

    def stub(self, name, body, subst):
        for token, value in subst.items():
            body = body.replace(token, value)
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def overlay(self, backups=None, env=None):
        environ = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', CALL_LOG=str(self.log),
                       BACKUP_ROOT=str(backups or self.backups), COWORK_PROJECT_DIR=str(self.manager),
                       RUNNING_APP=str(self.running_app), CAND_APP=str(self.cand_app))
        for name in ('STALE_FILE', 'MISSING_LISTING_DIR'):
            environ.pop(name, None)
        for name in ('MISSING_RUNNING_DIR', 'FAIL_TOOL', 'FAIL_PWD', 'FAIL_MODE', 'TRUNCATED_MANIFEST'):
            environ.pop(name, None)
        environ.pop('INJECT_GZIP_FAILURE', None)
        environ.update(env or {})
        return subprocess.run(['bash', str(self.script), self.NEW], env=environ, capture_output=True, text=True, timeout=60)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def assert_only_diary_is_disturbed(self, calls):
        for line in calls:
            self.assertNotIn('appdata.backup', line, line)
            argv = line.split()
            if argv[0] == 'php':
                continue
            self.assertEqual(argv[0], 'docker', line)
            verb = argv[1]
            if verb == 'compose':
                self.assertEqual(argv[2:4], ['--env-file', str(self.config)], line)
                sub = argv[4]
                if sub == 'up':
                    self.assertIn('--no-deps', argv, line)
                    self.assertEqual(argv[-1], 'diary', line)
                else:
                    self.assertEqual(sub, 'config', f'compose {sub} is not allowed in the Diary overlay: {line}')
            elif verb in self.LIFECYCLE:
                self.assertEqual(argv[-1], 'cowork-diary-1', f'{verb} must name only the Diary container: {line}')
            if 'cowork-web-1' in line:
                self.assertEqual(verb, 'exec', f'web may only be read through docker exec: {line}')

    def test_success_stops_and_recreates_only_diary_and_archives_only_diary_state(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('DIARY_OVERLAY_COMPLETE', result.stdout)
        calls = self.calls()
        self.assert_only_diary_is_disturbed(calls)
        stops = [c for c in calls if c.startswith('docker stop')]
        self.assertEqual(stops, ['docker stop --time 30 cowork-diary-1'])
        ups = [c for c in calls if c.startswith('docker compose') and ' up ' in c]
        self.assertEqual(len(ups), 1, ups)
        self.assertTrue(ups[0].endswith(' diary'), ups[0])
        self.assertLess(calls.index(stops[0]), calls.index(ups[0]))
        self.assertIn(f'DIARY_VERSION={self.NEW}', self.config.read_text())
        # No Appdata Backup plugin folder, and one diary_<SHA>_<UTC> folder holding only Diary state and .env.
        self.assertEqual(list(self.backups.glob('ab_*')), [])
        folders = list(self.backups.iterdir())
        self.assertEqual(len(folders), 1, folders)
        self.assertRegex(folders[0].name, rf'^diary_{self.NEW}_\d{{8}}T\d{{6}}Z$')
        with tarfile.open(folders[0] / 'diary-appdata.tar.gz') as archive:
            names = archive.getnames()
        self.assertIn('config/.env', names)
        self.assertIn('state/diary/users/u1/managed-diary.db', names)
        self.assertFalse([n for n in names if n.startswith('state/web')], names)

    CANDIDATE_RM = f'docker image rm cowork-diary:{NEW}-candidate'

    def test_a_failed_candidate_check_removes_the_candidate(self):
        # P3-1: a refused candidate is never left behind (Docker resources are never pruned).
        result = self.overlay(env={'FAIL_CANDIDATE_IMPORT': '1'})
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls()
        self.assertEqual(calls.count(self.CANDIDATE_RM), 1, calls)
        self.assertFalse([c for c in calls if c.startswith('docker stop')], calls)

    def test_a_rolled_back_overlay_removes_the_candidate(self):
        result = self.overlay(env={'FAIL_UP': '1'})
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls()
        self.assertIn(f'docker image rm cowork-diary:{self.NEW}', calls)
        self.assertEqual(calls.count(self.CANDIDATE_RM), 1, calls)
        self.assertLess(calls.index(f'docker image rm cowork-diary:{self.NEW}'), calls.index(self.CANDIDATE_RM))

    def test_a_completed_overlay_removes_the_candidate_once(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls().count(self.CANDIDATE_RM), 1)

    def test_a_failure_before_the_build_removes_no_image(self):
        result = self.overlay(backups=self.temp / 'missing-backups')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse([c for c in self.calls() if c.startswith('docker image rm')], self.calls())

    def test_the_candidate_is_kept_while_the_new_tag_names_it(self):
        # A failure after cowork-diary:<V> was tagged and kept: that tag names the same image, so nothing is removed again.
        result = self.overlay(env={'FAIL_CANDIDATE_RM': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('DIARY_OVERLAY_COMPLETE', result.stdout)
        self.assertEqual(self.calls().count(self.CANDIDATE_RM), 1, self.calls())

    def test_a_stale_agent_file_in_the_candidate_stops_before_anything_is_stopped_or_tagged(self):
        # #1624: COPY never deletes, so an old static/ file would survive; the overlay must refuse it.
        result = self.overlay(env={'STALE_FILE': 'agent/static/app.js'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from releases', result.stderr)
        self.assertIn('static/app.js', result.stderr)
        calls = self.calls()
        self.assertFalse([c for c in calls if c.startswith(('docker stop', 'docker compose', 'docker tag cowork-diary:abc'))], calls)
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())
        self.assertEqual(list(self.backups.iterdir()), [])

    def test_an_unlistable_candidate_stops_before_anything_is_stopped(self):
        result = self.overlay(env={'MISSING_LISTING_DIR': 'agent'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('could not list /app/agent in the candidate', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith('docker stop')])

    def test_the_candidate_listing_of_the_replaced_and_the_preserved_directories_is_checked_and_reported(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('candidate agent/ matches the release (1 files)', result.stdout)
        self.assertIn('candidate config/ is the running image\'s, untouched', result.stdout)
        self.assertIn('candidate scripts/ is the running image\'s, untouched', result.stdout)
        self.assertNotIn('candidate config/ matches the release', result.stdout)
        self.assertNotIn('candidate scripts/ matches the release', result.stdout)
        listing = [c for c in self.calls() if '--entrypoint sh cowork-diary:abc1234-candidate' in c]
        self.assertEqual(len(listing), 3, self.calls())
        for line, name in zip(listing, ('agent', 'config', 'scripts')):
            self.assertIn(f' sh /app/{name} ', line + ' ')

    def test_only_agent_is_replaced_config_and_scripts_stay_the_running_images(self):
        # Companion rule (review P2-1, supersedes the #2112 whole-tree replacement): agent/ code only.
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.dockerfile_text()), 'FROM cowork-diary:rollback-before-diary-overlay\n' + OVERLAY_TAIL)
        self.assertNotIn('config', self.dockerfile_text())
        self.assertNotIn('scripts', self.dockerfile_text())
        app = self.cand_app
        self.assertEqual((app / 'agent/app.py').read_text(), 'x = 1\n')
        self.assertFalse((app / 'agent/static/old.js').exists(), 'a file the release dropped does not survive')
        for rel in ('config/config.yaml', 'config/prompts/system.md', 'scripts/tool.py'):
            self.assertEqual((app / rel).read_bytes(), (self.running_app / rel).read_bytes(), rel)

    def test_the_build_context_holds_the_agent_directory_only(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.context_files(), ['Dockerfile', 'agent/app.py'])

    def test_a_release_whose_config_or_scripts_differ_from_the_running_image_refuses_before_anything_is_built(self):
        # Silently keeping the old prompt/config under new agent code is the #2112 bug; the overlay refuses instead.
        for rel, text in (('config/config.yaml', 'prompt: new\n'), ('config/prompts/system.md', 'new system prompt\n'),
                          ('config/prompts/extra.md', 'added\n'), ('scripts/tool.py', 'y = 3\n'), ('scripts/new.py', 'z = 1\n')):
            with self.subTest(rel=rel):
                path = self.release / rel
                existed = path.exists()
                before = path.read_text() if existed else None
                path.write_text(text)
                try:
                    result = self.overlay()
                finally:
                    path.write_text(before) if existed else path.unlink()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'differs from the running image\'s /app/{rel.split("/")[0]}', result.stderr)
                self.assertIn('rebuild the image instead', result.stderr)
                self.assert_nothing_started()
                self.assertEqual(list(self.backups.iterdir()), [])
                self.log.unlink(missing_ok=True)

    def test_a_release_that_drops_a_config_or_scripts_file_the_image_has_refuses(self):
        for rel in ('config/prompts/system.md', 'scripts/tool.py'):
            with self.subTest(rel=rel):
                (self.release / rel).rename(self.release / (rel + '.parked'))
                try:
                    result = self.overlay()
                finally:
                    (self.release / (rel + '.parked')).rename(self.release / rel)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('rebuild the image instead', result.stderr)
                self.assert_nothing_started()
                self.log.unlink(missing_ok=True)

    def test_a_running_image_that_cannot_list_a_preserved_directory_refuses(self):
        for name in ('config', 'scripts'):
            with self.subTest(name=name):
                result = self.overlay(env={'MISSING_RUNNING_DIR': name})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'could not inventory /app/{name} in the running image completely', result.stderr)
                self.assert_nothing_started()
                self.log.unlink(missing_ok=True)

    def test_the_release_smoke_asset_may_differ_and_is_never_installed(self):
        # The smoke script is the one scripts/ file the overlay uses; it is run from the release, so the image
        # may hold an older (or no) copy without blocking the overlay, and the candidate does not gain one.
        (self.release / 'scripts/smoke_diary_leaves.py').write_text('# release smoke\n')
        (self.running_app / 'scripts/smoke_diary_leaves.py').write_text('# older smoke\n')
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.cand_app / 'scripts/smoke_diary_leaves.py').read_text(), '# older smoke\n')
        self.assertNotIn('smoke_diary_leaves', self.dockerfile_text())
        self.assertNotIn('scripts/smoke_diary_leaves.py', ' '.join(self.context_files()))

    def test_a_candidate_whose_preserved_directory_differs_from_the_running_image_stops_before_anything_is_stopped(self):
        for stale in ('config/prompts/old.md', 'scripts/old.py'):
            with self.subTest(stale=stale):
                result = self.overlay(env={'STALE_FILE': stale})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'candidate /app/{stale.split("/")[0]} differs from the running image', result.stderr)
                self.assertIn(stale.split('/', 1)[1].rsplit('/', 1)[-1], result.stderr)
                self.assertFalse([c for c in self.calls() if c.startswith(('docker stop', 'docker compose', 'docker tag cowork-diary:abc'))])
                self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())
                self.log.unlink(missing_ok=True)

    # ---- the preserved-directory inventory covers links and cannot be completed silently (round-2 review P2-1, P2-2)

    def tree(self, root, entries):
        """Write {relative path: text} (a str is a regular file) or {path: ('link', target)} under root, replacing any entry."""
        for rel, value in entries.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_symlink() or path.is_file():
                path.unlink()
            if isinstance(value, tuple):
                path.symlink_to(value[1])
            else:
                path.write_text(value)

    def assert_refused_before_build(self, result, text=None):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        if text:
            self.assertIn(text, result.stderr)
        self.assert_nothing_started()
        self.assertEqual(list(self.backups.iterdir()), [])
        self.log.unlink(missing_ok=True)

    def both(self, entries):
        self.tree(self.release, entries)
        self.tree(self.running_app, entries)

    def test_the_round_three_collisions_are_differences(self):
        # Link `a -> b` to `c` versus link `a` to `b -> c` printed one identical line; a target with and without a
        # trailing newline printed one identical line. Each pair is one effective difference the guard must refuse.
        pairs = {
            'separator in the name or the target': ({'config/a -> b': ('link', 'c')}, {'config/a': ('link', 'b -> c')}),
            'trailing newline in the target': ({'config/l': ('link', 'target')}, {'config/l': ('link', 'target\n')}),
            'two trailing newlines': ({'config/l': ('link', 'target\n')}, {'config/l': ('link', 'target\n\n')}),
            'name that imitates a record': ({'config/D 2e2f78': 'x\n'}, {'config/D': 'x\n'}),
        }
        for name, (image, release) in pairs.items():
            with self.subTest(name):
                for root, entries in ((self.running_app, image), (self.release, release)):
                    self.tree(root, entries)
                self.assert_refused_before_build(self.overlay(), "differs from the running image's /app/config")
                for root, entries in ((self.running_app, image), (self.release, release)):
                    for rel in entries:
                        (root / rel).unlink()

    def test_identical_awkward_links_and_names_are_accepted(self):
        entries = {'config/a -> b': ('link', 'c'), 'config/l': ('link', 'target\n'), 'config/sp ace': 'x\n',
                   'config/prompts/F 00': 'y\n'}
        self.both(entries)
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.cand_app / 'config/l').readlink().as_posix(), 'target\n')

    def test_a_difference_is_shown_decoded_with_control_characters_quoted(self):
        self.both({'config/a -> b': ('link', 'c'), 'config/l': ('link', 'target\n')})
        self.tree(self.release, {'config/l': ('link', 'other\n')})
        refused = self.overlay()
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("$'target\\n'", refused.stderr)
        self.assertIn("$'other\\n'", refused.stderr)
        self.assertIn('./l', refused.stderr)

    def test_ignored_cache_contents_do_not_change_the_verdict_on_either_side(self):
        # Round-3 P3-1: the newline scan walked __pycache__ although the inventory prunes it.
        for root in (self.release, self.running_app):
            self.tree(root, {'config/__pycache__/x.pyc': 'c', 'scripts/__pycache__/y.pyc': 'c'})
        (self.release / 'config/__pycache__/ignored\nname.pyc').write_text('x')
        (self.running_app / 'scripts/__pycache__/also\nignored.pyc').write_text('x')
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root can read an unreadable directory')
    def test_an_unreadable_ignored_cache_does_not_refuse(self):
        for root in (self.release, self.running_app):
            self.tree(root, {'config/__pycache__/x.pyc': 'c'})
            (root / 'config/__pycache__').chmod(0)
        try:
            result = self.overlay()
        finally:
            for root in (self.release, self.running_app):
                (root / 'config/__pycache__').chmod(0o755)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_link_that_points_at_another_identical_file_is_a_difference(self):
        # The regular-file manifests are equal; the effective system prompt is not.
        self.both({'config/prompts/a.md': 'same\n', 'config/prompts/b.md': 'same\n'})
        self.tree(self.running_app, {'config/prompts/system.md': ('link', 'a.md')})
        self.tree(self.release, {'config/prompts/system.md': ('link', 'b.md')})
        self.assert_refused_before_build(self.overlay(), "differs from the running image's /app/config")

    def test_a_link_present_on_one_side_only_is_a_difference(self):
        for side, name in (('release', 'scripts__new_py'), ('image', 'scripts__new_py'), ('release', 'config__extra'), ('image', 'config__extra')):
            with self.subTest(side=side, name=name):
                root = self.release if side == 'release' else self.running_app
                self.tree(root, {name.replace('__', '/').replace('_py', '.py'): ('link', 'tool.py' if name.startswith('scripts') else 'config.yaml')})
                self.assert_refused_before_build(self.overlay(), "differs from the running image's")
                (root / name.replace('__', '/').replace('_py', '.py')).unlink()

    def test_a_file_replaced_by_a_link_or_a_link_by_a_file_is_a_difference(self):
        self.both({'config/prompts/real.md': 'body\n'})
        self.tree(self.running_app, {'config/prompts/system.md': 'body\n'})
        self.tree(self.release, {'config/prompts/system.md': ('link', 'real.md')})
        self.assert_refused_before_build(self.overlay(), "differs from the running image's /app/config")
        self.tree(self.running_app, {'config/prompts/system.md': ('link', 'real.md')})
        self.tree(self.release, {'config/prompts/system.md': 'body\n'})
        self.assert_refused_before_build(self.overlay(), "differs from the running image's /app/config")

    def test_a_directory_link_is_compared_by_target_not_followed(self):
        self.both({'config/a/x': '1\n', 'config/b/x': '1\n'})
        self.tree(self.running_app, {'config/cur': ('link', 'a')})
        self.tree(self.release, {'config/cur': ('link', 'b')})
        self.assert_refused_before_build(self.overlay(), "differs from the running image's /app/config")

    def test_identical_links_including_dangling_and_directory_links_are_accepted(self):
        self.both({'config/prompts/a.md': 'x\n', 'config/prompts/system.md': ('link', 'a.md'), 'config/dir/f': '1\n',
                   'config/cur': ('link', 'dir'), 'scripts/gone': ('link', 'missing.py')})
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.cand_app / 'config/prompts/system.md').readlink().as_posix(), 'a.md')
        self.assertEqual((self.cand_app / 'scripts/gone').readlink().as_posix(), 'missing.py')

    def test_empty_preserved_directories_on_both_sides_are_accepted(self):
        for root in (self.release, self.running_app):
            (root / 'scripts/tool.py').unlink()
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("candidate scripts/ is the running image's, untouched", result.stdout)

    def test_unsupported_entries_and_names_refuse_on_either_side(self):
        cases = []
        for side in ('release', 'image'):
            root = self.release if side == 'release' else self.running_app
            cases.append((side, 'fifo', lambda r=root: os.mkfifo(r / 'config/pipe')))
            cases.append((side, 'newline name', lambda r=root: (r / 'config/bad\nname').write_text('x')))
        for side, name, make in cases:
            with self.subTest(side=side, name=name):
                make()
                self.assert_refused_before_build(self.overlay(), 'could not inventory')
                for root in (self.release, self.running_app):
                    for leftover in ('pipe', 'bad\nname'):
                        (root / 'config' / leftover).unlink(missing_ok=True)

    TOOLS = ('find', 'sort', 'sha256sum', 'readlink')

    def test_a_failing_tool_while_inventorying_either_tree_refuses(self):
        # Hidden before: find | sort | xargs sha256sum reported only xargs' status, so a failed traversal looked like
        # an empty (or short) directory. Each producer failing, with nothing or only part of its output, must refuse.
        self.both({'config/prompts/a.md': 'x\n', 'config/prompts/link': ('link', 'a.md')})
        sides = (('release', f'*/releases/{self.NEW}/services/diary/config*', 'could not inventory releases/'),
                 ('image', '*/running-app/config*', 'in the running image completely'))
        for side, pattern, message in sides:
            for tool in self.TOOLS:
                for mode in ('fail', 'partial'):
                    if tool in ('sha256sum', 'readlink') and mode == 'partial':
                        continue
                    with self.subTest(side=side, tool=tool, mode=mode):
                        result = self.overlay(env={'FAIL_TOOL': tool, 'FAIL_PWD': pattern, 'FAIL_MODE': mode})
                        self.assert_refused_before_build(result, message)

    def test_a_failed_traversal_is_not_an_empty_directory_that_equals_an_empty_directory(self):
        # The reviewer's case: the image's scripts/ is empty, the release's cannot be traversed.
        for root in (self.release, self.running_app):
            (root / 'scripts/tool.py').unlink()
        for tool in ('find', 'sort'):
            with self.subTest(tool=tool):
                result = self.overlay(env={'FAIL_TOOL': tool, 'FAIL_PWD': f'*/releases/{self.NEW}/services/diary/scripts*'})
                self.assert_refused_before_build(result, 'could not inventory releases/')
            with self.subTest(tool=tool, side='image'):
                result = self.overlay(env={'FAIL_TOOL': tool, 'FAIL_PWD': '*/running-app/scripts*'})
                self.assert_refused_before_build(result, 'in the running image completely')

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root can read an unreadable directory')
    def test_an_unreadable_subdirectory_on_either_side_refuses(self):
        self.both({'config/prompts/a.md': 'x\n'})
        for root, message in ((self.release, 'could not inventory releases/'), (self.running_app, 'in the running image completely')):
            with self.subTest(root=root.name):
                locked = root / 'config/prompts'
                locked.chmod(0)
                try:
                    result = self.overlay()
                finally:
                    locked.chmod(0o755)
                self.assert_refused_before_build(result, message)

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root can read an unreadable file')
    def test_an_unreadable_file_on_either_side_refuses(self):
        for root in (self.release, self.running_app):
            with self.subTest(root=root.name):
                target = root / 'config/config.yaml'
                target.chmod(0)
                try:
                    result = self.overlay()
                finally:
                    target.chmod(0o644)
                self.assert_refused_before_build(result, 'could not inventory')

    def test_an_incomplete_manifest_without_its_end_marker_is_not_accepted(self):
        result = self.overlay(env={'TRUNCATED_MANIFEST': 'config'})
        self.assert_refused_before_build(result, 'in the running image completely')

    def test_a_candidate_inventory_that_fails_or_is_incomplete_refuses_before_anything_is_stopped(self):
        cases = [('agent', {'FAIL_TOOL': 'find', 'FAIL_PWD': '*/candidate-app/agent*'}, 'could not list /app/agent in the candidate'),
                 ('config', {'FAIL_TOOL': 'sort', 'FAIL_PWD': '*/candidate-app/config*'}, 'could not list /app/config in the candidate'),
                 ('scripts', {'FAIL_TOOL': 'sha256sum', 'FAIL_PWD': '*/candidate-app/scripts*'}, 'could not list /app/scripts in the candidate'),
                 ('agent', {'FAIL_TOOL': 'find', 'FAIL_PWD': '*/ctx/agent*'}, 'completely'),
                 ('config', {'TRUNCATED_MANIFEST': 'config'}, None)]
        for name, env, message in cases:
            with self.subTest(name=name, env=env):
                result = self.overlay(env=env)
                self.assertNotEqual(result.returncode, 0)
                if message:
                    self.assertIn(message, result.stderr)
                self.assertFalse([c for c in self.calls() if c.startswith(('docker stop', 'docker compose', 'docker tag cowork-diary:abc'))])
                self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())
                self.log.unlink(missing_ok=True)

    def test_a_release_without_one_of_the_directories_refuses_before_anything_is_built(self):
        shutil.rmtree(self.release / 'config')
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f'no releases/{self.NEW}/services/diary/config', result.stdout)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag'))])

    def test_a_dockerfile_that_copies_another_directory_into_app_refuses_naming_it(self):
        self.dockerfile(DIARY_DOCKERFILE + 'COPY gate/ ./gate/\n')
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('the Dockerfile copies gate/ but this overlay would leave it out', result.stderr)
        self.assertIn('update overlay_dirs', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag', 'docker compose'))], self.calls())
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_a_dockerfile_that_no_longer_copies_a_listed_directory_refuses_naming_it(self):
        self.dockerfile(DIARY_DOCKERFILE.replace('COPY scripts/ ./scripts/\n', ''))
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('this overlay handles scripts/ but the Dockerfile does not copy it', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag'))])

    def assert_nothing_started(self):
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag', 'docker compose'))], self.calls())
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_every_other_copy_or_add_of_the_final_stage_refuses_instead_of_being_ignored(self):
        # #2112 review: only `COPY <dir>/ ./<dir>/` was recognised, so these were silently left out of the overlay.
        variants = ['COPY --chown=1000:1000 prompts/ ./prompts/', 'COPY gate ./gate', 'COPY web-assets/ ./web-assets/', 'ADD tools/ ./tools/',
                    'COPY entry.sh ./', 'copy extra/ ./extra/', 'COPY ["extra/", "./extra/"]', 'COPY --from=other /x /y', 'COPY extra/ ./other/',
                    'COPY extra/ \\\n  ./extra/', 'COPY /abs/ ./abs/', 'ADD agent/ ./agent/']
        for line in variants:
            with self.subTest(line=line):
                self.dockerfile(DIARY_DOCKERFILE + line + '\n')
                result = self.overlay()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('does not know how to ship', result.stderr)
                self.assert_nothing_started()
                self.log.unlink(missing_ok=True)

    def test_copy_lines_of_the_first_stage_are_not_the_images(self):
        self.dockerfile(DIARY_DOCKERFILE)   # its Rust stage has an ADD and a COPY of another directory
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_requirements_file_that_differs_from_the_running_images_refuses_before_anything_is_built(self):
        (self.release / 'requirements.txt').write_text('synthetic-dependency==2.0\n')
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requirements.txt', result.stderr)
        self.assert_nothing_started()

    def test_a_missing_requirements_file_refuses(self):
        (self.release / 'requirements.txt').unlink()
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requirements.txt', result.stderr)
        self.assert_nothing_started()
        (self.release / 'requirements.txt').write_text('synthetic-dependency==1.0\n')
        (self.running_app / 'requirements.txt').unlink()
        self.assertNotEqual(self.overlay().returncode, 0, 'one the running image cannot show is a refusal too')

    def test_the_overlay_ships_the_operator_entrypoint_as_an_executable_and_copies_it(self):
        # Before this, the overlay refused a release whose Dockerfile copies the entrypoint (an unknown shape).
        (self.release / 'entrypoint.sh').write_text('#!/bin/sh\nexec "$@"\n')
        self.dockerfile(DIARY_DOCKERFILE.replace('CMD [', 'COPY entrypoint.sh /usr/local/bin/diary-entrypoint\nCMD ['))
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('entrypoint.sh', self.context_files())
        self.assertEqual(pathlib.Path(f'{self.log}.entrypoint_mode').read_text().strip(), '755')
        self.assertTrue(self.dockerfile_text().rstrip().endswith('COPY entrypoint.sh /usr/local/bin/diary-entrypoint'), self.dockerfile_text())
        self.assertNotIn('ENTRYPOINT', self.dockerfile_text())   # inherited from the running image's base

    def test_an_overlay_whose_release_lacks_the_entrypoint_file_refuses_before_anything_is_built(self):
        self.dockerfile(DIARY_DOCKERFILE.replace('CMD [', 'COPY entrypoint.sh /usr/local/bin/diary-entrypoint\nCMD ['))
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('entrypoint.sh', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker compose'))], self.calls())
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_a_missing_release_dockerfile_refuses(self):
        (self.release / 'Dockerfile').unlink()
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('to check the overlay directories against', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag'))])

    def dockerfile_text(self):
        return pathlib.Path(f'{self.log}.dockerfile').read_text()

    def context_files(self):
        """The files of the last docker build context, as the build stub listed them."""
        return pathlib.Path(f'{self.log}.context').read_text().splitlines()

    def test_a_failed_archive_restarts_diary_on_the_old_image_and_leaves_the_env_alone(self):
        result = self.overlay(env={'INJECT_GZIP_FAILURE': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('restarting cowork-diary-1', result.stderr)
        calls = self.calls()
        self.assert_only_diary_is_disturbed(calls)
        stop = calls.index('docker stop --time 30 cowork-diary-1')
        ups = [i for i, c in enumerate(calls) if c.startswith('docker compose') and ' up ' in c]
        self.assertEqual(len(ups), 1, calls)
        self.assertGreater(ups[0], stop)
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())
        self.assertFalse([c for c in calls if c.startswith('docker tag') and c.endswith(f'cowork-diary:{self.NEW}')])

    def test_a_missing_backup_root_fails_before_anything_is_built_or_stopped(self):
        result = self.overlay(backups=self.temp / 'absent')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('backup root', result.stderr)
        self.assertIn('not deploying', result.stderr)
        calls = self.calls()
        self.assert_only_diary_is_disturbed(calls)
        self.assertFalse([c for c in calls if c.startswith(('docker stop', 'docker build', 'docker compose'))], calls)
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_a_partial_preflight_install_refuses_before_anything_is_built_stopped_or_tagged(self):
        # #1597: only up.sh refreshed by hand. up.sh would exit 2 after Diary was stopped, and the
        # rollback up.sh would exit 2 again; the overlay must refuse up front instead.
        for missing in ['diary-image-guard.sh', 'check.php', 'up.sh', 'diary-models-check.sh']:
            with self.subTest(missing=missing):
                self.log.unlink(missing_ok=True)
                installed = self.base / 'tools/preflight'
                backup = installed / missing
                saved = backup.read_bytes()
                backup.unlink()
                try:
                    result = self.overlay()
                finally:
                    backup.write_bytes(saved)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(missing, result.stderr)
                self.assertIn('not deploying', result.stderr)
                self.assertEqual(self.calls(), [], 'nothing, not even a docker inspect, ran before the refusal')
                self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_a_refusing_model_check_stops_the_overlay_before_anything_is_built_stopped_or_tagged(self):
        # #2105: the .env names models the router does not serve; nothing may run, not even a docker inspect.
        self.log.unlink(missing_ok=True)
        result = self.overlay(env={'FAIL_MODELS_CHECK': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('REFUSED stub', result.stderr)
        self.assertIn('not deploying', result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(list(self.backups.iterdir()), [])
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())
        self.assertEqual((self.log.parent / (self.log.name + '.modelcheck')).read_text().strip(), f'--env-file {self.config}')

    def test_a_passing_model_check_is_given_the_env_file_this_overlay_deploys(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.log.parent / (self.log.name + '.modelcheck')).read_text().strip(), f'--env-file {self.config}')

    def test_only_up_sh_staged_refuses_before_docker_stop(self):
        for name in ['diary-image-guard.sh', 'check.php', 'web-env-keys.txt']:
            (self.base / 'tools/preflight' / name).unlink()
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('diary-image-guard.sh is missing', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker stop', 'docker build', 'docker tag', 'docker compose'))])

    def test_the_installer_refuses_a_partial_source_and_verifies_a_full_one(self):
        src = self.temp / 'src'
        src.mkdir()
        for name in ['up.sh', 'diary-image-guard.sh', 'diary-models-check.sh']:
            shutil.copy(ROOT / 'deploy/preflight' / name, src / name)
        shutil.copy(ROOT / 'deploy/preflight/install.sh', src / 'install.sh')
        dest = self.temp / 'dest'
        partial = subprocess.run(['bash', str(src / 'install.sh'), str(dest)], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(partial.returncode, 0)
        self.assertIn('check.php is missing', partial.stderr)
        self.assertFalse(dest.exists(), 'nothing is installed from a partial source')
        (src / 'diary-models-check.sh').unlink()
        shutil.copy(ROOT / 'deploy/preflight/check.php', src / 'check.php')
        no_models_check = subprocess.run(['bash', str(src / 'install.sh'), str(dest)], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(no_models_check.returncode, 0)
        self.assertIn('diary-models-check.sh is missing', no_models_check.stderr)
        self.assertFalse(dest.exists(), 'nothing is installed without the diary model check (#2105)')
        shutil.copy(ROOT / 'deploy/preflight/diary-models-check.sh', src / 'diary-models-check.sh')
        full = subprocess.run(['bash', str(src / 'install.sh'), str(dest)], capture_output=True, text=True, timeout=30)
        self.assertEqual(full.returncode, 0, full.stderr)
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ['check.php', 'diary-image-guard.sh', 'diary-models-check.sh', 'up.sh'])

    def test_a_failed_rollback_up_still_starts_the_unchanged_diary_container(self):
        # The recreate fails and so does the rollback's up.sh; Diary must not be left stopped.
        result = self.overlay(env={'FAIL_UP': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ROLLING BACK', result.stdout)
        calls = self.calls()
        self.assert_only_diary_is_disturbed(calls)
        self.assertIn('docker start cowork-diary-1', calls)
        self.assertGreater(calls.index('docker start cowork-diary-1'), calls.index('docker stop --time 30 cowork-diary-1'))
        self.assertIn(f'DIARY_VERSION={self.OLD}', self.config.read_text())

    def test_a_failed_up_after_an_interrupted_archive_still_starts_diary(self):
        result = self.overlay(env={'INJECT_GZIP_FAILURE': '1', 'FAIL_UP': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('docker start cowork-diary-1', self.calls())
        self.assertNotIn('did not restart', result.stderr)

    def test_a_recreated_container_on_the_new_image_is_not_started_by_the_fallback(self):
        result = self.overlay(env={'FAIL_UP': '1', 'LATER_IMAGE': 'sha256:' + 'b' * 64})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('docker start cowork-diary-1', self.calls())
        self.assertIn('start it by hand', result.stderr)

    def test_the_script_text_has_no_plugin_call_and_no_stack_wide_command(self):
        text = DIARY.read_text()
        self.assertNotIn('backup.php', text)
        self.assertNotIn('appdata.backup', text)
        for line in text.splitlines():
            if line.lstrip().startswith('#'):
                continue
            if re.search(r'\bdocker (stop|restart|kill|rm|down|pause)\b', line) or re.search(r'\bcompose\b.*\b(down|stop|restart|kill|rm)\b', line):
                self.assertIn('cowork-diary-1', line, line)


class InstalledPreflightBlock(unittest.TestCase):
    """#1597: both overlay scripts check the installed preflight directory before they change anything."""

    def run_block(self, script, present):
        lines = script.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('# BEGIN preflight-installed'))
        end = next(i for i, l in enumerate(lines) if l.startswith('# END preflight-installed'))
        temp = pathlib.Path(tempfile.mkdtemp(prefix='noevia-preflight-block-'))
        self.addCleanup(shutil.rmtree, temp, ignore_errors=True)
        (temp / 'tools/preflight').mkdir(parents=True)
        for name in present:
            (temp / 'tools/preflight' / name).write_text('x\n')
        body = 'set -euo pipefail\nbase=$1\n' + '\n'.join(lines[start + 1:end]) + '\necho BLOCK_PASSED'
        return subprocess.run(['bash', '-c', body, 'x', str(temp)], capture_output=True, text=True, timeout=30)

    def test_each_script_needs_up_sh_the_guard_check_php_and_the_model_check(self):
        for script in (DIARY, OVERLAY):
            for present in (['up.sh'], ['up.sh', 'diary-image-guard.sh'], ['up.sh', 'check.php'], [],
                            ['up.sh', 'diary-image-guard.sh', 'check.php']):
                with self.subTest(script=script.name, present=present):
                    result = self.run_block(script, present)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('BLOCK_PASSED', result.stdout)
                    self.assertIn('not deploying', result.stderr)
            with self.subTest(script=script.name, present='all'):
                result = self.run_block(script, ['up.sh', 'diary-image-guard.sh', 'check.php', 'diary-models-check.sh'])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('BLOCK_PASSED', result.stdout)

    def test_the_check_runs_before_anything_changes(self):
        overlay = OVERLAY.read_text()
        self.assertLess(overlay.index('# BEGIN preflight-installed'), overlay.index('docker image inspect'))
        diary = DIARY.read_text()
        self.assertLess(diary.index('# BEGIN preflight-installed'), diary.index('docker image inspect'))


class RsStage(unittest.TestCase):
    """Run the `rs-stage` block of diary-overlay.sh against synthetic release Dockerfiles."""

    REF = 'a' * 40
    SUM = 'b' * 64

    def block(self, name='rs-stage'):
        lines = DIARY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith(f'# BEGIN {name}'))
        end = next(i for i, l in enumerate(lines) if l.startswith(f'# END {name}'))
        return '\n'.join(lines[start + 1:end])

    def stage(self, dockerfile, smoke=False):
        with tempfile.TemporaryDirectory(prefix='noevia-rs-stage-') as directory:
            temp = pathlib.Path(directory)
            (temp / 'releases/abc1234/services/diary').mkdir(parents=True)
            if dockerfile is not None:
                (temp / 'releases/abc1234/services/diary/Dockerfile').write_text(dockerfile)
            if smoke:
                (temp / 'releases/abc1234/services/diary/scripts').mkdir()
                (temp / 'releases/abc1234/services/diary/scripts/smoke_diary_leaves.py').write_text('# synthetic\n')
            (temp / 'ctx').mkdir()
            script = ('set -euo pipefail\nbase=$1; V=abc1234; ctx=$1/ctx\n' + self.block('overlay-dirs') + '\n'
                      + self.block('rust-leaves') + '\n' + self.block() + '\necho "STAGE $rs_stage LEAVES $rs_leaves"')
            result = subprocess.run(['bash', '-c', script, 'x', str(temp)], capture_output=True, text=True, timeout=30)
            out = (temp / 'ctx/Dockerfile').read_text() if (temp / 'ctx/Dockerfile').exists() else None
            return result, out

    def test_a_pinned_release_builds_the_binary_from_exactly_that_pin(self):
        result, df = self.stage(f'FROM rust AS x\nARG NOEVIA_RS_REF={self.REF}\nARG NOEVIA_RS_SHA256={self.SUM}\nRUN pip install evil\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('STAGE 1', result.stdout)
        self.assertIn(f'tar.gz/{self.REF} ', df)
        self.assertIn(f'echo "{self.SUM}  /tmp/noevia-rs.tar.gz" | sha256sum -c - \\\n', df)
        self.assertIn('cargo build --release --locked -p tenant-assertion-cli', df)
        # The builder image is pinned by registry digest, not a movable tag (#1145).
        self.assertRegex(df, r'(?m)^FROM rust:1\.99-slim-bookworm@sha256:[0-9a-f]{64} AS tenant-assertion$')
        self.assertNotRegex(df, r'(?m)^FROM rust:[^@\n]* AS')
        self.assertIn('COPY --from=tenant-assertion /out/ /usr/local/bin/', df)
        # P3-2: two cargo jobs on DaServer, and no build tree or registry left in the builder layer.
        self.assertIn('ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never CARGO_BUILD_JOBS=2\n', df)
        self.assertTrue(self.rust_run(df).rstrip().endswith('&& rm -rf /src/target /usr/local/cargo/registry'), df)
        # noevia#982: workspace-restore-verify is built and self-tested only when the pinned
        # noevia-rs has the crate, so an older release still overlays.
        self.assertIn('if [ -d bins/workspace-restore-verify ]; then', df)
        self.assertIn('cargo build --release --locked -p workspace-restore-verify-cli', df)
        self.assertIn('./target/release/workspace-restore-verify self-test | grep -qx ok', df)
        # agent/ is replaced whole, so files the release dropped do not survive (#1624); config/ and scripts/ are not touched.
        self.assertTrue(df.rstrip().endswith(OVERLAY_TAIL.rstrip()), df)
        # Only the pins are taken from the release's Dockerfile; never its text, and no pip.
        self.assertNotIn('pip', df)
        self.assertEqual(df.count('FROM cowork-diary:rollback-before-diary-overlay'), 1)

    PINNED = f'ARG NOEVIA_RS_REF={REF}\nARG NOEVIA_RS_SHA256={SUM}\n'
    # noevia#1071 P0: (source directory, cargo package, installed binary) for every leaf a Python adapter calls.
    LEAVES = [('crates/diary-backup-run', 'diary-backup-run', 'diary-backup-run'),
              ('crates/diary-entity-focus', 'diary-entity-focus', 'diary-entity-focus'),
              ('crates/diary-index-transform', 'diary-index-transform', 'diary-index-transform'),
              ('crates/diary-storage-backoff', 'diary-storage-backoff', 'diary-storage-backoff'),
              ('crates/diary-workspace-rules', 'diary-workspace-rules', 'diary-workspace-rules'),
              ('crates/diary-backup-format', 'diary-backup-format', 'diary-backup-format'),
              ('bins/diary-corpus-write', 'diary-corpus-write-cli', 'diary-corpus-write-cli'),
              ('crates/diary-corpus-parse', 'diary-corpus-parse', 'diary-corpus-parse'),
              ('crates/diary-score-gap', 'diary-score-gap', 'diary-score-gap'),
              ('crates/diary-temporal-focus', 'diary-temporal-focus', 'diary-temporal-cli'),
              ('crates/diary-workspace-export', 'diary-workspace-export', 'diary-workspace-export'),
              ('crates/diary-workspace-import-apply', 'diary-workspace-import-apply', 'diary-workspace-import-apply'),
              # D4-D5: the Rust Diary server process (Python starts it only when DIARY_RUST_ROUTES/WRITES is set).
              ('bins/noevia-diary', 'noevia-diary', 'noevia-diary')]

    @staticmethod
    def rust_run(df):
        """The Rust stage's single RUN instruction, continuation lines joined as Docker joins them."""
        stage = df.split('\nFROM cowork-diary:rollback-before-diary-overlay\n')[0]
        run = stage[stage.index('\nRUN ') + 5:]
        return run.replace('\\\n', ' ')

    def test_a_release_with_the_leaf_smoke_builds_every_declared_leaf_into_the_bundle(self):
        result, df = self.stage(self.PINNED, smoke=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('STAGE 1 LEAVES 1', result.stdout)
        run = self.rust_run(df)
        for directory, package, binary in self.LEAVES:
            with self.subTest(binary=binary):
                # Guarded like workspace-restore-verify: a pin without the crate still overlays.
                self.assertIn(f'&& if [ -d {directory} ]; then cargo build --release --locked -p {package}'
                              f' && cp target/release/{binary} /out/; fi', run)
        # One RUN instruction, valid shell, ending with the last leaf; only the /out/ bundle reaches the image.
        last = self.LEAVES[-1]
        self.assertTrue(' '.join(run.split()).endswith(f'cp target/release/{last[2]} /out/; fi && rm -rf /src/target /usr/local/cargo/registry'),
                        run[-200:])
        checked = subprocess.run(['sh', '-n', '-c', run], capture_output=True, text=True, timeout=30)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertEqual([l for l in df.splitlines() if l.startswith('COPY --from=')],
                         ['COPY --from=tenant-assertion /out/ /usr/local/bin/'])
        self.assertEqual(df.count('\nRUN '), 3, df)  # the Rust stage RUN, the stale-binary rm and the overlay's rm -rf
        self.assertTrue(df.rstrip().endswith(OVERLAY_TAIL.rstrip()), df)
        self.assertNotIn('pip', df)

    def test_a_release_without_the_leaf_smoke_builds_only_the_two_self_tested_binaries(self):
        result, df = self.stage(self.PINNED)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('STAGE 1 LEAVES 0', result.stdout)
        for _, package, binary in self.LEAVES:
            self.assertNotIn(binary, self.rust_run(df))  # none is built (the stale-binary removal still names them)
        self.assertTrue(' '.join(self.rust_run(df).split()).endswith(
            'cp target/release/workspace-restore-verify /out/; fi && rm -rf /src/target /usr/local/cargo/registry'))

    def stale_line(self, df):
        lines = [l for l in df.splitlines() if l.startswith('RUN cd /usr/local/bin && rm -f --')]
        self.assertEqual(len(lines), 1, df)
        return lines[0]

    def test_inherited_native_binaries_are_removed_before_the_pinned_bundle_is_installed(self):
        for smoke in (True, False):
            with self.subTest(smoke=smoke):
                result, df = self.stage(self.PINNED, smoke=smoke)
                self.assertEqual(result.returncode, 0, result.stderr)
                line = self.stale_line(df)
                lines = df.splitlines()
                self.assertEqual(lines[lines.index('FROM cowork-diary:rollback-before-diary-overlay') + 1], line)
                self.assertLess(df.index(line), df.index('COPY --from=tenant-assertion /out/ /usr/local/bin/'))
                # Every binary this overlay can install, so none is left from an earlier release.
                self.assertEqual(set(line.split(' -- ')[1].split()),
                                 {'tenant-assertion', 'workspace-restore-verify'} | {b for _, _, b in self.LEAVES})

    def test_a_leaf_built_from_an_older_pin_is_never_left_behind(self):
        # Run the generated removal against a /usr/local/bin that holds every native binary of the running image,
        # then install a bundle from a pin that predates most crates (only tenant-assertion): the old
        # noevia-diary, exporter and leaves must be gone, so native-required cannot be satisfied by them.
        result, df = self.stage(self.PINNED, smoke=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        line = self.stale_line(df)
        names = [b for _, _, b in self.LEAVES] + ['tenant-assertion', 'workspace-restore-verify']
        with tempfile.TemporaryDirectory(prefix='noevia-stale-bins-') as directory:
            root = pathlib.Path(directory)
            (root / 'bin').mkdir()
            (root / 'out').mkdir()
            for name in names + ['python3-keep']:
                (root / 'bin' / name).write_text('#!/bin/sh\n# from the running image\n')
            (root / 'out' / 'tenant-assertion').write_text('#!/bin/sh\n# from the selected pin\n')
            removal = line[len('RUN '):].replace('/usr/local/bin', str(root / 'bin'))
            done = subprocess.run(['sh', '-c', removal], capture_output=True, text=True, timeout=30)
            self.assertEqual(done.returncode, 0, done.stderr)
            for entry in (root / 'out').iterdir():  # COPY --from=tenant-assertion /out/ /usr/local/bin/
                (root / 'bin' / entry.name).write_text(entry.read_text())
            left = sorted(p.name for p in (root / 'bin').iterdir())
            self.assertEqual(left, ['python3-keep', 'tenant-assertion'])
            self.assertIn('selected pin', (root / 'bin' / 'tenant-assertion').read_text())

    def test_an_unpinned_release_removes_nothing(self):
        result, df = self.stage('FROM python:3.12-slim\n', smoke=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('rm -f --', df)

    def test_the_declared_leaves_are_exactly_the_adapters_binaries(self):
        script = self.block('rust-leaves') + '\nfor spec in $rust_leaves; do echo "$spec"; done'
        result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [':'.join(leaf) for leaf in self.LEAVES])

    def test_an_unpinned_release_overlays_only_the_directories_copied_into_app(self):
        for dockerfile in ('FROM python:3.12-slim\nCOPY agent/ ./agent/\n', None):
            with self.subTest(dockerfile=dockerfile):
                result, df = self.stage(dockerfile, smoke=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('STAGE 0', result.stdout)
                self.assertEqual(df, 'FROM cowork-diary:rollback-before-diary-overlay\n' + OVERLAY_TAIL)

    def test_a_malformed_pin_stops_before_any_build(self):
        for ref, digest in [('a' * 39, self.SUM), (self.REF, 'B' * 64), (self.REF + ';id', self.SUM), (self.REF, ''),
                            ('', self.SUM), ('$(id)' + 'a' * 35, self.SUM)]:
            with self.subTest(ref=ref, digest=digest):
                result, df = self.stage(f'ARG NOEVIA_RS_REF={ref}\nARG NOEVIA_RS_SHA256={digest}\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('not a 40-hex ref', result.stderr)
                self.assertIsNone(df)


class DiaryLeafSmoke(unittest.TestCase):
    """noevia#1071 P0: run the `leaf-smoke` block of diary-overlay.sh with a recording docker stub."""

    ALL = [binary for _, _, binary in RsStage.LEAVES]
    DOCKER = r"""#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
case "$*" in
  "run --rm --network none --entrypoint sh cowork-diary:abc1234-candidate -c"*)
    [ -z "${LIST_FAIL:-}" ] || exit 1
    printf '%s\n' $LEAVES_PRESENT ;;
  "run --rm --network none -v "*":/app/scripts/smoke_diary_leaves.py:ro --entrypoint python cowork-diary:abc1234-candidate scripts/smoke_diary_leaves.py"*)
    [ -z "${SMOKE_FAIL:-}" ] || { echo "diary-score-gap: FAILED" >&2; exit 1; } ;;
  *) echo "unexpected docker call: $*" >&2; exit 99 ;;
esac
"""

    def run_block(self, present, rs_stage=1, rs_leaves=1, **env):
        with tempfile.TemporaryDirectory(prefix='noevia-leaf-smoke-') as directory:
            temp = pathlib.Path(directory)
            (temp / 'docker').write_text(self.DOCKER)
            (temp / 'docker').chmod(0o755)
            log = temp / 'calls.log'
            blocks = RsStage()
            script = (f'set -euo pipefail\nbase=/synthetic-appdata; V=abc1234; rs_stage={rs_stage}; rs_leaves={rs_leaves}\n'
                      + blocks.block('overlay-dirs') + '\n' + blocks.block('rust-leaves') + '\n' + blocks.block('leaf-smoke') + '\necho SMOKED')
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, timeout=30,
                                    env=dict(os.environ, PATH=f'{temp}:{os.environ["PATH"]}', CALL_LOG=str(log),
                                             LEAVES_PRESENT=' '.join(present), **env))
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls

    def test_every_leaf_the_candidate_has_is_smoked_through_the_release_script(self):
        result, calls = self.run_block(self.ALL)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SMOKED', result.stdout)
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(calls[0].startswith('run --rm --network none --entrypoint sh cowork-diary:abc1234-candidate -c'))
        for binary in self.ALL:
            self.assertIn(binary, calls[0])
        # The release's own smoke file is bind-mounted read-only at its place in /app/scripts for this container only.
        self.assertEqual(calls[1], 'run --rm --network none -v /synthetic-appdata/releases/abc1234/services/diary/scripts/'
                         'smoke_diary_leaves.py:/app/scripts/smoke_diary_leaves.py:ro --entrypoint python '
                         'cowork-diary:abc1234-candidate scripts/smoke_diary_leaves.py ' + ' '.join(self.ALL))

    def test_the_smoke_asset_is_mounted_read_only_never_copied_into_the_image(self):
        text = DIARY.read_text()
        self.assertEqual(re.findall(r'-v "[^"]*:/app/\$leaf_smoke:ro"', text), ['-v "$base/releases/$V/services/diary/$leaf_smoke:/app/$leaf_smoke:ro"'])
        self.assertNotRegex(text, r'(?m)^\s*cp .*\$leaf_smoke')
        # The generated Dockerfile copies only overlay_dirs (agent): no COPY line is written for any other directory.
        self.assertEqual(text.count("printf 'COPY %s/ ./%s/\\n' \"$d\" \"$d\""), 1)

    def test_only_the_leaves_present_are_smoked(self):
        result, calls = self.run_block(['diary-score-gap', 'diary-temporal-cli'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(calls[1].endswith('scripts/smoke_diary_leaves.py diary-score-gap diary-temporal-cli'), calls)

    def test_a_candidate_without_leaves_is_reported_and_not_smoked(self):
        result, calls = self.run_block([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1, calls)
        self.assertIn('selectors must stay python', result.stdout)

    def test_a_failing_leaf_stops_the_overlay(self):
        result, _ = self.run_block(self.ALL, SMOKE_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('SMOKED', result.stdout)
        self.assertIn('leaf smoke failed; not deploying', result.stderr)

    def test_an_unlistable_candidate_or_an_unknown_name_stops_the_overlay(self):
        for present, env in (([], {'LIST_FAIL': '1'}), (['diary-score-gap', 'evil;id'], {})):
            with self.subTest(present=present):
                result, calls = self.run_block(present, **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('SMOKED', result.stdout)
                self.assertEqual(len(calls), 1, calls)

    def test_nothing_runs_without_a_rust_stage_or_a_release_smoke(self):
        for rs_stage, rs_leaves in ((0, 1), (1, 0), (0, 0)):
            with self.subTest(rs_stage=rs_stage, rs_leaves=rs_leaves):
                result, calls = self.run_block(self.ALL, rs_stage=rs_stage, rs_leaves=rs_leaves)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls, [])

    def test_the_smoke_runs_after_the_candidate_matches_the_release_and_before_anything_is_stopped(self):
        text = DIARY.read_text()
        self.assertLess(text.index('# END dirs-exact'), text.index('# BEGIN leaf-smoke'))
        self.assertLess(text.index('# END leaf-smoke'), text.index('docker stop'))


class DiaryNativeRequired(unittest.TestCase):
    """D4-D5: run the `native-required` block of diary-overlay.sh with a recording docker stub."""

    NATIVE = ['noevia-diary', 'tenant-assertion', 'diary-workspace-export']
    DOCKER = r"""#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
case "$*" in
  "run --rm --network none --entrypoint sh cowork-diary:abc1234-candidate -c"*)
    [ -z "${CHECK_FAIL:-}" ] || exit 1
    printf '%s\n' $MISSING ;;
  *) echo "unexpected docker call: $*" >&2; exit 99 ;;
esac
"""

    def run_block(self, forwarder=True, rs_stage=1, rs_leaves=1, missing=(), **env):
        with tempfile.TemporaryDirectory(prefix='noevia-native-required-') as directory:
            temp = pathlib.Path(directory)
            (temp / 'docker').write_text(self.DOCKER)
            (temp / 'docker').chmod(0o755)
            agent = temp / 'releases/abc1234/services/diary/agent'
            agent.mkdir(parents=True)
            if forwarder:
                (agent / 'rust_forward.py').write_text('# synthetic\n')
            log = temp / 'calls.log'
            blocks = RsStage()
            script = (f'set -euo pipefail\nbase=$1; V=abc1234; rs_stage={rs_stage}; rs_leaves={rs_leaves}\n'
                      + blocks.block('rust-leaves') + '\n' + blocks.block('native-required') + '\necho CHECKED')
            result = subprocess.run(['bash', '-c', script, 'x', str(temp)], capture_output=True, text=True, timeout=30,
                                    env=dict(os.environ, PATH=f'{temp}:{os.environ["PATH"]}', CALL_LOG=str(log),
                                             MISSING=' '.join(missing), **env))
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls

    def test_a_candidate_with_the_three_executables_passes_and_they_are_checked_at_the_fixed_paths(self):
        result, calls = self.run_block()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CHECKED', result.stdout)
        self.assertIn('candidate native Diary binaries present: ' + ' '.join(self.NATIVE), result.stdout)
        self.assertEqual(len(calls), 1, calls)
        self.assertIn('for b in ' + ' '.join(self.NATIVE) + ';', calls[0])
        self.assertIn('/usr/local/bin/$b', calls[0])
        self.assertIn('-f', calls[0])
        self.assertIn('-x', calls[0])

    def test_each_missing_binary_stops_the_overlay_naming_it(self):
        for name in self.NATIVE:
            with self.subTest(name=name):
                result, _ = self.run_block(missing=[name])
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('CHECKED', result.stdout)
                self.assertIn(name, result.stderr)
                self.assertIn('not deploying', result.stderr)

    def test_all_three_missing_are_all_named(self):
        result, _ = self.run_block(missing=self.NATIVE)
        self.assertNotEqual(result.returncode, 0)
        for name in self.NATIVE:
            self.assertIn(name, result.stderr)

    def test_an_unreadable_candidate_stops_the_overlay(self):
        result, _ = self.run_block(CHECK_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('could not check the native Diary binaries', result.stderr)

    def test_a_release_with_the_forwarder_but_no_rust_stage_or_no_leaf_smoke_stops_without_asking_docker(self):
        for rs_stage, rs_leaves in ((0, 1), (1, 0), (0, 0)):
            with self.subTest(rs_stage=rs_stage, rs_leaves=rs_leaves):
                result, calls = self.run_block(rs_stage=rs_stage, rs_leaves=rs_leaves)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('CHECKED', result.stdout)
                self.assertEqual(calls, [])
                self.assertIn('not deploying', result.stderr)

    def test_a_release_without_the_forwarder_is_not_checked(self):
        for rs_stage, rs_leaves in ((1, 1), (0, 0)):
            with self.subTest(rs_stage=rs_stage, rs_leaves=rs_leaves):
                result, calls = self.run_block(forwarder=False, rs_stage=rs_stage, rs_leaves=rs_leaves,
                                               missing=self.NATIVE)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('CHECKED', result.stdout)
                self.assertEqual(calls, [])

    def test_the_overlay_does_not_touch_the_native_switches(self):
        text = DIARY.read_text()
        for name in ('DIARY_RUST_ROUTES', 'DIARY_RUST_WRITES'):
            code = [l for l in text.splitlines() if name in l and not l.lstrip().startswith('#')]
            self.assertEqual(code, [], name)

    def test_the_check_runs_after_the_smoke_and_before_anything_is_stopped(self):
        text = DIARY.read_text()
        self.assertLess(text.index('# END leaf-smoke'), text.index('# BEGIN native-required'))
        self.assertLess(text.index('# END native-required'), text.index('docker stop'))

    def test_noevia_diary_is_built_into_the_bundle_like_the_other_leaves(self):
        self.assertIn(('bins/noevia-diary', 'noevia-diary', 'noevia-diary'), RsStage.LEAVES)
        result, df = RsStage().stage(RsStage.PINNED, smoke=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('&& if [ -d bins/noevia-diary ]; then cargo build --release --locked -p noevia-diary'
                      ' && cp target/release/noevia-diary /out/; fi', RsStage.rust_run(df))
        # A pin from before noevia-diary still builds (guarded by the directory), and a release without the smoke
        # builds no leaf at all.
        _, plain = RsStage().stage(RsStage.PINNED)
        self.assertNotIn('noevia-diary', RsStage.rust_run(plain))


class DiaryNativeProvenance(unittest.TestCase):
    """D4-D5: run the `native-provenance` block of diary-overlay.sh with a stub check script."""

    REF = 'c' * 40

    def run_block(self, forwarder=True, script=True, fail=False):
        with tempfile.TemporaryDirectory(prefix='noevia-native-provenance-') as directory:
            temp = pathlib.Path(directory)
            release = temp / 'releases/abc1234'
            (release / 'services/diary/agent').mkdir(parents=True)
            if forwarder:
                (release / 'services/diary/agent/rust_forward.py').write_text('# synthetic\n')
            tools = release / 'noevia/deploy/tools'
            tools.mkdir(parents=True)
            log = temp / 'calls.log'
            if script:
                (tools / 'check-diary-image-native.sh').write_text(
                    '#!/bin/bash\nprintf "%s|%s\\n" "$1" "$2" >> "$CALL_LOG"\n[ -z "${CHECK_FAIL:-}" ] || exit 1\n')
            blocks = RsStage()
            script_text = (f'set -euo pipefail\nbase=$1; V=abc1234; rs_ref={self.REF}\n'
                           + blocks.block('native-provenance') + '\necho CHECKED')
            result = subprocess.run(['bash', '-c', script_text, 'x', str(temp)], capture_output=True, text=True, timeout=30,
                                    env=dict(os.environ, CALL_LOG=str(log), **({'CHECK_FAIL': '1'} if fail else {})))
            return result, (log.read_text().splitlines() if log.exists() else [])

    def test_the_candidate_is_checked_against_the_pinned_ref(self):
        result, calls = self.run_block()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CHECKED', result.stdout)
        self.assertEqual(calls, [f'cowork-diary:abc1234-candidate|{self.REF}'])

    def test_a_failing_check_stops_the_overlay(self):
        result, calls = self.run_block(fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('CHECKED', result.stdout)
        self.assertIn('provenance check failed; not deploying', result.stderr)

    def test_a_release_without_the_check_script_stops_the_overlay(self):
        result, calls = self.run_block(script=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('check-diary-image-native.sh; not deploying', result.stderr)
        self.assertEqual(calls, [])

    def test_a_release_without_the_forwarder_is_not_checked(self):
        result, calls = self.run_block(forwarder=False, script=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])

    def test_the_check_runs_after_native_required_and_before_anything_is_stopped(self):
        text = DIARY.read_text()
        self.assertLess(text.index('# END native-required'), text.index('# BEGIN native-provenance'))
        self.assertLess(text.index('# END native-provenance'), text.index('docker stop'))

    def test_the_builder_stage_passes_the_pinned_ref_to_cargo_as_an_arg(self):
        result, df = RsStage().stage(RsStage.PINNED, smoke=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = df.splitlines()
        self.assertEqual(lines[lines.index(f'ARG NOEVIA_RS_REF={RsStage.REF}') + 1], 'WORKDIR /src')
        self.assertLess(df.index('ARG NOEVIA_RS_REF='), df.index('cargo build'))


class DiaryCopyContract(unittest.TestCase):
    """Run the final-stage check and the CI parser on the same synthetic instructions."""

    def check(self, dockerfile, preserved='config scripts'):
        with tempfile.TemporaryDirectory(prefix='noevia-copy-contract-') as temp:
            path = pathlib.Path(temp) / 'Dockerfile'
            path.write_text(dockerfile)
            block = RsStage().block('dockerfile-copy-check')
            script = ('set -euo pipefail\ndiary_df_check=$1; overlay_dirs="agent"; preserved_dirs="' + preserved + '"\n'
                      + block + '\nprintf "CHECKED\\n%s\\n" "$df_dirs"')
            return subprocess.run(['bash', '-c', script, 'x', str(path)],
                                  capture_output=True, text=True, timeout=30)

    def accepted(self, dockerfile):
        result = self.check(dockerfile)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['CHECKED', 'agent', 'config', 'scripts'])
        self.assertEqual(OverlayDirsInSync.dockerfile_dirs(dockerfile), {'agent', 'config', 'scripts'})

    def refused(self, instruction):
        # Keep the directory set valid: only the instruction under test can cause refusal.
        dockerfile = DIARY_DOCKERFILE + instruction + '\n'
        with self.subTest(parser='production', instruction=instruction):
            result = self.check(dockerfile)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(instruction.splitlines()[0], result.stderr)
        with self.subTest(parser='CI', instruction=instruction):
            with self.assertRaises(ValueError):
                OverlayDirsInSync.dockerfile_dirs(dockerfile)

    def test_requirements_copy_exception(self):
        self.accepted(DIARY_DOCKERFILE.replace('COPY --from=tenant-assertion /out/ /usr/local/bin/\n', ''))

    def test_requirements_with_constraints_copy_exception(self):
        # noevia#2523: the dependency list may come with the constraints file that pins its versions.
        self.accepted(DIARY_DOCKERFILE.replace('COPY requirements.txt .\n', 'COPY requirements.txt constraints.txt ./\n'))

    def test_constraints_copy_shape_is_exact(self):
        for instruction in ['COPY constraints.txt ./', 'COPY requirements.txt constraints.txt .',
                            'COPY constraints.txt requirements.txt ./', 'COPY requirements.txt constraints.txt other.txt ./',
                            'COPY requirements.txt constraints.txt /app/']:
            self.refused(instruction)

    def test_binary_copy_exception(self):
        self.accepted(DIARY_DOCKERFILE.replace('COPY requirements.txt .\n', ''))

    def test_directory_copies_and_whitespace(self):
        text = DIARY_DOCKERFILE.replace('COPY requirements.txt .\n', '').replace(
            'COPY --from=tenant-assertion /out/ /usr/local/bin/\n', '')
        self.accepted(text.replace('COPY ', ' \tCOPY ').replace('/\n', '/ \t\n'))

    def test_builder_copies_are_ignored_before_final_stage(self):
        self.accepted('FROM builder\nCOPY unknown /elsewhere\nADD other /other\n  fRoM runtime\n'
                      + DIARY_DOCKERFILE.split('FROM python:3.12-slim\n')[1])

    def test_binary_copy_stage_must_match(self):
        self.refused('COPY --from=other /out/ /usr/local/bin/')

    def test_binary_copy_source_must_match(self):
        self.refused('COPY --from=tenant-assertion /elsewhere/ /usr/local/bin/')

    def test_binary_copy_destination_must_match(self):
        self.refused('COPY --from=tenant-assertion /out/ /elsewhere/')

    def test_binary_copy_has_no_extra_operand(self):
        self.refused('COPY --from=tenant-assertion /out/ /extra/ /usr/local/bin/')

    def test_unknown_final_stage_copy_and_add_refuse(self):
        for instruction in ['COPY --chown=1000:1000 agent/ ./agent/', 'COPY agent ./agent',
                            'COPY web-assets/ ./web-assets/', 'ADD agent/ ./agent/',
                            'COPY entry.sh ./', 'copy agent/ ./agent/', 'COPY ["agent/", "./agent/"]',
                            'COPY agent/ ./config/', 'COPY /agent/ ./agent/', 'COPY', 'ADD',
                            'COPY requirements.txt ./', 'COPY agent/ \\\n  ./agent/']:
            self.refused(instruction)

    def test_operator_entrypoint_copy_is_an_accepted_shape(self):
        self.accepted(DIARY_DOCKERFILE.replace('CMD [', 'COPY entrypoint.sh /usr/local/bin/diary-entrypoint\nCMD ['))

    def test_operator_entrypoint_copy_is_exact(self):
        for instruction in ['COPY entrypoint.sh /usr/local/bin/other', 'COPY entrypoint.sh /usr/local/bin/diary-entrypoint2',
                            'COPY --chmod=755 entrypoint.sh /usr/local/bin/diary-entrypoint', 'COPY entrypoint.sh ./']:
            self.refused(instruction)

    def test_individual_release_binary_copies_pass_both_parsers(self):
        copies = '\n'.join(
            f'COPY --from=tenant-assertion /src/target/release/{name} /usr/local/bin/{name}'
            for name in ('tenant-assertion', 'workspace-restore-verify')) + '\n'
        self.accepted(DIARY_DOCKERFILE.replace(
            'COPY --from=tenant-assertion /out/ /usr/local/bin/\n', copies))

    @unittest.skipUnless(os.environ.get('NOEVIA_SERVICES_DIR'), 'set NOEVIA_SERVICES_DIR for actual release COPY controls')
    def test_actual_release_dockerfile_passes_both_parsers(self):
        text = (pathlib.Path(os.environ['NOEVIA_SERVICES_DIR']) / 'diary/Dockerfile').read_text()
        self.accepted(text)
        # Independently alter the real artifact, rather than replacing it with a
        # synthetic generated Dockerfile that teaches the same assumption twice. The release copies either the
        # /out/ bundle (noevia#1071 P0) or the two individual binaries; every binary copy it has is altered.
        originals = [line for line in (
            'COPY --from=tenant-assertion /out/ /usr/local/bin/',
            *(f'COPY --from=tenant-assertion /src/target/release/{name} /usr/local/bin/{name}'
              for name in ('tenant-assertion', 'workspace-restore-verify'))) if line in text]
        self.assertTrue(originals, 'the release Diary Dockerfile copies no Rust binary')
        for original in originals:
            altered = text.replace(original, original.replace('--from=tenant-assertion /', '--from=tenant-assertion /elsewhere/'))
            with self.subTest(binary=original):
                self.assertNotEqual(self.check(altered).returncode, 0)
                with self.assertRaises(ValueError):
                    OverlayDirsInSync.dockerfile_dirs(altered)

    def test_release_binary_stage_source_destination_and_operands_are_exact(self):
        for name in ('tenant-assertion', 'workspace-restore-verify'):
            source = f'/src/target/release/{name}'
            destination = f'/usr/local/bin/{name}'
            for instruction in (
                f'COPY --from=other {source} {destination}',
                f'COPY --from=tenant-assertion /elsewhere/{name} {destination}',
                f'COPY --from=tenant-assertion {source} /elsewhere/{name}',
                f'COPY --from=tenant-assertion {source} /usr/local/bin/',
                f'COPY --from=tenant-assertion {source} /extra {destination}',
                f'COPY --chown=1000:1000 --from=tenant-assertion {source} {destination}',
                f'COPY --from=tenant-assertion {source} {destination}-other',
            ):
                self.refused(instruction)

    def test_generated_binary_copy_spans_both_parsers(self):
        result, generated = RsStage().stage(
            f'ARG NOEVIA_RS_REF={RsStage.REF}\nARG NOEVIA_RS_SHA256={RsStage.SUM}\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        copies = [line for line in generated.splitlines() if line.startswith('COPY --from=')]
        self.assertEqual(copies, ['COPY --from=tenant-assertion /out/ /usr/local/bin/'])
        # The generated overlay copies only the replaced directory (agent/); both parsers accept it as that.
        checked = self.check(generated, preserved='')
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertEqual(checked.stdout.splitlines(), ['CHECKED', 'agent'])
        self.assertEqual(OverlayDirsInSync.dockerfile_dirs(generated), {'agent'})


class DiaryRequirementsProbe(unittest.TestCase):
    """Exercise the requirements check with a recording docker stub, without an engine."""

    REQUIREMENTS = b'synthetic-dependency==1.0\n'
    HASH = hashlib.sha256(REQUIREMENTS).hexdigest()

    def probe(self, output=None, status=0, missing=False):
        with tempfile.TemporaryDirectory(prefix='noevia-requirements-probe-') as temp:
            base = pathlib.Path(temp)
            release = base / 'releases/abc1234/services/diary'
            release.mkdir(parents=True)
            if not missing:
                (release / 'requirements.txt').write_bytes(self.REQUIREMENTS)
            docker = base / 'docker'
            docker.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                              'with open(os.environ["ARGV_LOG"], "w") as log: json.dump(sys.argv[1:], log)\n'
                              'print(os.environ["PROBE_OUTPUT"])\nsys.exit(int(os.environ["PROBE_STATUS"]))\n')
            docker.chmod(0o755)
            block = RsStage().block('requirements-check')
            script = 'set -euo pipefail\nbase=$1; V=abc1234; OLD=def5678\n' + block + '\necho PROBED'
            result = subprocess.run(['bash', '-c', script, 'x', str(base)],
                                    env=dict(os.environ, PATH=f'{base}:{os.environ["PATH"]}',
                                             ARGV_LOG=str(base / 'argv.json'),
                                             PROBE_OUTPUT=output if output is not None else self.HASH + '  /app/requirements.txt',
                                             PROBE_STATUS=str(status)),
                                    capture_output=True, text=True, timeout=30)
            return result, json.loads((base / 'argv.json').read_text())

    def successful_probe(self):
        result, argv = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['PROBED'])
        return argv

    def test_requirements_probe_is_read_only(self):
        self.assertIn('--read-only', self.successful_probe())

    def test_requirements_probe_never_pulls(self):
        argv = self.successful_probe()
        self.assertIn('--pull', argv)
        self.assertEqual(argv[argv.index('--pull') + 1], 'never')

    def test_requirements_probe_command_preserves_its_restrictions(self):
        self.assertEqual(self.successful_probe(), [
            'run', '--rm', '--network', 'none', '--read-only', '--pull', 'never',
            '--entrypoint', 'sh', 'cowork-diary:def5678', '-c', 'sha256sum /app/requirements.txt'])

    def test_requirements_probe_refuses_missing_mismatched_or_unreadable_hashes(self):
        self.successful_probe()
        for kwargs in [{'missing': True}, {'output': 'c' * 64 + '  /app/requirements.txt'},
                       {'output': ''}, {'output': 'not-a-hash'}, {'status': 1}]:
            with self.subTest(kwargs=kwargs):
                result, argv = self.probe(**kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PROBED', result.stdout)
                self.assertEqual(argv[-2:], ['-c', 'sha256sum /app/requirements.txt'])


class DiaryConstraintsProbe(unittest.TestCase):
    """noevia#2523: a release with constraints.txt needs the running image to carry the same file."""

    REQUIREMENTS = b'synthetic-dependency>=1\n'
    CONSTRAINTS = b'synthetic-dependency==1.0\n'

    def probe(self, image_constraints=CONSTRAINTS, release_constraints=CONSTRAINTS, dockerfile_copies=False):
        with tempfile.TemporaryDirectory(prefix='noevia-constraints-probe-') as temp:
            base = pathlib.Path(temp)
            release = base / 'releases/abc1234/services/diary'
            release.mkdir(parents=True)
            (release / 'requirements.txt').write_bytes(self.REQUIREMENTS)
            if release_constraints is not None:
                (release / 'constraints.txt').write_bytes(release_constraints)
            image = base / 'image'
            image.mkdir()
            (image / 'requirements.txt').write_bytes(self.REQUIREMENTS)
            if image_constraints is not None:
                (image / 'constraints.txt').write_bytes(image_constraints)
            docker = base / 'docker'
            docker.write_text('#!/usr/bin/env python3\nimport hashlib, json, os, pathlib, sys\n'
                              'with open(os.environ["ARGV_LOG"], "a") as log: log.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                              'name = sys.argv[-1].split("/app/", 1)[1]\n'
                              'path = pathlib.Path(os.environ["IMAGE_APP"]) / name\n'
                              'if not path.exists(): sys.exit(1)\n'
                              'print(hashlib.sha256(path.read_bytes()).hexdigest() + "  /app/" + name)\n')
            docker.chmod(0o755)
            block = RsStage().block('requirements-check')
            script = ('set -euo pipefail\nbase=$1; V=abc1234; OLD=def5678\n'
                      + ('df_constraints=1\n' if dockerfile_copies else '') + block + '\necho PROBED')
            result = subprocess.run(['bash', '-c', script, 'x', str(base)],
                                    env=dict(os.environ, PATH=f'{base}:{os.environ["PATH"]}',
                                             ARGV_LOG=str(base / 'argv.jsonl'), IMAGE_APP=str(image)),
                                    capture_output=True, text=True, timeout=30)
            argv = [json.loads(line) for line in (base / 'argv.jsonl').read_text().splitlines()]
            return result, argv

    def test_equal_constraints_pass_and_are_probed_read_only(self):
        result, argv = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['PROBED'])
        self.assertEqual(argv[-1], ['run', '--rm', '--network', 'none', '--read-only', '--pull', 'never',
                                    '--entrypoint', 'sh', 'cowork-diary:def5678', '-c', 'sha256sum /app/constraints.txt'])

    def test_a_release_without_constraints_probes_only_the_requirements(self):
        result, argv = self.probe(image_constraints=None, release_constraints=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([a[-1] for a in argv], ['sha256sum /app/requirements.txt'])

    def test_a_dockerfile_that_copies_constraints_needs_the_release_file(self):
        # The copy check saw COPY requirements.txt constraints.txt ./, but the release has no constraints.txt.
        result, _ = self.probe(release_constraints=None, dockerfile_copies=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PROBED', result.stdout)
        self.assertIn('constraints.txt', result.stderr)

    def test_different_or_missing_image_constraints_refuse(self):
        for image_constraints in (b'synthetic-dependency==2.0\n', None):
            with self.subTest(image_constraints=image_constraints):
                result, _ = self.probe(image_constraints=image_constraints)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PROBED', result.stdout)
                self.assertIn('constraints.txt', result.stderr)


def hx(value):
    """The inventory's field encoding: the bytes of a string (or bytes), lower-case hex, nothing else."""
    return (value if isinstance(value, bytes) else os.fsencode(value)).hex()


class DirectoryManifest(unittest.TestCase):
    """The inventory script itself, run by every POSIX shell available (the image's is dash, no pipefail)."""

    SHELLS = [sh for sh in ('sh', 'dash', 'bash') if shutil.which(sh)]

    def run_manifest(self, shell, directory, skip=''):
        script = RsStage().block('overlay-dirs') + '\nsh_bin=$1; shift; "$sh_bin" -c "$manifest_sh" sh "$@"'
        return subprocess.run(['bash', '-c', script, 'x', shell, str(directory), skip], capture_output=True, text=True, timeout=30)

    def tmp(self):
        temp = pathlib.Path(tempfile.mkdtemp(prefix='noevia-manifest-'))
        self.addCleanup(shutil.rmtree, temp, ignore_errors=True)
        return temp

    def make(self):
        root = self.tmp() / 'tree'
        (root / 'sub').mkdir(parents=True)
        (root / '__pycache__').mkdir()
        (root / '__pycache__/x.pyc').write_text('c')
        (root / 'a.txt').write_text('x\n')
        (root / 'sub/b.txt').write_text('y\n')
        (root / 'link').symlink_to('a.txt')
        (root / 'dlink').symlink_to('sub')
        (root / 'dangling').symlink_to('nowhere')
        (root / 'empty').mkdir()
        return root

    def manifest(self, root, skip='', shell='sh'):
        result = self.run_manifest(shell, root, skip)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], 'MANIFEST-COMPLETE')
        return result.stdout.splitlines()[:-1]

    def test_entries_have_types_and_links_are_listed_by_target_not_followed(self):
        root = self.make()
        sha = lambda text: hashlib.sha256(text.encode()).hexdigest()
        want = [f'D {hx("./empty")}', f'F {hx("./a.txt")} {sha("x" + chr(10))}', f'D {hx("./sub")}',
                f'F {hx("./sub/b.txt")} {sha("y" + chr(10))}', f'L {hx("./dangling")} {hx("nowhere")}',
                f'L {hx("./dlink")} {hx("sub")}', f'L {hx("./link")} {hx("a.txt")}']
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                lines = self.manifest(root, shell=shell)
                self.assertEqual(sorted(lines), sorted(want))
                self.assertTrue(all(re.fullmatch(r'[DFL]( [0-9a-f]+)+', line) for line in lines), lines)
                self.assertNotIn(hx('pycache'), ''.join(lines))

    def test_an_empty_directory_is_a_valid_empty_inventory(self):
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                empty = self.tmp()
                result = self.run_manifest(shell, empty)
                self.assertEqual((result.returncode, result.stdout), (0, 'MANIFEST-COMPLETE\n'), result.stderr)

    def test_the_skipped_name_is_left_out_only_as_a_regular_file(self):
        root = self.make()
        (root / 'smoke.py').write_text('s')
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                self.assertNotIn(hx('./smoke.py'), ' '.join(self.manifest(root, 'smoke.py', shell)))
        (root / 'smoke.py').unlink()
        (root / 'smoke.py').symlink_to('a.txt')
        for shell in self.SHELLS:
            with self.subTest(shell=shell, kind='link'):
                self.assertIn(f'L {hx("./smoke.py")} {hx("a.txt")}', self.manifest(root, 'smoke.py', shell))

    def link_tree(self, **links):
        root = self.tmp() / 'tree'
        root.mkdir()
        for name, target in links.items():
            os.symlink(target, root / name)
        return root

    def test_a_target_with_a_trailing_newline_is_not_the_target_without_it(self):
        # `$(readlink x)` drops trailing newlines; the inventory reads the target exactly (round-3 review P2-1).
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                plain = self.manifest(self.link_tree(link='target'), shell=shell)
                one = self.manifest(self.link_tree(link='target\n'), shell=shell)
                two = self.manifest(self.link_tree(link='target\n\n'), shell=shell)
                self.assertEqual(one, [f'L {hx("./link")} {hx("target" + chr(10))}'])
                self.assertEqual(two, [f'L {hx("./link")} {hx("target" + chr(10) * 2)}'])
                self.assertEqual(len({tuple(plain), tuple(one), tuple(two)}), 3)

    def test_separators_inside_names_and_targets_cannot_collide(self):
        # Round-3 P2-2: link `a -> b` to `c` and link `a` to `b -> c` printed the same line.
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                one = self.manifest(self.link_tree(**{'a -> b': 'c'}), shell=shell)
                two = self.manifest(self.link_tree(a='b -> c'), shell=shell)
                self.assertNotEqual(one, two)
                self.assertEqual(one, [f'L {hx("./a -> b")} {hx("c")}'])
                self.assertEqual(two, [f'L {hx("./a")} {hx("b -> c")}'])

    def test_awkward_but_legal_names_and_targets_are_recorded_byte_for_byte(self):
        names = {'sp ace': 't u', 'F deadbeef': 'L x y', 'x\\y': '\\', 'quote"\'s': '"', 'tab\tname': 'a\tb', 'ünï': 'ø', '-dash': '-t',
                 '.hidden': '.', 'star*?[x]': '*'}
        root = self.link_tree(**names)
        (root / 'f\\g').write_text('body')   # sha256sum prints a leading backslash for such names
        (root / '-opt').write_text('o')
        (root / 'D 2e2f78').write_text('fake record')
        raw = b'bytes-\xff\xfe'
        try:
            os.symlink(raw, os.fsencode(root) + b'/raw-\xff')
            raw_names = True
        except OSError:   # APFS refuses names that are not UTF-8; Linux (CI, DaServer) takes them
            raw_names = False
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                lines = self.manifest(root, shell=shell)
                for name, target in names.items():
                    self.assertIn(f'L {hx("./" + name)} {hx(target)}', lines)
                if raw_names:
                    self.assertIn(f'L {hx(b"./raw-" + bytes([255]))} {hx(raw)}', lines)
                sha = lambda t: hashlib.sha256(t.encode()).hexdigest()
                self.assertIn(f'F {hx("./f" + chr(92) + "g")} {sha("body")}', lines)
                self.assertIn(f'F {hx("./D 2e2f78")} {sha("fake record")}', lines)
                self.assertIn(f'F {hx("./-opt")} {sha("o")}', lines)
                self.assertTrue(all(re.fullmatch(r'[DFL]( [0-9a-f]+)+', line) for line in lines), lines)

    def test_excluded_caches_are_ignored_by_every_scan(self):
        # Round-3 P3-1: the newline scan walked __pycache__ although the inventory prunes it.
        root = self.make()
        (root / '__pycache__/ignored\nname.pyc').write_text('x')
        (root / 'sub/__pycache__').mkdir()
        (root / 'sub/__pycache__/also\nignored').write_text('x')
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                self.assertEqual(self.manifest(root, shell=shell), self.manifest(self.make(), shell=shell))

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root can read an unreadable directory')
    def test_an_unreadable_excluded_cache_is_not_traversed(self):
        root = self.make()
        locked = root / '__pycache__'
        locked.chmod(0)
        self.addCleanup(locked.chmod, 0o755)
        for shell in self.SHELLS:
            with self.subTest(shell=shell):
                self.assertEqual(self.manifest(root, shell=shell), self.manifest(self.make(), shell=shell))

    def test_every_failure_exits_non_zero_without_a_complete_manifest(self):
        root = self.make()
        os.mkfifo(root / 'pipe')
        newline = self.make().parent / 'tree'
        (newline / 'bad\nname').write_text('x')
        newline_dir = self.make().parent / 'tree'
        (newline_dir / 'd\ne').mkdir()
        for shell in self.SHELLS:
            for name, target in (('missing directory', root / 'absent'), ('fifo', root), ('newline name', newline),
                                 ('newline directory name', newline_dir)):
                with self.subTest(shell=shell, case=name):
                    result = self.run_manifest(shell, target)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('MANIFEST-COMPLETE', result.stdout)


class OverlayDirsInSync(unittest.TestCase):
    """#2112: the directory list of diary-overlay.sh, its documentation and the Diary Dockerfile stay one list."""

    def script_lists(self):
        text = DIARY.read_text()
        lists = []
        for name in ('overlay_dirs', 'preserved_dirs'):
            found = re.findall(rf'(?m)^{name}="([a-z_ ]+)"$', text)
            self.assertEqual(len(found), 1, (name, found))
            lists.append(set(found[0].split()))
        return lists

    def script_dirs(self):
        """Every directory the overlay accounts for: replaced and preserved."""
        replaced, preserved = self.script_lists()
        self.assertFalse(replaced & preserved)
        return replaced | preserved

    @staticmethod
    def dockerfile_dirs(text):
        final_stage = re.split(r'(?mi)^[ \t]*FROM[ \t].*$', text)[-1]   # the image is its last stage
        dirs = set()
        for line in final_stage.splitlines():
            line = line.strip()
            if not re.match(r'(?i)^(COPY|ADD)(\s|$)', line):
                continue
            if line in ('COPY requirements.txt .', 'COPY requirements.txt constraints.txt ./'):
                continue
            if line in (
                'COPY --from=tenant-assertion /out/ /usr/local/bin/',
                'COPY --from=tenant-assertion /src/target/release/tenant-assertion /usr/local/bin/tenant-assertion',
                'COPY --from=tenant-assertion /src/target/release/workspace-restore-verify /usr/local/bin/workspace-restore-verify',
                'COPY entrypoint.sh /usr/local/bin/diary-entrypoint',
            ):
                continue
            match = re.fullmatch(r'COPY ([a-z_][a-z0-9_]*)/ \./\1/', line)
            if not match:
                raise ValueError(f'unsupported final-stage COPY/ADD: {line}')
            dirs.add(match[1])
        return dirs

    def test_only_agent_is_replaced_and_config_and_scripts_are_preserved(self):
        self.assertEqual(self.script_lists(), [{'agent'}, {'config', 'scripts'}])
        self.assertEqual(self.script_dirs(), {'agent', 'config', 'scripts'})

    def test_the_fixture_dockerfile_copies_the_same_directories(self):
        self.assertEqual(self.dockerfile_dirs(DIARY_DOCKERFILE), self.script_dirs())

    def test_the_deployment_guide_lists_the_same_directories(self):
        docs = (ROOT / 'docs/deployment.md').read_text()
        replaced, preserved = self.script_lists()
        for label, expected in (('replaced', replaced), ('preserved', preserved)):
            line = re.search(rf'(?m)^Diary overlay directories {label}: (.+)$', docs)
            self.assertIsNotNone(line, f'docs/deployment.md has no "Diary overlay directories {label}:" line')
            self.assertEqual(set(re.findall(r'`([a-z_]+)/`', line.group(1))), expected)

    @unittest.skipUnless(os.environ.get('NOEVIA_SERVICES_DIR'), 'set NOEVIA_SERVICES_DIR to a noevia-services checkout')
    def test_the_overlay_leaves_match_the_services_leaf_smoke(self):
        # noevia#1071 P0: the overlay builds exactly the leaves the release's smoke knows how to check.
        smoke = pathlib.Path(os.environ['NOEVIA_SERVICES_DIR']) / 'diary/scripts/smoke_diary_leaves.py'
        if not smoke.is_file():
            self.skipTest('the pinned noevia-services predates the Diary leaf smoke')
        body = smoke.read_text().split('LEAVES = {', 1)[1].split('}', 1)[0]
        # The same set, whatever the order the smoke lists them in.
        self.assertEqual(sorted(re.findall(r"(?m)^    '([a-z-]+)':", body)), sorted(binary for _, _, binary in RsStage.LEAVES))

    @unittest.skipUnless(os.environ.get('NOEVIA_SERVICES_DIR'), 'set NOEVIA_SERVICES_DIR to a noevia-services checkout to compare with its real Dockerfile')
    def test_the_list_matches_the_services_diary_dockerfile(self):
        text = (pathlib.Path(os.environ['NOEVIA_SERVICES_DIR']) / 'diary/Dockerfile').read_text()
        self.assertEqual(self.dockerfile_dirs(text), self.script_dirs())


if __name__ == '__main__':
    unittest.main()
