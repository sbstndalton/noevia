.PHONY: test test-web test-diary test-docling test-model-manager test-ocr test-laya test-code-sandbox test-deploy test-tools build compose-check

test: test-web test-diary test-docling test-model-manager test-ocr test-laya test-code-sandbox test-deploy test-tools

test-web:
	cd apps/web && npm test && npm run typecheck

test-diary:
	cd services/diary && pytest -q

# The extraction contract, with Docling stubbed (extract.py keeps every Docling import inside a
# function, so these run without the models). Previously absent from this target and from CI, so
# nothing ran them.
test-docling:
	cd services/docling && pytest -q

# Needs `pip install -r services/model-manager/requirements.txt pytest pytest-asyncio`.
test-model-manager:
	cd services/model-manager && pytest -q

# Standard library only. The real-engine cases generate their own synthetic PDFs (synthetic_pdfs.py)
# and run when tesseract (eng+deu), ghostscript and poppler-utils are installed; otherwise they skip
# and -rs prints which engine is missing.
test-ocr:
	cd services/ocr && pytest -q -rs

# Standard library only (the decision worker is faked).
test-laya:
	cd services/laya && pytest -q

test-code-sandbox:
	node --test services/code-sandbox/pi-acp-bridge.test.cjs

# Deploy tooling: the shell and wrapper tests CI runs, plus the unittest suites under deploy/tests
# (rclone/flock-dependent cases skip themselves when those are absent) and the PHP preflight test
# when php is installed.
test-deploy:
	python3 -m unittest discover -s deploy/tests -p 'test_*.py'
	python3 deploy/preflight/test_wrapper.py
	python3 deploy/nextcloud/test_repair_push.py
	bash deploy/tools/test-build-web-release.sh
	bash deploy/tools/test-sidecar-restart-alert.sh
	@if command -v php >/dev/null 2>&1; then php deploy/preflight/test_check.php; else echo "php not installed; skipping deploy/preflight/test_check.php"; fi

# Dev tooling (tools/repo-index). Plain node, no install step.
test-tools:
	node --test tools/repo-index/*.test.cjs

build:
	cd apps/web && npm run build
	docker build -t cowork-diary:dev services/diary

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
