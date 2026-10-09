"""Guards in the live-server overlay scripts that can be exercised without Docker or the server.

The release SHA becomes a path component, an image tag and a sed replacement, so both scripts
refuse anything but a hex SHA before touching anything. The Diary overlay takes its own appdata
backup and must verify the folder it then verifies is that backup, not a leftover.
"""
import json
import os
import pathlib
import shutil
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


class BackupVerify(unittest.TestCase):
    """Run the `backup-verify` block of diary-overlay.sh: .tar.zst or .tar.gz, never neither."""

    NAMES = ('cowork-diary-1', 'cowork-web-1', 'extra_files')

    def run_block(self, folder):
        lines = DIARY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('# BEGIN backup-verify'))
        end = next(i for i, l in enumerate(lines) if l.startswith('# END backup-verify'))
        script = 'set -euo pipefail\nB=$1\n' + '\n'.join(lines[start + 1:end])
        return subprocess.run(['bash', '-c', script, 'x', str(folder)], capture_output=True, text=True)

    def test_accepts_gzip_and_zstd_backups_and_refuses_missing_or_corrupt_ones(self):
        import gzip
        with tempfile.TemporaryDirectory(prefix='noevia-backup-verify-') as temp:
            temp = pathlib.Path(temp)
            gz = temp / 'gz'
            gz.mkdir()
            for n in self.NAMES:
                (gz / f'{n}.tar.gz').write_bytes(gzip.compress(b'x'))
            ok = self.run_block(gz)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertIn('backup verified', ok.stdout)

            (gz / 'extra_files.tar.gz').write_bytes(b'not gzip')
            self.assertNotEqual(self.run_block(gz).returncode, 0)

            empty = temp / 'empty'
            empty.mkdir()
            missing = self.run_block(empty)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn('not deploying', missing.stderr)

            if shutil.which('zstd'):
                zs = temp / 'zs'
                zs.mkdir()
                for n in self.NAMES:
                    (zs / f'{n}.tar.zst').write_bytes(subprocess.run(['zstd', '-q', '-c'], input=b'x', capture_output=True, check=True).stdout)
                self.assertEqual(self.run_block(zs).returncode, 0)
                (zs / 'cowork-web-1.tar.zst').write_bytes(b'not zstd')
                self.assertNotEqual(self.run_block(zs).returncode, 0)


class RsStage(unittest.TestCase):
    """Run the `rs-stage` block of diary-overlay.sh against synthetic release Dockerfiles."""

    REF = 'a' * 40
    SUM = 'b' * 64

    def block(self):
        lines = DIARY.read_text().splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith('# BEGIN rs-stage'))
        end = next(i for i, l in enumerate(lines) if l.startswith('# END rs-stage'))
        return '\n'.join(lines[start + 1:end])

    def stage(self, dockerfile):
        temp = pathlib.Path(tempfile.mkdtemp(prefix='noevia-rs-stage-'))
        (temp / 'releases/abc1234/services/diary').mkdir(parents=True)
        if dockerfile is not None:
            (temp / 'releases/abc1234/services/diary/Dockerfile').write_text(dockerfile)
        (temp / 'ctx').mkdir()
        script = 'set -euo pipefail\nbase=$1; V=abc1234; ctx=$1/ctx\n' + self.block() + '\necho "STAGE $rs_stage"'
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
        self.assertIn('COPY --from=tenant-assertion /src/target/release/tenant-assertion /usr/local/bin/tenant-assertion', df)
        self.assertTrue(df.rstrip().endswith('COPY agent/ ./agent/'))
        # Only the pins are taken from the release's Dockerfile; never its text, and no pip.
        self.assertNotIn('pip', df)
        self.assertEqual(df.count('FROM cowork-diary:rollback-before-diary-overlay'), 1)

    def test_an_unpinned_release_keeps_the_agent_only_overlay(self):
        for dockerfile in ('FROM python:3.12-slim\nCOPY agent/ ./agent/\n', None):
            with self.subTest(dockerfile=dockerfile):
                result, df = self.stage(dockerfile)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('STAGE 0', result.stdout)
                self.assertEqual(df, 'FROM cowork-diary:rollback-before-diary-overlay\nCOPY agent/ ./agent/\n')

    def test_a_malformed_pin_stops_before_any_build(self):
        for ref, digest in [('a' * 39, self.SUM), (self.REF, 'B' * 64), (self.REF + ';id', self.SUM), (self.REF, ''),
                            ('', self.SUM), ('$(id)' + 'a' * 35, self.SUM)]:
            with self.subTest(ref=ref, digest=digest):
                result, df = self.stage(f'ARG NOEVIA_RS_REF={ref}\nARG NOEVIA_RS_SHA256={digest}\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('not a 40-hex ref', result.stderr)
                self.assertIsNone(df)


if __name__ == '__main__':
    unittest.main()
