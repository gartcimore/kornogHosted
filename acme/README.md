# ACME (Let's Encrypt)

Docker Compose setup for [acme.sh](https://github.com/acmesh-official/acme.sh) to issue and auto-renew Let's Encrypt certificates for `kornoglab.fr` using DNS-01 challenge via OVH API.

## Prerequisites

Create an OVH API token at <https://api.ovh.com/createToken/> with validity set to **Unlimited** (needed for automated renewal) and the following rights:

- `GET /domain/zone/*`
- `PUT /domain/zone/*`
- `POST /domain/zone/*`
- `DELETE /domain/zone/*`

## Setup

1. Copy `.env.sample` to `.env` and adjust paths if needed
2. Copy `acme.secrets.env.sample` to `acme.secrets.env` and fill in your OVH API credentials
3. Start the container:

```bash
docker compose up -d
```

On first start, the entrypoint script will automatically issue the certificate via DNS-01 challenge and install it to `./certs/`. A cron daemon then handles automatic renewal (every 60 days) and re-deploys the certs.

## Using the certs

The `./certs/` directory can be mounted as a volume in other containers that need TLS (Home Assistant, Nginx, etc.).

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `.env` | Host paths and general settings (gitignored) |
| `.env.sample` | Template for `.env` |
| `acme.secrets.env` | OVH API credentials (gitignored) |
| `acme.secrets.env.sample` | Template for `acme.secrets.env` |
