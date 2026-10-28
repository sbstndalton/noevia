"""Source contract; actual rendered profile and namespace execution are qualified in Linux CI."""
import pathlib
import unittest
from test_code_engine_relay_1853 import service_block, entries, sub_block

ROOT = pathlib.Path(__file__).resolve().parents[2]


class NativeVerifierProfile(unittest.TestCase):
    def setUp(self):
        self.lines = service_block((ROOT / 'deploy/examples/code-sandbox.override.yml').read_text(), 'code-verify')
        self.values = entries(self.lines)

    def test_native_authority_has_no_node_fallback(self):
        self.assertIn('command: ["/usr/local/libexec/noevia/code-verify-native"]', self.values)
        self.assertNotIn('command: ["node", "verifier.cjs"]', self.values)
        self.assertIn('user: "0:0"', self.values)
        self.assertNotIn('init: true', self.values)

    def test_keeps_restricted_identity_and_no_network_profile(self):
        for value in ['read_only: true', 'network_mode: none', 'cap_drop: ["ALL"]',
                      'cap_add: ["SETUID", "SETGID"]', 'security_opt: ["no-new-privileges:true"]',
                      'pids_limit: 256', 'mem_limit: 2g', 'cpus: 2.0']:
            self.assertIn(value, self.values)
        self.assertFalse(any(v.startswith(('privileged:', 'pid:', 'ipc:', 'ports:')) for v in self.values))

    def test_separate_source_socket_copy_and_worker_storage(self):
        self.assertEqual(entries(sub_block(self.lines, 'volumes')),
                         ['- code-workspaces:/workspaces:ro', '- code-verify-socket:/run/noevia-verify'])
        self.assertEqual(entries(sub_block(self.lines, 'tmpfs')),
                         ['- /tmp:size=64m,mode=0755',
                          '- /verify/copy:size=2g,mode=0755,uid=1002,gid=1002',
                          '- /verify/run:size=1g,mode=0700,uid=1003,gid=1003'])


if __name__ == '__main__':
    unittest.main()
