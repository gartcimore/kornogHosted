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

- [x] Step 4b: orisa moved to the rack, LACP bond of `nic0` and `nic1` (ports 7 and 8 aggregated), applied and verified 2026-11-18. Failover tested on `nic0` (about 0.6 s outage). Throughput tried: no gain between orisa and Ymir, as expected.
- [x] Step 8 (`rproxy`): LXC 121 at `192.168.0.21` (Debian 13, unprivileged, nesting + keyctl, 1 core, 512 MB, 8 GB). Wildcard cert bind-mounted read-only at `/certs` from the host's `/mnt/dataYmir/containers/volumes/acme/certs`. Docker CE installed. Traefik (file provider only, config in `rproxy/`, deployed to `/opt/rproxy`) tested with `curl --resolve` against heimdall routes: valid cert, HTTP redirects to HTTPS. DNS still points at heimdall.

- [x] Step 8 (`jellyfin`): LXC 122 at `192.168.0.22` (4 cores, 4 GB RAM, 16 GB disk, start order 2), created by the Ansible playbook. Media mounted read-only at `/mnt/dataYmir/media`, iGPU passed through (see "Pass through the iGPU"), hardware transcoding verified. Currently a fresh Jellyfin with a throwaway admin: heimdall's config (4.4 GB) is not migrated yet and DNS still points at heimdall.
- [x] Backup job `backup-c3366771-401a` (02:00, all guests, `ymir-backup`) exists; restore of `rproxy` tested.

- [x] Step 8 (`arr`): LXC 123 at `192.168.0.23` (4 cores, 6 GB RAM, 24 GB disk, start order 3), created by the Ansible playbook with UID/GID 1000 mapped to host 1000, `/dev/net/tun`, and read-write mounts of Ymir (`/mnt/dataYmir`, NFS) and drogo (`/mnt/dataDrogoRW` on the host, `/mnt/data` in the guest). Runs the `parr` stack (pinned commit, plus `arr/docker-compose.override.yml`, which turns Traefik and socket-proxy off) under `arr.service`. gluetun connects with kernel WireGuard (module loaded at boot by the playbook). Data copied from heimdall's `/docker/appdata` on 2026-11-17 and verified (file counts and sizes identical). Routes in `rproxy/traefik/dynamic/routes-arr.yml`, UniFi records moved to `192.168.0.21`. Details and lessons: [arr-guest-plan.md](arr-guest-plan.md).
- [x] PostgreSQL service: LXC `db` (126, `192.168.0.26`, native PostgreSQL 17, TLS, nightly dumps to Ymir), Ansible role `postgres_server`, **applied 2026-11-18** and verified (roles, databases, TLS, first backup, restore). See [section 7c](#7c-postgresql-service-db-guest--applied).
- [ ] UPS and safe shutdown: Ansible role `nut_client` written and dry-run checked, **prepared, not applied** (orisa does not read the UPS yet). See [section 7b](#7b-ups-and-safe-shutdown).
- [ ] Email notifications: Ansible role `postfix_relay` (direct delivery to an OVH redirection address, loop-proof matchers, queue alert; authenticated relay only as an optional fallback), **prepared, not applied**. See [section 7d](#7d-email-notifications-again-postfix-direct-delivery-to-an-ovh-redirection--prepared-not-applied).
- Drogo is mounted twice on the host: `/mnt/dataDrogo` (read-only, owner 101000, for jellyfin) and `/mnt/dataDrogoRW` (read-write, owner 1000, for arr). Each guest's own `mpN` line decides which one it sees.

### Where we stopped / next

1. Check the app integrations that use hostnames after the DNS move (Prowlarr apps, Bazarr, Seerr, download clients). Deferred Homarr integration edits and tile removal: see step 7 of the runbook in `arr-guest-plan.md`.
2. Watch `df -h` and `sensors` on orisa for a few days (transcoding plus the *arr stack). Retire heimdall's stack for good after about a week: remove its stopped containers, then the data it still holds in `/docker/appdata` (the rollback copy, about 6 GB with Jellyfin).
3. Build the `services` guest (valkey, zigbee2mqtt, ...) from the other `kornogHosted` stacks. PostgreSQL no longer goes there: it has its own guest `db` (next item).
3b. PostgreSQL `db` guest: applied. Left to do: Infisical's client address (see [section 7c](#7c-postgresql-service-db-guest--applied)).
4. Authelia and access hardening (guest firewall, container names for integrations, login in front of the admin UIs): [auth-and-hardening-plan.md](auth-and-hardening-plan.md). Noted, not started.
5. Apply the `nut_client` role (webhook file, dry run, `--tags nut`, checks: section 7b), then set the BIOS "power on after AC loss".
5b. Apply the `postfix_relay` role and then the matchers (section 7d).
6. Pending: two-factor (step 2b), confirm `default-matcher` lists `discord`, BIOS settings (SVM, IOMMU, power on after AC loss), restrict Ymir's `data` NFS export to orisa after heimdall is retired, drift check for guest definitions in Ansible.

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
- [ ] BIOS (optional): lowering the iGPU memory reservation from 3 GB would free RAM for the host. Its effect on Jellyfin hardware transcoding is not verified, so test transcoding after any change.
- [ ] Optional Proxmox firewall: Datacenter > Firewall. Before enabling, add a rule allowing `192.168.0.0/24` to TCP 22 and 8006, or you will lock yourself out. Enable at Datacenter level last.

### 4b. Rack move: LACP bond of both NICs (applied 2026-11-18)

Status: **applied 2026-11-18** (`802.3ad`, hash `layer2+3`, ports 7 and 8 aggregated in UniFi). Before that only `nic1` (port 7) had link and `nic0` (the port 8 cable) had no carrier, because `nic0` was administratively down (see step 0). There is no local console anymore, so the host change used self-reverting safety nets; they were armed but never had to fire, so the revert path itself is untested. Checks before the change: healthy host, static address and bridge MAC intact, `bonding` module loaded, `ifupdown2` installed, driver `r8169` on both NICs.

| Interface | MAC | Notes |
|---|---|---|
| `nic0` | `<nic0-mac>` | Realtek RTL8111/8168, 1 GbE, no carrier (second cable) |
| `nic1` | `<nic1-mac>` | Realtek RTL8111/8168, 1 GbE, up on switch port 7, bridge port of `vmbr0` |
| `nic3` | `<nic3-mac>` | ASIX AX88772 USB 2.0 adapter (100 Mb/s). Not plugged in, not for the bond |
| `wlp4s0` | `<wifi-mac>` | Wi-Fi, unused |

Notes on what UniFi shows:
- The host and every guest sit behind switch port 7, so UniFi lists one MAC per port, and it may be a guest's (`arr` in the check). A guest's address is set in its container config and has no UniFi reservation, so "Fixed IP" unticked there is normal.
- The host's reservation is tied to the host MAC (`vmbr0` takes `nic1`'s MAC). Look it up by that MAC in Client Devices.

**0. The second link.** Do not judge the port 8 cable by `ethtool nic0` yet. `nic0` is administratively down (`iface nic0 inet manual` without `auto`, no UP flag in `ip link`), and the `r8169` driver does not negotiate a link on an interface that is down, so "no carrier" is expected until the bond brings it up. A port LED that lights at boot and then goes out fits this (a hypothesis, not tested). Do **not** bring `nic0` up by hand with `ip link set nic0 up`: a standalone NIC on the same LAN answers ARP requests for `192.168.0.12` with its own MAC (ARP flux) and makes the host flaky. After step 3 `nic0` should show link. Only if it still has none, check the cable, the other RJ45 socket and the UniFi profile of port 8.

**1. Choose the mode.**

| Mode | Needs a UniFi change | Result |
|---|---|---|
| `802.3ad` (LACP) | yes, Aggregate on ports 7 and 8 | up to 2 Gb/s in total across several flows (a single transfer stays at 1 Gb/s), failover |
| `active-backup` | no | one link carries traffic, the other takes over on failure. Works with one cable linked |

Bandwidth expectation: LACP balances per flow, not per packet. All NFS traffic to Ymir comes from the host's single IP over one TCP connection per mount, and the guests only bind-mount it, so a single transfer stays at 1 Gb/s whatever the hash policy. A total above 1 Gb/s needs several flows (tried 2026-11-18, no gain between orisa and Ymir, see the Result below): for example `nfs ... nconnect=4` in the mount options with `bond-xmit-hash-policy layer3+4`, plus the switch's and Ymir's own hashing for the return direction (not verified). Measure before and after (`iperf3` between orisa and a second host).

**2. Order: host first, then the switch.** A UniFi aggregate on ports 7 and 8 while the host is not bonded probably suspends the link (LACP without a partner), which would cut orisa off with no console. Bonding the host first is safe with one cable: Linux forms a one-port aggregate even without a partner. (Neither behaviour was tested on this switch.)

**3. Host bond with safety nets** (as root on orisa, one block at a time; this is what was run):
```bash
cp -a /etc/network/interfaces /root/interfaces.pre-bond
# write /root/interfaces.new with the stanzas below (a heredoc, no manual editing), then check the diff
# safety nets, armed BEFORE anything changes: restore the old file after 8 min, and after 12 min
# reboot with it if the gateway still does not answer. Both survive losing the SSH session.
systemd-run --unit=net-revert --on-active=8m \
  /bin/sh -c 'cp -a /root/interfaces.pre-bond /etc/network/interfaces && /usr/sbin/ifreload -a'
systemd-run --unit=net-revert-reboot --on-active=12m \
  /bin/sh -c 'ping -c3 -W2 192.168.0.1 >/dev/null 2>&1 || { cp -a /root/interfaces.pre-bond /etc/network/interfaces; systemctl reboot; }'
cp /root/interfaces.new /etc/network/interfaces
systemd-run --unit=net-apply /usr/sbin/ifreload -a     # detached, a dropped SSH session cannot leave it half done
```
The `802.3ad` stanzas (keep one `iface nic0 inet manual`, delete the duplicate further down):
```
iface nic0 inet manual
iface nic1 inet manual

auto bond0
iface bond0 inet manual
        bond-slaves nic1 nic0
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
```
For `active-backup` use `bond-mode active-backup` and `bond-primary nic1` instead of the `802.3ad` and hash lines. `hwaddress` keeps the bridge on the MAC covered by the UniFi reservation (the bond would otherwise give it the first slave's MAC). No VLAN lines are needed. The SSH session may stall for a few seconds, reconnect.

**4. Check, then cancel the safety net:**
```bash
cat /proc/net/bonding/bond0       # mode as chosen, nic1 MII up; with 802.3ad the partner MAC stays 00:... until the switch is configured
ip -br link | grep -E 'bond0|vmbr0'    # vmbr0 must still have the nic1 MAC
ping -c3 192.168.0.1; pct list; pct exec 123 -- ping -c2 192.168.0.1
findmnt /mnt/dataYmir /mnt/dataDrogo /mnt/dataDrogoRW /mnt/pve/ymir-backup
systemctl stop net-revert.timer net-revert-reboot.timer   # only when everything above is fine, within 8 minutes
```
If the session does not come back, do nothing: after 8 minutes the old file is restored, and after 12 minutes the host reboots into it if the gateway still does not answer. Only physical access helps if that fails too.

**5. Switch side, `802.3ad` only**, after both slaves show `MII Status: up` in the bond file: UniFi Port Manager, select ports 7 and 8, Aggregate. Expect a few seconds of interruption. Then `/proc/net/bonding/bond0` must show the same Aggregator ID on both slaves and a non-zero partner MAC. The 5-minute host revert does not undo the switch change: undo the aggregate in UniFi by hand if the host disappears.

**6. Afterwards:** pull one cable and check connectivity holds, then put it back. Record the result here and in `ansible/README.md` (the network is not managed by Ansible). Open: BIOS "power on after AC loss" (cannot be checked remotely; without it a rack power cut leaves the host off), and an out-of-band option (smart plug, PiKVM) is worth considering.

**Result (2026-11-18).**
- Host bond applied: about 3 s of interruption (14:15:42 to 14:15:45), the bridge returned to forwarding by itself. Guests, mounts and containers were unaffected.
- `nic0` got its link as soon as the bond enslaved it, which confirms the step 0 explanation (the cable was fine).
- Before the switch was aggregated each NIC was its own aggregator (IDs 1 and 2, partner MAC all zeros) and one carried traffic. After UniFi aggregated ports 7 and 8: both slaves in Aggregator ID 1, `Number of ports: 2`, partner MAC is the switch's.
- `vmbr0` kept MAC `<nic1-mac>` (the `hwaddress` pin), so the UniFi reservation still applies. The `bridge-fd 0` "out of range" warning from `ifupdown2` is in the original config too and is harmless.
- Kept as manual rollback copies: `/root/interfaces.pre-bond` and `/root/interfaces.new`.
- Failover test, `nic0` only: `nic0` taken down in software for 20 s with a ping every 0.2 s from the desktop. The bond went to 1 port and returned to 2 by itself; 3 packets were lost (about 0.6 s) when the flow moved to the other link, none when `nic0` rejoined. The same test for `nic1` was not done, and no cable was physically pulled.
- Throughput, tried 2026-11-18 with `iperf3` (TCP, `layer2+3`): no improvement between orisa and Ymir, as expected from how LACP works. It spreads different flows over the links, never one flow, and traffic between the same two hosts keeps to the same link (about 934 Mb/s per stream, still about 940 Mb/s with parallel streams or three senders at once). The bond gives redundancy (failover tested), not more bandwidth for this pair. `layer3+4` and real file transfers were not tried. `iperf3` stays installed on orisa, its service is disabled.
- Open: the BIOS "power on after AC loss" setting.

Details and evidence: `.agents/tasks/orisa-rack-network-report.md` (local, not committed).

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

- [x] Datacenter > Notifications: Webhook target `discord` (POST to the Discord webhook URL, token stored as secret `token` and referenced as `{{ secrets.token }}`, header `Content-Type: application/json`, body `{"content": "**[{{ severity }}]** {{ escape title }}"}`), added to `default-matcher`. Keep the body short: Discord rejects messages over 2000 characters (HTTP 400), and backup failure logs exceed that. Other options are SMTP, Gotify and ntfy. Mail from `smartd` and cron goes to root, and the forwarder turns it into a notification of type `system-mail`.
  - **Email is off (2026-11-21), its return is prepared in section 7d.** `default-matcher` used to list `mail-to-root` besides `discord`. That target mails root's address, but Postfix on orisa could not reach Gmail's port 25 (the Freebox blocked it), so the mails sat in the queue and returned as "Undelivered Mail Returned to Sender" after 5 days. Proxmox forwards mail to root into its own notification system (`/root/.forward`), so each bounce reached Discord as `[unknown]` and was mailed again, a slow loop (22 mails stuck, 13 of them bounce notices). Fix: `pvesh set /cluster/notifications/matchers/default-matcher --target discord`, then `postsuper -d ALL` to empty the queue. Mail to root from other sources (cron, disk health) still goes through the forwarder, now to Discord only. Section 7d (role `postfix_relay`, prepared, not applied) brings email back by direct delivery to an OVH redirection address (no mailbox needed), with the loop made impossible by construction.
- [ ] SMART: `smartctl -a /dev/nvme0` for a baseline. Proxmox runs `smartd`; set the email in `/etc/smartd.conf` or rely on notifications.
- [x] Homarr Proxmox integration (2026-11-19): a dashboard widget showing node, containers, storage and CPU/RAM. It uses a dedicated read-only account in the built-in `pve` realm, because the docs say PAM users may not work with the API. Commands (run from the desktop, single-quote anything with `!` or bash history expansion eats it):
  - `pveum user add homarr@pve --comment 'Homarr read-only monitoring'` and `pveum acl modify / --users homarr@pve --roles PVEAuditor`
  - `pveum user token add homarr@pve homarr --privsep 1 --output-format json` (the secret is shown once: pipe it straight to `wl-copy`, never to the screen)
  - `pveum acl modify / --tokens 'homarr@pve!homarr' --roles PVEAuditor`. A token created with privilege separation has its own permissions, so the grant is needed for the user and for the token, and the token has to exist first.
  - `PVEAuditor` is read only (`Datastore`, `Mapping`, `Pool`, `SDN`, `Sys`, `VM`, `VM.GuestAgent` audit privileges). Check with `pveum user permissions 'homarr@pve!homarr' --path /`.
  - In Homarr (Management > Integrations > Proxmox): URL `https://orisa.kornoglab.fr:8006` (the certificate is valid, nothing to disable), username `homarr`, realm `pve`, token ID `homarr`, the secret as API key. Homarr builds the token as `<username>@<realm>!<tokenId>`.
  - Result: 1 node, 4 containers, 0 VMs, 3 storages. Open: the integration is stored with an `http://` URL. Port 8006 redirects plain HTTP to HTTPS, so it works, but it should be edited to `https://` (Homarr asks for the key again on save). Revoke with `pveum user token remove homarr@pve homarr`.
- [ ] `sensors-detect` then `sensors` to check temperatures. Mini PCs run warm under sustained transcoding.
- [ ] Optional: expose metrics (Datacenter > Metric Server) to InfluxDB/Prometheus, and add a Proxmox integration in Homarr.
- [x] UPS: the UniFi UPS 2U powers orisa and both NAS units. Monitoring and safe shutdown on orisa: section 7b (prepared, not applied).

---

## 7b. UPS and safe shutdown

Status: **applied 2026-11-18.** The Ansible role `nut_client` ([`../ansible/roles/nut_client`](../ansible/roles/nut_client)) is installed on orisa. `nut-monitor` runs, `upsmon` holds a TLS connection to the UPS and no login refusal is logged (the `monuser` / `secret` login is accepted), and the test alert reached Discord. Not tested: a real power cut.

### What was decided and why

- orisa, ymir and drogo hang on the UniFi UPS 2U (`192.168.0.138`, NUT server, UPS name `ups`). orisa is behind a power strip, not plugged into the UPS directly, and it is not in the UPS "Safe Shutdown Pairing". The UPS "Power Cycle on Restore" does not apply to it.
- **orisa shuts down at the same moment as the NAS units.** UniFi starts the safe shutdown when the remaining battery runtime reaches 5 minutes, and ymir and drogo follow that as Synology network-UPS clients ("Same as server"). orisa uses NUT's own low-battery handling: `upsmon` shuts the host down when the UPS reports `LB` (low battery), or `FSD` if it ever occurs. There is no timer, no percentage rule and no `upssched`.
- orisa is a **secondary** client (`MODE=netclient`, `MINSUPPLIES 1`). It only shuts itself down. It never tells the UPS to cut power.
- `SHUTDOWNCMD` is `/sbin/shutdown -h +0`, so it goes through systemd. Proxmox then stops the guests in reverse start order (123 `arr`, 122 `jellyfin`, 121 `rproxy`) before the mounts go away. The guests stop first, so nothing writes to the NFS mount when ymir disappears. This relies on the existing `10-nfs.conf` drop-in (guests start after the NFS mount, so they stop before it).
- Timing: the last clean shutdown of orisa took about 107 s (2026-11-18, guests 43 s of that). UniFi's trigger leaves 5 minutes of estimated runtime, so there is roughly 3 times the time needed. The runtime figure is not reliable, though: the UPS reports a load of 0 W although the three machines hang on it.
- **Alerts to Discord** come from `upsmon` (`NOTIFYCMD`) for ONBATT, ONLINE, LOWBATT, FSD, COMMBAD, COMMOK and SHUTDOWN. Each message names the event and gives the battery percentage and the runtime in minutes, read with `upsc` at that moment (shown as `unknown` if the UPS cannot be read). The same line goes to syslog (`logger -t nut-notify`). The script uses short timeouts (3 s for `upsc`, 5 s for `curl`) and ignores failures, so it cannot hold up a shutdown. It builds the JSON with `python3`, accepts only known event names, and disables Discord mentions.
- The webhook URL is a secret. It is kept in `nut/discord.env` (git-secret, same convention as `arr/.env`) and installed as `/etc/nut/discord.env`, mode 0640, owner `root:nut` (`upsmon` runs the notify script as the `nut` user). The role stops with a clear message if `nut/discord.env` is missing or has no URL.

### Reading the battery by hand

```bash
# host or any machine on the LAN with nut-client; reads only, no login needed
upsc ups@192.168.0.138 | grep -E '^(ups.status|battery.charge|battery.runtime):'
```

Reference values on 2026-11-18: `OL` (on line), 100 %, runtime 4340 s.

### Apply and verify

Run from the controller (pachimari). Steps 1 and 2 happen in the repo root, the rest in `ansible/`.

```bash
# 1. webhook file (plain text stays out of git, only the encrypted copy is committed)
cd /var/home/gart/depots/kornogHosted
cp nut/discord.env.sample nut/discord.env
$EDITOR nut/discord.env            # DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
git secret add nut/discord.env && git secret hide

# 2. dry run: shows the package, /etc/nut files, the script and the webhook file (its content is hidden)
cd ansible
ansible-playbook site.yml --check --diff --limit orisa --tags nut -K

# 3. apply
ansible-playbook site.yml --limit orisa --tags nut -K
```

A dry run on a host without the package skips the service task and the restart handler, since the unit does not exist yet. Files show owner `root` instead of `nut` for the same reason.

Then on orisa:

```bash
systemctl status nut-monitor                  # active (running), enabled
journalctl -u nut-monitor -b --no-pager       # look for the login result
upsc ups@192.168.0.138 | grep -E '^(ups.status|battery.charge|battery.runtime):'
upsmon -h                                     # usage only, changes nothing
ls -l /etc/nut /usr/local/sbin/nut-notify     # discord.env and upsmon.conf: root:nut 0640; script 0750
# harmless alert test: sends one real Discord message marked TEST, no UPS event, no shutdown
runuser -u nut -- env NOTIFYTYPE=ONLINE /usr/local/sbin/nut-notify "TEST from orisa, ignore"
journalctl -t nut-notify -n 5 --no-pager      # the same line, from syslog
```

Expect the Discord message `orisa: UPS ONLINE - TEST from orisa, ignore | battery 100 %, runtime 72 min` (values will differ). If the Discord message is missing, `journalctl -t nut-notify` says whether the webhook file was unreadable or `curl` failed.

### If the UPS login is refused

The server has "Login Credential" off, so it should not check anything. That is not verified for `upsmon` logins. The role uses the Synology client defaults `monuser` / `secret` (not real secrets). The first start decides: `journalctl -u nut-monitor` either shows the UPS as being monitored and `on line`, or an access-denied or login-failed line, and then `upsmon` retries without shutting anything down. To change the pair, set `nut_client_user` and `nut_client_password` (for example in `ansible/group_vars/proxmox.yml`) and apply again. The role restarts `nut-monitor` when `upsmon.conf` changes. The login that ymir and drogo use is shown in DSM (Control Panel > Hardware & Power > UPS), which can be used to copy their values.

### Limits and open items

- **BIOS "power on after AC loss" is not set.** After a UPS-triggered shutdown, orisa restarts by itself only if that BIOS option is enabled and the power was really cut. If the mains returns before the UPS cuts its outlets, orisa stays off. Otherwise: power button or Wake-on-LAN. Wake-on-LAN is not built. Setting the BIOS option is still pending (also listed in step 4).
- NUT login with `monuser` / `secret` is **unverified** (see above).
- **Client limit.** Community posts report that the UniFi UPS's NUT server accepts at most 3 clients (threads on community.ui.com; Ubiquiti documents no number). Checked 2026-11-18: with orisa connected as the third client (ymir, drogo, orisa), both NAS units still show the UPS in DSM (Hardware & Power > UPS > Device Information), and short `upsc` reads from orisa still answer on top of the three. A fourth **persistent** client (Home Assistant NUT integration, PeaNUT) was not tried: one report says the server can stop answering when over the limit, which would hurt the NAS shutdowns. Do not add one without a plan (a NUT proxy on orisa with `dummy-ups` in repeater mode could serve more readers, at the price of one more component in the shutdown path). The UPS refuses `LIST CLIENT`, so the client count cannot be read.
- **UPS firmware.** UniFi UPS release 1.6.9 fixed the NUT server not reporting `FSD` to clients when safe shutdown was armed on battery. Checked 2026-11-18: the UPS reports its firmware as up to date in UniFi (version number not recorded). Re-check after UniFi updates.
- The UPS runtime estimate is not trustworthy (load reported as 0). The 5-minute trigger is UniFi's, not orisa's.
- A real power cut test has not been done, and should not be done just to test (see below).
- The notify script was tested on the desktop with stub `curl` and `upsc` only. It has not run on orisa or sent a message to the real Discord webhook.

### What must never be run as a "test"

- `upsmon -c fsd` (forces shutdown for every client, including this host)
- `upsdrvctl shutdown`, `upscmd` with any `shutdown.*` command
- `shutdown` or `systemctl poweroff` to see `SHUTDOWNCMD` work
- unplugging the UPS input, or simulating low battery on a NAS: this takes ymir and drogo down too

---

## 7c. PostgreSQL service (`db` guest) — applied

Shared PostgreSQL for the other services, in its own LXC guest `db` (VMID 126, `192.168.0.26`, name `db.kornoglab.fr`). Native Debian 13 packages, no Docker. It replaces the old, never-used `postgres/` compose folder. Code: Ansible role [`postgres_server`](../ansible/roles/postgres_server), guest definition and service list in [`ansible/host_vars/db.yml`](../ansible/host_vars/db.yml). Nothing of it has been applied to orisa yet.

### Decisions and why

| Topic | Choice | Reason |
|---|---|---|
| Guest | own unprivileged LXC `db`, `192.168.0.26`, VMID 126 | one guest per service when possible |
| Software | PostgreSQL **17** (`postgresql` package of Debian 13, candidate `17.12-0+deb13u1` read on orisa 2026-11-18) | the packaged major version. Infisical's documentation names 16 as its tested version and recommends 14 or newer, Authelia supports any version still supported upstream |
| Docker | none | the inventory group `native_guests` holds `db`. The Docker and compose play runs on `guests:!native_guests`, so `rproxy`, `jellyfin` and `arr` match exactly as before. `lxc_guest` still creates `db` because it is also in `guests` |
| Start order | `order=1` | no `up=` delay. It ties with `rproxy` (1) and Proxmox starts the lower VMID first, so `rproxy` goes first. `rproxy` does not need the database. Clients (the future `auth` guest and Infisical's host) must use order 2 or higher. Shutdown runs in reverse order, so `db` stops after its clients |
| CPU / RAM / swap | 2 cores, 2048 MB, 256 MB | see below |
| Disk | 8 GB (proposal, open point) | Debian plus PostgreSQL is about 1.5 GB, two small databases stay in the MB range, dumps live on Ymir. Growing later is easy (`pct resize`), shrinking is not. 16 GB would also work |
| `shared_buffers` | 256 MB (proposal, open point) | used lazily, sized to a 2 GB guest on a shared host |
| `effective_cache_size` / `work_mem` / `maintenance_work_mem` | 1 GB / 4 MB / 64 MB | sized to the guest |
| `max_connections` | 50 | Authelia and Infisical use connection pools. Infisical's documentation says a rolling deploy briefly doubles the connections |

**Memory.** The host reports 12.7 GB (the iGPU reserves 3 GB). On 2026-11-18 about 3.7 GB were used and 8.9 GB available. Guest limits are caps, not reservations: rproxy 512 MB, jellyfin 4096 MB and arr 6144 MB already add up to more than the host, because their real use is small (rproxy 80 MB, jellyfin 287 MB, arr 1077 MB, the rest is reclaimable cache). 2 GB for `db` is a cap that two small databases will not approach. `shared_buffers` is used lazily, so 256 MB costs nothing until the data needs it. About 512 MB would also fit; the smaller value is proposed for a 2 GB guest. All values are `postgres_server_*` variables.

### What the role sets up

- **Roles and databases:** one role and one database per entry of `postgres_server_services`, the database owned by the role (UTF-8, created from `template0`). Application roles are never superusers and cannot create databases or roles. `CONNECT` on each database is revoked from `PUBLIC`. No extension is installed.
- **Passwords:** random, 64 alphanumeric characters, one per role, in `postgres/db-passwords.env` (git-ignored, mode 600) on the controller. The role reads them there. The tasks that handle them use `no_log` and have diff off.
- **`pg_hba.conf`** (whole file templated): local `postgres` by peer, other local access rejected, remote only `hostssl <db> <role> <client>/32 scram-sha-256`, everything else rejected. `ssl = on`, `ssl_min_protocol_version = TLSv1.2`, `password_encryption = scram-sha-256`.
- **Settings** are in the drop-in `/etc/postgresql/17/main/conf.d/10-kornoglab.conf`. The Debian main file is untouched.
- **Clients per service:** `clients` in `host_vars/db.yml`. Changing an address is a one-line edit, then `--tags postgres`. A service with an empty list still gets its role and database, no `pg_hba` line, and the run prints a message naming it. A value that is not an IPv4 address stops the run before any change.

### TLS certificate

The server uses the wildcard `*.kornoglab.fr` certificate (it covers `db.kornoglab.fr`). The acme folder is bind-mounted read-only at `/certs` (as for `rproxy`). PostgreSQL refuses a key readable by others, so `pg-tls-sync` copies the files to `/etc/postgresql/tls/<timestamp>/` (key 0600 `postgres`) and swaps the symlink `current`.

- It runs 2 minutes after boot and daily at 04:00 guest time, Europe/Paris (`pg-tls-sync.timer`, `Persistent=true`). A path unit would not see a change made by another host on NFS.
- Checks before anything changes: files present, readable and not empty, certificate parses, not expired, covers `db.kornoglab.fr`, key matches the certificate. Any failure exits non-zero, keeps the current copy, and PostgreSQL keeps running. The failure goes to Discord (below).
- **Early expiry warning:** a certificate that is valid and passes every check but has fewer than `postgres_server_cert_warn_days` days left (default 14, 0 turns it off) is still installed as usual, and `pg-tls-sync` calls `pg-notify --cert-expiry <days>`. Discord gets "`db: WARNING the TLS certificate for PostgreSQL has N day(s) left. ...`" on every daily run until the certificate is renewed (the acme container renews about 30 days before expiry, so a warning means the renewal stopped). `N` is whole days, rounded down, computed from the certificate's end date. The message is fixed text plus that number, so no input can add to it. An expired certificate is unchanged behavior: failure and the `OnFailure` alert. To see the warning without touching a certificate, in `db`: `sed 's/^WARN_DAYS=.*/WARN_DAYS=60/' /usr/local/sbin/pg-tls-sync > /tmp/s && bash /tmp/s; rm /tmp/s` (the real certificate has fewer than 60 days left; the copy only runs the checks, installs nothing when the files are unchanged, and posts one warning). `pg-notify --cert-expiry 3` posts a test message directly.
- Identical files: no change and no reload. Otherwise the new copy is installed and PostgreSQL reloaded. If the reload command fails, the old link is put back. The last three copies are kept.
- The first Ansible run executes the script once, so a missing certificate stops the run with a clear message.

Clients connect to `db.kornoglab.fr` with `sslmode=verify-full`. This needs the UniFi A record (step 1 below). Connecting by IP address fails the name check, by design.

### Backups

The nightly vzdump job (02:00 Paris, all guests, storage `ymir-backup`) covers the guest. In addition, `postgres-backup.timer` runs `pg-backup` daily at 03:30 guest time (Europe/Paris). The vzdump job of 2026-11-18 took about 2 minutes for the three existing guests, so 90 minutes separate the two jobs:

- `globals.sql` (`pg_dumpall --globals-only`, holds the password hashes) and `<db>.dump` (`pg_dump --format=custom`) per database, in `/mnt/pgbackup/<YYYY-MM-DD>/`. Each dump is checked with `pg_restore --list`. The folder is written as `<date>.partial` and renamed when complete.
- Folder names use the guest's local date. Around midnight UTC, Paris is already on the next day, so a manual run between 23:00 and 24:00 UTC (winter) is filed under the Paris date. If the 03:30 run later finds a folder of the same name, it replaces it (existing logic). Retention sorts by name, so it is unaffected.
- `/mnt/pgbackup` is a bind mount of `/mnt/dataYmir/postgres_backup` (`mp1`), so the dumps are outside the guest, and vzdump skips it.
- **A missing mount can never fill the guest disk.** The script stops unless `/mnt/pgbackup` is a mount point and the file `.pgbackup-sentinel` exists in it. Otherwise it writes nothing and exits non-zero.
- **Owner on Ymir:** the dump runs as root of the guest, which is uid `100000` on the host (`/etc/subuid`), and the share has no root squash. The folder is therefore `100000:100000`, mode 0700, so no other NFS client can read the password hashes. The files are 0600. This is the same uid that vzdump runs as. The first backup in the guest is the real proof that writing works.
- **Retention (proposal, open point):** the newest 14 daily folders plus the folders dated the 1st of the newest 6 months. The total size stays small. Pruning runs only after a successful dump and only touches names of the form `YYYY-MM-DD`.
- **How a failure is noticed (open point):** `postgres-backup.service` and `pg-tls-sync.service` have `OnFailure=` pointing to a unit that runs `pg-notify`, which posts "`db: <unit> failed at <time>`" to the Discord webhook (same pattern as `nut_client`, message without any secret). Alternatives: mail (no relay is configured), Proxmox notifications (they only cover vzdump jobs, not jobs inside a guest), a dead-man's switch such as Healthchecks (needs an external service). Cost of the chosen option: a copy of the webhook secret (`nut/discord.env`) in the guest at `/etc/postgresql/discord.env` (mode 0600, root). If the guest were compromised, the attacker could post to that channel. Not detected: the guest down or the timer not firing. A dead guest shows in the vzdump notifications. Set `postgres_server_notify_enabled: false` to go without.

### Time zone
The role sets the guest time zone (`postgres_server_timezone`, default `Europe/Paris`, as on the Docker guests): symlink `/etc/localtime` and `/etc/timezone`, package `tzdata`. When it changes, the role restarts the two timers so they recompute their next run. Effect: timers use local time, so `postgres-backup.timer` and `pg-tls-sync.timer` still say 03:30 and 04:00, which is now Paris time. The dump moves from 03:30 UTC to 02:30 UTC in winter (01:30 UTC in summer), that is from 04:30 to 03:30 Paris time. It stays 90 minutes after vzdump (02:00 Paris), which finishes in minutes. The certificate sync copies are now named in UTC, so sorting stays right whichever zone is set. PostgreSQL itself keeps `timezone = 'Etc/UTC'` (set when the cluster was created), so timestamps seen by applications do not change. The guest's `date`, journal and the Discord messages show Paris time with the zone name.
### Restore procedure (tested locally, see "Tested")

On `db`, as root. `<date>` is a folder of `/mnt/pgbackup`. The dump files belong to root, so give them to `pg_restore` on standard input.

```bash
# host: db (root). One database, into a scratch name first
D=/mnt/pgbackup/<date>
runuser -u postgres -- createdb -T template0 -E UTF8 --locale=C.UTF-8 -O authelia authelia_restore
runuser -u postgres -- pg_restore --exit-on-error -d authelia_restore < $D/authelia.dump
runuser -u postgres -- psql -d authelia_restore -c '\dt'   # check, then drop it: dropdb authelia_restore
```

To replace the real database: stop its client, `runuser -u postgres -- dropdb authelia`, create it as above with the real name, restore, start the client, then run `ansible-playbook site.yml -K --limit db --tags postgres` once to put the `CONNECT` revoke back.

To rebuild a whole server (after a new `db` guest and the role are applied, the roles already exist): `runuser -u postgres -- psql -f - postgres < $D/globals.sql` loads the roles and password hashes. Errors "role ... already exists" are expected for roles that exist. Then create and restore each database as above. If the guest itself is lost, restore it from the vzdump backup (spare VMID, see section 6) or rebuild it with the playbook and restore the dumps.

### Commands to run (in this order)

1. **UniFi:** add the Host (A) record `db.kornoglab.fr` → `192.168.0.26` (Settings > Routing & Firewall > DNS, as in the main README). Check: `dig +short db.kornoglab.fr`.
2. **pachimari, passwords:** `./postgres/make-secrets.sh`, then `git secret add postgres/db-passwords.env && git secret hide`, then commit `postgres/db-passwords.env.secret`. The script prints only key names.
3. **pachimari, retire the old files** (the old folder was never used): run `git secret remove -h` first to check the flags, then `git secret remove postgres/.env postgres/postgres.secrets.env`, `git rm postgres/.env.secret postgres/postgres.secrets.env.secret`, `rm postgres/.env postgres/postgres.secrets.env`, and delete the lines `postgres.secrets.env` and `.env` from `postgres/.gitignore`. The compose file and sample files are already gone from the working tree (commit that deletion).
4. **orisa, as root, before creating the guest** (`mp1` needs the folder, and if `pct set` failed after `pct create` the role would skip the guest next time because it exists):
   `install -d -o 100000 -g 100000 -m 0700 /mnt/dataYmir/postgres_backup` and
   `install -o 100000 -g 100000 -m 0600 /dev/null /mnt/dataYmir/postgres_backup/.pgbackup-sentinel`
5. **Dry run:** `cd ansible && ansible-galaxy collection install -r requirements.yml && ansible-playbook site.yml --check --diff -K --limit orisa`. The tasks for `db` show as skipped, because dry runs skip commands. Nothing may change for 121 to 123.
6. **Create the guest and apply:** `ansible-playbook site.yml -K --limit orisa,db`. If you set a client address for Infisical first, it is included.
7. **Verify:**
   - in `db`: `systemctl list-timers` lists `pg-tls-sync` and `postgres-backup`. `runuser -u postgres -- psql -c 'show ssl'` says `on`.
   - TLS login: `./postgres/copy-password.sh authelia` copies the password to the clipboard (pasted once, not shown), then `psql "host=db.kornoglab.fr dbname=authelia user=authelia sslmode=verify-full"` and paste. Only the addresses in `clients` are accepted, today `192.168.0.25` (the future `auth` guest), so from pachimari the connection is refused. To test a login from pachimari, temporarily add `192.168.0.33` to `clients` of `authelia`, run `--tags postgres`, test, then remove it again.
   - from a non-listed address, the connection must be refused (`pg_hba.conf rejects connection`).
8. **First backup and restore test:** in `db`, `systemctl start postgres-backup`. Check `/mnt/dataYmir/postgres_backup/<date>/` on orisa (owner 100000). Restore into a scratch database with the procedure above. Then test the alert: `rm /mnt/pgbackup/.pgbackup-sentinel; systemctl start postgres-backup` must fail and post to Discord. Put the sentinel back with `touch` afterwards.

### How to add a database for a new service

1. Add an entry in `ansible/host_vars/db.yml`: `- name: <service>` (lowercase letters, digits, underscore) and `clients: ["<ip of the host running it>"]`.
2. `./postgres/make-secrets.sh <service>` (only adds the missing key), then `git secret hide` and commit the `.secret` file.
3. `ansible-playbook site.yml -K --limit db --tags postgres`. The run adds the role, the database and the `pg_hba` line.
4. `./postgres/copy-password.sh <service>` to paste the password into the service's configuration. Use `sslmode=verify-full` and host `db.kornoglab.fr`.

### What the official documentation says

- **Infisical** ([requirements](https://infisical.com/docs/self-hosting/configuration/requirements), [environment variables](https://infisical.com/docs/self-hosting/configuration/envars)): PostgreSQL only, "extensively tested" on 16, 14 or newer recommended. The database user needs all privileges on its database, including creating schemas, tables and indexes (the owning role has them). Connection through `DB_CONNECTION_URI` with `sslmode` in the query string. It also needs Redis, which is not part of this service.
- **Authelia** ([PostgreSQL storage](https://www.authelia.com/configuration/storage/postgres/)): any PostgreSQL version still supported upstream. Options `address`, `database`, `schema` (default `public`), `username`, `password`, `tls`. It verifies the server certificate against the system trust store and migrates its own schema. It recommends a random alphanumeric password of 64 characters or more, which matches the generator.
- **Not verified:** neither page names required extensions or an encoding, so none are installed (UTF-8 databases). Check each service's first start log. Whether Infisical's Node client verifies a Let's Encrypt chain with the container's trust store without `DB_ROOT_CERT` is unconfirmed (the documentation shows that variable only for cloud providers). Try `sslmode=verify-full` first. The Authelia version-support page that was fetched was truncated, so that criterion comes from the search snippet of its GitHub source.

### Applied and verified (2026-11-18, on the real guest)
- Guest `db` created by the playbook (`ansible-playbook site.yml -K --limit orisa,db`), role applied to it. A second run: `changed=0`.
- **Lesson:** the first run stopped at "Application roles" with "No start of json char found". The Debian LXC template has no `sudo`, and Ansible's default become method is `sudo`. The task output was hidden by `no_log`, so the cause only showed with a password-free ad hoc call. The role-creation tasks now use `become_method: ansible.builtin.su`. The podman tests did not catch it.
- `\du`: `authelia` and `infisical` have no attributes (not superusers), only `postgres` does. `\l`: each database is owned by its role, UTF-8, with the `PUBLIC` connect right revoked.
- TLS: `openssl s_client -starttls postgres -connect db.kornoglab.fr:5432 -verify_hostname db.kornoglab.fr` returns `Verification: OK`, issuer Let's Encrypt. This works from any address, the handshake comes before the `pg_hba` check.
- First backup: `/mnt/dataYmir/postgres_backup/<date>/` holds `globals.sql`, `infisical.dump`, `authelia.dump`, owned by `100000`, mode 0600. A second run on the same day replaces the folder.
- Restore test: `authelia.dump` restored into a scratch database and dropped (the database is still empty, so no tables yet). The restore of real data has not been tested.
- Failure path: with the sentinel file removed, `systemctl start postgres-backup` fails with exit 1 and writes nothing. The journal shows `pg-notify` building the message (`db: postgres-backup.service failed at ...`); the message itself was not looked at in Discord, but the same script, webhook file and `curl` call delivered the certificate warning, so the path is proven. After the test the sentinel was recreated from inside the guest (`install -m 0600 /dev/null /mnt/pgbackup/.pgbackup-sentinel`, owned by `100000` on Ymir).
- Follow-ups applied 2026-11-19 (`ansible-playbook site.yml --limit db --tags postgres`): first run `changed=5` (time zone, the two scripts, timer restart), second run `changed=0`. `date` on the guest shows CET, the timers now fire at 03:30 and 04:00 Paris time. The warning path was exercised with the threshold raised to 60 days: it reported "certificate has 35 day(s) left" and left the installed files unchanged. The Discord message arrived ("db: WARNING the TLS certificate for PostgreSQL has 35 day(s) left. Check that the acme renewal still runs.", stamped in CET). The real certificate ends 2026-12-25, so with the default 14 days no warning is expected before renewal.
- Still to do: a real restore once a service has data, and the first `psql` login over TLS from an allowed address (the future `auth` guest). Infisical is shelved, so its `clients` entry stays empty.

### Tested (2026-11-18, throwaway Debian 13 systemd containers, since removed)

- Role run twice: second run `changed=0`. Cluster UTF-8, `ssl on`, `max_connections` 50, roles not superusers, databases owned by their role, `pg_hba_file_rules` without errors, role and database created for a service with no client.
- Over TLS from a second container: `verify-full` login as the allowed address works. Refused: another address, no TLS, wrong password, a role on another service's database, an entry with no client, connecting by IP (name mismatch).
- Certificate sync: unchanged files (no reload), renewal (installed, reload logged, key 0600), mismatched key, garbage, empty, missing, unreadable by another user, expired, wrong name (all non-zero with the current link unchanged and PostgreSQL up), failed reload (link put back, retry works), keeping three copies.
- Backup: dumps, `pg_restore --list`, retention on fake folders (14 daily + 6 first-of-month, other names untouched), refusal without sentinel and without mount point, failure with PostgreSQL stopped (no final folder created).
- Restore: drop and restore of a database (row count and owner identical), `globals.sql` loaded on a fresh cluster (only the expected "role already exists" errors).
- Failure notification: `OnFailure` ran `pg-notify` after a failed backup. The URL goes to curl on stdin only, the message holds the host, unit and time. Without a webhook file it logs and exits 0. A hostile unit name is replaced by `unknown`.
- Secrets: a `-vvv --diff` run does not contain any of the passwords. Missing file, missing key, bad IPv4 and bad name each stop the run with a clear message.
- **Not tested:** the real LXC (unprivileged uid mapping, bind mounts, a write to Ymir as uid 100000), a systemd run under LXC rather than podman, the real Let's Encrypt chain, the exact package `17.12` (the container had the current trixie package), the Discord post to the real webhook, `pct create` with `mp1`, and a dry run that shows the guest as "to be created" (dry runs skip `command` tasks). The `createcluster.d` UTF-8 setting is harmless but not shown to be needed: a trixie container without any `LANG` already created a UTF-8 cluster.

### Open points

1. Infisical's client address (`clients: []` in `host_vars/db.yml`).
2. How failed dumps are noticed: Discord from the guest is proposed. Not covered: the guest down or the timer not firing.
3. Retention: 14 daily and 6 monthly are proposed. vzdump uses 7, 4 and 3.
4. Disk: 8 GB proposed (16 GB was suggested). `shared_buffers` 256 MB proposed (512 MB was suggested).
5. PostgreSQL 17 is the packaged major version. Infisical documents 16 as the tested one.
6. The BIOS iGPU memory reservation (3 GB) could be lowered to free RAM. The effect on Jellyfin transcoding is not verified.
7. Folder owner on Ymir is uid 100000: proven only by the first backup in the guest.

Resolved: the early certificate expiry warning and the guest time zone (see "TLS certificate" and "Time zone" above).

---

## 7d. Email notifications again (Postfix, direct delivery to an OVH redirection) — prepared, not applied
Role `postfix_relay` (tag `postfix`). It is off until `postfix_relay_enabled: true`, so a normal `site.yml` run changes nothing. Steps 1 to 4 are a separate run from step 5 (the matchers). Placeholders: `<redirect-address>` is the OVH redirection address on `kornoglab.fr` that forwards to your Gmail, `<gmail-address>` is your Gmail. Neither is stored in the repo.
### Decisions and why
- **Default: direct delivery (`postfix_relay_mode: direct`).** Decided by the user on 2026-11-21. The OVH offer of `kornoglab.fr` is the free "Redirection" offer: there is no mailbox and therefore no SMTP login, so an authenticated relay is not possible. Postfix on orisa delivers itself on port 25 (the Freebox block was lifted) to `<redirect-address>`; OVH's MX (`mx1.mail.ovh.net`) accepts it and forwards it to Gmail. Verified live on 2026-11-21: `mx1.mail.ovh.net` answered `250 2.0.0 Ok: queued` to a test mail from orisa and Gmail delivered it (first into spam; mark it "not spam" and create a Gmail filter on the address). Gmail itself refuses direct delivery (`550-5.7.26`, no SPF or DKIM for `orisa.kornoglab.fr`), so the recipient must be the OVH address, never a Gmail address. No secret, no SASL package, no password is needed.
- **Recipient.** The builtin target `mail-to-root` mails the email of the Proxmox user `root@pam`. Set it once, by hand (it is not stored in the repo): `ssh root@192.168.0.12 "pveum user modify root@pam --email <redirect-address>"`, or Datacenter > Permissions > Users > root > Edit > E-Mail. The role can also set it from `postfix_relay_root_email` (empty by default = untouched).
- **Sender.** The header From stays `root@orisa.kornoglab.fr` (what the manual test used and OVH's MX accepted). Only the envelope sender (Return-Path) of local mail becomes `pve-bounce@orisa.kornoglab.fr`, a local alias to a script that only logs (see loop safety).
- **TLS toward the MX: `smtp_tls_security_level = may`** (opportunistic). An MX is not checked against a name without DANE or MTA-STS, and nothing secret is sent. (The strongest level, `secure`, is used in the optional relay fallback, where a password is sent.)
- **IPv4 only** (`inet_protocols = ipv4`): IPv6 attempts fail on this network and slow every delivery. It is only read at start, so the apply steps include one `systemctl restart postfix`.
- **Unchanged:** `inet_interfaces = loopback-only`, `mynetworks = 127.0.0.0/8`, `myhostname`. orisa accepts mail only from itself, so it is not an open relay. The role checks this after each real run.
- **Give up after 2 days** (`maximal_queue_lifetime` and `bounce_queue_lifetime`, Postfix default 5 days), variable `postfix_relay_queue_lifetime`.
### Loop safety (why the old loop cannot come back)
The old loop: an email failed, its bounce came back to root, `/root/.forward` turned it into a notification, and that notification was emailed again. Two independent breakers prevent it:
1. **Postfix: bounces never reach root.** All mail created on orisa has the envelope sender `pve-bounce@orisa.kornoglab.fr`, so any bounce (immediate or after the 2-day expiry) goes to the alias `pve-bounce`, which runs `/usr/local/sbin/postfix-bounce-sink`. It writes one syslog line (tag `postfix-bounce`, subject only, addresses masked, 150 characters at most) and sends nothing. A bounce therefore never reaches `/root/.forward` or the notification system, whatever its type or severity. The queue alert posts those lines to Discord once.
2. **Proxmox: the email matcher can never match a bounce or forwarded mail.** Mail that reaches root through the forwarder (cron, smartd, double bounces) arrives as type `system-mail` with severity `unknown`. The email matcher requires a known severity (`info`, `notice`, `warning`, `error`) AND a type other than `system-mail`. Both conditions are built into the role and cannot be configured away (it refuses `unknown` and `system-mail` in its lists).
Forwarded local mail (cron, smartd) is therefore **not emailed**, only posted to Discord, because its body can be anything, including a bounce notice, which is exactly the old path.
### Notification layout (after step 5)
| Matcher | Rule | Target |
|---|---|---|
| `default-matcher` | always | `discord` (every notification, short alert) |
| `email` | `{"all-of":[{"match":{"type":"severity","severities":["info","notice","warning","error"]}},{"not":{"match":{"type":"field","field":"type","values":["system-mail"]}}}]}` | `mail-to-root` |
**Which types are emailed: all (the user's decision, 2026-11-21).** Default `postfix_relay_email_types: []` means every type (vzdump, package-updates, replication, fencing, ...) and `postfix_relay_email_severities: []` means all four known severities. Discord always receives everything. To narrow it, change one line in `ansible/group_vars/proxmox.yml` (optionally also `postfix_relay_email_severities: [warning, error]`):
```yaml
postfix_relay_email_types: [vzdump, fencing, replication]   # only these types
```
then run step 5 again. `system-mail` and `unknown` are rejected by the role.
The matchers are managed by Ansible (`pvesh get`, compare, then `pvesh create` or `set` only when different), because a written, idempotent rule is easier to keep right than a UI click and the dry run shows what would change. It runs only with `-e postfix_relay_manage_matchers=true`. Only these two matchers (and root's email when `postfix_relay_root_email` is set) are touched. The Discord target and its token stay manual.
### Apply and verify (direct mode, the default)
Run from the controller (pachimari), in `ansible/`, as root over SSH like the dry runs.
```bash
cd /var/home/gart/depots/kornogHosted/ansible
# 1. switch the role on (no secret file, no mailbox needed)
echo 'postfix_relay_enabled: true' >> group_vars/proxmox.yml
# 2. dry run, Postfix and queue alert only. Shows main.cf lines, /etc/aliases, the sender map, the two scripts, the timer.
ansible-playbook site.yml --check --diff -e ansible_user=root --limit orisa --tags postfix
# 3. apply, then restart Postfix once (inet_protocols is only read at start)
ansible-playbook site.yml -e ansible_user=root --limit orisa --tags postfix
ssh root@192.168.0.12 'systemctl restart postfix && postconf -h inet_protocols relayhost inet_interfaces sender_canonical_classes && postqueue -p | tail -1'
# expected: ipv4, an empty line (no relayhost), loopback-only, envelope_sender, "Mail queue is empty"
# 4. recipient of mail-to-root (once), then ONE harmless test mail, sent by you
ssh root@192.168.0.12 "pveum user modify root@pam --email <redirect-address>"
ssh root@192.168.0.12 "printf 'Subject: orisa mail test\n\nTest from orisa after the postfix_relay role, ignore.\n' | sendmail -i <redirect-address>"
ssh root@192.168.0.12 'sleep 10; journalctl -t postfix/smtp -t postfix/qmgr --since -5min --no-pager'
```
Reading the result. **Success** in the log: `to=<...>, relay=mx1.mail.ovh.net[...]:25, ... status=sent (250 2.0.0 Ok: queued as ...)`: OVH's MX took the mail. Gmail's answer is only visible in Gmail: on success the mail arrives (look in the inbox and **spam**; "Show original" shows `SPF`, `DKIM` and `DMARC`). **Failure** shows as `status=deferred` (`Connection timed out` = port 25 blocked again; `4xx` = temporary refusal, retried) or `status=bounced` (`5xx`, refused). A bounce is not mailed to root: it is discarded by the sink and the queue alert posts one line to Discord. Gmail answers `550-5.7.26 ... unauthenticated` when a Gmail address is addressed directly: that is why the recipient is the OVH address. If Gmail files the mail in spam, check DKIM and DMARC in the original headers.
```bash
# 5. notification routing (separate run). The dry run prints what it would change.
ansible-playbook site.yml --check --diff -e ansible_user=root --limit orisa --tags postfix -e postfix_relay_manage_matchers=true
ansible-playbook site.yml -e ansible_user=root --limit orisa --tags postfix -e postfix_relay_manage_matchers=true
ssh root@192.168.0.12 'pvesh get /cluster/notifications/matchers --output-format json'
```
Without Ansible, the same layout by hand (the quoted heredoc keeps the JSON intact):
```bash
ssh root@192.168.0.12 bash -s <<'EOF'
pvesh set /cluster/notifications/matchers/default-matcher --target discord --comment 'All notifications go to Discord. Email only through the email matcher'
pvesh create /cluster/notifications/matchers --name email --target mail-to-root \
  --comment 'Email for known severities, never system-mail or unknown (no bounce loop)' \
  --expression '{"all-of":[{"match":{"type":"severity","severities":["info","notice","warning","error"]}},{"not":{"match":{"type":"field","field":"type","values":["system-mail"]}}}]}'
pvesh get /cluster/notifications/matchers --output-format json
EOF
```
The real check is the next 02:00 backup: one Discord alert and one email. The Test button of the `mail-to-root` target (Datacenter > Notifications) sends one email straight to the target, without the matcher.
```bash
# 6. queue alert check (read-only)
ssh root@192.168.0.12 'systemctl list-timers postfix-queue-alert.timer --no-pager; systemctl start postfix-queue-alert.service; journalctl -t postfix-queue-alert -t postfix-bounce -n 10 --no-pager'
```
### Queue alert
`/usr/local/sbin/postfix-queue-alert`, run every 15 minutes by `postfix-queue-alert.timer`. It posts to Discord (webhook file `/etc/nut/discord.env`, URL passed to `curl` on stdin) when the oldest queued message waits longer than `postfix_relay_alert_max_age_minutes` (60) or the queue holds more than `postfix_relay_alert_max_count` (20) messages, with the delay reason of the oldest message (addresses masked). The same situation is posted again only after `postfix_relay_alert_repeat_hours` (24), a change (age, count, both) is posted at once, and "back to normal" is posted once. It also posts the discarded bounce notices (journal tag `postfix-bounce`), once each. It never fails the unit (`ExecStart=-`, every error is logged and ignored, `curl` limited to 5 s). If `/etc/nut/discord.env` is missing it only logs `no Discord webhook`.
### Weak points
- **Gmail may file the forwarded mail in spam.** There is no DKIM for `kornoglab.fr` signing mail from orisa and no DMARC record; the first test mail landed in spam. Use a Gmail filter on the `<redirect-address>` with "Never send it to Spam". Suggestions, not done: enable DKIM for the domain in the OVH console (recommended by OVH; it signs mail sent through OVH's servers, so it helps the relay fallback more than this path) and add a DMARC record (`_dmarc.kornoglab.fr`, none today).
- **Silent failures after OVH accepted the mail.** OVH's own bounce goes to `pve-bounce@orisa.kornoglab.fr`, which has no public MX, so it is lost. Only a missing mail reveals it.
- **OVH limits.** Limits of the redirection MX are not documented; a few mails per day are far below any usual threshold. If OVH refuses or greylists, mail stays `deferred` for up to 2 days and the queue alert fires. Find the cause with `postqueue -p`, then `postqueue -f` once fixed.
- **Port 25 blocked again** (Freebox reset): `deferred ... Connection timed out`, queue alert.
- **The redirection is a single point:** if OVH removes or changes it, mail bounces to the sink (one Discord line).
### Rollback (direct mode)
```bash
# Proxmox side (back to the state of 2026-11-21: Discord only)
ssh root@192.168.0.12 'pvesh delete /cluster/notifications/matchers/email'
# Postfix side: remove the lines the role added and restart
ssh root@192.168.0.12 'cp /etc/postfix/main.cf /root/main.cf.postfix_relay && postconf -X inet_protocols maximal_queue_lifetime bounce_queue_lifetime smtp_tls_security_level sender_canonical_maps sender_canonical_classes && systemctl restart postfix && postfix check'
ssh root@192.168.0.12 'systemctl disable --now postfix-queue-alert.timer'
```
Then set `postfix_relay_enabled: false` again (or remove the line). The alias `pve-bounce` and the scripts can stay: they do nothing once no mail uses that sender. The root@pam email can stay, or be reset with `pveum user modify root@pam --email <old-address>`.
### Optional fallback (off): authenticated relay (`postfix_relay_mode: relay`)
Kept because it is small and tested. It is not part of the default path and needs a real mailbox with SMTP login, which the user does not have today. Do not enable it without one.
- **Profiles** (`postfix_relay_profile`). `ovh`: `smtp.mail.ovh.net:465`, implicit TLS, login = the full mailbox address, the server OVH documents for MX Plan accounts (Email Pro and Exchange use other servers: set `postfix_relay_host` and `postfix_relay_port`). `gmail`: `smtp.gmail.com:587`, STARTTLS, an app password (needs 2-step verification).
- **TLS: `secure` with `smtp_tls_secure_cert_match = nexthop`**, the strongest Postfix level, with the Debian CA bundle. Checked from orisa on 2026-11-21: the certificate on `smtp.mail.ovh.net:465` has CN `ns0.ovh.net` (Sectigo) and alternative names `ns0.ovh.net`, `smtp.mail.ovh.net`, `ssl0.ovh.net`, so the name is covered; `smtp.gmail.com` presents its own name. If a certificate loses its name, delivery stops (mail stays queued, the alert fires) instead of falling back to a weaker level.
- **Sender.** Both providers require the From to match the account, so the envelope sender and the header From of local mail are rewritten to the mailbox address (display name kept). Bounces then arrive in that mailbox, not on orisa.
- **Secret.** The address and the password live only in `postfix/relay.env` (git-secret, like `nut/discord.env`), created by `postfix/set-relay-secret.sh` (hidden input, mode 600). On orisa: `/etc/postfix/sasl_passwd` and its `.db`, `root:root 0600`. A real run stops with a clear message if the file is missing or incomplete; a dry run prints a warning, skips the two secret-derived files and shows everything else.
- **Limits.** OVH documents about 200 mails per hour per account and 300 per hour per source IP. If OVH blocks the account for sending too much, its console or support mail says so, and logins are refused until it is released. Mail stays `deferred` and the queue alert fires.
Apply steps (instead of step 1 above; the other steps are the same):
```bash
cd /var/home/gart/depots/kornogHosted/ansible
# create the mailbox in the OVH customer area (Web Cloud > Emails) if it does not exist, then:
../postfix/set-relay-secret.sh                           # hidden input, writes postfix/relay.env (600)
git secret add postfix/relay.env && git secret hide      # then commit the .secret file
printf 'postfix_relay_enabled: true\npostfix_relay_mode: relay\n' >> group_vars/proxmox.yml
ansible-playbook site.yml --check --diff -e ansible_user=root --limit orisa --tags postfix
ansible-playbook site.yml -e ansible_user=root --limit orisa --tags postfix
ssh root@192.168.0.12 'systemctl restart postfix && postconf -h inet_protocols relayhost inet_interfaces'
# expected: ipv4, [smtp.mail.ovh.net]:465, loopback-only. Then the test mail (step 4) to <gmail-address>.
```
Gmail's answer to a relayed mail: success arrives in the inbox (check spam; "Show original" shows SPF, DKIM, DMARC). Failure comes back to the mailbox as a bounce such as `550-5.7.26 ... unauthenticated` (no SPF or DKIM) or `5.7.1 ... DMARC`. Problems before OVH show in the log: `SASL authentication failed` (wrong login or password, the mail stays queued), `certificate verification failed`, `Connection timed out`.
Rollback of the relay mode: the direct-mode rollback above, plus these keys and files, then remove the two lines from `group_vars/proxmox.yml`:
```bash
ssh root@192.168.0.12 'postconf -X relayhost smtp_sasl_auth_enable smtp_sasl_password_maps smtp_sasl_security_options smtp_sasl_tls_security_options smtp_tls_secure_cert_match smtp_tls_wrappermode smtp_tls_CAfile smtp_tls_mandatory_protocols smtp_tls_loglevel && rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db && systemctl restart postfix'
```
Switching from relay to direct: set `postfix_relay_mode: direct` (or remove the line) and apply again; the role removes the SASL and relay keys itself.
### Tested (2026-11-21, throwaway Debian 13 container without network, since removed)
Postfix 3.10.13, a Python `aiosmtpd` stub as the MX or relay, a test CA, stand-ins for `curl` and `journalctl`. The container runs with `--network none` (only `lo`) and every provider and MX name (`smtp.mail.ovh.net`, `ssl0.ovh.net`, `smtp.gmail.com`, `mx1.mail.ovh.net`, `mx.test`) is mapped to the stub in `/etc/hosts`, so nothing can reach the Internet. Covered: direct apply without any secret file, idempotence, delivery (envelope `pve-bounce@...`, header From kept), 550 and 451 behavior, bounce routing to the sink (nothing in root's mailbox), the queue alert with de-duplication and recovery, hostile input in the sink and the helper script, relay mode with login, wrong password, wrong-name and self-signed certificates, IPv4 only, file modes, switching modes. Details: `.agents/tasks/postfix-relay/report.md`. **Not tested:** real delivery through OVH's MX to Gmail via the role, real OVH or Gmail login, the matcher change on the real host, OVH's limits, and Proxmox's own evaluation of the expression (checked against the documented semantics only).
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
| `services` | Debian LXC or VM | Stack from `kornogHosted` (valkey, zigbee2mqtt, speedtest, it-tools, infisical, ...; postgres moved to its own guest `db`, section 7c) | Different lifecycle from media. |
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
- [ ] `nut_client` applied: `nut-monitor` running, UPS login accepted, test alert received in Discord, BIOS power-on after AC loss set
- [ ] `db` guest applied (section 7c): record `db.kornoglab.fr`, TLS login from an allowed host, first dump on Ymir, restore tested, failure alert tested
- [ ] `rproxy`, `jellyfin`, `arr` guests with fixed IPs; iGPU, tun and NFS working; Traefik file routes in place; Jellyfin hardware transcoding confirmed in the playback log
- [ ] Migration cut over and heimdall retired

## References

- Proxmox VE Administration Guide: user management (`pveum`), ACME, backup, notifications, LXC (https://pve.proxmox.com/pve-docs/)
- Package repositories: https://pve.proxmox.com/wiki/Package_Repositories
