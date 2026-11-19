.PHONY: up down migrate seed validate validate-upgrade detect-drift test

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

test: validate validate-upgrade
