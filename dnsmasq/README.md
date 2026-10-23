# dnsmasq

> **Status: superseded / never deployed.** LAN DNS for `*.kornoglab.fr` is now
> handled by UniFi Local DNS records pointing at heimdall (`192.168.0.20`,
> running Traefik) — see the "Local DNS for `*.kornoglab.fr` (UniFi)" section in
> the repo root [README](../README.md). This dnsmasq setup (wildcard →
> `192.168.0.54`) was a work-in-progress and is kept for reference only. Do not
> set it as the DHCP DNS server unless deliberately switching strategies.

Local DNS server that resolves `*.kornoglab.fr` to the Synology (`192.168.0.54`) and forwards everything else to the UniFi gateway (`192.168.0.1`).

## Setup

1. Start the container:

```bash
docker compose up -d
```

2. In UniFi Network controller, update DHCP DNS server for your main network:
   - Settings → Networks → wu tang lan → DHCP → DHCP DNS Server
   - Set to `192.168.0.54` (the Synology running this container)

## How it works

```
Clients → dnsmasq (192.168.0.54:53)
  ├── *.kornoglab.fr → 192.168.0.54
  └── everything else → UniFi gateway (192.168.0.1)
        ├── *.becquerel → resolved by UniFi
        ├── *.iot → resolved by UniFi
        └── public domains → forwarded upstream
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definition |
| `dnsmasq.conf` | DNS configuration |
