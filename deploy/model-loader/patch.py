"""Build-time patches for noevia.

1. Serve bundled browser libraries instead of CDN copies.
2. Accept llama.cpp preset files that start with top-level keys (`version = 1`) before the
   first section. Python's configparser rejects them, and Model Loader rewrites the whole
   file on save, so the preamble is captured on read and written back unchanged.

Fails the build if an expected line is missing, so an upstream change cannot silently
reintroduce a third-party script or drop the preamble handling.
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

ini = Path('/srv/app/ini.py')
text = ini.read_text()
old_read = """    cp = _new_parser()
    if settings.models_ini_path.exists():
        cp.read(settings.models_ini_path, encoding="utf-8")
    return cp"""
new_read = """    cp = _new_parser()
    cp._noevia_preamble = ""
    if settings.models_ini_path.exists():
        # noevia: keep top-level keys such as `version = 1` that precede the first section.
        lines = settings.models_ini_path.read_text(encoding="utf-8").splitlines(keepends=True)
        first = next((i for i, line in enumerate(lines) if line.lstrip().startswith("[")), len(lines))
        cp._noevia_preamble = "".join(lines[:first])
        cp.read_string("".join(lines[first:]), source=str(settings.models_ini_path))
    return cp"""
old_write = """    text = buf.getvalue()

    tmp = path.with_suffix(path.suffix + ".tmp")"""
new_write = """    preamble = getattr(cp, "_noevia_preamble", "")
    if preamble and not preamble.endswith("\\n"):
        preamble += "\\n"
    text = preamble + buf.getvalue()

    tmp = path.with_suffix(path.suffix + ".tmp")"""
for old, new in ((old_read, new_read), (old_write, new_write)):
    if text.count(old) != 1:
        raise SystemExit(f'ini.py: expected exactly one {old.splitlines()[0]!r}')
    text = text.replace(old, new)
ini.write_text(text)
