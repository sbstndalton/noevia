"""Explicit, synthetic DaServer GPU qualification; always restores production.

Run with --run after reviewing the fixed host/profile configuration. No app state
or credentials are read. Host watchdog independently enforces memory and timeout.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import shlex
import subprocess
import threading
import time
import urllib.parse
import urllib.request
import urllib.error
import zlib
import struct
import os
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
HOST = 'root@10.69.0.130'
BASE = 'http://10.69.0.130:8084'
IMAGE = 'ghcr.io/ggml-org/llama.cpp:server-vulkan@sha256:94bd70ef60ef6d670c85999c144f59013e06525d9ee26b3563ab9b2f29d1ea41'
CHAT = 'Qwen_Qwen3.5-4B-GGUF-Q8_0'
SMART = 'Qwen3.5-9B-GGUF-UD-Q4_K_XL'
DIARY = 'Gemma-4-E4B-it-GGUF'
AUX = 'gemma-4-E2B-it-GGUF-UD-Q4_K_XL'
EMBED = 'nomic-embed-text-v1-GGUF'


def ssh(command, data=None, timeout=45):
    return subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', HOST, command],
                          input=data, text=True, capture_output=True, timeout=timeout, check=True).stdout


def request(path, body=None, timeout=300):
    req = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'{path}: HTTP {error.code}: {error.read(3000).decode()}') from error


def profiles():
    root = '/models/'
    artifacts = {
        CHAT: ('models--bartowski--Qwen_Qwen3.5-4B-GGUF/snapshots/4168f45a16a1290d65a4ec0fa312ae917a4c15d6/', 'Qwen_Qwen3.5-4B-Q8_0.gguf', None),
        SMART: ('models--unsloth--Qwen3.5-9B-GGUF/snapshots/3885219b6810b007914f3a7950a8d1b469d598a5/', 'Qwen3.5-9B-UD-Q4_K_XL.gguf', 'mmproj-F16.gguf'),
        DIARY: ('models--unsloth--gemma-4-E4B-it-GGUF/snapshots/bfc15c382204943c3a8fff0c750b94ae2364d7a3/', 'gemma-4-E4B-it-Q4_K_M.gguf', 'mmproj-F16.gguf'),
        AUX: ('models--unsloth--gemma-4-E2B-it-GGUF/snapshots/0314792d7f1f7e229411f620751375812bb9faf2/', 'gemma-4-E2B-it-UD-Q4_K_XL.gguf', 'mmproj-BF16.gguf'),
        EMBED: ('models--nomic-ai--nomic-embed-text-v1-GGUF/snapshots/90c80ac5c2a0d13de9a36cf1dec39f34acee54a8/', 'nomic-embed-text-v1.Q4_K_S.gguf', None),
    }
    result = {}
    for name, (folder, model, projector) in artifacts.items():
        values = {'model': root + folder + model, 'ctx-size': 262144 if name == SMART else 32768,
                  'parallel': 1, 'ngl': 999, 'flash-attn': 'on', 'cache-type-k': 'q8_0',
                  'cache-type-v': 'q8_0', 'jinja': 'true', 'cache-ram': 1024, 'ubatch-size': 1024}
        if projector:
            values.update({'mmproj': root + folder + projector, 'mmproj-offload': 'on', 'image-max-tokens': 1024})
        if name in (CHAT, SMART):
            values.update({'reasoning': 'on', 'reasoning-format': 'deepseek'})
        if name == CHAT:
            values['spec-type'] = 'draft-mtp'
        if name == EMBED:
            values.update({'ctx-size': 2048, 'embedding': 'true', 'pooling': 'mean',
                           'cache-type-k': 'q5_0', 'cache-type-v': 'q4_0'})
        result[name] = values
    return result


def image_fixture():
    # Code-generated flat red square is a deterministic test fixture, not image editing.
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    raw = (b'\0' + bytes([255, 0, 0]) * 224) * 224
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 224, 224, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    return 'data:image/png;base64,' + base64.b64encode(png).decode()


def chat(model, content='Reply with exactly NATIVE_OK.', **kwargs):
    body = {'model': model, 'messages': [{'role': 'user', 'content': content}], 'max_tokens': 128,
            'temperature': 0, 'chat_template_kwargs': {'enable_thinking': False}}
    body.update(kwargs)
    return request('/v1/chat/completions', body)


def status():
    return {m['id']: m['status']['value'] for m in request('/models')['data']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--results', default='/tmp/noevia-native-qualification')
    parser.add_argument('--app-only', action='store_true', help='Run actual isolated app/client checks after the GPU workload suite has passed')
    args = parser.parse_args()
    config = profiles()
    ini = 'version = 1\n' + ''.join('\n[' + name + ']\n' + ''.join(f'{key} = {value}\n' for key, value in opts.items()) for name, opts in config.items())
    if not args.run:
        print(ini)
        return
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    remote = '/mnt/docker/appdata/noevia-native-qualification/' + stamp
    local = pathlib.Path(args.results) / stamp
    local.mkdir(parents=True)
    quote = shlex.quote(remote)
    report = {'started_at': stamp, 'remote': remote, 'image': IMAGE, 'profiles': config, 'checks': [], 'status': 'running'}
    stop = threading.Event()

    def save():
        (local / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def check(name, action):
        print('START ' + name, flush=True)
        started = time.monotonic()
        result = action()
        report['checks'].append({'name': name, 'seconds': round(time.monotonic() - started, 2), 'result': result})
        save()
        print('PASS ' + name, flush=True)
        return result

    def heartbeat():
        while not stop.wait(10):
            try:
                ssh(f'test ! -e {quote}/restored && touch {quote}/heartbeat', timeout=15)
            except Exception:
                return  # The independent host watchdog restores on stale heartbeat.

    compose = {'name': 'noevia-native-qualification', 'services': {'llama': {
        'image': IMAGE, 'container_name': 'noevia-native-qualification', 'restart': 'no',
        'ports': ['10.69.0.130:8084:8080'],
        'devices': ['/dev/dri/renderD129:/dev/dri/renderD129', '/dev/dri/card1:/dev/dri/card1'],
        'volumes': ['/mnt/user/ai-models:/models:ro', remote + ':/config:ro', remote + '/cache:/cache'],
        'environment': {'LLAMA_CACHE': '/cache'}, 'mem_limit': '14g', 'memswap_limit': '14g',
        'command': ['--models-preset', '/config/models.ini', '--host', '0.0.0.0', '--port', '8080', '--models-max', '1', '--metrics']}}}
    ssh(f'mkdir -p {quote}/cache && chmod 700 {quote}')
    for name, data in [('models.ini', ini), ('compose.yaml', json.dumps(compose)), ('maintenance.sh', (HERE / 'maintenance.sh').read_text())]:
        ssh(f'cat > {quote}/{name}', data)
    save()
    ssh(f'nohup bash {quote}/maintenance.sh {quote} > {quote}/supervisor.log 2>&1 < /dev/null &')
    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    try:
        for _ in range(100):
            state = ssh(f'if test -f {quote}/ready; then echo ready; elif test -f {quote}/restore-failed; then echo failed; elif test -f {quote}/restored; then echo restored; fi')
            if state.strip() == 'ready':
                break
            if state.strip():
                raise RuntimeError('Window exited before ready: ' + state)
            time.sleep(1)
        else:
            raise RuntimeError('Window not ready')
        for _ in range(30):
            try:
                initial = status()
                break
            except Exception:
                time.sleep(1)
        assert set(initial) == set(config) and all(v == 'unloaded' for v in initial.values()), initial
        report['actual_image'] = ssh("docker inspect noevia-native-qualification --format '{{.Image}}'").strip()

        if args.app_only:
            repo = HERE.parent.parent
            env = {**os.environ, 'NATIVE_QA_BASE': BASE, 'NATIVE_QA_RUN': '1',
                   'NATIVE_QA_EMBED_REFERENCE': '/tmp/noevia-native-embedding-reference.json',
                   'DB_PATH': '/tmp/noevia-native-client-unused/index.db',
                   'PYTHONPATH': str(repo / 'services/diary')}
            def external(command):
                result = subprocess.run(command, cwd=repo, env=env, text=True, capture_output=True, timeout=900)
                if result.returncode:
                    raise RuntimeError(result.stdout + '\n' + result.stderr)
                return {'output': result.stdout}
            check('actual Diary LLMClient and embedding compatibility', lambda: external([
                str(repo / 'services/diary/.venv/bin/python'), str(HERE / 'diary-client.py')]))
            check('actual app HTTP and write approvals', lambda: external(['node', str(repo / 'apps/web/qa/native-live.cjs')]))
            report['status'] = 'passed'
            return

        def text_check(model):
            response = chat(model)
            assert 'NATIVE_OK' in (response['choices'][0]['message']['content'] or ''), response
            assert response['choices'][0]['finish_reason'] == 'stop', response
            props = request('/props?' + urllib.parse.urlencode({'model': model, 'autoload': 'false'}))
            assert props['default_generation_settings']['n_ctx'] == config[model]['ctx-size'], props
            assert props['total_slots'] == 1, props
            states = status()
            assert [m for m, state in states.items() if state == 'loaded'] == [model], states
            return {'response': response, 'context': props['default_generation_settings']['n_ctx'],
                    'slots': props['total_slots'], 'build': props.get('build_info'), 'states': states}

        check('4B MTP chat and context', lambda: text_check(CHAT))

        def tools_check():
            tool = {'type': 'function', 'function': {'name': 'synthetic_lookup', 'description': 'Return the synthetic code for a key.',
                    'parameters': {'type': 'object', 'properties': {'key': {'type': 'string'}}, 'required': ['key']}}}
            result = chat(CHAT, 'Use synthetic_lookup with key test-7429. Do not answer without calling it.', tools=[tool], tool_choice='required')
            calls = result['choices'][0]['message'].get('tool_calls')
            assert calls and calls[0]['function']['name'] == 'synthetic_lookup', result
            assert json.loads(calls[0]['function']['arguments'])['key'] == 'test-7429', result
            return result
        check('structured synthetic tool call', tools_check)

        def cancellation():
            body = {'model': CHAT, 'messages': [{'role': 'user', 'content': 'Count integers from one to one thousand, each on its own line.'}],
                    'stream': True, 'max_tokens': 2048, 'chat_template_kwargs': {'enable_thinking': False}}
            req = urllib.request.Request(BASE + '/v1/chat/completions', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=60) as stream:
                for line in stream:
                    if line.startswith(b'data: ') and b'content' in line:
                        break
            for _ in range(50):
                slots = request('/slots?' + urllib.parse.urlencode({'model': CHAT, 'autoload': 'false'}))
                if all(not s['is_processing'] for s in slots):
                    return {'idle_after_disconnect': True}
                time.sleep(.2)
            raise AssertionError('Generation did not stop after disconnect')
        check('stream cancellation releases slot', cancellation)
        check('post-cancel chat', lambda: text_check(CHAT))

        def long_context():
            def messages(n):
                return [{'role': 'user', 'content': 'Remember the start marker NATIVE-7429.\n' + 'Synthetic context padding with no personal information.\n' * n + '\nReturn only the start marker.'}]
            low, high, best = 0, 5000, None
            while low <= high:
                mid = (low + high) // 2
                rendered = request('/apply-template', {'model': CHAT, 'messages': messages(mid), 'chat_template_kwargs': {'enable_thinking': False}})['prompt']
                count = len(request('/tokenize', {'model': CHAT, 'content': rendered, 'add_special': False})['tokens'])
                if count <= 28672:
                    best = (messages(mid), count)
                    low = mid + 1
                else:
                    high = mid - 1
            assert best and best[1] > 28000
            result = chat(CHAT, messages=best[0], max_tokens=2048)
            assert 'NATIVE-7429' in (result['choices'][0]['message']['content'] or ''), result
            assert result['choices'][0]['finish_reason'] == 'stop', result
            return {'measured_input': best[1], 'reserved_output': 2048, 'result': result}
        check('28k prompt with 2k output reserve', long_context)

        def embed_check():
            result = request('/v1/embeddings', {'model': EMBED, 'input': ['search_query: synthetic amber', 'search_document: synthetic blue']})
            data = sorted(result['data'], key=lambda item: item['index'])
            assert len(data) == 2 and [d['index'] for d in data] == [0, 1]
            assert all(len(d['embedding']) == 768 for d in data), [len(d['embedding']) for d in data]
            assert data[0]['embedding'] != data[1]['embedding']
            assert [m for m, state in status().items() if state == 'loaded'] == [EMBED]
            return {'dimensions': 768, 'ordered_batch': True, 'usage': result.get('usage')}
        check('embedding evicts chat; ordered batch', embed_check)
        check('Diary auxiliary identity reload', lambda: text_check(AUX))
        check('Diary chat identity reload', lambda: text_check(DIARY))

        def vision_check(model):
            result = chat(model, [{'type': 'text', 'text': 'What is the dominant color? Answer with one color word.'},
                                  {'type': 'image_url', 'image_url': {'url': image_fixture()}}])
            assert 'red' in (result['choices'][0]['message']['content'] or '').lower(), result
            return result
        check('Gemma vision projector', lambda: vision_check(DIARY))
        check('Qwen 9B qualified allocation', lambda: text_check(SMART))
        check('Qwen 9B vision at 262k allocation', lambda: vision_check(SMART))
        check('embedding after vision eviction', embed_check)
        check('return to original 4B identity', lambda: text_check(CHAT))
        report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        stop.set()
        thread.join(timeout=20)
        ssh(f'rm -f {quote}/heartbeat')
        for _ in range(240):
            restored = ssh(f'if test -f {quote}/restored; then echo restored; elif test -f {quote}/restore-failed; then echo failed; fi')
            if restored.strip():
                report['restoration'] = restored.strip()
                break
            time.sleep(1)
        else:
            report['restoration'] = 'unconfirmed'
        for name in ('original-health.json', 'restored-health.json', 'memory-kib.log', 'guard-event', 'operations.log', 'supervisor.log'):
            try:
                (local / name).write_text(ssh(f'cat {quote}/{name}'))
            except Exception:
                pass
        memory = local / 'memory-kib.log'
        if memory.exists():
            report['minimum_available_gib'] = min(int(line.split()[1]) for line in memory.read_text().splitlines()) / 1048576
        report['guard_event'] = (local / 'guard-event').read_text().strip() if (local / 'guard-event').exists() else None
        try:
            original = json.loads((local / 'original-health.json').read_text())['all_models_loaded']
            restored = json.loads((local / 'restored-health.json').read_text())['all_models_loaded']
            report['models_restored_exactly'] = all(any(m['model_name'] == old['model_name'] and m['loaded'] and
                all(m['recipe_options'].get(k) == v for k, v in old['recipe_options'].items()) for m in restored) for old in original if old['loaded'])
        except Exception:
            report['models_restored_exactly'] = False
        if report['guard_event'] or report['restoration'] != 'restored' or not report['models_restored_exactly']:
            report['status'] = 'failed'
        save()
        print(json.dumps({k: report.get(k) for k in ('status', 'error', 'restoration', 'models_restored_exactly', 'minimum_available_gib', 'guard_event')}), flush=True)
        print(str(local / 'report.json'), flush=True)


if __name__ == '__main__':
    main()
