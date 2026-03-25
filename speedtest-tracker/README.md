# Speedtest Tracker

Docker Compose setup for [Speedtest Tracker](https://docs.speedtest-tracker.dev/) using SQLite.

## Setup

1. Copy `.env.sample` to `.env` and adjust host paths
2. Copy `speedtest.secrets.env.sample` to `speedtest.secrets.env`
3. Generate an app key and fill it in:
   ```bash
   echo -n 'base64:'; openssl rand -base64 32;
   ```
4. Set `APP_URL` to your instance URL (e.g. `http://192.168.1.x:8080`)

## Usage

```bash
docker compose up -d
```

Default login: `admin@example.com` / `password` — change after first login.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and general settings (gitignored) |
| `.env.sample` | Template for `.env` |
| `speedtest.secrets.env` | App key and URL (gitignored) |
| `speedtest.secrets.env.sample` | Template for `speedtest.secrets.env` |
