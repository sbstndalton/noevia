"""Selector source contract; actual image/caller qualification is a separate Linux gate."""
import pathlib
import unittest
from test_code_engine_relay_1853 import service_block, entries, sub_block

ROOT = pathlib.Path(__file__).resolve().parents[2]


class NativeSupervisorProfile(unittest.TestCase):
    def setUp(self):
        self.lines = service_block((ROOT / 'deploy/examples/code-sandbox.override.yml').read_text(), 'code-sandbox')
        self.values = entries(self.lines)

    def test_explicit_selector_is_forwarded_without_changing_defaults(self):
        env = entries(sub_block(self.lines, 'environment'))
        self.assertIn('CODE_SANDBOX_SUPERVISOR_IMPL: ${CODE_SANDBOX_SUPERVISOR_IMPL:-node}', env)
        self.assertIn('SANDBOX_BRIDGE_IMPL: ${SANDBOX_BRIDGE_IMPL:-js}', env)
        self.assertFalse(any(v.startswith('command:') for v in self.values))

    def test_keeps_unprivileged_read_only_internal_profile(self):
        for value in ['user: "1000:1000"', 'read_only: true', 'cap_drop: ["ALL"]',
                      'security_opt: ["no-new-privileges:true"]', 'pids_limit: 512', 'mem_limit: 3g']:
            self.assertIn(value, self.values)
        self.assertFalse(any(v.startswith(('privileged:', 'pid:', 'ipc:', 'ports:', 'cap_add:')) for v in self.values))
        self.assertEqual(entries(sub_block(self.lines, 'networks')), ['- code'])
        self.assertEqual(entries(sub_block(self.lines, 'volumes')), ['- code-workspaces:/workspaces'])

    def test_verifier_remains_a_separate_explicit_native_authority(self):
        values = entries(service_block((ROOT / 'deploy/examples/code-sandbox.override.yml').read_text(), 'code-verify'))
        self.assertIn('command: ["/usr/local/libexec/noevia/code-verify-native"]', values)
        self.assertIn('network_mode: none', values)
        self.assertNotIn('CODE_SANDBOX_SUPERVISOR_IMPL: ${CODE_SANDBOX_SUPERVISOR_IMPL:-node}', values)


if __name__ == '__main__':
    unittest.main()
