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

Each service hostname is an individual **A record** pointing at the reverse
proxy, **`rproxy` (`192.168.0.21`)**, an LXC guest on the Proxmox host orisa
(see [`rproxy/`](rproxy/) and [`docs/orisa-proxmox-setup.md`](docs/orisa-proxmox-setup.md)).
Its Traefik terminates TLS with the wildcard `*.kornoglab.fr` Let's Encrypt cert
produced by the [`acme`](acme/) container (shared over NFS) and forwards by
hostname to the guest that runs the service. Routes are files, not Docker labels,
because the services are in different guests.

```
client → UniFi gateway DNS → <service>.kornoglab.fr = 192.168.0.21 (rproxy)
       → Traefik :443 (wildcard cert) → file route → http://<guest>:<port>
```

### Where to manage records

UniFi Network → **Settings → Routing & Firewall → DNS → DNS Records**
(Policy Engine → DNS Records on some firmware). Create a **Host (A)** policy:

- **Domain Name:** `<service>.kornoglab.fr`
- **IP Address:** `192.168.0.21`
- **TTL:** Auto

UniFi Local DNS does **not** support wildcards — every hostname is a separate
record. The guests have fixed addresses, listed in [`docs/ip-inventory.md`](docs/ip-inventory.md).

### When to add a new record

Add a UniFi A record (→ `192.168.0.21`) **whenever a service gets a hostname**.
DNS and the Traefik route are two halves of the same change:

1. Add a router and service to a file in `rproxy/traefik/dynamic/`
   (`routes-arr.yml`, `routes-jellyfin.yml`, or a new `routes-<guest>.yml`).
   The file provider does not expand variables, write the domain out.
2. Deploy it: `cd ansible && ansible-playbook site.yml --limit rproxy --tags stacks`.
3. Add the matching UniFi A record here.

A record with no matching route still resolves but returns a Traefik 404 —
harmless, so records may be created ahead of the route. Test a route before
moving DNS with `curl --resolve <name>:443:192.168.0.21 https://<name>/`.

### Current records

| Hostname | → | Served by |
|----------|---|-----------|
| `radarr`, `sonarr`, `bazarr`, `lidarr`, `prowlarr`, `seerr`, `homarr`, `books` (`.kornoglab.fr`) | `192.168.0.21` | `arr` guest `192.168.0.23` (ports in `rproxy/traefik/dynamic/routes-arr.yml`) |
| `qbittorrent`, `qbt` | `192.168.0.21` | same route: gluetun `192.168.0.23:8080` (qBittorrent runs behind gluetun) |
| `jellyfin` | `192.168.0.21` | `jellyfin` guest `192.168.0.22:8096` |
| `heimdall` | `192.168.0.20` | the Raspberry Pi itself (no longer runs the stack or a dashboard) |
| `orisa` | `192.168.0.12` | the Proxmox host |

The `webhook` record and heimdall's Traefik dashboard are gone.

To verify a record resolves from a client:

```bash
dig +short radarr.kornoglab.fr         # expect 192.168.0.21
curl -I https://radarr.kornoglab.fr/   # expect a response + valid cert (no -k)
```

### Device records (not behind rproxy)

A few names point at other hosts and are served by those devices directly, not
through rproxy:

| Hostname | IP | Served by |
|----------|----|-----------|
| `ymir.kornoglab.fr` | `192.168.0.54` | Synology DSM itself. Set in DSM → Control Panel → Login Portal → DSM → "Customized domain", with the `*.kornoglab.fr` wildcard cert imported in DSM → Security → Certificate. Reachable at `https://ymir.kornoglab.fr:5001`. |
| `drogo.kornoglab.fr` | `192.168.0.44` | the drogo NAS directly (same idea as ymir if it's a Synology). |
| `ha.kornoglab.fr` | (via nginx-proxy) | **configured but NOT in use** — Home Assistant lives at `192.168.0.30:8123` and is currently reached via the old LAN name `homeassistant.becquerel`. The `nginx-proxy/` container has an `ha.conf` route but it was never adopted. To make it real, prefer DSM's Login Portal → Reverse Proxy over the nginx-proxy container. |

So there are two patterns for a LAN hostname:

- **Proxied** (`<service>.kornoglab.fr` → `192.168.0.21`): a file route in `rproxy/traefik/dynamic/` to the guest running the service. Add a UniFi A record + the route.
- **Device-direct** (`ymir`/`drogo`): point the UniFi A record at the device's own IP and let the device serve itself (DSM customized-domain + imported wildcard cert). No Traefik involved.

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

## Homarr MCP access from Kiro

Homarr exposes an MCP endpoint at `/api/mcp` that Kiro can use to read and edit
boards programmatically. Kiro refuses to load a remote MCP server unless it is
reached over **HTTPS or `localhost`**, so the endpoint must be served with TLS.

Homarr now has an HTTPS Traefik router at **`homarr.kornoglab.fr`** (wildcard
`*.kornoglab.fr` cert), so Kiro connects directly — no tunnel needed.

### Kiro MCP config

In `~/.kiro/settings/mcp.json`, point the server at the HTTPS endpoint and
authenticate with the **`ApiKey`** header (not `Authorization: Bearer` — Homarr's
endpoint returns `unauthorized` otherwise and tells you to use `ApiKey`):

```json
"homarr": {
  "url": "https://homarr.kornoglab.fr/api/mcp",
  "headers": { "ApiKey": "${HOMARR_API_KEY}" },
  "disabled": false
}
```

Export the key where Kiro can read it:

```bash
export HOMARR_API_KEY="<homarr-api-key>"
```

Generate the key in Homarr: **Management → Tools → API** (admin only). The key is
admin-capable (it can create users, stop containers, etc.), so keep it in the env
var rather than inline, and rotate it if it leaks.

Verify the endpoint resolves, presents a valid cert, and authenticates:

```bash
curl -sS https://homarr.kornoglab.fr/api/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "ApiKey: $HOMARR_API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | head -c 200
```

> **Common pitfalls (all seen during setup):**
> - **Path must be `/api/mcp`, not `/mcp`.** `/mcp` returns `404` and Kiro logs
>   `SSE error: Non-200 status code (404)`.
> - **Header is `ApiKey`.** `Authorization: Bearer` fails auth.
> - **Invalid JSON** in `mcp.json` (e.g. a duplicate `mcpServers` object) makes
>   the whole server silently fail to load.
> - The wildcard cert's CA must be trusted by the Kiro host, or Kiro's MCP client
>   rejects the TLS handshake. Test with `curl` **without** `-k`: if it validates
>   (`ssl_verify_result=0`), Kiro will too.

### Fallback: SSH tunnel (pre-HTTPS method)

Before the HTTPS router existed, Homarr was only on `http://heimdall.becquerel:7575`,
which Kiro rejects (`Remote MCP Servers must use https or localhost, ignoring`).
The workaround was an SSH tunnel terminating on `localhost`. It is **superseded**
by the HTTPS endpoint above, but kept here as a fallback if the router or cert
breaks.

A small idempotent helper lives at `~/.local/bin/homarr-tunnel` (on the Kiro
host, not in this repo). It forwards `localhost:7575` → `heimdall:7575` over SSH:

```bash
HOMARR_SSH_USER=gart homarr-tunnel up      # start (verifies the endpoint answers)
homarr-tunnel status                       # check tunnel + endpoint
homarr-tunnel down                         # stop

# under the hood:
ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L 127.0.0.1:7575:localhost:7575 gart@heimdall.becquerel
```

With the tunnel up, the MCP config URL becomes `http://localhost:7575/api/mcp`
(same `ApiKey` header).
