# syntax=docker/dockerfile:1.7
# noevia code-task egress proxy, Rust (#926): `egress-proxy` from sbstndalton/noevia-rs, pinned to
# release/versions.lock's NOEVIA_RS_REF and fetched as an anonymous tarball whose sha256 is checked
# before anything is built (the same pin and checksum as services/model-manager/Dockerfile; CI
# fails if either default differs from the lock). Dark: used only with CODE_EGRESS_IMPL=rust and
# deploy/examples/code-egress-rust.override.yml. See docs/egress-grant-contract.md.
FROM rust:1.99-slim-bookworm AS build
ARG NOEVIA_RS_REF=a6a50ad971339eea7534d9266d887e04a26af384
ARG NOEVIA_RS_SHA256=056ade791458364563b7711ccb53bb604dffff046da96740d4aaa607e5acc676
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never
WORKDIR /src
ADD https://codeload.github.com/sbstndalton/noevia-rs/tar.gz/${NOEVIA_RS_REF} /tmp/noevia-rs.tar.gz
RUN echo "${NOEVIA_RS_SHA256}  /tmp/noevia-rs.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/noevia-rs.tar.gz --strip-components=1 \
 && rm /tmp/noevia-rs.tar.gz \
 && cargo build --release --locked -p egress-proxy \
 && (./target/release/egress-proxy --help 2>&1 || true) | grep -q usage

FROM debian:bookworm-slim
COPY --from=build /src/target/release/egress-proxy /usr/local/bin/egress-proxy
# No shell tools are needed at run time; the proxy runs unprivileged and reads only the grant key
# file from its read-only mount.
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/egress-proxy"]
