"""Capture only synthetic embedding vectors before the guarded native trial."""
import argparse
import json
import pathlib
import urllib.request

PAIRS = [
    ('The apple orchard harvest produces fruit for cider.', 'Where are apples harvested for cider?'),
    ('The spacecraft launched a satellite into orbit around Earth.', 'How did the satellite reach Earth orbit?'),
    ('The baker mixed flour yeast and water before baking bread.', 'What ingredients did the bread baker mix?'),
    ('The jazz pianist played a concert with drums and saxophone.', 'Which musicians performed jazz together?'),
    ('The bicycle mechanic replaced the chain and repaired the brakes.', 'Who fixed the bicycle brakes and chain?'),
    ('The coral reef supports tropical fish and marine biodiversity.', 'Where do tropical fish live among corals?'),
    ('The software developer fixed a database transaction rollback bug.', 'What software error affected database rollbacks?'),
    ('The hiking trail crosses a mountain ridge to a snowy summit.', 'Where does the mountain hiking trail lead?'),
]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, help='Current production embedding endpoint, without /v1')
    parser.add_argument('--output', default='/tmp/noevia-native-embedding-reference.json')
    args = parser.parse_args()
    inputs = ['search_query: synthetic amber', 'search_document: synthetic blue']
    inputs += ['search_document: ' + p[0] for p in PAIRS]
    inputs += ['search_query: ' + p[1] for p in PAIRS]
    request = urllib.request.Request(args.base.rstrip('/') + '/v1/embeddings',
        data=json.dumps({'model': 'nomic-embed-text-v1-GGUF', 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.load(response)
    assert len(result['data']) == len(inputs)
    result['synthetic_inputs'] = inputs
    pathlib.Path(args.output).write_text(json.dumps(result) + '\n')
    print('Saved 18 synthetic reference vectors; no corpus read or changed.')
