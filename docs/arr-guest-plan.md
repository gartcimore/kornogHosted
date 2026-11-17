# Plan: the `arr` guest (CT 123)

Status: **prepared, not applied.** Written 2026-11-16 after reading `parr/docker-compose.yml`, `.env.sample`, `arr.service` and the webhook files. The Ansible role changes, `arr/` files and `host_vars/arr.yml` exist and pass lint and a dry run; the guest has not been created.

Target: LXC `arr`, `192.168.0.23`, VMID 123 (reserved in [ip-inventory.md](ip-inventory.md)). It runs the `parr` stack without Traefik, Jellyfin and the webhook.

## What moves

| Service | Port | Hostname (via `rproxy`) |
|---|---|---|
| prowlarr | 9696 | `prowlarr.kornoglab.fr` |
| radarr | 7878 | `radarr.kornoglab.fr` |
| sonarr | 8989 | `sonarr.kornoglab.fr` |
| bazarr | 6767 | `bazarr.kornoglab.fr` |
| lidarr | 8686 | `lidarr.kornoglab.fr` |
| seerr | 5055 | `seerr.kornoglab.fr` |
| homarr | 7575 | `homarr.kornoglab.fr` |
| gluetun (qBittorrent UI) | 8080 | `qbittorrent.kornoglab.fr`, `qbt.kornoglab.fr` |
| qbittorrent | none, shares gluetun's network | |
| gluetun-qbt-watchdog | none | |
| calibre-web-automated | 8083 | `books.kornoglab.fr` |

Not moved:
- **traefik, socket-proxy:** `rproxy` routes to the guest by IP and port. The Traefik labels on the services stay in the file and are harmless without Traefik.
- **jellyfin:** already in CT 122.
- **webhook and the Homarr reboot button:** dropped. Rebooting is done from Proxmox now. This removes `host.docker.internal`, `traefik/dynamic/webhook.yml` and the `webhook.kornoglab.fr` record.
- **heimdall Traefik dashboard** (`heimdall.kornoglab.fr`): gone with Traefik.

## Decisions

1. **Same compose file as `parr`, no fork, and no change to `parr`.** Compose loads `docker-compose.override.yml` next to the main file. `arr/docker-compose.override.yml` puts `traefik` and `socket-proxy` in a profile that is never enabled and raises calibre-web's CPU cap from 2 to 3. (An earlier idea, a `proxy` profile inside `parr`, would have stopped Traefik on heimdall at its next update, because heimdall's `.env` has an empty `COMPOSE_PROFILES`.)
2. **User IDs: map guest UID/GID 1000 straight to host 1000.** Needed so files created on Ymir are owned by 1000 like today (existing downloads are `1000:1000`, mode 644, and a different UID could not modify them). Requires `root:1000:1` in the host's `/etc/subuid` and `/etc/subgid` and these lines in `/etc/pve/lxc/123.conf`:
   ```
   lxc.idmap: u 0 100000 1000
   lxc.idmap: g 0 100000 1000
   lxc.idmap: u 1000 1000 1
   lxc.idmap: g 1000 1000 1
   lxc.idmap: u 1001 101001 64535
   lxc.idmap: g 1001 101001 64535
   ```
3. **Drogo is mounted twice on the host, once per access level.** `/mnt/dataDrogo` stays read-only and owned by 101000 (Jellyfin, unchanged). A new `/mnt/dataDrogoRW` is read-write and owned by 1000 (mode 0775/0664), and only the `arr` guest gets it, at `/mnt/data` where parr's compose file expects it. Which guest sees which mount is decided by each guest's own `mpN` line.
4. **Secrets: the `.env` is encrypted with git-secret** (`arr/.env` is gitignored, `arr/.env.secret` is committed), revealed locally and copied by Ansible with mode 0600. `arr/.env.sample` lists the variables. `HOMARR_SECRET_KEY` must be the same value as on heimdall. The webhook variables are dropped.
5. **Routing:** a new `rproxy/traefik/dynamic/routes-arr.yml`, one router and service per hostname, pointing at `192.168.0.23:<port>`. Then the UniFi A records for those names move from `192.168.0.20` to `192.168.0.21`.
6. **Start at boot with the systemd unit** (with the restart fixes from `parr`), installed by Ansible with `WorkingDirectory=/opt/parr`.
7. **Stack delivery:** Ansible clones `parr` into `/opt/parr` at a pinned commit (`host_vars/arr.yml`), copies the override file and the `.env`, installs `arr.service` and starts it. Update by changing the pinned commit. `DOCKER_CONFIG_DIR=/docker/appdata` and `DATA_DIR=/mnt/dataYmir` stay as on heimdall, so no path inside any app config changes.

## Guest definition

See `ansible/host_vars/arr.yml`: 4 cores, 6 GB RAM, 512 MB swap, 24 GB disk (appdata is about 1.3 GB without Jellyfin, plus Docker images), start order 3, `dev0: /dev/net/tun`, read-write bind mounts of `/mnt/dataYmir` and, at `/mnt/data` (where parr's compose expects it), the read-write drogo mount `/mnt/dataDrogoRW`, and the six `lxc.idmap` lines.

## Changes needed in the repos

Done (uncommitted at the time of writing):
- `ansible/roles/proxmox_host`: `root:1000:1` in `/etc/subuid` and `/etc/subgid`.
- `ansible/roles/lxc_guest`: `raw_config` lines added to the guest config before the first start.
- `ansible/roles/compose_stack`: clone a repository, copy extra files, install the systemd unit.
- `ansible/roles/docker_host`: `git` installed.
- `ansible/group_vars/proxmox.yml`: second drogo mount `/mnt/dataDrogoRW`, read-write, owned by 1000.
- `ansible/host_vars/arr.yml`, inventory entry, `arr/docker-compose.override.yml`, `arr/.env.sample`.

Still to do:
- ~~`arr/.env`~~ created from heimdall's `.env` and encrypted (`arr/.env.secret`). `git secret hide` only needs the public key; the YubiKey is needed for `git secret reveal`.
- `rproxy/traefik/dynamic/routes-arr.yml` at cutover (and remove the temporary radarr route from `routes-heimdall.yml`, two files must not define the same router).

## Risks to test before moving anything

1. **gluetun with WireGuard inside an unprivileged LXC.** Needs `/dev/net/tun` and either the host `wireguard` module or the userspace fallback. Not tried. Spike: create the guest, start gluetun alone with the real `.env`, and check that the VPN connects and a forwarded port is assigned.
2. **NFS with the id-map.** From the guest: create a file and a hardlink in `downloads` and check it is owned by `1000:1000` on Ymir, and that existing 1000-owned files can be changed.
3. **Drogo read-write** after the mount change: Sonarr must be able to import into `/dataDrogo`.
4. **Memory:** the sum of the guests must fit in 16 GB. Currently `rproxy` 0.5 GB and `jellyfin` 4 GB are allocated.

## Sequence

1. Prepare the repo and Ansible changes. Dry-run.
2. Create CT 123 with an empty stack. Run the spike tests (risks 1 to 3).
3. Quiet moment: stop the stack on heimdall (`sudo systemctl stop arr`), copy `/docker/appdata/<service>` for the ten services with `tar` over SSH (as for Jellyfin, keeping numeric owners), copy the `.env` values, start the stack in the guest.
4. Test each app through its IP and port: Prowlarr app sync, Radarr/Sonarr download client test (`gluetun:8080`), Bazarr, Seerr, Homarr integrations, qBittorrent port matches gluetun's forwarded port.
5. Add `routes-arr.yml` to `rproxy`, move the UniFi records to `192.168.0.21`, test through the hostnames.
6. Re-point anything outside the stack that used heimdall's address.
7. Leave heimdall's stack stopped for a week, then retire it.

## Rollback

Before step 5: start `arr` on heimdall again (`sudo systemctl start arr`) and stop the guest's stack. After step 5: also point the UniFi records back to `192.168.0.20`. Do not run both stacks at once: both would use the same VPN account and the same Ymir paths.

## Decisions taken

- Homarr keeps its Docker widget (the container restart button). Note that restarting `gluetun` alone cuts qBittorrent off until it is restarted too; the watchdog handles that.
- calibre-web-automated gets 3 CPUs.
- Read-write drogo is acceptable.
- git-secret for the `.env`.

## Open questions

1. ~~recyclarr~~: resolved. `/docker/appdata/recyclarr` on heimdall was never used, so it is dropped and not copied.
2. ~~Remount of drogo~~: replaced by a second mount. An earlier run of `--tags host` had remounted `/mnt/dataDrogo` read-write with owner 1000 and Jellyfin kept working (bind mount `ro`, write test failed with "Read-only file system"). The final design keeps `/mnt/dataDrogo` read-only as it was and adds `/mnt/dataDrogoRW` for `arr`, so Jellyfin's source is read-only at the CIFS level too. Running `--tags host` again moves `/mnt/dataDrogo` back to its read-only options and creates the new mount.
