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

| IP | Name | Type | How assigned | Notes | Switch port |
|---|---|---|---|---|---|
| `.1` | UniFi Cloud Gateway | gateway, DNS | static | UniFi Local DNS holds the `*.kornoglab.fr` A records | ? |
| `.2` | SLZB-06 (Thread / Bluetooth) | Zigbee/Thread coordinator | UniFi fixed IP | MAC suffix `69:b7` | ? |
| `.10` | SLZB-MR3 | Zigbee coordinator | UniFi fixed IP | MAC suffix `8b:f7`. Used by zigbee2mqtt over TCP | ? |
| `.12` | `orisa` | Proxmox VE host | static in `/etc/network/interfaces` + UniFi fixed IP | `orisa.kornoglab.fr`. See [orisa-proxmox-setup.md](orisa-proxmox-setup.md) | rack 7+8 (LACP bond) |
| `.14` | APsystems ECU (monitoring) | solar monitoring, wired | UniFi fixed IP | | ? |
| `.15` | APsystems ECU (monitoring) | solar monitoring, Wi-Fi | UniFi fixed IP | same function as `.14` on its Wi-Fi interface | Wi-Fi |
| `.20` | `heimdall` | Raspberry Pi | UniFi fixed IP | the parr stack and Traefik moved to orisa on 2026-11-17 (its `arr` service is disabled, containers removed, data kept as a rollback copy). `heimdall.kornoglab.fr` still points here. To retire after a few days | rack 9 |
| `.30` | Home Assistant | HA | UniFi fixed IP | `:8123` | ? |
| `.33` | `pachimari` | your desktop | UniFi fixed IP | | ? |
| `.40` | Philips SmartTV (living room) | TV | UniFi fixed IP | UniFi shows hostname `USWFlexMiniChas`, which is a wrong name set by the TV. It is plugged into port 2 of the USW Flex Mini "salon" | Flex Mini salon 2 |
| `.44` | `drogo` | NAS | UniFi fixed IP | `drogo.kornoglab.fr` | rack 10 |
| `.54` | `ymir` | Synology NAS | UniFi fixed IP | `ymir.kornoglab.fr`. NFS: `data`, `proxmox-backup` | rack 11+12 (LACP bond) |
| `.138` | UniFi UPS 2U | UPS, network UPS (NUT) server | to confirm | Powers orisa, drogo and ymir. drogo and ymir use it as their network UPS server. The Ansible role `nut_client` is prepared (orisa as NUT secondary client, shuts down with the NAS units, Discord alerts) but not applied: orisa reads the UPS only after it is applied, see `orisa-proxmox-setup.md` 7b | rack 16 (FE) |
| `.190` | Shelly Pro 3EM | energy meter | UniFi fixed IP | MAC suffix `66:64` | ? |

"Switch port" names the switch and port(s) as shown in UniFi: `rack` is the 16-port rack switch (section below). `?` means not recorded yet, fill it in when you next look. A bonded device uses two ports and is listed with both.

## Guests on orisa

| IP | VMID | Guest | Role | State |
|---|---|---|---|---|
| `.21` | 121 | `rproxy` | Traefik, all `*.kornoglab.fr` A records point here | running |
| `.22` | 122 | `jellyfin` | Jellyfin with iGPU | running |
| `.23` | 123 | `arr` | *arr apps, qBittorrent + gluetun, Seerr, Homarr, Calibre-web | running |
| `.24` | 124 | `services` | `kornogHosted` services (valkey, zigbee2mqtt, ...) | reserved, not created |
| `.25` | 125 | `auth` | Authelia, see [auth-and-hardening-plan.md](auth-and-hardening-plan.md) | planned, not created |
| `.26` | 126 | `db` | shared PostgreSQL 17 (native, TLS), `db.kornoglab.fr` points here directly (UniFi A record, created). See [orisa-proxmox-setup.md](orisa-proxmox-setup.md) 7c | running |

Guests have no switch port of their own: they are bridged behind orisa's bond (rack ports 7+8), so UniFi shows one of their MACs on those ports.

Convention: guest VMID = `1` + last octet (`.21` is VMID `121`). Guests use static addresses set in their LXC network config.

## Rack switch ports (as seen in UniFi, 2026-11-18)

UniFi switch with 16 RJ45 ports and 2 SFP (model and name to fill in).

| Port | Device | IP | Link | Notes |
|---|---|---|---|---|
| 4 | U6 Mesh (access point) | ? | GbE, PoE+ | |
| **7 + 8** | **orisa** | `.12` (guests `.21` to `.23` behind it) | **LACP aggregate**, 2 x GbE | host `bond0`, mode `802.3ad`, hash `layer2+3`, set up 2026-11-18. `nic1` is on port 7 and `nic0` on port 8 (derived from the link state before the bond, not confirmed by unplugging). UniFi shows a guest's MAC on these ports, not the host's |
| 9 | heimdall | `.20` | GbE | |
| 10 | drogo | `.44` | GbE | |
| **11 + 12** | **ymir** | `.54` | **LACP aggregate**, 2 x GbE | Synology bond |
| 13 | uplink to the USW-Lite-8-PoE (its port 7) | | GbE | the only way out of this switch, see below |
| 14 | Garage (camera) | ? | GbE | |
| 16 | UPS 2U | ? | FE (100 Mb/s) | |

Seen unused: ports 1, 2, 3, 5, 6, 15, and the two SFP ports.

How to read this:
- **Bonded links use two ports on purpose.** Aggregate both in UniFi (Port Manager, Aggregate) and bond the device at the same time. For a Linux host, bond the host first, then aggregate on the switch, never the other way round (the guide, section 4b, has the procedure and the reason).
- **The aggregate only helps traffic that stays inside this switch.** Orisa, Ymir, drogo and heimdall are all on it. Anything between them and a device elsewhere on the LAN (the gateway, other switches, Wi-Fi) goes through the single 1 Gb/s uplink on port 13.
- When a port or cable changes, update this table in the same commit.

Other switches: USW Flex Mini "salon" (TV on port 2), USW Flex Mini in the office (powered off since the move), USW-Lite-8-PoE (uplink side of port 13). Their ports are not recorded yet.

## Seen but dynamic or other subnets

| IP | What | Notes |
|---|---|---|
| `192.168.0.206` | USW Flex Mini (office switch) | in the DHCP pool. Powered off since orisa moved to the rack, so UniFi still shows orisa on its port 5 until that record ages out. Separate device from `.40` (that one is the TV) |
| `192.168.20.2` | other subnet, allowed in Ymir's `data` NFS export | to document |

All entries in "Assigned" are UniFi fixed IPs, confirmed by the owner. `192.168.20.2` and the name of the `.206` switch are still to document.
