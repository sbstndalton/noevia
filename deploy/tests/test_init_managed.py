from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class ManagedInitTests(unittest.TestCase):
    def run_case(self, existing=None, docker_state='', env_override=None):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'deploy').mkdir();(root/'bin').mkdir()
            shutil.copy(ROOT/'deploy/init-managed.sh',root/'deploy/init-managed.sh')
            shutil.copy(ROOT/'.env.example',root/'.env.example');shutil.copy(ROOT/'compose.yaml',root/'compose.yaml')
            if existing=='env':(root/'.env').write_text('PRESERVE-EXISTING-CONFIG')
            if existing=='state':(root/'state').mkdir()
            if existing=='symlink':(root/'.env').symlink_to(root/'missing')
            fake=root/'bin/docker';fake.write_text('''#!/bin/bash
case "$1" in
 info) [[ "$INIT_QA_DOCKER" != offline ]];;
 compose) [[ "$2" == version ]] || exit 77;;
 ps) [[ "$INIT_QA_DOCKER" != containers ]] || echo existing-container;;
 volume) [[ "$2" == ls ]] || exit 77; [[ "$INIT_QA_DOCKER" != volumes ]] || echo cowork_web-data;;
 *) exit 77;;
esac
exit 0
'''.replace('info) [[ "$INIT_QA_DOCKER" != offline ]];;', 'info) [[ "$INIT_QA_DOCKER" != offline ]] || exit 9;;'));fake.chmod(0o700)
            env={k:v for k,v in os.environ.items() if k not in ['COWORK_STATE_DIR','COWORK_WEB_STORAGE','COWORK_DIARY_STORAGE','COMPOSE_PROJECT_NAME']}
            env.update({'PATH':str(root/'bin')+os.pathsep+env['PATH'],'INIT_QA_DOCKER':docker_state});env.update(env_override or {})
            result=subprocess.run(['bash',str(root/'deploy/init-managed.sh')],env=env,capture_output=True,text=True)
            if not existing and not docker_state and not env_override:
                self.assertEqual(result.returncode,0,result.stderr)
                content=(root/'.env').read_text();self.assertIn('COWORK_WEB_STORAGE=web-data',content);self.assertIn('COWORK_DIARY_STORAGE=diary-data',content)
                self.assertEqual((root/'.env').stat().st_mode&0o777,0o600)
            else:
                self.assertNotEqual(result.returncode,0)
                if existing=='env':self.assertEqual((root/'.env').read_text(),'PRESERVE-EXISTING-CONFIG')
                elif existing=='symlink':self.assertTrue((root/'.env').is_symlink())
                else:self.assertFalse((root/'.env').exists())
            self.assertEqual(list(root.glob('.env.fresh.*')),[])
    def test_fresh_initialization(self):self.run_case()
    def test_existing_config_state_and_symlinks_untouched(self):
        for value in ['env','state','symlink']:
            with self.subTest(value=value):self.run_case(existing=value)
    def test_existing_engine_state_or_unavailable_engine_refused(self):
        for value in ['containers','volumes','offline']:
            with self.subTest(value=value):self.run_case(docker_state=value)
    def test_explicit_host_storage_refused(self):self.run_case(env_override={'COWORK_STATE_DIR':'/existing/state'})
if __name__=='__main__':unittest.main()
