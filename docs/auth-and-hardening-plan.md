# Plan: Authelia and access hardening

Status: **noted 2026-11-18, not started.** Nothing in this document is built or applied. It records the suggestions made after the `arr` cutover so the work can resume later.

## Goal

Put a login (with WebAuthn on the YubiKey) in front of the browser-only admin UIs, and make sure the protection cannot simply be walked around. Authelia is the candidate. The Traefik dashboard (removed for now, see below) is the pilot.

## Things that would make Authelia useless or break services

1. **Direct access bypasses it.** Authelia only guards traffic through `rproxy` (`192.168.0.21`). The guests' app ports are open to the whole LAN (`192.168.0.23:7878`, `:8989`, ...). Restrict them to `rproxy` with the Proxmox firewall, allow SSH from the desktop (`192.168.0.33`), drop the rest. This is the "firewall limited to the rproxy IP" item from the guide. Not tested on this setup yet.
2. **In-stack integrations must not go through the proxy.** Today these use hostnames and would be redirected to the login page: Prowlarr, Bazarr and Seerr (to Radarr and Sonarr), and the Homarr integrations (for example `https://lidarr.kornoglab.fr/lidarr`, `https://qbittorrent.kornoglab.fr`). Switch them to container names first (`http://radarr:7878`, `http://gluetun:8080`, and so on; keep each app's URL base where it has one, Lidarr has `/lidarr`). The alternative, bypass rules for API paths in Authelia, is more fragile.
3. **Not everything goes behind it.** Jellyfin (TV and phone apps cannot follow a login redirect), Seerr and Homarr have their own logins. Protect the browser-only admin UIs: Radarr, Sonarr, Lidarr, Prowlarr, Bazarr, the qBittorrent UI, the Traefik dashboard. Calibre-web: check OPDS clients before deciding.
4. **It fails closed.** If the Authelia guest is down the protected UIs are unreachable. Keep the direct firewall rule from the desktop as the way in.

## Tool choice (from blog comparisons, nothing run here)

| Tool | What it is | Fit |
|---|---|---|
| Authelia | Forward-auth gateway for Traefik, also an OIDC provider, 2FA and WebAuthn. [Traefik integration](https://www.authelia.com/integration/proxies/traefik/) | Lightest of the full options, YAML config. Chosen candidate |
| Authentik | Full identity provider, own admin UI and database ([comparison](https://meetrix.io/blogs/authentik-vs-authelia/)) | More capable, heavier, more than needed on a shared 16 GB host |
| Pocket ID | Passkey-only OIDC provider, does not sit in front of apps ([comparison](https://sumguy.com/tinyauth-vs-pocket-id-vs-authelia/)) | Only for OIDC-capable apps, the *arr apps are not |
| Tinyauth | Minimal forward-auth | Simpler, fewer features |

## Design sketch

- A small LXC `auth`, reserved `192.168.0.25`, VMID 125, defined in `ansible/host_vars/auth.yml` like the other guests.
- Portal at `auth.kornoglab.fr` (UniFi record to `192.168.0.21`, route in `rproxy`). Session cookie domain `kornoglab.fr`. WebAuthn needs this HTTPS name, which exists.
- A ForwardAuth middleware in a file in `rproxy/traefik/dynamic/`: address `http://192.168.0.25:9091/api/authz/forward-auth`, `trustForwardHeader: true`, response headers `Remote-User`, `Remote-Groups`, `Remote-Email`, `Remote-Name`. Authelia should trust only `rproxy`'s address as a proxy, not a whole subnet.
- One Authelia instance with the file user backend and SQLite is enough to start; no Redis or Postgres needed.
- Secrets (JWT, session and storage encryption keys, user hashes) through git-secret, as for `arr/.env`.
- Later, optional: Authelia as OIDC provider for Proxmox and Homarr, keeping `root@pam` as the way back into Proxmox.

## Other hardening on the list

- Guest firewall (point 1). Highest effect.
- Proxmox: WebAuthn/TOTP for `gart@pam` and `root@pam` (pending, step 2b of the guide) and an API token for automation.
- Ymir: restrict the `data` NFS export (now the whole `192.168.0.0/24`) to orisa after heimdall is retired, and tighten the permissions of the wildcard certificate files (`key.pem` is world-readable and writable through that export).
- Monitoring: route and certificate-expiry checks (Uptime Kuma or Gatus in a `services` guest, alerting to Discord). Proxmox renews its own certificate, nothing watches the wildcard from the `acme` container.
- Pin image versions: most of the stack pulls `:latest`, so a breaking release arrives with the next `update.sh`.
- No public exposure without a VPN. For outside access use UniFi's WireGuard server instead of publishing services, then Authelia is a second layer.

## Suggested order

1. Remove the Traefik tile from Homarr (decision A, below).
2. Switch all in-stack integrations to container names.
3. Per-guest firewall rules.
4. Create the `auth` guest, deploy Authelia, protect only the Traefik dashboard as a pilot (re-add the dashboard behind it: `--api.dashboard=true` and a router for `api@internal` on `traefik.kornoglab.fr`).
5. Add the *arr UIs one at a time, test the integrations after each.

## Decisions pending

- **Traefik tile in Homarr:** option A (remove it, nothing listens on `192.168.0.21:8080`) is the recommendation. The dashboard comes back as the pilot in step 4.
- **Access from outside the LAN:** planned or not? If yes, firewall and VPN come first.
- Which users (just one, or family accounts), and whether Calibre-web OPDS clients are in use.

*Sources are blog comparisons and the Authelia documentation; nothing here has been tested on this infrastructure.*
