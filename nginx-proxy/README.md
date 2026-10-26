# Nginx Reverse Proxy (Ymir-hosted services)

Reverse proxy, running on **Ymir**, that gives HTTPS `*.kornoglab.fr` hostnames
to services **hosted on Ymir itself** (containers in this repo), using the
wildcard cert from the `acme` container. TLS + WebSocket termination is handled
here; backends are plain HTTP on the LAN.

> **Scope:** this proxies **Ymir-local** services only. Media services
> (`jellyfin`, `sonarr`, `radarr`, `seerr`, `homarr`, qbit, webhook, the Traefik
> dashboard...) are served by **Traefik on heimdall** (`192.168.0.20`) — their
> `*.kornoglab.fr` UniFi DNS records point at heimdall, not here. Do not add
> routes for heimdall services; they'd conflict. (The old `ha.conf` and
> `heimdall.conf` — the latter pointing at the dead `heimdall.becquerel:80` —
> were removed.)

## Ports

On the Synology host, DSM nginx already binds port 443 for QuickConnect, so this container exposes HTTPS on `${HTTPS_PORT}` (default `8443`). Forward `443 → 8443` at the router/firewall so external clients can keep using the standard port.

## Setup

1. Copy `.env.sample` to `.env` and adjust the certs path and port if needed
2. Start the container:

```bash
docker compose up -d
```

## Adding a new subdomain

1. Add a UniFi Local DNS A record `<name>.kornoglab.fr → 192.168.0.54` (Ymir).
2. Create a `conf.d/<name>.conf` following the pattern in `z2m.conf` (include the
   WebSocket headers if the service needs them — the `$connection_upgrade` map is
   defined in `nginx.conf`).
3. Reload:

```bash
docker compose exec nginx-proxy nginx -s reload
```

## Current routes

| Subdomain | Backend | Notes |
|-----------|---------|-------|
| `z2m.kornoglab.fr` | Zigbee2MQTT (`192.168.0.54:8099`) | WebSocket enabled (live view/logs) |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `nginx.conf` | Main Nginx config (TLS, WebSocket map) |
| `conf.d/z2m.conf` | Zigbee2MQTT reverse proxy |
| `.env` | Certs path and external port (gitignored) |
| `.env.sample` | Template for `.env` |
