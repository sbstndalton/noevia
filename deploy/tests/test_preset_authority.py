from pathlib import Path
import os
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'deploy/tools/preset-authority-backup.sh'

class PresetAuthorityBackupTests(unittest.TestCase):
    def invoke(self, *args):
        return subprocess.run(['bash', str(HELPER), *map(str,args)],capture_output=True,text=True,timeout=20)

    def test_backup_contains_committed_wal_and_restores_without_stale_sidecars(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);source=d/'authority.sqlite';snapshot=d/'snapshot.sqlite';restored=d/'restored.sqlite'
            writer=sqlite3.connect(source)
            try:
                writer.execute('PRAGMA journal_mode=WAL')
                writer.execute('CREATE TABLE preset_operations(id TEXT PRIMARY KEY,state TEXT)')
                writer.execute("INSERT INTO preset_operations VALUES('first','issued')");writer.commit()
                writer.execute("INSERT INTO preset_operations VALUES('second','recovery')");writer.commit()
                self.assertTrue(Path(str(source)+'-wal').exists())
                result=self.invoke('backup',source,snapshot);self.assertEqual(result.returncode,0,result.stderr)
                with sqlite3.connect(snapshot) as db:self.assertEqual(db.execute('SELECT count(*) FROM preset_operations').fetchone()[0],2)
                self.assertEqual(snapshot.stat().st_mode&0o777,0o600)
                Path(str(restored)+'-wal').write_bytes(b'old wal');Path(str(restored)+'-shm').write_bytes(b'old shm')
                result=self.invoke('restore',snapshot,restored,'--services-stopped');self.assertEqual(result.returncode,0,result.stderr)
                self.assertFalse(Path(str(restored)+'-wal').exists());self.assertFalse(Path(str(restored)+'-shm').exists())
                self.assertEqual(restored.stat().st_mode&0o777,0o644,'Gate has a separate UID on a read-only mount')
                with sqlite3.connect(restored) as db:self.assertEqual(db.execute('SELECT count(*) FROM preset_operations').fetchone()[0],2)
                self.assertEqual(list(d.glob('.preset-authority-*')),[])
            finally:writer.close()

    def test_restore_requires_quiesced_services_and_backup_never_overwrites(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);source=d/'authority.sqlite';target=d/'existing.sqlite'
            with sqlite3.connect(source) as db:db.execute('CREATE TABLE state(value TEXT)')
            target.write_bytes(b'preserve')
            self.assertNotEqual(self.invoke('restore',source,target).returncode,0)
            self.assertEqual(target.read_bytes(),b'preserve')
            self.assertNotEqual(self.invoke('backup',source,target).returncode,0)
            self.assertEqual(target.read_bytes(),b'preserve')
            self.assertNotEqual(self.invoke('backup',d/'missing',d/'new').returncode,0)
            self.assertFalse((d/'missing').exists());self.assertFalse((d/'new').exists())

    def test_named_volume_topology(self):
        try:import yaml
        except ImportError:self.skipTest('PyYAML is supplied by the Linux deploy verification host')
        base=yaml.safe_load((ROOT/'compose.yaml').read_text());overlay=yaml.safe_load((ROOT/'compose.llamacpp.yaml').read_text())
        self.assertIn('preset-authority',base['volumes']);self.assertIn('preset-authority',overlay['volumes'])
        for name,mode in [('web','rw'),('model-loader','rw'),('inference-gate','ro')]:
            service=overlay['services'][name]
            mounts=[v for v in service['volumes'] if isinstance(v,str) and v.startswith('preset-authority:')]
            self.assertEqual(len(mounts),1)
            parts=mounts[0].split(':');self.assertEqual(parts[1],'/preset-authority');self.assertEqual(parts[2] if len(parts)>2 else 'rw',mode)
            self.assertEqual(service['environment']['NOEVIA_PRESET_AUTHORITY_FILE'],'/preset-authority/authority.sqlite')
        self.assertEqual(overlay['services']['inference-gate']['environment']['NOEVIA_PRESET_AUTHORITY_URL'],'http://model-loader:8090')
        self.assertTrue(any(v.endswith(':/llamacpp-config:ro') for v in overlay['services']['web']['volumes'] if isinstance(v,str)))
        for document in ['DEPLOY.md','docs/deployment.md','deploy/backups/README.md','deploy/examples/overlay-release.sh']:
            self.assertIn('preset-authority',(ROOT/document).read_text(),document+' must cover the persistent authority')

if __name__=='__main__':unittest.main()
