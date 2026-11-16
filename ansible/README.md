# Ansible: orisa (Proxmox) and its guests

Rebuilds the configuration described in [`docs/orisa-proxmox-setup.md`](../docs/orisa-proxmox-setup.md) from this repo. Run it from a workstation (pachimari) over SSH. Nothing is installed on the managed hosts except what the playbook installs.

## Layout

| Path | Purpose |
|---|---|
| `inventory/hosts.yml` | Hosts: `orisa` (group `proxmox`) and the LXC guests (group `guests`) |
| `group_vars/` | Shared settings: network, time zone, Proxmox host settings, NFS and backup definitions |
| `host_vars/<guest>.yml` | One file per guest: VMID, IP, size, mounts (`lxc:`) and compose stacks. This is the single place an IP is written for a guest |
| `site.yml` | Plays: host and guest creation on orisa, then software inside the guests |
| `roles/proxmox_host` | Packages, key-only SSH, NFS data mount, guest start ordering, vzdump tmpdir, backup storage and nightly job, web UI admin group/user/ACL |
| `roles/lxc_guest` | Downloads the template, creates and starts each guest |
| `roles/docker_host` | Time zone, Docker CE and compose plugin |
| `roles/compose_stack` | Copies `rproxy/` (and other stacks) to `/opt/<name>` and runs `docker compose up -d` |

## Set up the controller (once)

```bash
uv tool install --python 3.13 ansible-core ansible-lint   # Bazzite: no system install needed
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Usage

Always look first. A dry run changes nothing and shows what would change:

```bash
ansible-playbook site.yml --check --diff -K
```

`-K` asks for the sudo password of `gart` on orisa (the inventory logs in as `gart` and uses `become`). Then apply:

```bash
ansible-playbook site.yml -K
```

Useful subsets: `--tags host`, `--tags lxc`, `--tags docker`, `--tags stacks`, and `--limit rproxy` for one guest.

On an already-built host the dry run should show no changes on orisa. The first real run changes two cosmetic things on `rproxy`: the Docker apt source file is rewritten in the module's format, and apt refreshes.

## Adding a guest

1. Pick an address and VMID (convention: VMID is `1` + last octet) and record it in `docs/ip-inventory.md`.
2. Add the host under `guests:` in `inventory/hosts.yml`.
3. Create `host_vars/<name>.yml` from `host_vars/rproxy.yml`.
4. `ansible-playbook site.yml -K --limit orisa,<name>`

## Limits (read before relying on it)

- **Guests are configured only when created.** If `host_vars/<guest>.yml` changes later (memory, mounts), the existing guest is not modified. Change it with `pct set`, then update the file to match. A drift check is not implemented.
- **Rebuilding the host from scratch has not been tested.** The dry run against the live hosts is the evidence that it matches. A real rebuild is.
- **The empty mount point is made immutable only while the share is not mounted** (it cannot be changed underneath a mount). On a fresh host the role does this before the first mount.
- **The playbook never touches permissions on the NFS share root.**
- **Not managed** (by design, they hold secrets or are done in a UI): the Let's Encrypt certificate and OVH credentials (Datacenter > ACME), the Discord notification target and its token, two-factor authentication, the network bridge and the future LACP bond (see section 4b of the guide, applied at the console), the BIOS settings, and anything on UniFi or DSM (DNS records, fixed IPs, NFS rules). These are documented in the guide.
- **Untested paths:** guest creation (`pct create`), template download, `pvesm add`, and creation of the backup job and users run only when something is missing, so the dry run on the live host skips them. The `pct`/`pvesh`/`pveum` parameter names were checked against the live CLI, but the creation commands themselves have not been executed.
- Ansible on the host runs as root. Keep decrypted secrets out of this tree.
