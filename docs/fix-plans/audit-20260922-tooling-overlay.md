# Remove stale overlay code and repair repo-index regressions

Implemented for review; not merged or deployed. Issues: [#12](https://github.com/sbstndalton/noevia/issues/12), [#13](https://github.com/sbstndalton/noevia/issues/13).

Repo-index regressions now target `server/toolboxes.cjs` and assert the documented top-level declaration contract: the nested `toolTokenBudgetFor` helper belongs to the enclosing `createToolboxes` factory. A small nested-function fixture protects this behavior, and the README reflects the split server layout.

Overlay image cleanup now removes every application-owned top-level entry recursively before copying the new server tree. It preserves inherited `server/node_modules` and the `server/ui-data` runtime mount point. This removes old nested routes/modules without changing flattening, config comparison, rollback, health waits, sidecar handling or native-engine checks.

Validation: 9 repo-index tests pass; deployment tests pass (5 passed, 9 environment-dependent rclone/flock skips), plus the preflight wrapper test and shell syntax check. The filesystem regression executes the exact Dockerfile cleanup command against synthetic OLD/NEW trees and verifies retired nested files and symlinks disappear while dependency files, runtime data and external symlink targets survive. 1,247 web tests, typecheck, production build and design lint pass.

Limits: no Docker image build or production release was run. Docker and PHP preflight execution are unavailable locally; filesystem semantics and the Python wrapper were tested.
