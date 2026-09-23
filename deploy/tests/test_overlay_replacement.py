"""Exercise the exact image-cleanup command on synthetic OLD/NEW trees, no Docker."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class OverlayReplacement(unittest.TestCase):
    def test_nested_old_code_removed_dependencies_and_runtime_kept(self):
        script = (ROOT / 'deploy/examples/overlay-release.sh').read_text()
        command = next(line[4:] for line in script.splitlines() if line.startswith('RUN find /app/server'))
        with tempfile.TemporaryDirectory(prefix='noevia-overlay-') as temp:
            app = pathlib.Path(temp) / 'app'
            for rel in ['server/routes/retired.cjs', 'server/nested/deep/retired.cjs',
                        'server/.obsolete', 'server/node_modules/package/index.js',
                        'server/ui-data/tenant/data.json', 'dist/assets/old.js']:
                p = app / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('old')
            # Neither symlink targets nor runtime-mounted data may be traversed.
            outside = pathlib.Path(temp) / 'outside'
            outside.mkdir()
            (outside / 'keep').write_text('keep')
            (app / 'server/old-link').symlink_to(outside)
            subprocess.run(['sh', '-c', command.replace('/app/', str(app) + '/')], check=True)
            self.assertFalse((app / 'server/routes').exists())
            self.assertFalse((app / 'server/nested').exists())
            self.assertFalse((app / 'server/.obsolete').exists())
            self.assertFalse((app / 'server/old-link').exists())
            self.assertFalse((app / 'dist').exists())
            self.assertEqual((outside / 'keep').read_text(), 'keep')
            for rel in ['server/node_modules/package/index.js', 'server/ui-data/tenant/data.json']:
                self.assertEqual((app / rel).read_text(), 'old')
            new = pathlib.Path(temp) / 'new/server/routes'
            new.mkdir(parents=True)
            (new / 'current.cjs').write_text('new')
            shutil.copytree(new.parent, app / 'server', dirs_exist_ok=True)
            self.assertEqual((app / 'server/routes/current.cjs').read_text(), 'new')
            self.assertFalse((app / 'server/routes/retired.cjs').exists())

if __name__ == '__main__':
    unittest.main()
