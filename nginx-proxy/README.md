# Nginx Reverse Proxy

Nginx reverse proxy for `kornoglab.fr` subdomains with TLS termination using the wildcard cert from the `acme` container.

## Setup

1. Copy `.env.sample` to `.env` and adjust the certs path if needed
2. Start the container:

```bash
docker compose up -d
```

## Adding a new subdomain

Create a new `.conf` file in `conf.d/` following the pattern in `ha.conf`, then reload:

```bash
docker compose exec nginx-proxy nginx -s reload
```

## Current routes

| Subdomain | Backend |
|-----------|---------|
| `ha.kornoglab.fr` | Home Assistant (`192.168.0.30:8123`) |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `nginx.conf` | Main Nginx config (TLS, WebSocket) |
| `conf.d/ha.conf` | Home Assistant reverse proxy |
| `.env` | Certs path (gitignored) |
| `.env.sample` | Template for `.env` |
