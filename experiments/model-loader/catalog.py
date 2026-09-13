"""Summarize remembered trials without treating a successful load as capacity proof."""
import json
import pathlib
import sys


def catalog(root):
    groups = {}
    for path in pathlib.Path(root).glob('*/trial-*.json'):
        trial = json.loads(path.read_text())
        config = trial.get('config', {})
        model = config.get('model')
        if not model:
            continue
        item = groups.setdefault(model, {'profiles': [], 'best_capacity_verified': None})
        context = int(config['ctx-size'])
        accepted = trial.get('accepted_prompt_tokens', 0)
        # Near-capacity tests, with memory margin and complete output, qualify.
        qualified = (trial.get('status') == 'passed' and
                     accepted >= context * .95 and
                     trial.get('minimum_available_gib', 0) >= 4 and
                     not trial.get('guard_events') and
                     trial.get('result', {}).get('choices', [{}])[0].get('finish_reason') == 'stop')
        profile = {'fingerprint': trial.get('fingerprint'), 'record': str(path),
                   'configured_context': context, 'tested_prompt_tokens': accepted,
                   'status': trial.get('status'), 'capacity_verified': qualified,
                   'minimum_available_gib': trial.get('minimum_available_gib'),
                   'config': config, 'scope': trial.get('scope'),
                   'finished_at': trial.get('finished_at')}
        item['profiles'].append(profile)
        current = item['best_capacity_verified']
        if qualified and (not current or context > current['configured_context']):
            item['best_capacity_verified'] = profile
    return {'schema': 1,
            'reuse_rule': 'Match model bytes, backend image, kernel/GPU, cache, context and concurrency fingerprint; recheck available memory before loading.',
            'limits': 'Synthetic text capacity only. Not a guarantee of reasoning quality, image processing, simultaneous sessions or future host contention.',
            'models': groups}


if __name__ == '__main__':
    print(json.dumps(catalog(sys.argv[1]), indent=2))
