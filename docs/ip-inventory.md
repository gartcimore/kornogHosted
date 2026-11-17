# LAN IP inventory (192.168.0.0/24)

Single list of addresses that are assigned by hand (static, or fixed-IP reservation in UniFi). Check here before picking a new one, and update it in the same commit that uses it.

Network: UniFi "wu tang lan", gateway `192.168.0.1`, usable `.1` to `.254`.
DHCP pool: `192.168.0.200` to `192.168.0.240` (dynamic clients only). Fixed addresses stay below `.200`.

Before taking an address, check it is really free from two machines:
```bash
ping -c1 -W1 192.168.0.<n>
```
and look in the UniFi client list. A device with a hand-set static IP does not appear in the DHCP pool, and some ignore ping.

## Assigned

| IP | Name | Type | How assigned | Notes |
|---|---|---|---|---|
| `.1` | UniFi Cloud Gateway | gateway, DNS | static | UniFi Local DNS holds the `*.kornoglab.fr` A records |
| `.2` | SLZB-06 (Thread / Bluetooth) | Zigbee/Thread coordinator | UniFi fixed IP | MAC suffix `69:b7` |
| `.10` | SLZB-MR3 | Zigbee coordinator | UniFi fixed IP | MAC suffix `8b:f7`. Used by zigbee2mqtt over TCP |
| `.12` | `orisa` | Proxmox VE host | static in `/etc/network/interfaces` + UniFi fixed IP | `orisa.kornoglab.fr`. See [orisa-proxmox-setup.md](orisa-proxmox-setup.md) |
| `.14` | APsystems ECU (monitoring) | solar monitoring, wired | UniFi fixed IP | |
| `.15` | APsystems ECU (monitoring) | solar monitoring, Wi-Fi | UniFi fixed IP | same function as `.14` on its Wi-Fi interface |
| `.20` | `heimdall` | Raspberry Pi | UniFi fixed IP | the parr stack and Traefik moved to orisa on 2026-11-17 (its `arr` service is disabled, containers removed, data kept as a rollback copy). `heimdall.kornoglab.fr` still points here. To retire after a few days |
| `.30` | Home Assistant | HA | UniFi fixed IP | `:8123` |
| `.33` | `pachimari` | your desktop | UniFi fixed IP | |
| `.40` | Philips SmartTV (living room) | TV | UniFi fixed IP | UniFi shows hostname `USWFlexMiniChas`, which is a wrong name set by the TV. It is plugged into port 2 of the USW Flex Mini "salon" |
| `.44` | `drogo` | NAS | UniFi fixed IP | `drogo.kornoglab.fr` |
| `.54` | `ymir` | Synology NAS | UniFi fixed IP | `ymir.kornoglab.fr`. NFS: `data`, `proxmox-backup` |
| `.190` | Shelly Pro 3EM | energy meter | UniFi fixed IP | MAC suffix `66:64` |

## Guests on orisa

| IP | VMID | Guest | Role | State |
|---|---|---|---|---|
| `.21` | 121 | `rproxy` | Traefik, all `*.kornoglab.fr` A records point here | running |
| `.22` | 122 | `jellyfin` | Jellyfin with iGPU | running |
| `.23` | 123 | `arr` | *arr apps, qBittorrent + gluetun, Seerr, Homarr, Calibre-web | running |
| `.24` | 124 | `services` | `kornogHosted` services (postgres, valkey, zigbee2mqtt, ...) | reserved, not created |
| `.25` | 125 | `auth` | Authelia, see [auth-and-hardening-plan.md](auth-and-hardening-plan.md) | planned, not created |

Convention: guest VMID = `1` + last octet (`.21` is VMID `121`). Guests use static addresses set in their LXC network config.

## Seen but dynamic or other subnets

| IP | What | Notes |
|---|---|---|
| `192.168.0.206` | USW Flex Mini (office switch, orisa's current port) | in the DHCP pool. Separate device from `.40` (that one is the TV) |
| `192.168.20.2` | other subnet, allowed in Ymir's `data` NFS export | to document |

All entries in "Assigned" are UniFi fixed IPs, confirmed by the owner. `192.168.20.2` and the name of the `.206` switch are still to document.
