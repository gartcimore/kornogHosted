# kornogHosted

Docker Compose configurations for self-hosted services.

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

## Emergency: stop Container Manager and Synology indexer

Stop Docker and heavy processes on the Synology (run after SSH):

```bash
sudo synosystemctl stop pkg-ContainerManager-dockerd.service; sudo synopkg stop SynoFinder; sudo killall synoelasticd; sudo killall findhostd; top -b -n 1 | head -30
```

Restart Container Manager when ready:

```bash
sudo synosystemctl start pkg-ContainerManager-dockerd.service
```
