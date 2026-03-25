# LibreSpeed

Docker Compose setup for [LibreSpeed](https://github.com/librespeed/speedtest) in standalone mode with telemetry.

## Setup

1. Copy `.env.sample` to `.env` and adjust settings
2. Copy `librespeed.secrets.env.sample` to `librespeed.secrets.env` and set a stats password and GDPR email

## Usage

```bash
docker compose up -d
```

Speedtest UI at `http://your-host:8090`. Stats at `http://your-host:8090/results/stats.php`.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and general settings (gitignored) |
| `.env.sample` | Template for `.env` |
| `librespeed.secrets.env` | Stats password and email (gitignored) |
| `librespeed.secrets.env.sample` | Template for `librespeed.secrets.env` |
