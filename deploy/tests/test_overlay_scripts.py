"""Guards in the live-server overlay scripts that can be exercised without Docker or the server.

The release SHA becomes a path component, an image tag and a sed replacement, so both scripts
refuse anything but a hex SHA before touching anything. The Diary overlay takes its own appdata
backup and must verify the folder it then verifies is that backup, not a leftover.
"""
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OVERLAY = ROOT / 'deploy/examples/overlay-release.sh'
DIARY = ROOT / 'deploy/examples/diary-overlay.sh'
RCLONE = ROOT / 'deploy/offsite/rclone-sync.sh'

BAD_SHAS = ['', 'ABCDEF1', 'abc12', 'abc123g', '../../etc', 'abc1234;touch x', 'abc1234 x', '$(id)', 'a' * 41]


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
        result = self.probe('echo sha256:abc123')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ID=[sha256:abc123]', result.stdout)

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


class BackupPick(unittest.TestCase):
    """Run the `backup-pick` block of diary-overlay.sh against synthetic backup folders."""

    def block(self):
        lines = DIARY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('# BEGIN backup-pick'))
        end = next(i for i, l in enumerate(lines) if l.startswith('# END backup-pick'))
        return '\n'.join(lines[start + 1:end])

    def pick(self, root, marker):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\nmarker=$1\n' + self.block() + '\necho "PICKED $B"', 'x', str(marker)],
                              env=dict(os.environ, BACKUP_ROOT=str(root)), capture_output=True, text=True)

    def test_picks_the_backup_this_run_took_and_refuses_stale_or_missing_ones(self):
        with tempfile.TemporaryDirectory(prefix='noevia-backup-pick-') as temp:
            temp = pathlib.Path(temp)
            root = temp / 'backups'
            root.mkdir()
            marker = temp / 'marker'
            old = root / 'ab_20260101_000000'
            old.mkdir()
            past = time.time() - 3600
            os.utime(old, (past, past))
            marker.touch()
            before = time.time() - 60  # the run started a minute ago; coarse mtimes cannot blur the order
            os.utime(marker, (before, before))

            none = self.pick(temp / 'absent', marker)
            self.assertNotEqual(none.returncode, 0)
            self.assertIn('no appdata backup', none.stderr)

            stale = self.pick(root, marker)
            self.assertNotEqual(stale.returncode, 0, 'a leftover backup from an earlier run is not this run\'s backup')
            self.assertIn('older than this run', stale.stderr)

            fresh = root / 'ab_20260102_000000'
            fresh.mkdir()
            ok = self.pick(root, marker)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertIn(f'PICKED {fresh}', ok.stdout)


if __name__ == '__main__':
    unittest.main()
