# postgres
Files for the shared PostgreSQL service. The service itself is **native PostgreSQL in the LXC guest `db`** (`192.168.0.26`, `db.kornoglab.fr`), set up by the Ansible role [`ansible/roles/postgres_server`](../ansible/roles/postgres_server). This folder only holds the password tooling. Guide, decisions, restore and "add a database": [`docs/orisa-proxmox-setup.md`](../docs/orisa-proxmox-setup.md), section 7c.
The old Docker compose setup was never used and is gone.
| File | Purpose |
|---|---|
| `make-secrets.sh [--file PATH] [service ...]` | Creates `db-passwords.env` (mode 600) with a random 64-character alphanumeric password per service (default `infisical authelia`). Never prints a password, never changes an existing key |
| `copy-password.sh <service>` | Copies one password to the clipboard (`wl-copy`, paste once, hidden) |
| `db-passwords.env.sample` | Key names only |
| `db-passwords.env` | The real file. Git-ignored. Encrypt with `git secret add postgres/db-passwords.env && git secret hide` |
Retiring the old encrypted files (`.env.secret`, `postgres.secrets.env.secret`) is a manual step, listed in section 7c of the guide.
