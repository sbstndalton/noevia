FROM rust:1.99-slim-bookworm AS front
ENV RUSTUP_TOOLCHAIN=1.99.0 CARGO_TERM_COLOR=never
COPY rs/ /src/
WORKDIR /src
RUN set -e; mkdir -p /out; \
    if [ -f bins/noevia-server/Cargo.toml ]; then \
      features=rust-reasoning-settings,rust-routing-mode; \
      if grep -qx 'rust-project-chats = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-project-chats"; fi; \
      if grep -qx 'rust-free-chats = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-free-chats"; fi; \
      if grep -qx 'rust-project-writes = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-project-writes"; fi; \
      if grep -qx 'rust-routing-default = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-routing-default"; fi; \
      if grep -qx 'rust-stats = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-stats"; fi; \
      if grep -q '^rust-storage-reads = ' bins/noevia-server/Cargo.toml; then features="$features,rust-storage-reads"; fi; \
      if grep -q '^rust-storage-browse = ' bins/noevia-server/Cargo.toml; then features="$features,rust-storage-browse"; fi; \
      if grep -qx 'rust-export = \[\]' bins/noevia-server/Cargo.toml; then features="$features,rust-export"; fi; \
      if grep -q '^rust-chatgpt-status = ' bins/noevia-server/Cargo.toml; then features="$features,rust-chatgpt-status"; fi; \
      cargo build --release --locked -p noevia-server --features "$features"; \
      cp target/release/noevia-server /out/noevia-server; \
      /out/noevia-server 2>&1 | grep -q NOEVIA_LEGACY_UPSTREAM; \
    else \
      echo "noevia-rs in this tree has no bins/noevia-server: the image ships without the Rust front"; \
    fi

