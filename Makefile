.PHONY: up down dev test migrate seed

up:
	docker compose up -d

down:
	docker compose down

dev:
	uv run uvicorn vaakya.main:app --reload --env-file .env.dev --port 8000

test:
	uv run pytest -v

migrate:
	uv run alembic upgrade head

seed:
	uv run python -m vaakya.seed
