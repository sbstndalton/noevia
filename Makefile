.PHONY: test test-web test-diary build compose-check

test: test-web test-diary

test-web:
	cd apps/web && npm test && npm run typecheck

test-diary:
	cd services/diary && pytest -q

build:
	cd apps/web && npm run build
	docker build -t cowork-diary:dev services/diary

compose-check:
	docker compose -f compose.yaml config --quiet
