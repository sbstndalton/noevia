# syntax=docker/dockerfile:1.7
# noevia code-task egress proxy, Rust (#926): `egress-proxy` from sbstndalton/noevia-rs, pinned to
# release/versions.lock's NOEVIA_RS_REF and fetched as an anonymous tarball whose sha256 is checked
# before anything is built (the same pin and checksum as services/model-manager/Dockerfile; CI
# fails if either default differs from the lock). Dark: used only with CODE_EGRESS_IMPL=rust and
# deploy/examples/code-egress-rust.override.yml. See docs/egress-grant-contract.md.
FROM rust:1.99-slim-bookworm@sha256:2c3a22f0a5533ea2dd5a16627bc841228151faa2d4de2644ac9987e4a2f1f2fa AS build
ARG NOEVIA_RS_REF=3a34a0ed85791e7950a130e96357b9252871d377
ARG NOEVIA_RS_SHA256=b34a692a30f4bff6f199992235e51a032e8e30c2dda1dfd0fae5d47947f782dd
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never CARGO_BUILD_JOBS=2
WORKDIR /src
ADD https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/${NOEVIA_RS_REF} /tmp/noevia-rs.tar.gz
RUN echo "${NOEVIA_RS_SHA256}  /tmp/noevia-rs.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/noevia-rs.tar.gz --strip-components=1 \
 && rm /tmp/noevia-rs.tar.gz \
 && cargo build --release --locked -p egress-proxy \
 && (./target/release/egress-proxy --help 2>&1 || true) | grep -q usage

FROM debian:bookworm-slim AS runtime
COPY --from=build /src/target/release/egress-proxy /usr/local/bin/egress-proxy
# No shell tools are needed at run time; the proxy runs unprivileged and reads only the grant key
# file from its read-only mount.
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/egress-proxy"]

# Explicit native profile: an older globally selected pin must fail the image build rather
# than silently start a legacy grant listener. Metadata is only a source-compatibility gate.
FROM runtime AS native-control
RUN probe="$(/usr/local/bin/egress-proxy --capabilities)" \
 && printf '%s\n' "$probe" | grep -F '"nativeControl":true' \
 && printf '%s\n' "$probe" | grep -F '"noevia-code-egress-control/1"' \
 && printf '%s\n' "$probe" | grep -F '"readiness":"requires-authenticated-ready"'

# Keep the selected release's existing default image and pin smoke check unchanged.
FROM runtime AS release
