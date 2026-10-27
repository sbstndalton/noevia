#!/usr/bin/env python3
"""Validate rendered Compose native-egress isolation, pairing and key ownership.

This is a source/profile check, never an authenticated Ready or runtime qualification.
"""
import json
import sys


TARGET = '/run/noevia-egress-control'


def validate(config):
    def require(condition, reason):
        if not condition:
            raise ValueError(reason)

    services = config['services']
    native, web = services['egress-rs'], services['web']
    ne, we = native['environment'], web['environment']
    bind = ne['CODE_EGRESS_BIND']
    require(bind != 'egress-rs' and bool(bind), 'bind must be a code-only alias')
    require(bind in native['networks']['code'].get('aliases', []), 'missing native code alias')
    for service in services.values():
        for network, settings in service.get('networks', {}).items():
            require(network == 'code' or bind not in (settings or {}).get('aliases', []), 'alias exposed outside code')
    require(config['networks']['code']['internal'] is True, 'code network must be internal')
    require(not native.get('ports'), 'native ports must not be published')
    require(native['build']['target'] == 'native-control', 'native image capability gate required')
    require(native['command'] == ['--native-control-v1'], 'explicit native mode required')
    require(we['CODE_EGRESS_IMPL'] == 'rust', 'Node fallback is retired')
    require(we['CODE_EGRESS_RUST_HOST'] == bind, 'web/native endpoint mismatch')
    port = str(ne['CODE_EGRESS_PORT'])
    require(port.isascii() and port.isdecimal() and 0 < int(port) <= 65535, 'invalid native port')
    require(str(we['CODE_EGRESS_PORT']) == port, 'web/native port mismatch')
    require(ne['CODE_EGRESS_CONTROL_KEY_FILE'] == we['CODE_EGRESS_CONTROL_KEY_FILE'] == TARGET + '/current.key', 'current key path mismatch')
    for suffix in ('UID', 'GID'):
        value = str(we['CODE_EGRESS_KEY_' + suffix])
        require(value.isascii() and value.isdecimal() and int(value) < 0xffffffff and (suffix == 'UID' or int(value) > 0), 'invalid key identity')
        require(str(ne['CODE_EGRESS_CONTROL_KEY_' + suffix]) == value, 'key identity mismatch')
    require(str(we['CODE_EGRESS_KEY_GID']) in [str(g) for g in native['group_add']], 'native supplementary key group missing')
    require(not any('GRANT_KEY' in key for key in (*ne, *we)), 'legacy key mode must not coexist')
    mounts = []
    for service, readonly in ((native, True), (web, False)):
        matches = [v for v in service['volumes'] if v.get('target') == TARGET]
        require(len(matches) == 1, 'exactly one current-key mount required')
        mount = matches[0]
        require(mount['type'] == 'bind' and mount.get('read_only', False) is readonly, 'key mount access mismatch')
        require(mount.get('bind', {}).get('create_host_path') is False, 'key directory must be explicitly prepared')
        require(str(mount['source']).startswith('/'), 'key source must be absolute')
        mounts.append(mount['source'])
    require(mounts[0] == mounts[1], 'web/native key source mismatch')
    for name, service in services.items():
        if name in ('web', 'egress-rs'):
            continue
        require(all(v.get('source') != mounts[0] and v.get('target') != TARGET for v in service.get('volumes', [])), 'key mounted into another service')


if __name__ == '__main__':
    try:
        validate(json.load(sys.stdin))
    except (ValueError, KeyError, TypeError) as exc:
        sys.exit('native egress profile rejected: ' + str(exc))
    print('native egress profile pairing/isolation PASS (runtime readiness not tested)')
