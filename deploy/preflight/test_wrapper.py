"""The deployment wrapper must stop before up when either validation step fails."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

class WrapperTests(unittest.TestCase):
    def test_gate_and_argument_preservation(self):
        wrapper=Path(__file__).with_name('up.sh').resolve()
        for fail in ['', 'compose', 'check']:
            with self.subTest(fail=fail),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);log=root/'calls'
                docker=root/'docker';docker.write_text('''#!/bin/bash
printf '<%s>' "$@" >> "$PREFLIGHT_QA_LOG"
printf '\\n' >> "$PREFLIGHT_QA_LOG"
if [[ " $* " == *" config "* ]]; then
  if [[ "$PREFLIGHT_QA_FAIL" == compose ]]; then exit 9; fi
  printf '{"services":{"web":{}}}'
fi
''');docker.chmod(0o700)
                php=root/'php';php.write_text('''#!/bin/bash
cat >/dev/null
[[ "$PREFLIGHT_QA_FAIL" != check ]]
''');php.chmod(0o700)
                env={**os.environ,'PATH':str(root)+os.pathsep+os.environ['PATH'],'PREFLIGHT_QA_LOG':str(log),'PREFLIGHT_QA_FAIL':fail,'COWORK_PROJECT_DIR':str(root)}
                result=subprocess.run(['bash',str(wrapper),'--env-file','a file.env','--','--no-build','--wait'],env=env,capture_output=True)
                calls=log.read_text()
                self.assertEqual(result.returncode==0,not fail)
                self.assertEqual('<up>' in calls,not fail)
                self.assertIn('<--env-file><a file.env><config><--format><json>',calls)
                if not fail:self.assertIn('<--env-file><a file.env><up><--no-build><--wait>',calls)

    def run_wrapper(self,root,cwd,extra_env,args=('--','--wait')):
        docker=root/'docker';docker.write_text('''#!/bin/bash
pwd >> "$PREFLIGHT_QA_LOG"
if [[ " $* " == *" config "* ]]; then printf '{}'; fi
''');docker.chmod(0o700)
        php=root/'php';php.write_text('#!/bin/bash\ncat >/dev/null\n');php.chmod(0o700)
        env={k:v for k,v in os.environ.items() if k!='COWORK_PROJECT_DIR'}
        env.update({'PATH':str(root)+os.pathsep+env['PATH'],'PREFLIGHT_QA_LOG':str(root/'calls')},**extra_env)
        wrapper=Path(__file__).with_name('up.sh').resolve()
        return subprocess.run(['bash',str(wrapper),*args],env=env,cwd=cwd,capture_output=True,text=True)

    def test_runs_in_project_dir_regardless_of_cwd(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();project=root/'proj';project.mkdir();other=root/'other';other.mkdir()
            result=self.run_wrapper(root,other,{'COWORK_PROJECT_DIR':str(project)})
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(set((root/'calls').read_text().split()),{str(project)})

    def test_missing_project_dir_names_it_and_never_runs_docker(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();gone=root/'nope'
            result=self.run_wrapper(root,root,{'COWORK_PROJECT_DIR':str(gone)})
            self.assertNotEqual(result.returncode,0)
            self.assertIn(str(gone),result.stderr)
            self.assertFalse((root/'calls').exists())

    def test_no_project_dir_and_no_compose_file_fails_clearly(self):
        if Path('/boot/config/plugins/compose.manager/projects/Cowork').is_dir():self.skipTest('running on the Compose Manager host')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve()
            result=self.run_wrapper(root,root,{})
            self.assertNotEqual(result.returncode,0)
            self.assertIn('COWORK_PROJECT_DIR',result.stderr)
            self.assertFalse((root/'calls').exists())

    def test_cwd_with_compose_file_still_works_off_server(self):
        if Path('/boot/config/plugins/compose.manager/projects/Cowork').is_dir():self.skipTest('running on the Compose Manager host')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();(root/'compose.yaml').write_text('services: {}\n')
            result=self.run_wrapper(root,root,{})
            self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':unittest.main()
