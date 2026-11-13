#!/usr/bin/env python3
"""R10 deletion graph: what Node code can be deleted only after what. Read-only; git objects only.

Usage:
  python3 -I tools/removal/deletion-graph.py ~/noevia-work/noevia-core origin/main [--prod-only] [--with-tests]
      [--open-pr-files FILE] [--also ~/noevia-work/noevia --also ~/noevia-work/noevia-rs ...]

Edges: relative require('./x') / import('./x') / from './x' in each .cjs/.js/.mjs/.json file under
server/ and code-sandbox/ (plus tests/ with --with-tests). Unresolvable requires are listed, not guessed.

Output sections:
  1. Roots and reachability (required files only).
  2. Removal layers: a file moves only when every file that requires it has moved.
  3. Cycle group: files that must be removed together.
  4. String references: for each file NOT reachable from a root, every other tracked file at REF whose
     text contains the file's basename. A require graph misses path strings (the sandbox Dockerfile copies
     verifier.cjs by name, spawn(... 'supervisor.cjs') in tests, shell scripts, workflows). A file with any
     string reference is not deletable yet.
  5. Deletable now: unreachable, no string reference outside itself, not a manifest or data file, not in
     --open-pr-files (paths touched by open pull requests, one per line), not in a cycle.
The deletable list is a candidate list for a human review, not an instruction to delete.
"""
import os, re, subprocess, sys

def opt_values(name):
    return [sys.argv[i + 1] for i, a in enumerate(sys.argv[:-1]) if a == name]


ALSO = opt_values("--also")
OPEN_PR_FILES = opt_values("--open-pr-files")
_skip = set(ALSO) | set(OPEN_PR_FILES)
args = [a for a in sys.argv[1:] if not a.startswith("--") and a not in _skip]
REPO, REF = args[0], args[1]
PROD_ONLY = "--prod-only" in sys.argv
WITH_TESTS = "--with-tests" in sys.argv
OPEN_PR_FILE = OPEN_PR_FILES[0] if OPEN_PR_FILES else None
SCOPE = ["server", "code-sandbox"] + (["tests"] if WITH_TESTS else [])
# Entry points that production starts directly (Dockerfile CMD / supervisor / compose / web-supervisor.sh).
ROOTS = ["server/index.cjs", "code-sandbox/supervisor.cjs", "code-sandbox/pi-acp-bridge.cjs",
         "code-sandbox/sandbox-bridge-wasm.cjs", "server/mcp-internal.cjs"]
EXT = (".cjs", ".js", ".mjs", ".json")
IS_TEST = re.compile(r"(\.test\.cjs$|\.test\.js$|/tests?/|/qualif|-oracle\.cjs$|\.probe\.cjs$)")
MANIFEST = re.compile(r"(^|/)(package(-lock)?\.json|feature-catalog\.json)$|\.json$")
REQ = re.compile(r"""(?:require|import)\s*\(\s*['"](\.{1,2}/[^'"]+)['"]\s*\)|from\s+['"](\.{1,2}/[^'"]+)['"]""")
DYN = re.compile(r"require\(\s*[^'\"\s)]")


def git(*a, inp=None):
    return subprocess.run(["git", "-C", REPO, *a], check=True, capture_output=True, input=inp).stdout


files = git("ls-tree", "-r", "--name-only", REF, "--", *SCOPE).decode().split()
files = [f for f in files if f.endswith(EXT)]
if PROD_ONLY:
    files = [f for f in files if not IS_TEST.search(f)]
fileset = set(files)

blob_req = "".join(f"{REF}:{f}\n" for f in files).encode()
out = git("cat-file", "--batch", inp=blob_req)
src, pos = {}, 0
for f in files:
    nl = out.index(b"\n", pos)
    size = int(out[pos:nl].decode().split()[2])
    src[f] = out[nl + 1: nl + 1 + size].decode("utf-8", "replace")
    pos = nl + 1 + size + 1


def resolve(base_dir, spec):
    p = os.path.normpath(os.path.join(base_dir, spec))
    cands = [p] + [p + e for e in EXT] + [os.path.join(p, "index.cjs"), os.path.join(p, "index.js")]
    for c in cands:
        if c in fileset:
            return c
    return None


edges, unresolved, dyn = {}, [], {}
for f in files:
    outs = set()
    for m in REQ.finditer(src[f]):
        spec = m.group(1) or m.group(2)
        t = resolve(os.path.dirname(f), spec)
        if t is None:
            unresolved.append((f, spec))
        elif t != f:
            outs.add(t)
    edges[f] = outs
    dyn[f] = len(DYN.findall(src[f]))

importers = {f: set() for f in files}
for f, outs in edges.items():
    for t in outs:
        importers[t].add(f)

reach, stack = set(), [r for r in ROOTS if r in fileset]
while stack:
    f = stack.pop()
    if f in reach:
        continue
    reach.add(f)
    stack.extend(edges.get(f, ()))
unreach = sorted(f for f in files if f not in reach)

remaining_imp = {f: set(importers[f]) for f in files}
removed, layers = set(), []
while True:
    ready = sorted(f for f in files if f not in removed and remaining_imp[f] <= removed)
    if not ready:
        break
    layers.append(ready)
    removed.update(ready)
cyclic = sorted(f for f in files if f not in removed)

lines_of = {f: src[f].count("\n") + (0 if src[f].endswith("\n") or not src[f] else 1) for f in files}

# String references across every tracked text file at REF (one git grep per unreachable basename batch).
all_tracked = git("ls-tree", "-r", "--name-only", REF).decode().split()
text_ok = (".cjs", ".js", ".mjs", ".json", ".sh", ".py", ".rs", ".toml", ".yml", ".yaml", ".md", ".ts", ".tsx",
           ".txt", ".conf", "Dockerfile", ".env", ".example")
text_files = [p for p in all_tracked if p.endswith(text_ok) or os.path.basename(p) in ("Dockerfile", "Makefile")]
blob_req = "".join(f"{REF}:{p}\n" for p in text_files).encode()
bo = git("cat-file", "--batch", inp=blob_req)
text = {}
pos = 0
for p in text_files:
    nl = bo.index(b"\n", pos)
    head = bo[pos:nl].decode().split()
    if len(head) < 3 or head[1] != "blob":
        pos = nl + 1
        continue
    size = int(head[2])
    text[p] = bo[nl + 1: nl + 1 + size].decode("utf-8", "replace")
    pos = nl + 1 + size + 1

# Other repos (--also DIR): release scripts, Rust pairing constants and workflows read these names too.
# A basename found there is a string reference, reported as DIR-name:path.
for extra in ALSO:
    name = os.path.basename(os.path.normpath(extra))
    ls = subprocess.run(["git", "-C", extra, "ls-tree", "-r", "--name-only", REF], check=True,
                        capture_output=True).stdout.decode().split()
    ex = [p for p in ls if p.endswith(text_ok) or os.path.basename(p) in ("Dockerfile", "Makefile")]
    req = "".join(f"{REF}:{p}\n" for p in ex).encode()
    eo = subprocess.run(["git", "-C", extra, "cat-file", "--batch"], input=req, check=True, capture_output=True).stdout
    q = 0
    for p in ex:
        nl = eo.index(b"\n", q)
        head = eo[q:nl].decode().split()
        if len(head) < 3 or head[1] != "blob":
            q = nl + 1
            continue
        size = int(head[2])
        text[f"{name}:{p}"] = eo[nl + 1: nl + 1 + size].decode("utf-8", "replace")
        q = nl + 1 + size + 1


def string_refs(f):
    base = os.path.basename(f)
    hits = []
    for p, t in text.items():
        if p == f:
            continue
        if base in t:
            hits.append(p)
    return hits


open_pr = set()
if OPEN_PR_FILE:
    with open(OPEN_PR_FILE) as fh:
        open_pr = {l.strip() for l in fh if l.strip()}

print(f"# R10 deletion graph  repo={REPO} ref={REF} scope={','.join(SCOPE)} prod_only={PROD_ONLY}")
print(f"files={len(files)} lines={sum(lines_of.values())} edges={sum(len(v) for v in edges.values())}")
print(f"roots present={[r for r in ROOTS if r in fileset]}")
print(f"reachable from roots={len(reach)} lines={sum(lines_of[f] for f in reach)}")
print(f"unreachable from roots={len(unreach)} lines={sum(lines_of[f] for f in unreach)}")
print(f"unresolved relative requires={len(unresolved)} dynamic require sites={sum(dyn.values())}")
print()
print("## 1. Unreachable from roots (dead candidates)")
for f in unreach:
    print(f"  {lines_of[f]:6d}  {f}")
print()
print("## 2. Removal layers (delete layer 1 first; a file moves only when every importer is already gone)")
for i, layer in enumerate(layers, 1):
    print(f"layer {i}: {len(layer)} files, {sum(lines_of[f] for f in layer)} lines")
    for f in layer:
        print(f"  {lines_of[f]:6d}  {f}")
print()
print("## 3. Cycle group (must be removed together, in one step)")
print(f"files={len(cyclic)} lines={sum(lines_of[f] for f in cyclic)}")
for f in cyclic:
    print(f"  {lines_of[f]:6d}  {f}  <- importers still present: {sorted(importers[f] - removed)[:6]}")
print()
print("## 4. String references to unreachable files (path or basename in other tracked files)")
refs = {f: string_refs(f) for f in unreach}
for f in unreach:
    r = refs[f]
    print(f"  {f}: {len(r)} -> {', '.join(r[:5])}{' ...' if len(r) > 5 else ''}")
print()
print("## 5. Deletable now (candidates for review; unreachable, no string reference, not a manifest, not in an open PR, not in a cycle)")
deletable = []
for f in unreach:
    # Tests, fixtures and oracles are not candidates here: they retire with the fixture freeze (R10-1).
    if refs[f] or MANIFEST.search(f) or f in open_pr or f in cyclic or IS_TEST.search(f):
        continue
    deletable.append(f)
print(f"count={len(deletable)} lines={sum(lines_of[f] for f in deletable)}")
for f in deletable:
    print(f"  {lines_of[f]:6d}  {f}")
print()
print("## 6. Unreachable but kept (reason)")
for f in unreach:
    if f in deletable:
        continue
    why = []
    if refs[f]:
        why.append("string refs")
    if MANIFEST.search(f):
        why.append("manifest/data")
    if f in open_pr:
        why.append("open PR")
    if f in cyclic:
        why.append("cycle")
    print(f"  {lines_of[f]:6d}  {f}  [{', '.join(why) or 'other'}]")
print()
print("## 7. Unresolved relative requires (read by hand)")
for f, s in unresolved[:60]:
    print(f"  {f}: {s}")
