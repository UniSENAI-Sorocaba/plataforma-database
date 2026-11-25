.PHONY: up down migrate seed validate validate-upgrade detect-drift monitor-pool test-pool test

up:
	docker compose up -d --wait

down:
	docker compose down

migrate:
	./scripts/migrate.sh

seed:
	./scripts/seed.sh

validate:
	./scripts/validate.sh

validate-upgrade:
	./scripts/validate_upgrade.sh

detect-drift:
	./scripts/detect_drift.sh

monitor-pool:
	./scripts/monitor_pool.sh

test-pool:
	./scripts/run_pool_load_test.sh

test: validate validate-upgrade
