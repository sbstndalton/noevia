# release/

`versions.lock` pins the repos a release is assembled from (see its header and `docs/repo-split-cutover.md`).

**Optional `NOEVIA_SERVICES_RS_REF` / `NOEVIA_SERVICES_RS_SHA256`**: the noevia-rs commit (40-hex) and tarball checksum (64-hex) the pinned Services tree's sidecar Dockerfiles were built against. Absent means "same as `NOEVIA_RS_REF` / `NOEVIA_RS_SHA256`" (the default, and every older lock).
Use them only for a release that moves the web Rust pin and leaves `NOEVIA_SERVICES_REF` unchanged, so no sidecar image is rebuilt. CI then compares the assembled `services/*/Dockerfile` pins with these keys (`deploy/egress-proxy/Dockerfile` and the web image still follow `NOEVIA_RS_REF`).
CI fails if the keys equal the main rs keys (remove them), if only one is set, or if `NOEVIA_SERVICES_REF` differs from the lock on the PR's base branch.
The release that next moves `NOEVIA_SERVICES_REF` must remove both keys and bump the Services Dockerfiles to `NOEVIA_RS_REF`. Never build a sidecar image from the lock's rs keys while these are set; sidecar builds read the Dockerfile's own pin.
Check: `deploy/tools/check-services-rs-pins.sh <assembled-tree> release/versions.lock [<base-lock>]`; tests: `deploy/tools/test-check-services-rs-pins.sh`.
