# Pinned backend under Lemonade — isolated candidate

This tests the existing Lemonade manager image with llama.cpp b10920 selected by
its supported backend-version setting. It is not a production provider switch.
The manager image is pinned by digest; record the downloaded engine's version and
hash before comparing results. A release tag alone is not an immutable binary ID.

The test has a separate cache, only the existing public Gemma model directory
mounted read-only, and host port 127.0.0.1:8083. No production cache, credentials,
Docker socket or noevia configuration is shared. It has no automatic restart.
The engine may download from the official ggml-org release when first requested.

Do not run model inference concurrently with another shared-GPU test or production
chat model. Snapshot the production model/options, verify processing/deferred
requests are zero, unload only for the controlled test, enforce the 4 GiB host-memory
reserve and stop if production resumes. Stop the candidate and restore the original
production model/options afterward. Never save new production options for this.
Use the installed Unraid preflight wrapper for Compose up; the candidate's writable
cache must resolve to the intended data disk. Check port 8083 is unused first.

The current standalone llama.cpp image uses glibc 2.43, while this manager image
has glibc 2.39. Copying its binaries blindly into the manager is not a qualified
upgrade. This candidate uses Lemonade's release download path; actual library
compatibility still needs verification before any model load.

Acceptance: backend version/library startup; model discovery; one-slot context
reporting; synthetic short text/tools/vision where claimed; unload/reload and
restoration. Compare full configuration fingerprints with the direct tests.
A successful manager startup is not a capacity or speed result. Do not transfer
an earlier profile across a different binary build without checking its identity.
See ../../docs/spec-backend-portability.md for source evidence and remaining gates.
