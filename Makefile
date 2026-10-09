.PHONY: up down migrate seed validate validate-upgrade test

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

test: validate validate-upgrade
