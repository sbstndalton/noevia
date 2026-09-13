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
                env={**os.environ,'PATH':str(root)+os.pathsep+os.environ['PATH'],'PREFLIGHT_QA_LOG':str(log),'PREFLIGHT_QA_FAIL':fail}
                result=subprocess.run(['bash',str(wrapper),'--env-file','a file.env','--','--no-build','--wait'],env=env,capture_output=True)
                calls=log.read_text()
                self.assertEqual(result.returncode==0,not fail)
                self.assertEqual('<up>' in calls,not fail)
                self.assertIn('<--env-file><a file.env><config><--format><json>',calls)
                if not fail:self.assertIn('<--env-file><a file.env><up><--no-build><--wait>',calls)
if __name__=='__main__':unittest.main()
