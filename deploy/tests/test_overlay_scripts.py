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


# Shaped like the release's Diary Dockerfile: dependencies first, then the three directories that land in /app.
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
OVERLAY_TAIL = 'RUN rm -rf ./agent ./config ./scripts\nCOPY agent/ ./agent/\nCOPY config/ ./config/\nCOPY scripts/ ./scripts/\n'


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
printf 'docker %s\n' "$*" >> "$CALL_LOG"
case "$*" in
  "image inspect cowork-diary:@NEW@") exit 1 ;;
  "image inspect cowork-diary:@OLD@ --format {{.Id}}") echo "@OLD_ID@" ;;
  "inspect cowork-diary-1 --format {{.Image}}")
    if [ -n "${LATER_IMAGE:-}" ] && [ -e "$CALL_LOG.inspected" ]; then echo "$LATER_IMAGE"; else : > "$CALL_LOG.inspected"; echo "@OLD_ID@"; fi ;;
  "inspect cowork-diary-1 --format diary"*) echo "diary healthy restarts=0" ;;
  "exec cowork-diary-1 python -c"*) exit 1 ;;
  "run --rm "*"--entrypoint sh cowork-diary:@OLD@ -c"*)
    # The running image's /app/requirements.txt (#2112): the overlay installs no dependencies.
    [ -f "$RUNNING_APP/requirements.txt" ] && sha256sum "$RUNNING_APP/requirements.txt" ;;
  "run --rm --entrypoint python"*) echo "candidate imports ok" ;;
  "build -q -t cowork-diary:@NEW@-candidate "*)
    # Emulate the build of the generated overlay Dockerfile on top of the running image's /app (#2112): `RUN rm -rf`
    # removes, `COPY <dir>/ ./<dir>/` copies from the build context. Anything else is the running image's.
    ctx="${!#}"; cp "$ctx/Dockerfile" "$CALL_LOG.dockerfile"
    rm -rf "$CAND_APP"; cp -R "$RUNNING_APP" "$CAND_APP"
    while IFS= read -r line; do
      case "$line" in
        "RUN rm -rf "*) for t in ${line#RUN rm -rf }; do rm -rf "$CAND_APP/${t#./}"; done ;;
        "COPY --from"*) ;;
        "COPY "*) src="${line#COPY }"; src="${src%% *}"; mkdir -p "$CAND_APP/$src"; cp -R "$ctx/$src/." "$CAND_APP/$src/" ;;
      esac
    done < "$ctx/Dockerfile" ;;
  "run --rm --network none --entrypoint sh cowork-diary:@NEW@-candidate -c"*)
    # The candidate's /app/<dir> as the emulated build left it, plus a stale file when the test asks (#1624).
    all="$*"; dir="${all#*cd /app/}"; dir="${dir%% *}"
    [ "${MISSING_LISTING_DIR:-}" != "$dir" ] || exit 1
    (cd "$CAND_APP/$dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
    case "${STALE_FILE:-}" in "$dir/"*) echo "$(printf x | sha256sum | cut -d' ' -f1)  ./${STALE_FILE#$dir/}" ;; esac ;;
  "compose "*" config --format json") echo "{}" ;;
  "compose "*" up "*) [ -z "${FAIL_UP:-}" ] || exit 1 ;;
esac
exit 0
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
        # The release tree: what the Diary Dockerfile copies into /app (agent/, config/, scripts/).
        self.release = self.base / f'releases/{self.NEW}/services/diary'
        for rel, text in {'agent/app.py': 'x = 1\n', 'config/config.yaml': 'prompt: new\n',
                          'config/prompts/system.md': 'new system prompt\n', 'scripts/tool.py': 'y = 2\n'}.items():
            (self.release / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.release / rel).write_text(text)
        self.dockerfile(DIARY_DOCKERFILE)
        # The running image's /app: older agent code (with a file the release dropped), config and prompt.
        self.running_app = self.temp / 'running-app'
        self.cand_app = self.temp / 'candidate-app'
        (self.release / 'requirements.txt').write_text('synthetic-dependency==1.0\n')
        self.running_app.mkdir(parents=True, exist_ok=True)
        (self.running_app / 'requirements.txt').write_text('synthetic-dependency==1.0\n')
        for rel, text in {'agent/app.py': 'x = 0\n', 'agent/static/old.js': 'gone\n', 'config/config.yaml': 'prompt: old\n',
                          'config/prompts/system.md': 'old system prompt\n', 'scripts/tool.py': 'y = 2\n'}.items():
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
        self.assertIn('could not list /app/agent', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith('docker stop')])

    def test_the_candidate_listing_of_every_overlaid_directory_is_checked_and_reported(self):
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('candidate agent/ matches the release (1 files)', result.stdout)
        self.assertIn('candidate config/ matches the release (2 files)', result.stdout)
        self.assertIn('candidate scripts/ matches the release (1 files)', result.stdout)
        listing = [c for c in self.calls() if '--entrypoint sh cowork-diary:abc1234-candidate' in c]
        self.assertEqual(len(listing), 3, self.calls())
        for line, name in zip(listing, ('agent', 'config', 'scripts')):
            self.assertIn(f'cd /app/{name} ', line)

    def test_config_prompt_and_scripts_changes_ship_with_the_agent_code(self):
        # #2112: the release changed the system prompt and config.yaml; an agent-only overlay left the old ones in.
        result = self.overlay()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.dockerfile_text()), 'FROM cowork-diary:rollback-before-diary-overlay\n' + OVERLAY_TAIL)
        app = self.cand_app
        self.assertEqual((app / 'config/config.yaml').read_text(), 'prompt: new\n')
        self.assertEqual((app / 'config/prompts/system.md').read_text(), 'new system prompt\n')
        self.assertEqual((app / 'agent/app.py').read_text(), 'x = 1\n')
        self.assertFalse((app / 'agent/static/old.js').exists(), 'a file the release dropped does not survive')
        self.assertEqual((app / 'scripts/tool.py').read_text(), 'y = 2\n')

    def test_a_config_directory_that_differs_in_the_candidate_stops_before_anything_is_stopped(self):
        for stale in ('config/prompts/old.md', 'scripts/old.py'):
            with self.subTest(stale=stale):
                result = self.overlay(env={'STALE_FILE': stale})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'candidate /app/{stale.split("/")[0]} differs from releases', result.stderr)
                self.assertIn(stale.split('/', 1)[1].rsplit('/', 1)[-1], result.stderr)
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
        self.assertIn('this overlay ships scripts/ but the Dockerfile does not copy it', result.stderr)
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

    def test_a_missing_release_dockerfile_refuses(self):
        (self.release / 'Dockerfile').unlink()
        result = self.overlay()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('to check the overlay directories against', result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith(('docker build', 'docker stop', 'docker tag'))])

    def dockerfile_text(self):
        return pathlib.Path(f'{self.log}.dockerfile').read_text()

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

    def stage(self, dockerfile):
        with tempfile.TemporaryDirectory(prefix='noevia-rs-stage-') as directory:
            temp = pathlib.Path(directory)
            (temp / 'releases/abc1234/services/diary').mkdir(parents=True)
            if dockerfile is not None:
                (temp / 'releases/abc1234/services/diary/Dockerfile').write_text(dockerfile)
            (temp / 'ctx').mkdir()
            script = 'set -euo pipefail\nbase=$1; V=abc1234; ctx=$1/ctx\n' + self.block('overlay-dirs') + '\n' + self.block() + '\necho "STAGE $rs_stage"'
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
        # noevia#982: workspace-restore-verify is built and self-tested only when the pinned
        # noevia-rs has the crate, so an older release still overlays.
        self.assertIn('if [ -d bins/workspace-restore-verify ]; then', df)
        self.assertIn('cargo build --release --locked -p workspace-restore-verify-cli', df)
        self.assertIn('./target/release/workspace-restore-verify self-test | grep -qx ok', df)
        # agent/, config/ and scripts/ are replaced whole, so files the release dropped do not survive (#1624, #2112).
        self.assertTrue(df.rstrip().endswith(OVERLAY_TAIL.rstrip()), df)
        # Only the pins are taken from the release's Dockerfile; never its text, and no pip.
        self.assertNotIn('pip', df)
        self.assertEqual(df.count('FROM cowork-diary:rollback-before-diary-overlay'), 1)

    def test_an_unpinned_release_overlays_only_the_directories_copied_into_app(self):
        for dockerfile in ('FROM python:3.12-slim\nCOPY agent/ ./agent/\n', None):
            with self.subTest(dockerfile=dockerfile):
                result, df = self.stage(dockerfile)
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


class DiaryCopyContract(unittest.TestCase):
    """Run the final-stage check and the CI parser on the same synthetic instructions."""

    def check(self, dockerfile):
        with tempfile.TemporaryDirectory(prefix='noevia-copy-contract-') as temp:
            path = pathlib.Path(temp) / 'Dockerfile'
            path.write_text(dockerfile)
            block = RsStage().block('dockerfile-copy-check')
            script = ('set -euo pipefail\ndiary_df_check=$1; overlay_dirs="agent config scripts"\n'
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

    def test_generated_binary_copy_spans_both_parsers(self):
        result, generated = RsStage().stage(
            f'ARG NOEVIA_RS_REF={RsStage.REF}\nARG NOEVIA_RS_SHA256={RsStage.SUM}\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        copies = [line for line in generated.splitlines() if line.startswith('COPY --from=')]
        self.assertEqual(copies, ['COPY --from=tenant-assertion /out/ /usr/local/bin/'])
        self.accepted(generated)


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


class OverlayDirsInSync(unittest.TestCase):
    """#2112: the directory list of diary-overlay.sh, its documentation and the Diary Dockerfile stay one list."""

    def script_dirs(self):
        found = re.findall(r'(?m)^overlay_dirs="([a-z_ ]+)"$', DIARY.read_text())
        self.assertEqual(len(found), 1, found)
        return set(found[0].split())

    @staticmethod
    def dockerfile_dirs(text):
        final_stage = re.split(r'(?mi)^[ \t]*FROM[ \t].*$', text)[-1]   # the image is its last stage
        dirs = set()
        for line in final_stage.splitlines():
            line = line.strip()
            if not re.match(r'(?i)^(COPY|ADD)(\s|$)', line):
                continue
            if line == 'COPY requirements.txt .':
                continue
            if line == 'COPY --from=tenant-assertion /out/ /usr/local/bin/':
                continue
            match = re.fullmatch(r'COPY ([a-z_][a-z0-9_]*)/ \./\1/', line)
            if not match:
                raise ValueError(f'unsupported final-stage COPY/ADD: {line}')
            dirs.add(match[1])
        return dirs

    def test_the_list_is_exactly_agent_config_and_scripts(self):
        self.assertEqual(self.script_dirs(), {'agent', 'config', 'scripts'})

    def test_the_fixture_dockerfile_copies_the_same_directories(self):
        self.assertEqual(self.dockerfile_dirs(DIARY_DOCKERFILE), self.script_dirs())

    def test_the_deployment_guide_lists_the_same_directories(self):
        docs = (ROOT / 'docs/deployment.md').read_text()
        line = re.search(r'(?m)^Diary overlay directories: (.+)$', docs)
        self.assertIsNotNone(line, 'docs/deployment.md has no "Diary overlay directories:" line')
        self.assertEqual(set(re.findall(r'`([a-z_]+)/`', line.group(1))), self.script_dirs())

    @unittest.skipUnless(os.environ.get('NOEVIA_SERVICES_DIR'), 'set NOEVIA_SERVICES_DIR to a noevia-services checkout to compare with its real Dockerfile')
    def test_the_list_matches_the_services_diary_dockerfile(self):
        text = (pathlib.Path(os.environ['NOEVIA_SERVICES_DIR']) / 'diary/Dockerfile').read_text()
        self.assertEqual(self.dockerfile_dirs(text), self.script_dirs())


if __name__ == '__main__':
    unittest.main()
