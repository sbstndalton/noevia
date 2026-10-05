"""Guards in the live-server overlay scripts that can be exercised without Docker or the server.

The release SHA becomes a path component, an image tag and a sed replacement, so both scripts
refuse anything but a hex SHA before touching anything. The Diary overlay takes its own appdata
backup and must verify the folder it then verifies is that backup, not a leftover.
"""
import os
import pathlib
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OVERLAY = ROOT / 'deploy/examples/overlay-release.sh'
DIARY = ROOT / 'deploy/examples/diary-overlay.sh'

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
        # No bare inspect of the optional containers: each must be allowed to fail.
        for line in text.splitlines():
            if 'docker inspect cowork-llama-1' in line:
                self.assertIn('|| true', line)
        self.assertNotIn('cowork-model-loader-1 \\', text)


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
