"""Build-time patch: serve bundled browser libraries instead of CDN copies.

Fails the build if an expected tag is missing, so an upstream change cannot silently
reintroduce a third-party script.
"""
from pathlib import Path

templates = Path('/srv/app/templates')
swaps = {
    'base.html': [
        ('<script src="https://cdn.tailwindcss.com"></script>', '<script src="/_vendor/tailwind.js"></script>'),
        ('<script src="https://unpkg.com/htmx.org@2.0.4"></script>', '<script src="/_vendor/htmx.min.js"></script>'),
        ('<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.14.8/dist/cdn.min.js"></script>', '<script defer src="/_vendor/alpine.min.js"></script>'),
    ],
    'benchmark.html': [
        ('<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>', '<script src="/_vendor/chart.umd.min.js"></script>'),
    ],
}
for name, pairs in swaps.items():
    path = templates / name
    text = path.read_text()
    for old, new in pairs:
        if text.count(old) != 1:
            raise SystemExit(f'{name}: expected exactly one {old!r}')
        text = text.replace(old, new)
    path.write_text(text)
for path in templates.rglob('*.html'):
    for host in ('cdn.tailwindcss.com', 'unpkg.com', 'cdn.jsdelivr.net', 'cdnjs.cloudflare.com'):
        if host in path.read_text():
            raise SystemExit(f'{path.name} still references {host}')

main = Path('/srv/app/main.py')
main.write_text(main.read_text() + '\n\n# noevia: bundled browser libraries.\nfrom fastapi.staticfiles import StaticFiles as _NoeviaStatic\napp.mount("/_vendor", _NoeviaStatic(directory="/srv/vendor"), name="noevia-vendor")\n')
