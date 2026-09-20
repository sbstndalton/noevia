.PHONY: test test-web test-diary test-tools build compose-check

test: test-web test-diary test-tools

test-web:
	cd apps/web && npm test && npm run typecheck

test-diary:
	cd services/diary && pytest -q

# Dev tooling (tools/repo-index). Plain node, no install step.
test-tools:
	node --test tools/repo-index/*.test.cjs

build:
	cd apps/web && npm run build
	docker build -t cowork-diary:dev services/diary

compose-check:
	docker compose -f compose.yaml config --quiet
