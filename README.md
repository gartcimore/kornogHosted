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

## NFS mount from Ymir (Synology)

Heimdall mounts Ymir's `/volume1/data` share via NFS at `/mnt/dataYmir` (replaced the previous SMB/CIFS mount).

fstab entry on heimdall:

```
192.168.0.54:/volume1/data /mnt/dataYmir nfs rw,hard,intr,nofail,x-systemd.automount,x-systemd.mount-timeout=30,x-systemd.idle-timeout=300,retry=5,_netdev,bg,vers=3,sec=sys 0 0
```

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
