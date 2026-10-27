"""Fault cases for the validator used on actual rendered Compose in Linux CI."""
import copy
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('egress_profile', ROOT / 'deploy/tools/check-egress-native-profile.py')
PROFILE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROFILE)


def rendered():
    source = '/operator/prepared/native-egress'
    mount = {'type': 'bind', 'source': source, 'target': PROFILE.TARGET, 'read_only': True, 'bind': {'create_host_path': False}}
    return {'networks': {'code': {'internal': True}}, 'services': {
        'egress-rs': {'build': {'target': 'native-control'}, 'command': ['--native-control-v1'], 'group_add': ['1006'],
            'networks': {'default': {}, 'code': {'aliases': ['egress-rs-code']}},
            'environment': {'CODE_EGRESS_BIND': 'egress-rs-code', 'CODE_EGRESS_PORT': '8040', 'CODE_EGRESS_CONTROL_KEY_FILE': PROFILE.TARGET + '/current.key', 'CODE_EGRESS_CONTROL_KEY_UID': '0', 'CODE_EGRESS_CONTROL_KEY_GID': '1006'},
            'volumes': [mount]},
        'web': {'networks': {'default': {}, 'code': {'aliases': ['egress']}},
            'environment': {'CODE_EGRESS_IMPL': 'rust', 'CODE_EGRESS_RUST_HOST': 'egress-rs-code', 'CODE_EGRESS_PORT': '8040', 'CODE_EGRESS_CONTROL_KEY_FILE': PROFILE.TARGET + '/current.key', 'CODE_EGRESS_KEY_UID': '0', 'CODE_EGRESS_KEY_GID': '1006'},
            'volumes': [{**copy.deepcopy(mount), 'read_only': False}]},
        'code-sandbox': {'networks': {'code': {}}, 'volumes': [{'type': 'volume', 'source': 'workspaces', 'target': '/workspaces'}]}}}


class NativeProfileTests(unittest.TestCase):
    def test_matching_prepared_profile(self):
        PROFILE.validate(rendered())

    def reject(self, change):
        config = rendered()
        change(config['services'])
        with self.assertRaises(ValueError):
            PROFILE.validate(config)

    def test_legacy_mode_or_image_rejected(self):
        self.reject(lambda s: s['web']['environment'].update(CODE_EGRESS_IMPL='node'))
        self.reject(lambda s: s['egress-rs']['build'].update(target='release'))
        self.reject(lambda s: s['egress-rs'].update(command=[]))
        self.reject(lambda s: s['web']['environment'].update(CODE_EGRESS_GRANT_KEY_FILE='/old/key'))

    def test_disconnected_port_or_key_identity_rejected(self):
        self.reject(lambda s: s['web']['environment'].update(CODE_EGRESS_PORT='8041'))
        self.reject(lambda s: s['egress-rs']['environment'].update(CODE_EGRESS_CONTROL_KEY_UID='65532'))
        self.reject(lambda s: s['egress-rs'].update(group_add=[]))
        self.reject(lambda s: s['web']['environment'].update(CODE_EGRESS_CONTROL_KEY_FILE='/old/grant.key'))

    def test_published_or_multinetwork_listener_rejected(self):
        self.reject(lambda s: s['egress-rs'].update(ports=['8040:8040']))
        self.reject(lambda s: s['web']['networks']['default'].update(aliases=['egress-rs-code']))
        self.reject(lambda s: s['egress-rs']['environment'].update(CODE_EGRESS_BIND='egress-rs'))

    def test_implicit_creation_or_writable_reader_rejected(self):
        self.reject(lambda s: s['web']['volumes'][0]['bind'].update(create_host_path=True))
        self.reject(lambda s: s['egress-rs']['volumes'][0].update(read_only=False))
        self.reject(lambda s: s['web']['volumes'][0].update(source='/different/key'))
        self.reject(lambda s: s['web']['volumes'][0].update(type='volume'))

    def test_key_exposure_to_sandbox_rejected(self):
        self.reject(lambda s: s['code-sandbox']['volumes'].append(copy.deepcopy(s['egress-rs']['volumes'][0])))


if __name__ == '__main__':
    unittest.main()
