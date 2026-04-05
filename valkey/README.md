# Valkey

Shared [Valkey](https://valkey.io/) instance (Redis-compatible) for services that need caching or a message broker.

## Setup

1. Copy `.env.sample` to `.env` and adjust paths

## Usage

```bash
docker compose up -d
```

## Connecting from other services

Other Docker Compose services can reach this instance at `valkey-kornoglab:6379` if they share a Docker network, or at `<host-ip>:6379` via the exposed port.

Connection string: `redis://valkey-kornoglab:6379` (or `redis://<host-ip>:6379`)

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and settings (gitignored) |
| `.env.sample` | Template for `.env` |
