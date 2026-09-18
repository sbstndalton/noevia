"""The off-site mirror's safety rules, against a real rclone.

A mirror is the one tool that can destroy a backup, so each rule is proven rather than assumed.
Google Drive is stood in for by an rclone `local` remote with the same name, which exercises
exactly the same copy/sync logic without touching anyone's account.

Needs `rclone` and `flock` (Linux). On a machine without them the whole class is skipped. The
Unraid host has rclone but no Python, so run it in a container with the host's static rclone
binary mounted in:

    docker run --rm -v /usr/bin/rclone:/usr/bin/rclone:ro -v "$PWD":/repo -w /repo \
      --entrypoint python cowork-diary:<tag> -m unittest deploy/tests/test_rclone_sync.py -v
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'deploy/offsite/rclone-sync.sh'


@unittest.skipUnless(shutil.which('rclone') and shutil.which('flock'), 'needs rclone and flock (run on the server)')
class RcloneSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='noevia-rclone-test-'))
        self.local = self.tmp / 'local'
        self.remote = self.tmp / 'remote'
        self.local.mkdir()
        self.remote.mkdir()
        self.conf = self.tmp / 'rclone.conf'
        # The stand-in for Google Drive: same remote name, local storage.
        self.conf.write_text('[gdrive]\ntype = local\n')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_sync(self, remote_name='gdrive', conf=None, max_delete=500):
        env = dict(os.environ, LOCAL=str(self.local), REMOTE=f'{remote_name}:{self.remote}',
                   RCLONE_CONFIG=str(conf or self.conf), LOG=str(self.tmp / 'sync.log'), MAX_DELETE=str(max_delete))
        return subprocess.run(['bash', str(SCRIPT)], env=env, capture_output=True, text=True).returncode

    def healthy_store(self):
        (self.local / 'data/ab').mkdir(parents=True, exist_ok=True)
        (self.local / 'snapshots').mkdir(exist_ok=True)
        (self.local / 'config').write_text('c')
        (self.local / 'data/ab/chunk1').write_text('x')
        (self.local / 'snapshots/snap1').write_text('s')

    def remote_files(self):
        return sorted(str(p.relative_to(self.remote)) for p in self.remote.rglob('*') if p.is_file())

    def mirror_state(self):
        import json
        return json.loads((self.local / '.mirror-status.json').read_text())['state']

    def test_missing_config_or_remote_is_a_setup_error(self):
        self.healthy_store()
        self.assertEqual(self.run_sync(conf=self.tmp / 'absent.conf'), 2)
        self.assertEqual(self.mirror_state(), 'not-connected', 'the settings page must say so')
        self.assertEqual(self.run_sync(remote_name='nope'), 2)
        self.assertEqual(self.mirror_state(), 'not-connected')

    def test_success_and_failure_are_reported_to_the_page(self):
        self.healthy_store()
        self.assertEqual(self.run_sync(), 0)
        self.assertEqual(self.mirror_state(), 'ok')
        self.assertNotIn('.mirror-status.json', ' '.join(self.remote_files()), 'the status file never goes to Drive')
        (self.local / 'data/ab/chunk1').write_text('CORRUPT')
        self.assertEqual(self.run_sync(), 4)
        self.assertEqual(self.mirror_state(), 'failed')

    def test_a_store_that_was_never_set_up_is_refused(self):
        self.assertEqual(self.run_sync(), 3)
        (self.local / 'config').write_text('c')
        self.assertEqual(self.run_sync(), 3, 'a config with no snapshot is not yet a backup')

    def test_a_healthy_store_is_mirrored_without_temp_files(self):
        self.healthy_store()
        (self.local / 'data/ab/.tmp-deadbeef').write_text('half written')
        self.assertEqual(self.run_sync(), 0)
        self.assertEqual(self.remote_files(), ['config', 'data/ab/chunk1', 'snapshots/snap1'])

    def test_retention_is_followed_on_the_remote(self):
        self.healthy_store()
        (self.local / 'data/ab/chunk2').write_text('y')
        self.assertEqual(self.run_sync(), 0)
        (self.local / 'data/ab/chunk2').unlink()
        self.assertEqual(self.run_sync(), 0)
        self.assertNotIn('data/ab/chunk2', self.remote_files())

    def test_a_wiped_local_store_never_wipes_the_remote(self):
        # The disaster case. `rclone sync` of an empty folder would delete everything on Drive
        # at exactly the moment the backup is needed.
        self.healthy_store()
        self.assertEqual(self.run_sync(), 0)
        before = self.remote_files()
        shutil.rmtree(self.local)
        self.local.mkdir()
        self.assertEqual(self.run_sync(), 3)
        self.assertEqual(self.remote_files(), before)

    def test_restored_timestamps_are_not_mistaken_for_corruption(self):
        # Restoring the folder from a backup resets modification times on identical files.
        self.healthy_store()
        self.assertEqual(self.run_sync(), 0)
        old = 1577836800  # 2020-01-01
        for p in self.local.rglob('*'):
            if p.is_file():
                os.utime(p, (old, old))
        self.assertEqual(self.run_sync(), 0)

    def test_different_content_under_an_existing_name_is_refused(self):
        # Chunk names are content hashes, so this can only be corruption on one side.
        self.healthy_store()
        self.assertEqual(self.run_sync(), 0)
        (self.local / 'data/ab/chunk1').write_text('CORRUPT')
        self.assertEqual(self.run_sync(), 4)
        self.assertEqual((self.remote / 'data/ab/chunk1').read_text(), 'x', 'the good copy survives')

    def test_a_prune_over_the_cap_is_stopped(self):
        self.healthy_store()
        self.assertEqual(self.run_sync(), 0)
        for i in range(20):
            (self.remote / f'data/ab/extra{i}').write_text(str(i))
        self.assertEqual(self.run_sync(max_delete=5), 5)
        # rclone deletes up to the cap and then stops; the rest survive for a human to look at.
        self.assertGreaterEqual(len(self.remote_files()), 3 + 20 - 5)
        self.assertEqual(self.run_sync(max_delete=500), 0)
        self.assertEqual(self.remote_files(), ['config', 'data/ab/chunk1', 'snapshots/snap1'])


if __name__ == '__main__':
    unittest.main()
