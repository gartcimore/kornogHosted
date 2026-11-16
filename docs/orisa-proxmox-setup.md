# orisa: Proxmox VE host setup guide

Host: Chuwi UBox, Ryzen 5 6600H, 16 GB LPDDR5, 512 GB NVMe SSD, Radeon 660M iGPU.
Address: `192.168.0.12` (name `orisa`). Role: virtualization host for the `parr` stack and other services, replacing heimdall (Raspberry Pi, `192.168.0.20`).

Status legend: [x] done, [ ] to do.

- [x] Proxmox VE installed
- [x] "no subscription" repository added
- [x] Non-root Linux user created
- [x] Step 1: repos checked, system updated
- [x] Step 2: `gart@pam` in group `admins` (Administrator), sudo works
- [ ] Step 2b: two-factor (pending: YubiKey WebAuthn as main, TOTP + recovery keys as backup; set WebAuthn ID `orisa.kornoglab.fr` first, always use the hostname)
- [x] Step 3: SSH key-only (root by key still allowed)
- [x] Step 4: static IP, UniFi reservation and DNS record (rack bond planned, see 4b)
- [x] Step 5: Let's Encrypt certificate for `orisa.kornoglab.fr` (expires 2027-02-13, renews automatically)
- [x] Step 6 (storage part): NFS storage `ymir-backup` (Ymir `/volume1/proxmox-backup`, 800 GB quota, content Backup only). Backup job and restore test pending until the first guest exists.
- [x] Step 9.1-9.2: `data` share mounted on host at `/mnt/dataYmir` (NFSv3, no squash, real UIDs visible). Guest bind mounts and id-map pending.
- [x] Step 7: Discord notifications working; SMART baseline OK (NVMe 0% used, about 41 C idle).

Fixed addresses (host and guests) are tracked in [ip-inventory.md](ip-inventory.md).

Configuration as code: the host settings, guest definitions, Docker and the `rproxy` stack are described in [`../ansible/`](../ansible/README.md). A dry run (`--check`) against orisa and `rproxy` shows no changes on orisa. What is not managed (certificate, notifications, 2FA, network bridge/bond, BIOS, UniFi, DSM) is listed in that README and stays documented here.

- [x] Step 8 (`rproxy`): LXC 121 at `192.168.0.21` (Debian 13, unprivileged, nesting + keyctl, 1 core, 512 MB, 8 GB). Wildcard cert bind-mounted read-only at `/certs` from the host's `/mnt/dataYmir/containers/volumes/acme/certs`. Docker CE installed. Traefik (file provider only, config in `rproxy/`, deployed to `/opt/rproxy`) tested with `curl --resolve` against heimdall routes: valid cert, HTTP redirects to HTTPS. DNS still points at heimdall.

- [x] Step 8 (`jellyfin`): LXC 122 at `192.168.0.22` (4 cores, 4 GB RAM, 16 GB disk, start order 2), created by the Ansible playbook. Media mounted read-only at `/mnt/dataYmir/media`, iGPU passed through (see "Pass through the iGPU"), hardware transcoding verified. Currently a fresh Jellyfin with a throwaway admin: heimdall's config (4.4 GB) is not migrated yet and DNS still points at heimdall.
- [x] Backup job `backup-c3366771-401a` (02:00, all guests, `ymir-backup`) exists; restore of `rproxy` tested.

### Where we stopped / next

1. `jellyfin` is migrated (2026-11-16): drogo mounted on the host (CIFS, read-only, mapped to the guest's UID 1000) and bind-mounted into CT 122, heimdall's 4.4 GB config copied with `tar` over SSH (VAAPI `encoding.xml` kept from the fresh install), route in `rproxy/traefik/dynamic/routes-jellyfin.yml`, UniFi record `jellyfin.kornoglab.fr` -> `192.168.0.21`, Seerr/Radarr/Sonarr/Homarr re-pointed. heimdall's container is stopped and kept for rollback (remove it from the `parr` compose, then `docker rm` after about a week). To do: set Known proxies to `192.168.0.21` in Jellyfin (Dashboard > Networking) if not done.
   - Rollback: point the UniFi record back to `192.168.0.20` and `docker start jellyfin` on heimdall.
   - Library paths in the Jellyfin database are `/mediaYmir` and `/mediaDrogo`; keep these container paths.
2. Next: build the `arr` guest (`/dev/net/tun`, `/mnt/dataYmir` read-write, UID 1000 id-map, `root:1000:1` in `/etc/subuid` and `/etc/subgid`) and `services`.
3. Pending: two-factor (step 2b), confirm `default-matcher` lists `discord`, BIOS settings (SVM, IOMMU, power on after AC loss), rack move with the LACP bond (4b), restrict Ymir's `data` NFS export to orisa after heimdall is retired, drift check for guest definitions in Ansible.

> Commands marked `# host` run in a shell on orisa (web UI Shell, console or SSH). Check your version first with `pveversion`. Proxmox VE 8 (Debian 12) and 9 (Debian 13) differ in apt source file format (see step 1).

---

## 0. Decisions to make first

| Decision | Recommendation | Why |
|---|---|---|
| Filesystem | Keep the installer default (ext4 + LVM-thin) | Single disk, 16 GB RAM. ZFS gives no redundancy here and uses RAM for ARC. |
| Where Docker runs | Debian LXC for `parr` (see step 8) | Only an LXC can share the iGPU with Jellyfin for hardware transcoding. A VM would need AMD iGPU passthrough, which is fragile. |
| Media/data | Stay on Ymir (NFS), not on the 512 GB SSD | The SSD holds only VM/LXC disks and local backups. |
| Backups | vzdump to Ymir over NFS, PBS later if wanted | The SSD is a single point of failure. |
| Login realm for web UI | `gart@pam` | Reuses the Linux account. The `pve` realm is the alternative if you want web users with no shell account. |

---

## 1. Repositories and updates

Disable the enterprise repos (they return 401 without a subscription) and keep only no-subscription.

PVE 8:
```bash
# host
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list      # if present
```

PVE 9 (deb822 `.sources` files): either delete `pve-enterprise.sources` / `ceph.sources`, or add `Enabled: false` to each.

Then:
```bash
# host
apt update && apt full-upgrade -y
apt install -y amd64-microcode sudo curl vim htop smartmontools lm-sensors
reboot
```

`amd64-microcode` is in `non-free-firmware`. Make sure that component is on the Debian lines in `/etc/apt/sources.list` (the installer normally adds it).

The "no valid subscription" popup at login is cosmetic. Leave it, or accept that patching it breaks on updates.

Verify: `apt update` shows no 401 errors, `pveversion` reports the new version.

---

## 2. Admin access (users, groups, permissions)

Proxmox has two separate layers:

1. **Linux users** (`/etc/passwd`): SSH and shell access.
2. **Proxmox users** (realms `pam`, `pve`): web UI and API, with permissions assigned by ACL.

A Linux user does not get web UI rights until you also add it to Proxmox and grant a role. A Linux group named `admin` has no effect on Proxmox permissions, so create the group on the Proxmox side.

```bash
# host: sudo for the shell user
usermod -aG sudo gart

# host: Proxmox group, ACL, and user
pveum group add admins -comment "Proxmox administrators"
pveum acl modify / -group admins -role Administrator
pveum user add gart@pam -groups admins
```

Then log in to `https://192.168.0.12:8006` with realm **Linux PAM standard authentication**, user `gart`.

Check: Datacenter > Permissions shows `admins` with role `Administrator` on `/`.

Hardening, in this order:

1. Confirm `gart` can log in to the web UI **and** run `sudo`. Do this before changing anything on root.
2. Enable two-factor for `gart` (Datacenter > Permissions > Two Factor). You have a YubiKey: add it as WebAuthn, and add TOTP and recovery keys as backup. WebAuthn requires accessing the UI by a hostname with HTTPS (see step 5); it will not work on a bare IP.
3. Keep `root@pam` as break-glass with a long password and TOTP. Do not disable it until recovery is tested. Proxmox does not require a root web login for daily use.
4. Day-to-day automation should use an API token, not a password:
   ```bash
   pveum user token add gart@pam automation --privsep 1
   pveum acl modify / -token 'gart@pam!automation' -role PVEAdmin
   ```
   The secret is shown once. Store it with git-secret like the other secrets in this repo.

Optional least-privilege roles: `PVEAuditor` for read-only monitoring users.

---

## 3. SSH hardening

From your workstation:
```bash
ssh-copy-id gart@192.168.0.12
```

Test a key login in a **second terminal**, then on orisa:
```bash
# host: /etc/ssh/sshd_config.d/10-hardening.conf
PasswordAuthentication no
PermitRootLogin no
```
```bash
sshd -t && systemctl reload ssh
```

Notes:
- `PermitRootLogin no` is fine on a single node. Cluster joins need root SSH between nodes, so revisit if you add a second node.
- `fail2ban` is optional. Do not expose 8006 or 22 to the internet, so the benefit is small.

---

## 4. Network

- [ ] Reserve `192.168.0.12` for orisa's MAC in UniFi (DHCP reservation) even though it is static, to avoid conflicts. The Proxmox config (`/etc/network/interfaces`, bridge `vmbr0`) holds the static address.
- [ ] Add a UniFi Local DNS A record: `orisa.kornoglab.fr` -> `192.168.0.12` (see the main README, "Local DNS").
- [ ] Use the wired NIC for `vmbr0`. Ignore the Wi-Fi 6 card (disable in BIOS if you want).
- [ ] BIOS: enable SVM (AMD-V), IOMMU, and "Restore on AC power loss = Power On".
- [ ] Optional Proxmox firewall: Datacenter > Firewall. Before enabling, add a rule allowing `192.168.0.0/24` to TCP 22 and 8006, or you will lock yourself out. Enable at Datacenter level last.

### 4b. Rack move: LACP bond (do later, at the rack, with a screen and keyboard)

Hardware facts (checked on orisa):

| Interface | MAC | Notes |
|---|---|---|
| `nic0` | `<nic0-mac>` | Realtek RTL8111/8168, 1 GbE, not cabled yet |
| `nic1` | `<nic1-mac>` | Realtek RTL8111/8168, 1 GbE, in use, bridge port of `vmbr0`, UniFi fixed IP is tied to this MAC |
| `nic3` | `<nic3-mac>` | ASIX AX88772 **USB 2.0** adapter (100 Mb/s). Not useful for the bond. |
| `wlp4s0` | `<wifi-mac>` | Wi-Fi, unused |

Current switch: UniFi USW Flex Mini (port 5), which cannot aggregate links. The bond only applies once orisa is on the rack switch.

Two 1 GbE ports give 2 Gb/s in total across several flows, not for a single transfer. Redundancy is the main gain. If the rack switch does not support LACP, use `bond-mode active-backup` (no switch configuration, failover only).

Procedure:
1. On the rack switch (UniFi Port Manager): select the two ports, set **Aggregate** (LACP).
2. On orisa, back up the config: `cp /etc/network/interfaces /root/interfaces.bak`.
3. Edit `/etc/network/interfaces`, replacing `iface nic1 inet manual` and the `vmbr0` block with:

```
iface nic0 inet manual
iface nic1 inet manual

auto bond0
iface bond0 inet manual
        bond-slaves nic0 nic1
        bond-miimon 100
        bond-mode 802.3ad
        bond-xmit-hash-policy layer2+3

auto vmbr0
iface vmbr0 inet static
        address 192.168.0.12/24
        gateway 192.168.0.1
        hwaddress <nic1-mac>
        bridge-ports bond0
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

   `hwaddress` keeps the bridge on the MAC covered by the UniFi fixed-IP reservation. The two `bridge-vlan-aware` lines are optional and only matter if you add VLANs later.
4. Apply with `ifreload -a` from the console, not over SSH.
5. Verify: `cat /proc/net/bonding/bond0` shows `802.3ad`, both slaves `up`, and the same Aggregator ID. Ping the gateway. In UniFi, the two ports show as aggregating.
6. Pull one cable and check connectivity holds.

Rollback: `cp /root/interfaces.bak /etc/network/interfaces && ifreload -a`.

---

## 5. TLS certificate for the web UI

Needed for WebAuthn and to avoid browser warnings. You already issue `*.kornoglab.fr` with acme.sh + OVH DNS-01 (`acme/`). Two options:

- **Built-in Proxmox ACME** (Datacenter > ACME): register an account, add a challenge plugin of type DNS with API `ovh` and your OVH credentials, then in the node's System > Certificates add `orisa.kornoglab.fr` and order it. Renewal is automatic.
- **Reuse the wildcard** from the acme container: copy `fullchain` and key to Node > System > Certificates > Upload Custom Certificate, and automate renewal yourself.

The first option is less to maintain. Use a dedicated OVH API credential limited to the DNS zone.

Note: the Datacenter > ACME menu entry (above Firewall) is only shown when logged in as `root@pam`, even for users with the `Administrator` role. Log in as root for this step.

---

## 6. Storage and backups

Disk layout on a single 512 GB drive: `local` (ISOs, templates, backups) and `local-lvm` (guest disks). Keep guest disks small. Anything bulky stays on Ymir.

- [ ] On Ymir (DSM > Control Panel > Shared Folder > NFS Permissions) allow `192.168.0.12`. Create a dedicated share/folder, e.g. `proxmox-backup`. See the README note about Synology POSIX bits on NFS.
- [ ] Datacenter > Storage > Add > NFS: server `192.168.0.54`, export path, content **VZDump backup** only.
- [ ] Datacenter > Backup: nightly job, all guests, mode `snapshot`, zstd, retention e.g. keep-daily 7, keep-weekly 4, keep-monthly 3.
- [x] Backing up an **unprivileged** LXC to the NFS share failed with `tar: ...vzdump-lxc-121-....tmp: Cannot open: Permission denied`. vzdump runs `tar` as UID 100000 inside the user namespace and the temp folder it creates on the share belongs to root (the NFS rule has no root squash). Fix: `echo 'tmpdir: /var/tmp' >> /etc/vzdump.conf`, so the temp files stay on the local disk. Bind mounts (`/certs`) are excluded from backups, as expected.
- [x] Restore tested (2026-11-16): `rproxy` archive (1.4 GiB read) restored as CT 199 from the node's `ymir-backup` > Backups tab, config matches the original. Nightly job runs at 02:00 on `ymir-backup`, all guests, retention keep-daily 7 / weekly 4 / monthly 3.
- Restore procedure: restore to a spare VMID (e.g. `199`) with "Start after restore" unticked, because the copy has the same static IP as the original. Remove it afterwards.
- [ ] Back up host config too: `/etc/pve` is in the cluster database (not in vzdump). Copy it with a cron job or `tar` to Ymir, plus `/etc/network/interfaces`, `/etc/fstab`, `/etc/ssh/sshd_config.d/`.

---

## 7. Monitoring and notifications

- [x] Datacenter > Notifications: Webhook target `discord` (POST to the Discord webhook URL, token stored as secret `token` and referenced as `{{ secrets.token }}`, header `Content-Type: application/json`, body `{"content": "**[{{ severity }}]** {{ escape title }}"}`), added to `default-matcher`. Keep the body short: Discord rejects messages over 2000 characters (HTTP 400), and backup failure logs exceed that. Other options are SMTP, Gotify and ntfy. Mail from `smartd` and cron still uses the local mailer (no relay configured).
- [ ] SMART: `smartctl -a /dev/nvme0` for a baseline. Proxmox runs `smartd`; set the email in `/etc/smartd.conf` or rely on notifications.
- [ ] `sensors-detect` then `sensors` to check temperatures. Mini PCs run warm under sustained transcoding.
- [ ] Optional: expose metrics (Datacenter > Metric Server) to InfluxDB/Prometheus, and add a Proxmox integration in Homarr.
- [ ] UPS: a mini PC does not draw much, but a power cut during a write is the main corruption risk. A small UPS is worth it.

---

## 8. Guests for the `parr` stack

### Layout: one guest per service or grouped?

Three options, from least to most split:

| Option | Guests | Pros | Cons |
|---|---|---|---|
| A. One LXC for the whole `parr` compose | 1 | Identical to today. Compose DNS names, Traefik docker labels and the `traefik` network keep working. | A crash or reboot affects everything. No per-service snapshot/restore. |
| **B. Grouped by coupling (recommended)** | 3-4 | Isolates what matters (edge, GPU, VPN downloads), keeps tightly coupled apps together. | Some compose edits (cross-guest addresses). |
| C. One LXC per service | 10+ | Per-service snapshot, restore and resource limits. | Every guest needs OS updates, a Docker install (or a native, non-Docker install), its own NFS mount and id-map. Compose service names no longer resolve between apps. |

Why B: the *arr apps, qBittorrent and Seerr talk to each other by container name (Prowlarr -> Radarr/Sonarr, Radarr -> qBittorrent via gluetun, Seerr -> Radarr/Sonarr/Jellyfin). Splitting them means rewriting every one of those connections to `IP:port`, for little isolation gain, since they share the same data and failure domain anyway. Proxmox already gives you snapshots per guest, and the stack config is in git.

| Guest | Type | Contents | Why separate |
|---|---|---|---|
| `rproxy` | Debian LXC, 1 core, 512 MB | Traefik only, with the wildcard cert | Single entry point, stable IP, rarely changes. Other guests can be rebuilt without touching TLS. |
| `jellyfin` | Debian LXC | Jellyfin only, iGPU passthrough | The only service needing `/dev/dri`. Heavy CPU/RAM use during transcodes, so it gets its own limits. Users see it most, so keeping it independent of the *arr churn helps. |
| `arr` | Debian LXC | Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, qBittorrent + gluetun, Seerr, Homarr, Calibre-web | Tightly coupled apps, one compose file, one `/data` mount (hardlinks need a single filesystem). gluetun needs `/dev/net/tun`. |
| `services` | Debian LXC or VM | Stack from `kornogHosted` (postgres, valkey, zigbee2mqtt, speedtest, it-tools, infisical, ...) | Different lifecycle from media. |
| `core-keeper` (later) | VM or LXC | Game server | Cannot starve the media stack. |

If you later want finer isolation, split out qBittorrent + gluetun first (VPN failures stay contained), then Seerr. Option C for everything is possible but not worth it unless you want per-app restore points badly.

### Traefik routing across guests

Today Traefik finds containers through the Docker provider (labels, via `socket-proxy`) on the shared `traefik` network. That only works for containers on the same Docker host. Your Traefik already enables the **file provider** (`--providers.file.directory=/etc/traefik/dynamic`, used for `dashboard-auth.yml` and `webhook.yml`), so the fix needs no new Traefik feature: one `rproxy` Traefik, with routes to the other guests declared as files.

```
client -> UniFi DNS: *.kornoglab.fr -> rproxy LXC IP -> Traefik :443 (wildcard cert)
       -> file-provider route -> http://<guest-ip>:<port>
```

Example `traefik/dynamic/arr.yml` (one router + service per app):
```yaml
http:
  routers:
    radarr-tls:
      rule: Host(`radarr.kornoglab.fr`)
      entryPoints: [websecure]
      tls: {}
      service: radarr
    radarr-http:
      rule: Host(`radarr.kornoglab.fr`)
      entryPoints: [web]
      middlewares: [redirect-https@file]
      service: radarr
  services:
    radarr:
      loadBalancer:
        servers:
          - url: http://192.168.0.21:7878   # arr LXC (reserved IP)
```

Rules to keep it working:
- **Give each guest a fixed IP** (static in the LXC network config plus a UniFi reservation). The file provider needs addresses that never change. Use IPs, not `.kornoglab.fr` names, to avoid a DNS loop through Traefik.
- **Publish app ports on the guest** (`ports: 7878:7878` is already in your compose). Traefik reaches them over the LAN, so keep each guest's firewall/Proxmox firewall limited to the rproxy IP for those ports if you want to enforce that.
- **Drop the `traefik` Docker network and docker labels** for apps that moved. Labels on a different host are ignored. You can keep labels for any service that stays on the same host as Traefik. Both providers run side by side.
- **`socket-proxy` is no longer needed** on `rproxy` if every route is a file route. Remove it to cut the attack surface.
- **DNS:** all the existing UniFi A records stay pointing at the `rproxy` IP. Nothing changes for clients, whatever number of guests sit behind it.
- **Cross-app addresses** inside the apps (Radarr's download client host, Prowlarr's apps, Seerr's servers) change from `qbittorrent` / `radarr` to the guest's IP, only when the two apps ended up on different guests. With layout B the only cross-guest links are Seerr/Homarr -> Jellyfin, and the Jellyfin mount. Those are few.
- **Generated config:** `parr/generate-arr-configs.sh` and the `webhook` route reference the old layout. Check them before cutting over.
- **High availability is not a goal here**: `rproxy` is a single point of failure for all hostnames, as heimdall is today. Snapshot it before changes. It is a tiny guest and restores in seconds.

Proxmox does not officially support Docker inside LXC, and an update to Proxmox or the kernel can break it. In practice it works with `nesting` and `keyctl`. If you want the supported path, use a Debian VM with Docker instead, and accept no iGPU transcoding.

### Create the LXC

```bash
# host
pveam update
pveam available --section system | grep debian-12
pveam download local <template-name-from-above>
```

In the UI (Create CT): unprivileged on, Features: **Nesting** and **keyctl** on, 4 cores, 6-8 GB RAM, 32 GB disk, bridge `vmbr0`, start at boot on.

### Pass through the iGPU (for Jellyfin VAAPI)

Done for the `jellyfin` guest (CT 122), tested 2026-11-16: a forced transcode played and `/sys/class/drm/card1/device/gpu_busy_percent` rose to 20-90% in bursts.

On the host the render node is `/dev/dri/renderD128` (group `render`, GID 993), driver `amdgpu`. In the guest definition (`ansible/host_vars/jellyfin.yml`, applied with `pct set`):
```
dev0: /dev/dri/renderD128,gid=1000
```
Lessons from the first attempt:
- **The `gid` must be the group the transcoder runs with, not the host's `render` group.** The linuxserver Jellyfin image runs ffmpeg as `abc` (PUID/PGID 1000) and does not add it to the device's group. With `gid=993` ffmpeg failed with `No device available for decoder: device type vaapi needed for codec hevc`, while `vainfo` as root worked. Setting `gid=1000` fixed it. This ties the setting to `PUID`/`PGID=1000`.
- Test as the real user, not root: `docker exec -u abc jellyfin /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128`.
- Compose needs `devices: [/dev/dri/renderD128:/dev/dri/renderD128]` (see `jellyfin/docker-compose.yml`).
- A changed `dev0` needs a guest restart (`pct reboot <id>`).
- `/dev/net/tun` for gluetun (the `arr` guest) is passed the same way: `dev1: /dev/net/tun`.

Hardware formats (from `vainfo`, Mesa radeonsi, Rembrandt): decode H.264, HEVC 8/10-bit, VP9 profiles 0 and 2, AV1; encode H.264 and HEVC. No VC1, MPEG2, VP8, HEVC RExt, or AV1 encode. In Jellyfin > Dashboard > Playback > Transcoding: VAAPI, device `/dev/dri/renderD128`, tick only the supported decode formats (untick VC1), leave the two Intel low-power encoder boxes off, and do not enable AV1 encoding.

### Media from Ymir

See the next section for the full NFS procedure and the guest bind mount.

### Install Docker and the stack

Install Docker from Docker's official apt repository inside the LXC, then clone `parr` and follow its `readme.md` / `setup.sh`. Review the Pi-specific settings first, for example the CPU cap on `calibre-web-automated` in `parr/docker-compose.yml`, which only existed to protect the Pi.

---

## 9. Mounting the Ymir (Synology) shares

Principle: mount NFS **once on the Proxmox host**, then bind-mount it into each guest that needs it. An unprivileged LXC cannot mount NFS itself without weakening its isolation, and one host mount means one set of mount options to maintain.

### 9.1 On Ymir (DSM)

1. Control Panel > File Services > NFS: enable the NFS service, maximum protocol NFSv4.1 (NFSv3 also allowed, matching what heimdall uses today).
2. Control Panel > Shared Folder > `data` > Edit > **NFS Permissions** > Create:
   - Hostname or IP: `192.168.0.12` (orisa only)
   - Privilege: Read/Write
   - Squash: **No mapping** (so UID 1000 stays 1000). "Map all users to admin" also works but hides real ownership, avoid it.
   - Security: `sys`
   - Enable asynchronous: leave off for config/databases, acceptable for pure media if you want speed.
   - Allow connections from non-privileged ports and "allow users to access mounted subfolders": leave off unless a mount fails.
3. Apply the POSIX fix from the README if access is denied: `sudo chmod 755 /volume1/data` on Ymir, or switch the shared folder from Windows ACL to UNIX permissions.
4. Do the same for any other export you need (a `proxmox-backup` folder for vzdump, see step 6). Add a rule per client IP. If a guest ever mounts NFS directly, add its IP too.

Do the same on drogo (`192.168.0.44`) if you still need its media; the compose file bind-mounts it as `/mnt/data`.

### 9.2 On the Proxmox host

```bash
# host
apt install -y nfs-common        # usually already present
mkdir -p /mnt/dataYmir
chattr +i /mnt/dataYmir          # safety: writes fail if the NFS mount is missing
showmount -e 192.168.0.54        # check the export is visible (NFSv3 query)
```

`/etc/fstab`, same options as heimdall (README), with the `x-systemd.automount`-less permanent mount that your `parr` stack requires:
```
192.168.0.54:/volume1/data /mnt/dataYmir nfs rw,hard,nofail,_netdev,retry=5,x-systemd.mount-timeout=30,x-systemd.device-timeout=30,vers=3,sec=sys 0 0
```
```bash
systemctl daemon-reload
mount /mnt/dataYmir
ls /mnt/dataYmir && touch /mnt/dataYmir/.write-test && rm /mnt/dataYmir/.write-test
```

Why `chattr +i` on the empty mount point: if the mount fails at boot, a guest would otherwise write into the local SSD under `/mnt/dataYmir` and fill it silently. With the immutable flag on the underlying directory, those writes error instead. The flag applies to the directory beneath the mount, not the mounted share.

Why `hard` and not `soft`: with `soft`, a NAS hiccup returns I/O errors to the apps and can corrupt downloads or databases. With `hard`, I/O waits. The downside is that a NAS outage can hang processes in `D` state until it returns, which is the correct behavior for this stack.

### 9.3 Into the guests

For each guest that needs media, add a bind mount in `/etc/pve/lxc/<id>.conf` (or `pct set <id> -mp0 /mnt/dataYmir,mp=/mnt/dataYmir`):
```
mp0: /mnt/dataYmir,mp=/mnt/dataYmir
```
Keep the **same path inside every guest** (`/mnt/dataYmir`), so compose files (`DATA_DIR`) and the apps' root folders are identical across guests. Mount the whole `data` share, not separate `media` and `downloads` mounts: Radarr/Sonarr hardlink or atomically move from downloads to library, which only works within one filesystem. Separate mounts of the same share count as different filesystems and force slow copies.

Mount read-only where write is not needed. Jellyfin only reads media: `mp0: /mnt/dataYmir,mp=/mnt/dataYmir,ro=1`. Its config stays on the guest disk.

Mount-ordering: start NFS-dependent guests after the host has mounted the share, which `_netdev` handles at boot, and give them a start delay as a safety net (guest Options > Start/Shutdown order, e.g. `rproxy` order 1, `arr` and `jellyfin` order 2 with a 30 s delay). Start ordering: by default `pve-guests.service` has no dependency on the NFS mount (`systemd-analyze critical-chain pve-guests.service` shows none), so a guest can start before `/mnt/dataYmir` is ready. Fix, applied on orisa:
```
# /etc/systemd/system/pve-guests.service.d/10-nfs.conf
[Unit]
Wants=mnt-dataYmir.mount
After=remote-fs.target mnt-dataYmir.mount
```
then `systemctl daemon-reload`. `Wants=` is deliberate (not `RequiresMountsFor=`): a NAS outage then delays guests but does not stop all of them from starting. After the next reboot, `systemd-analyze critical-chain pve-guests.service` should show `mnt-dataYmir.mount`.

Proxmox does not include bind mounts (host-path `mp` entries) in vzdump backups, so the NAS data is not copied into guest backups. Verify with one backup's size.

### 9.4 UID/GID mapping

An unprivileged LXC maps container UID 1000 to host UID 101000, so files owned by 1000 on Ymir show as `nobody` and writes fail. Map UID/GID 1000 straight through. On the host:
```
# /etc/subuid and /etc/subgid: append
root:1000:1
```
In each guest's `/etc/pve/lxc/<id>.conf`:
```
lxc.idmap: u 0 100000 1000
lxc.idmap: g 0 100000 1000
lxc.idmap: u 1000 1000 1
lxc.idmap: g 1000 1000 1
lxc.idmap: u 1001 101001 64535
lxc.idmap: g 1001 101001 64535
```
Restart the guest and check: `ls -ln /mnt/dataYmir` inside shows `1000 1000`. This must match `PUID`/`PGID` in the stack `.env` (see `parr/.env.sample`).

Alternative: make the guest privileged. It removes the mapping work but weakens isolation, so I do not recommend it for a guest running Docker and a VPN client.

### 9.5 Verify and monitor

```bash
# inside a guest
df -h /mnt/dataYmir
touch /mnt/dataYmir/.t && ln /mnt/dataYmir/.t /mnt/dataYmir/.t2 && rm /mnt/dataYmir/.t /mnt/dataYmir/.t2   # hardlink works
```
Add a check that alerts when the mount is missing (a `findmnt /mnt/dataYmir || notify` cron on the host), since Sonarr/Radarr would otherwise report "root folder missing" only after the fact.

---

## 10. Migration plan from heimdall

heimdall keeps running until the new stack is verified.

1. Build the guests (`rproxy`, `jellyfin`, `arr`) and confirm Docker, `/dev/dri` (jellyfin), `/dev/net/tun` (arr), NFS mount and UID mapping in each.
2. Stop heimdall's stack briefly and copy `DOCKER_CONFIG_DIR` (the *arr, Jellyfin, qBittorrent, Homarr configs) to the LXC. Back them up first (the repo has `parr/backup.sh`). Never run both qBittorrent/gluetun instances with the same VPN account at once.
3. Check the `acme` certs path: Traefik reads `/mnt/dataYmir/containers/volumes/acme/certs`. Keep that NFS mount at the same path in the LXC.
4. Start the stack on orisa. Fix path differences that show in the *arr health pages (root folders, download client host).
5. Test one hostname without touching DNS: `curl --resolve radarr.kornoglab.fr:443:<rproxy-IP> https://radarr.kornoglab.fr/`.
6. Switch the UniFi A records from `192.168.0.20` to the `rproxy` IP (`192.168.0.x`, reserve it). Update the README table and the records list.
7. Run for a week. Then shut heimdall's stack down, keep its SD card/disk image as a fallback, and later reuse it.

Rollback: change the A records back to `192.168.0.20` and restart the stack on heimdall.

---

## 11. Final checklist

- [ ] Enterprise repos disabled, system updated, microcode installed
- [ ] `gart@pam` in group `admins`, role `Administrator`, 2FA enabled (WebAuthn + TOTP + recovery)
- [ ] Root kept as break-glass with TOTP
- [ ] SSH key-only, root SSH off
- [ ] DHCP reservation, DNS record `orisa.kornoglab.fr`, valid certificate
- [ ] NFS backup storage, nightly job, one restore tested
- [ ] Notifications working (send a test)
- [ ] Host config backed up
- [ ] `rproxy`, `jellyfin`, `arr` guests with fixed IPs; iGPU, tun and NFS working; Traefik file routes in place; Jellyfin hardware transcoding confirmed in the playback log
- [ ] Migration cut over and heimdall retired

## References

- Proxmox VE Administration Guide: user management (`pveum`), ACME, backup, notifications, LXC (https://pve.proxmox.com/pve-docs/)
- Package repositories: https://pve.proxmox.com/wiki/Package_Repositories
