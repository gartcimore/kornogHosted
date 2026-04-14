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
| [postgres](postgres/) | Shared PostgreSQL instance for other services |
| [core-keeper](core-keeper/) | Core Keeper dedicated game server |
| [speedtest-tracker](speedtest-tracker/) | Speedtest Tracker with SQLite |
| [librespeed](librespeed/) | LibreSpeed self-hosted speedtest |
| [it-tools](it-tools/) | Developer utility tools collection |

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
