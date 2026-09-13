.PHONY: up down migrate seed validate

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
