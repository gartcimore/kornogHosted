# Postgres

Shared PostgreSQL instance for services that need a relational database.

## Setup

1. Copy `.env.sample` to `.env` and adjust paths
2. Copy `postgres.secrets.env.sample` to `postgres.secrets.env` and set a strong password

## Usage

```bash
docker compose up -d
```

## Adding a database for a new service

The first database (`infisical`) is created automatically via the `POSTGRES_DB` env var on first start. For additional databases on an existing instance:

```bash
docker exec -it postgres-kornoglab psql -U postgres -c "CREATE DATABASE myservice;"
```

## Connecting from other services

Other Docker Compose services can reach this instance at `postgres-kornoglab:5432` if they share a Docker network, or at `host.docker.internal:5432` / `<host-ip>:5432` via the exposed port.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and settings (gitignored) |
| `.env.sample` | Template for `.env` |
| `postgres.secrets.env` | Database password (gitignored) |
| `postgres.secrets.env.sample` | Template for `postgres.secrets.env` |
