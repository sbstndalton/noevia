#!/usr/bin/env bash
# Own-repo guard: do not depend on an unmerged companion core checkout.
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$here/build/web.Dockerfile" <<'PYGUARD'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
bulk='node --test --test-timeout=120000 tests/client/*.test.cjs tests/server/*.test.cjs'
phase='node --test --test-concurrency=1 tests/server/code-actions-performance.qualification.cjs'
assert s.count(phase)==1,'mandatory isolated performance qualification missing/duplicated'
assert s.index(bulk)<s.index(phase)<s.index('npm run build &&'),'qualification must follow full suite before build'
assert s.index('COPY --from=front /out/ /tmp/qualified-front/')<s.index(bulk),'Rust front compilation must finish before full suite/qualification'
assert 'export STAMP_VERSION="$NOEVIA_SHA" DAV_PARSE_WASM_REQUIRED=1' in s
print('full-image sequential qualification invocation verified')
PYGUARD
