.PHONY: test test-web test-diary test-docling test-tools build compose-check

test: test-web test-diary test-docling test-tools

test-web:
	cd apps/web && npm test && npm run typecheck

test-diary:
	cd services/diary && pytest -q

# The extraction contract, with Docling stubbed (extract.py keeps every Docling
# import inside a function, so these run without the models). Previously absent
# from this target and from CI, so nothing ran them.
test-docling:
	cd services/docling && pytest -q

# Dev tooling (tools/repo-index). Plain node, no install step.
test-tools:
	node --test tools/repo-index/*.test.cjs

build:
	cd apps/web && npm run build
	docker build -t cowork-diary:dev services/diary

compose-check:
	docker compose -f compose.yaml config --quiet
# The Docling sidecar is an overlay, so it is only validated when both files are
# passed together — checking compose.yaml alone never parses it.
	docker compose -f compose.yaml -f compose.docling.yaml config --quiet
