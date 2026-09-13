"""Bounded, synthetic context calibration for the isolated DaServer test stack.

Never changes noevia providers or saved Lemonade options. Requires an explicitly
started maintenance experiment; ordinary production chat must be idle.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import signal
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

HOST = 'root@10.69.0.130'
ROOT = '/mnt/docker/appdata/model-loader-test'
TEST = 'http://10.69.0.130:8082'
PROD = 'http://10.69.0.130:13305'
MODEL = 'qwen35-9b-test'
PROD_MODEL = 'Qwen3.5-9B-GGUF-UD-Q4_K_XL'


def stamp():
    return datetime.now(timezone.utc).isoformat()


def ssh(command, data=None, timeout=45):
    return subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', HOST, command],
                          input=data, text=True, capture_output=True, timeout=timeout, check=True).stdout


def request(base, path, payload=None, timeout=30):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base + path, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'HTTP {exc.code}: {exc.read(4096).decode(errors="replace")}') from exc


def atomic_json(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def identity(config):
    evidence = ssh(
        f'cat {ROOT}/results/model-sha256.txt; '
        'docker image inspect ghcr.io/ggml-org/llama.cpp:server-vulkan --format "{{.Id}}"; '
        'uname -r; cat /sys/class/drm/card1/device/vendor /sys/class/drm/card1/device/device; '
        'head -1 /proc/meminfo')
    material = {'hardware_model_backend': evidence, 'config': config,
                'workload_version': 1, 'memory_floor_gib': 4}
    return hashlib.sha256(json.dumps(material, sort_keys=True).encode()).hexdigest(), material


def sample():
    output = ssh('cat /proc/meminfo; '
                 'cat /sys/class/drm/card1/device/mem_info_vram_used '
                 '/sys/class/drm/card1/device/mem_info_gtt_used; '
                 'docker inspect llama-vulkan-test --format "{{json .State}}"')
    lines = output.splitlines()
    memory = {line.split(':')[0]: int(line.split()[1]) * 1024
              for line in lines if line.startswith(('MemAvailable:', 'MemTotal:'))}
    memory.update(time=stamp(), vram_used=int(lines[-3]), gtt_used=int(lines[-2]), state=json.loads(lines[-1]))
    return memory


def prompt_for(target):
    # A synthetic capacity/recall check, not a language-quality benchmark.
    def make(repeats):
        return [{'role': 'user', 'content':
                 'Remember the start marker: CONTEXT-7429.\n' +
                 ('This is synthetic padding for a context allocation validation.\n' * repeats) +
                 '\nReturn only the start marker.'}]
    low, high = 0, target
    best = None
    while low <= high:
        mid = (low + high) // 2
        messages = make(mid)
        rendered = request(TEST, '/apply-template', {'model': MODEL, 'messages': messages,
                            'chat_template_kwargs': {'enable_thinking': False}})['prompt']
        count = len(request(TEST, '/tokenize', {'model': MODEL, 'content': rendered,
                                               'add_special': False})['tokens'])
        if count <= target:
            best = (messages, count)
            low = mid + 1
        else:
            high = mid - 1
    if best is None:
        raise ValueError('Target too small for the chat template')
    return best


def run(args):
    config = json.loads(pathlib.Path(args.recommendation).read_text())
    config.update({'ctx-size': str(args.context), 'ngl': str(args.gpu_layers),
                   'cache-type-k': args.cache, 'cache-type-v': args.cache,
                   'parallel': '1', 'cache-ram': '1024'})
    # Automatic cache-RAM sizing assumes discrete VRAM; bound it on this shared-RAM host.
    config.pop('cache-reuse', None)  # llama.cpp explicitly disables it for multimodal models.
    key, evidence = identity(config)
    directory = pathlib.Path(args.results) / key
    directory.mkdir(parents=True, exist_ok=True)
    record_path = directory / f'trial-{args.prompt_tokens}.json'
    record = {'started_at': stamp(), 'fingerprint': key, 'identity': evidence,
              'requested_prompt_tokens': args.prompt_tokens, 'status': 'running', 'stage': 'preparation',
              'scope': 'text-only, one slot, synthetic repeated padding and start-marker recall',
              'config': config}
    if record_path.exists():
        old = json.loads(record_path.read_text())
        if old.get('status') == 'passed' and not args.force:
            print(json.dumps({'reused_verified_record': str(record_path), 'record': old}), flush=True)
            return
        # Preserve failed/interrupted records instead of erasing evidence on retry.
        record_path.rename(directory / f'trial-{args.prompt_tokens}-{time.time_ns()}.json')
    original_health = request(PROD, '/api/v1/health')
    original_models = [m for m in original_health.get('all_models_loaded', []) if m.get('loaded') and m.get('type') == 'llm']
    record['original_models'] = original_models
    atomic_json(record_path, record)
    done = threading.Event()
    problems = []
    telemetry_path = directory / f'telemetry-{time.time_ns()}.jsonl'
    monitor = None

    def watch():
        errors = 0
        while not done.is_set():
            try:
                current = sample()
                health = request(PROD, '/api/v1/health')
                current['production_llm_loaded'] = [m.get('model_name') for m in health.get('all_models_loaded', [])
                                                    if m.get('type') == 'llm' and m.get('loaded')]
                with telemetry_path.open('a') as stream:
                    stream.write(json.dumps(current) + '\n')
                errors = 0
                reason = None
                if current['MemAvailable'] < 4 * 1024 ** 3:
                    reason = 'Host available memory fell below the 4 GiB reserve'
                elif current['production_llm_loaded']:
                    reason = 'Production loaded a chat model; test stopped to avoid contention'
                elif current['state'].get('OOMKilled'):
                    reason = 'Test container was OOM killed'
                if reason:
                    problems.append(reason)
                    ssh('docker stop -t 5 llama-vulkan-test')
                    return
            except Exception as exc:
                errors += 1
                if errors >= 3:
                    problems.append('Telemetry unavailable on three checks: ' + str(exc))
                    try:
                        ssh('docker stop -t 5 llama-vulkan-test')
                    except Exception as stop_error:
                        problems.append('Could not stop test: ' + str(stop_error))
                    return
            done.wait(5)

    try:
        initial = sample()
        record['initial_memory'] = initial
        for original in original_models:
            request(PROD, '/api/v1/unload', {'model_name': original['model_name']}, timeout=120)
        ssh('docker stop -t 10 llama-vulkan-test')
        record['previous_test_preset'] = ssh(f'cat {ROOT}/config/models.ini')
        atomic_json(record_path, record)
        ini = '[' + MODEL + ']\n' + '\n'.join(f'{k} = {v}' for k, v in config.items() if v) + '\n'
        ssh(f'cat > {ROOT}/config/models.ini.next && mv {ROOT}/config/models.ini.next {ROOT}/config/models.ini', data=ini)
        ssh('docker start llama-vulkan-test')
        for _ in range(30):
            try:
                request(TEST, '/health', timeout=2)
                break
            except Exception:
                time.sleep(1)
        else:
            raise RuntimeError('Test router did not become healthy')
        monitor = threading.Thread(target=watch, daemon=True)
        monitor.start()
        record['stage'] = 'load'
        atomic_json(record_path, record)
        began = time.monotonic()
        warmup = request(TEST, '/v1/chat/completions', {'model': MODEL,
                         'messages': [{'role': 'user', 'content': 'Reply with OK.'}],
                         'max_tokens': 8, 'chat_template_kwargs': {'enable_thinking': False}}, timeout=180)
        record['load_and_warmup_seconds'] = time.monotonic() - began
        record['warmup'] = warmup
        props = request(TEST, '/props?model=' + MODEL)
        record['reported_context'] = props['default_generation_settings']['n_ctx']
        record['slots'] = props['total_slots']
        if record['reported_context'] != args.context or record['slots'] != 1:
            raise RuntimeError('Runtime allocation does not match requested profile')
        record['status'] = 'loaded'
        atomic_json(record_path, record)
        print(f'Loaded context {args.context}; constructing measured prompt', flush=True)
        messages, count = prompt_for(args.prompt_tokens)
        record['stage'] = 'near-capacity-prompt'
        record['templated_prompt_tokens'] = count
        atomic_json(record_path, record)
        print(f'Testing {count} templated tokens against {args.context} capacity', flush=True)
        began = time.monotonic()
        result = request(TEST, '/v1/chat/completions', {'model': MODEL, 'messages': messages,
                         'max_tokens': 64, 'temperature': 0, 'cache_prompt': False,
                         'chat_template_kwargs': {'enable_thinking': False}}, timeout=7200)
        record['request_seconds'] = time.monotonic() - began
        record['result'] = result
        record['marker_recalled'] = 'CONTEXT-7429' in (result['choices'][0]['message'].get('content') or '')
        record['accepted_prompt_tokens'] = result['usage']['prompt_tokens']
        record['status'] = 'passed' if (record['marker_recalled'] and not problems and
                                       record['accepted_prompt_tokens'] >= count - 8 and
                                       result['choices'][0].get('finish_reason') == 'stop') else 'failed'
    except BaseException as exc:
        record['status'] = 'interrupted' if isinstance(exc, (KeyboardInterrupt, SystemExit)) else 'failed'
        record['error'] = str(exc)
        raise
    finally:
        done.set()
        if monitor:
            monitor.join(timeout=45)
        record['guard_events'] = problems
        if problems and record['status'] == 'passed':
            record['status'] = 'failed'
        record['finished_at'] = stamp()
        record['telemetry_file'] = str(telemetry_path)
        if telemetry_path.exists():
            samples = [json.loads(line) for line in telemetry_path.read_text().splitlines()]
            if samples:
                record['minimum_available_gib'] = min(x['MemAvailable'] for x in samples) / 1024 ** 3
                record['peak_gpu_allocated_gib'] = max(x['vram_used'] + x['gtt_used'] for x in samples) / 1024 ** 3
        try:
            ssh(f'docker logs llama-vulkan-test > {ROOT}/results/last-calibration.log 2>&1; docker stop -t 10 llama-vulkan-test')
            now = request(PROD, '/api/v1/health')
            if any(m.get('loaded') and m.get('type') == 'llm' for m in now.get('all_models_loaded', [])):
                record['restore_skipped_active_production'] = True
            else:
                record['production_restore'] = [request(PROD, '/api/v1/load', {'model_name': m['model_name'], **m.get('recipe_options', {})}, timeout=180) for m in original_models]
            health = request(PROD, '/api/v1/health')
            record['production_restored'] = all(any(m.get('model_name') == original['model_name'] and m.get('loaded') and all(m.get('recipe_options', {}).get(k) == v for k, v in original.get('recipe_options', {}).items()) for m in health.get('all_models_loaded', [])) for original in original_models)
        except Exception as exc:
            record['restore_error'] = str(exc)
        atomic_json(record_path, record)
        try:
            ssh(f'mkdir -p {ROOT}/results/calibration/{key}')
            subprocess.run(['scp', str(record_path), str(telemetry_path),
                            f'{HOST}:{ROOT}/results/calibration/{key}/'], check=True, capture_output=True)
        except Exception as exc:
            record['remote_copy_error'] = str(exc)
            atomic_json(record_path, record)
        print(json.dumps({'record': str(record_path), 'status': record['status'],
                          'production_restored': record.get('production_restored'),
                          'error': record.get('error'), 'guard_events': problems}), flush=True)


if __name__ == '__main__':
    def terminate(signum, frame):
        raise SystemExit('Calibration interrupted; restoring production')
    signal.signal(signal.SIGTERM, terminate)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recommendation', required=True)
    parser.add_argument('--results', required=True)
    parser.add_argument('--context', type=int, required=True)
    parser.add_argument('--prompt-tokens', type=int, required=True)
    parser.add_argument('--gpu-layers', type=int, default=999)
    parser.add_argument('--cache', choices=['q8_0', 'q4_0'], default='q8_0')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--test-model', default=MODEL)
    parser.add_argument('--native-context', type=int, default=262144)
    args = parser.parse_args()
    MODEL = args.test_model
    if not 1024 <= args.prompt_tokens <= args.context - 128 or args.context > args.native_context:
        parser.error('Prompt must leave 128 tokens headroom; context must not exceed native 262144')
    run(args)
