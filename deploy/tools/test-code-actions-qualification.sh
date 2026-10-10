#!/usr/bin/env bash
# Own-repo guard: do not depend on an unmerged companion core checkout.
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$here/build/web.Dockerfile" "$here/.github/workflows/ci.yml" <<'PYGUARD'
import sys
from pathlib import Path
import re
s=Path(sys.argv[1]).read_text()
bulk='node --test --test-timeout=120000 tests/client/*.test.cjs tests/server/*.test.cjs'
phase='node --test --test-concurrency=1 tests/server/code-actions-performance.qualification.cjs'
assert s.count(phase)==1,'mandatory isolated performance qualification missing/duplicated'
assert s.index(bulk)<s.index(phase)<s.index('npm run build &&'),'qualification must follow full suite before build'
assert s.index('COPY --from=front /out/ /tmp/qualified-front/')<s.index(bulk),'Rust front compilation must finish before full suite/qualification'
assert 'export STAMP_VERSION="$NOEVIA_SHA" DAV_PARSE_WASM_REQUIRED=1' in s
workflow=Path(sys.argv[2]).read_text()
job=workflow.split('  deploy-tests:',1)[1]
checkout=re.search(r"- uses: actions/checkout@v4\n        if: ([^\n]+)",job)
guard=re.search(r"- run: bash deploy/tools/test-code-actions-qualification.sh\n        if: ([^\n]+)",job)
assert checkout and guard and checkout.group(1)==guard.group(1)=="env.RUN_JOB == 'true'",'guard condition must match required checkout condition'
assert "- 'deploy/**'" in workflow and "- 'build/**'" in workflow and "- '.github/workflows/**'" in workflow,'qualification changes must trigger deploy job'
print('full-image qualification and checkout/guard condition parity verified')
PYGUARD
