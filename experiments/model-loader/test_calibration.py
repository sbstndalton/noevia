import importlib.util
import json
import pathlib
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch


def module(name):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class CalibrationTests(unittest.TestCase):
    def test_failed_candidate_is_logged_and_original_model_restored(self):
        calibrate = module('calibrate')
        original = {'model_name': 'original-model', 'loaded': True, 'type': 'llm',
                    'recipe_options': {'ctx_size': 32768}}
        production = [original]
        calls = []
        def request(base, path, payload=None, timeout=30):
            calls.append((base, path, payload))
            if base == calibrate.PROD:
                if path.endswith('/health'):
                    return {'all_models_loaded': production[:]}
                if path.endswith('/unload'):
                    production.clear()
                    return {}
                if path.endswith('/load'):
                    production.append(original)
                    return {'status': 'success'}
            if path == '/health':
                return {}
            raise RuntimeError('Synthetic candidate load failure')
        class InertMonitor:
            def __init__(self, **kwargs): pass
            def start(self): pass
            def join(self, **kwargs): pass
        with tempfile.TemporaryDirectory() as tmp:
            rec = pathlib.Path(tmp) / 'recommendation.json'
            rec.write_text('{"model":"synthetic.gguf"}')
            args = SimpleNamespace(recommendation=str(rec), results=tmp, context=8192,
                                   gpu_layers=999, cache='q8_0', prompt_tokens=4096, force=False)
            with patch.object(calibrate, 'identity', return_value=('profile', {})), \
                 patch.object(calibrate, 'sample', return_value={'MemAvailable': 12 * 1024**3}), \
                 patch.object(calibrate, 'ssh', return_value=''), \
                 patch.object(calibrate, 'request', side_effect=request), \
                 patch.object(calibrate.threading, 'Thread', InertMonitor), \
                 patch.object(calibrate.subprocess, 'run'):
                with self.assertRaisesRegex(RuntimeError, 'candidate load failure'):
                    calibrate.run(args)
            record = json.loads((pathlib.Path(tmp) / 'profile' / 'trial-4096.json').read_text())
            self.assertEqual(record['status'], 'failed')
            self.assertTrue(record['production_restored'])
            restored = [body for base, route, body in calls if route == '/api/v1/load']
            self.assertEqual(restored, [{'model_name': 'original-model', 'ctx_size': 32768}])

    def test_load_success_is_not_capacity_verification(self):
        catalog = module('catalog')
        with tempfile.TemporaryDirectory() as tmp:
            p = pathlib.Path(tmp) / 'fingerprint'
            p.mkdir()
            row = {'config': {'model': '/models/gemma.gguf', 'ctx-size': '131072'},
                   'status': 'passed', 'accepted_prompt_tokens': 4096,
                   'minimum_available_gib': 8,
                   'result': {'choices': [{'finish_reason': 'stop'}]}}
            (p / 'trial-4096.json').write_text(json.dumps(row))
            self.assertIsNone(catalog.catalog(tmp)['models']['/models/gemma.gguf']['best_capacity_verified'])
            row['accepted_prompt_tokens'] = 128000
            (p / 'trial-128000.json').write_text(json.dumps(row))
            result = catalog.catalog(tmp)['models']['/models/gemma.gguf']['best_capacity_verified']
            self.assertEqual(result['configured_context'], 131072)

    def test_low_headroom_and_truncated_outputs_do_not_qualify(self):
        catalog = module('catalog')
        for headroom, finish in [(3, 'stop'), (8, 'length')]:
            with tempfile.TemporaryDirectory() as tmp:
                p = pathlib.Path(tmp) / 'fingerprint'
                p.mkdir()
                row = {'config': {'model': '/models/qwen.gguf', 'ctx-size': '262144'},
                       'status': 'passed', 'accepted_prompt_tokens': 260000,
                       'minimum_available_gib': headroom,
                       'result': {'choices': [{'finish_reason': finish}]}}
                (p / 'trial-260000.json').write_text(json.dumps(row))
                self.assertIsNone(catalog.catalog(tmp)['models']['/models/qwen.gguf']['best_capacity_verified'])

    def test_model_and_backend_changes_invalidate_identity(self):
        calibrate = module('calibrate')
        with patch.object(calibrate, 'ssh', return_value='modelhash backendhash hardware'):
            a, _ = calibrate.identity({'model': 'gemma', 'ctx-size': '131072'})
            b, _ = calibrate.identity({'model': 'qwen', 'ctx-size': '131072'})
            c, _ = calibrate.identity({'model': 'gemma', 'ctx-size': '8192'})
        with patch.object(calibrate, 'ssh', return_value='modelhash NEWBACKEND hardware'):
            d, _ = calibrate.identity({'model': 'gemma', 'ctx-size': '131072'})
        self.assertEqual(len({a, b, c, d}), 4)

    def test_prompt_sizing_counts_template_and_leaves_reserve(self):
        calibrate = module('calibrate')
        def request(base, path, payload):
            if path == '/apply-template':
                return {'prompt': 'TEMPLATE ' + payload['messages'][0]['content'] + ' END'}
            return {'tokens': list(range(len(payload['content'].split())))}
        with patch.object(calibrate, 'request', side_effect=request):
            _, count = calibrate.prompt_for(1000)
            self.assertGreater(count, 980)
            self.assertLessEqual(count, 1000)


if __name__ == '__main__':
    unittest.main()
