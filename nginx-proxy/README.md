# Nginx Reverse Proxy

> **Status: largely superseded / not in active use (Oct 2026).**
>
> This container was an early attempt to reverse-proxy `kornoglab.fr` subdomains
> from the Synology. Most of what it describes is no longer the live setup:
>
> - **Media services** (`jellyfin`, `sonarr`, `radarr`, `seer`, etc.) are now
>   served by **Traefik on heimdall** (`192.168.0.20`) with the wildcard cert.
>   UniFi Local DNS points each `<service>.kornoglab.fr` at heimdall. The routes
>   listed below pointed at `heimdall.becquerel:80`, a hostname that **no longer
>   resolves** — they are dead. See the repo-root README "Local DNS" section and
>   the `parr` repo for the current media routing.
> - **`ha.kornoglab.fr`** was configured here (→ Home Assistant at
>   `192.168.0.30:8123`) but **never put into real use** — Home Assistant is
>   still accessed via the old LAN name `homeassistant.becquerel`. If/when we
>   want `ha.kornoglab.fr` for real, the cleaner path is DSM's built-in
>   **Login Portal → Reverse Proxy** (+ the wildcard cert already imported in
>   DSM), which would let this nginx-proxy container be retired entirely.
>
> Kept for reference until the `ha` route is either migrated to DSM reverse
> proxy or dropped. Do not rely on the routes below as current.

---

Nginx reverse proxy for `kornoglab.fr` subdomains with TLS termination using the wildcard cert from the `acme` container.

## Ports

On the Synology host, DSM nginx already binds port 443 for QuickConnect, so this container exposes HTTPS on `${HTTPS_PORT}` (default `8443`). Forward `443 → 8443` at the router/firewall so external clients can keep using the standard port.

## Setup

1. Copy `.env.sample` to `.env` and adjust the certs path and port if needed
2. Start the container:

```bash
docker compose up -d
```

## Adding a new subdomain

Create a new `.conf` file in `conf.d/` following the pattern in `ha.conf`, then reload:

```bash
docker compose exec nginx-proxy nginx -s reload
```

## Routes (historical — see status note above)

| Subdomain | Backend | Current reality |
|-----------|---------|-----------------|
| `ha.kornoglab.fr` | Home Assistant (`192.168.0.30:8123`) | configured but unused (HA accessed via `homeassistant.becquerel`) |
| `jellyfin.kornoglab.fr` | `heimdall.becquerel:80` | **dead** — now served by Traefik on heimdall |
| `sonarr.kornoglab.fr` | `heimdall.becquerel:80` | **dead** — now served by Traefik on heimdall |
| `radarr.kornoglab.fr` | `heimdall.becquerel:80` | **dead** — now served by Traefik on heimdall |
| `seer.kornoglab.fr` | `heimdall.becquerel:80` | **dead** — now served by Traefik on heimdall |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `nginx.conf` | Main Nginx config (TLS, WebSocket) |
| `conf.d/ha.conf` | Home Assistant reverse proxy (unused) |
| `conf.d/heimdall.conf` | Media services pointing at the dead `heimdall.becquerel:80` (superseded by Traefik) |
| `.env` | Certs path and external port (gitignored) |
| `.env.sample` | Template for `.env` |
