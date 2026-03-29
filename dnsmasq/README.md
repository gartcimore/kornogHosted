# dnsmasq

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
