# Core Keeper Dedicated Server

Docker Compose setup for [escapingnetwork/core-keeper-dedicated](https://github.com/escapingnetwork/core-keeper-dedicated).

## Setup

1. Copy `.env.sample` to `.env` and adjust paths and game settings
2. Copy `core.secrets.env.sample` to `core.secrets.env` and fill in your password and webhook URL

## Usage

```bash
docker compose up -d
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and game settings (gitignored) |
| `.env.sample` | Template for `.env` |
| `core.secrets.env` | Passwords and webhook URLs (gitignored) |
| `core.secrets.env.sample` | Template for `core.secrets.env` |
