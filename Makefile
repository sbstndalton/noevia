.PHONY: test test-deploy assemble compose-check

# The client, server and sidecar tests live with their code since the repo split (#952):
# sbstndalton/noevia-web, noevia-core and noevia-services each run them in their own CI.
test: test-deploy

# Deploy tooling: the shell and wrapper tests CI runs, plus the unittest suites under deploy/tests
# (rclone/flock-dependent cases skip themselves when those are absent) and the PHP preflight test
# when php is installed.
test-deploy:
	python3 -m unittest discover -s deploy/tests -p 'test_*.py'
	python3 deploy/preflight/test_wrapper.py
	python3 deploy/nextcloud/test_repair_push.py
	bash deploy/tools/test-build-web-release.sh
	bash deploy/tools/test-assemble-release.sh
	bash deploy/tools/test-sidecar-restart-alert.sh
	@if command -v php >/dev/null 2>&1; then php deploy/preflight/test_check.php; else echo "php not installed; skipping deploy/preflight/test_check.php"; fi

# A release tree for HEAD from the pinned repos: out/noevia-release-<sha>.tar.gz, unpacked into a
# fresh out/tree. Point COWORK_SOURCE_DIR at it ($(CURDIR)/out/tree) and Compose builds from it.
# Needs a clean checkout.
assemble:
	rm -rf out/tree
	mkdir -p out/tree
	bash deploy/tools/assemble-release.sh $$(git rev-parse HEAD) out
	tar -xzf out/noevia-release-$$(git rev-parse HEAD).tar.gz -C out/tree

# Validates every Compose file the repo ships. `--env-file .env.example` supplies the required
# image tags (DIARY_VERSION, OCR_VERSION), so this passes on a clean checkout with no .env. The
# overlays are only parsed when passed together with compose.yaml. The llama.cpp overlays also
# require operator-specific values; COMPOSE_STUBS gives them obviously fake ones (nothing is
# started, built or pulled, and no path is read). The stack the repo documents is checked last:
# base + llamacpp + embed + rerank + docling, with the laya profile on.
COMPOSE_ENV = --env-file .env.example
COMPOSE_STUBS = LLAMACPP_RENDER_DEVICE=/dev/dri/renderD128 LLAMACPP_CARD_DEVICE=/dev/dri/card0 \
	LLAMACPP_MODELS_DIR=/stub/models LLAMACPP_CONFIG_DIR=/stub/config LLAMACPP_CACHE_DIR=/stub/cache \
	LLAMACPP_CHAT_MODEL=stub-chat LLAMACPP_AUX_MODEL=stub-aux LLAMACPP_EMBED_MODEL=stub-embed \
	MODEL_LOADER_TOKEN=stub-not-a-secret MODEL_LOADER_DATA_DIR=/stub/loader \
	EMBED_MODEL_FILE=stub-embed.gguf RERANK_MODEL_FILE=stub/rerank.gguf
compose-check:
	docker compose $(COMPOSE_ENV) -f compose.yaml config --quiet
	docker compose $(COMPOSE_ENV) --profile laya -f compose.yaml config --quiet
	docker compose $(COMPOSE_ENV) -f compose.yaml -f compose.docling.yaml config --quiet
	env $(COMPOSE_STUBS) docker compose $(COMPOSE_ENV) --profile laya -f compose.yaml -f compose.llamacpp.yaml -f compose.embed.yaml -f compose.rerank.yaml -f compose.docling.yaml config --quiet
	docker compose $(COMPOSE_ENV) --profile code -f compose.yaml -f deploy/examples/code-sandbox.override.yml -f deploy/examples/code-egress-rust.override.yml config --quiet
