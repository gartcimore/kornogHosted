# kornogHosted

Docker Compose configurations for self-hosted services.

## Setup

After cloning, run the init script to create the volume directories used by services for persistent data:

```bash
./init-volumes.sh
```

This creates the `volumes/` tree (git-ignored) where each service stores its data, keeping it outside the service config folders.

## Services

| Service | Description |
|---------|-------------|
| [acme](acme/) | Let's Encrypt certificates via acme.sh + OVH DNS-01 |
| [core-keeper](core-keeper/) | Core Keeper dedicated game server |
| [it-tools](it-tools/) | Developer utility tools collection |
| [librespeed](librespeed/) | LibreSpeed self-hosted speedtest |
| [postgres](postgres/) | Shared PostgreSQL instance for other services |
| [speedtest-tracker](speedtest-tracker/) | Speedtest Tracker with SQLite |
| [zigbee2mqtt](zigbee2mqtt/) | Zigbee2MQTT bridge (SLZB-MR3 coordinator over TCP) |

## Secrets management (git-secret)

Secrets (`.env`, `*.secrets.env`) are encrypted with [git-secret](https://git-secret.io/) using GPG keys. The plaintext files are gitignored; only the `.secret` encrypted versions are committed.

### Reveal secrets (after cloning or pulling)

```bash
git secret reveal
```

This decrypts all `.secret` files back to their plaintext versions. Requires your GPG key (YubiKey must be plugged in).

### Encrypt after editing a secret

```bash
git secret hide
git add -A
git commit -m "update secrets"
```

### Add a new secret file

```bash
git secret add path/to/file.env
git secret hide
git add -A
git commit -m "add new secret"
```

### Add a new team member

```bash
gpg --import their-public-key.gpg
git secret tell their@email.com
git secret hide
git add -A
git commit -m "re-encrypt secrets for new member"
```

## Synology SSH quick access

Using `sshpass` to connect without typing the password interactively:

```bash
export SSHPASS='your_password'
sshpass -e ssh gart@192.168.0.54
```

To set up key-based auth (one-time):

```bash
sshpass -e ssh-copy-id gart@192.168.0.54
```

## Local DNS for `*.kornoglab.fr` (UniFi)

LAN name resolution for the `kornoglab.fr` services is handled by **UniFi Local
DNS records** on the Cloud Gateway — not by the `dnsmasq/` service in this repo
(that was a never-deployed WIP, see note below).

Each service hostname is an individual **A record** pointing at the host that
runs its reverse proxy. Today that is **heimdall (`192.168.0.20`)**, which runs
the `parr` stack's Traefik. Traefik terminates TLS with the wildcard
`*.kornoglab.fr` Let's Encrypt cert produced by the [`acme`](acme/) container
and shared to heimdall over NFS.

```
client → UniFi gateway DNS → <service>.kornoglab.fr = 192.168.0.20 (heimdall)
       → Traefik :443 (wildcard cert) → routes by hostname to the container
```

### Where to manage records

UniFi Network → **Settings → Routing & Firewall → DNS → DNS Records**
(Policy Engine → DNS Records on some firmware). Create a **Host (A)** policy:

- **Domain Name:** `<service>.kornoglab.fr`
- **IP Address:** `192.168.0.20`
- **TTL:** Auto

UniFi Local DNS does **not** support wildcards — every hostname is a separate
record. heimdall itself is a fixed IP (`192.168.0.20`) reserved in UniFi, so the
target address is stable.

### When to add a new record

Add a UniFi A record (→ `192.168.0.20`) **whenever a new service gets a
hostname-based Traefik route** (a `Host(\`<name>.kornoglab.fr\`)` router in the
`parr` repo's `docker-compose.yml`). DNS and the Traefik router are two halves
of the same change:

1. Add the `-tls` / `-http` router pair in `parr/docker-compose.yml`.
2. Add the matching UniFi A record here.

A record with no matching Traefik router still resolves but returns a Traefik
404 — harmless, so records may be created ahead of the router.

### Current records (all → `192.168.0.20`)

| Hostname | Traefik HTTPS router exists? |
|----------|------------------------------|
| `radarr.kornoglab.fr`      | yes |
| `sonarr.kornoglab.fr`      | yes |
| `bazarr.kornoglab.fr`      | yes |
| `jellyfin.kornoglab.fr`    | yes |
| `seerr.kornoglab.fr`       | yes |
| `lidarr.kornoglab.fr`      | not yet (path route only) |
| `prowlarr.kornoglab.fr`    | not yet (path route only) |
| `homarr.kornoglab.fr`      | not yet (path route only) |
| `qbittorrent.kornoglab.fr` | not yet (path route only) |
| `qbt.kornoglab.fr`         | alias for qbittorrent |
| `webhook.kornoglab.fr`     | not yet (webhook HTTPS pending) |
| `heimdall.kornoglab.fr`    | not yet (intended: Traefik dashboard, with auth) |

To verify a record resolves from a client:

```bash
dig +short radarr.kornoglab.fr      # expect 192.168.0.20
curl -I https://radarr.kornoglab.fr/   # expect a response + valid cert (no -k)
```

> **Note on `dnsmasq/`:** that service resolves `*.kornoglab.fr` to the Synology
> (`192.168.0.54`) via nginx-proxy. It was never deployed and is **superseded**
> by the UniFi approach above. Do not set it as the DHCP DNS server unless you
> are deliberately switching strategies.

## NFS mount from Ymir (Synology)

Heimdall mounts Ymir's `/volume1/data` share via NFS at `/mnt/dataYmir` (replaced the previous SMB/CIFS mount).

fstab entry on heimdall (permanent mount, mounts at boot and never idle-unmounts):

```
192.168.0.54:/volume1/data /mnt/dataYmir nfs rw,hard,nofail,_netdev,retry=5,x-systemd.mount-timeout=30,x-systemd.device-timeout=30,vers=3,sec=sys 0 0
```

> Previously this used `x-systemd.automount` + `x-systemd.idle-timeout=300`
> (on-demand autofs that unmounted after 5 min idle). That was dropped because
> the `parr` stack bind-mounts this share into containers (e.g. Traefik reads
> the TLS certs from `/mnt/dataYmir/containers/volumes/acme/certs`), and an
> idle-unmount under a running container desyncs it. The mount is now permanent.

Synology ACL gotcha: Synology sets POSIX permissions to `000` on shared folder roots when Windows ACLs are active. NFS ignores Synology ACLs and only sees the POSIX bits, so access is denied. Fix by running on Ymir:

```bash
sudo chmod 755 /volume1/data
```

This may need to be re-applied if the shared folder settings are edited in DSM. To make it permanent, switch the shared folder from "Windows ACL" to "UNIX permissions" in DSM (Control Panel → Shared Folder → data → Edit → Advanced).

## Emergency: stop Container Manager and Synology indexer

Stop Docker and heavy processes on the Synology (run after SSH):

```bash
sudo synosystemctl stop pkgctl-ContainerManager; sudo synosystemctl stop pkgctl-SynoFinder; sudo synosystemctl stop pkgctl-DownloadStation; top -b -n 1 | head -30
```

Restart Container Manager when ready:

```bash
sudo synosystemctl start pkgctl-ContainerManager
```
