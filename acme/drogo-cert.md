# Dedicated TLS certificate for drogo (Synology, LAN-only)

drogo (`192.168.0.44`) gets its **own** single-name Let's Encrypt certificate for
`drogo.kornoglab.fr` — deliberately **not** the `*.kornoglab.fr` wildcard, and
**not** deployed from Ymir. Each NAS owns its own cert (isolation: a compromised
single-name cert is lower blast-radius than the wildcard, and nothing pushes
into drogo from another host).

Because drogo is **LAN-only** (never exposed to the internet), validation must
use **DNS-01 via the OVH API** — the same method Ymir uses. HTTP-01 (DSM's
built-in Let's Encrypt button) will NOT work: it needs inbound port 80 from the
internet, which we don't allow. DNS-01 proves domain control by writing a TXT
record in the OVH-hosted `kornoglab.fr` zone, so no port exposure is needed.

drogo has **no Container Manager**, so acme.sh runs **natively** (it is just a
POSIX shell script — no Docker required). Renewal is driven by a **DSM Scheduled
Task** (acme.sh's self-installed cron is unreliable on DSM).

## Prerequisites

- An OVH API token with the same rights as the main acme setup
  (`GET/PUT/POST/DELETE /domain/zone/*`), validity **Unlimited**. Prefer a
  **separate token** from Ymir's so drogo can be revoked independently.
- A DSM **admin** user on drogo for the deploy hook (cert import needs admin).
  Recommended: a dedicated `acme-deploy` user. If it has 2FA, you also need its
  `SYNO_TOTP_SECRET`.
- SSH enabled on drogo (Control Panel → Terminal & SNMP → Enable SSH).
- OVH endpoint region: `ovh-eu` (same as Ymir's acme).

## One-time setup (run on drogo as root)

```bash
ssh <you>@192.168.0.44
sudo -i

# 1. Install acme.sh natively (no Docker). Installs to /root/.acme.sh
#    NOTE: DSM has no standard `crontab`, so the installer's pre-check fails
#    ("cannot install"). Pass --force (AT THE END, after email, no `--`
#    separator — that mangles it to "----force") to skip acme.sh's self-cron;
#    we use a DSM Scheduled Task for renewal instead (see below).
curl https://get.acme.sh | sh -s email=__YOUR_EMAIL__ --force
source /root/.acme.sh/acme.sh.env   # or re-login

#    If the piped install still rejects the flag, use the two-step fallback:
#      cd /tmp
#      curl -sSL https://github.com/acmesh-official/acme.sh/archive/master.tar.gz | tar xz
#      cd acme.sh-master
#      ./acme.sh --install --force --accountemail __YOUR_EMAIL__

# 2. Use Let's Encrypt (acme.sh defaults to ZeroSSL otherwise)
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 3. OVH API credentials (DNS-01). These get saved into
#    /root/.acme.sh/account.conf so renewals work unattended.
export OVH_END_POINT="ovh-eu"
export OVH_AK="__OVH_APP_KEY__"
export OVH_AS="__OVH_APP_SECRET__"
export OVH_CK="__OVH_CONSUMER_KEY__"

# 4. Issue the single-name cert via OVH DNS-01 (no port exposure)
/root/.acme.sh/acme.sh --issue --dns dns_ovh -d drogo.kornoglab.fr

# 5. Deploy into drogo's DSM (imports cert + reloads nginx) via the
#    built-in synology_dsm deploy hook, running locally.
export SYNO_Username="acme-deploy"       # DSM admin user on drogo
export SYNO_Password="__DSM_PASSWORD__"
# export SYNO_TOTP_SECRET="__TOTP__"     # only if the user has 2FA
export SYNO_Hostname="localhost"
export SYNO_Port="5000"
export SYNO_Scheme="http"
export SYNO_Certificate="drogo.kornoglab.fr"   # label for the DSM cert slot
export SYNO_Create=1
/root/.acme.sh/acme.sh --deploy -d drogo.kornoglab.fr --deploy-hook synology_dsm
```

After step 5, in DSM: Control Panel → Security → Certificate — the new
`drogo.kornoglab.fr` cert should appear. Set it as the certificate for the DSM
service (Settings → assign it to the Login Portal / DSM service), and set
Control Panel → Login Portal → DSM → **Customized domain** = `drogo.kornoglab.fr`
(same as ymir) so DSM serves `https://drogo.kornoglab.fr:5001` with it.

## Automatic renewal (DSM Scheduled Task)

acme.sh only renews when inside the ~60-day window, so a weekly run is safe and
self-throttling. Do NOT rely on acme.sh's own crontab on DSM — use Task
Scheduler.

Control Panel → Task Scheduler → Create → **Scheduled Task → User-defined script**:
- User: **root** (required — the script lives in `/root/.acme.sh`; a non-root
  user can't read/execute it)
- Schedule: weekly (any day/time)
- Command — invoke via `bash` (running the script path directly fails with
  `Permission denied` / exit 126 on DSM because the execute bit isn't honored;
  `bash <script>` only needs read access):

```bash
/bin/bash /root/.acme.sh/acme.sh --cron --home /root/.acme.sh
```

On renewal, the `synology_dsm` deploy hook re-runs automatically (acme.sh
remembers the deploy target), re-importing the fresh cert and reloading nginx —
no manual step.

## Gotchas hit during setup (DSM-specific)

- **Install pre-check fails** (no crontab on DSM): use `--force` (see step 1).
- **Task Scheduler must run as `root`** AND invoke via `bash`. Running the task
  as a non-root user, or calling `/root/.acme.sh/acme.sh` directly, fails with
  `Permission denied` / exit 126 — because `/root` is root-only and the execute
  bit isn't honored. Do NOT `chmod o+rx` `/root/.acme.sh` to work around this
  (it exposes the OVH creds + cert key); just run the task as root via
  `/bin/bash /root/.acme.sh/acme.sh ...`.
- The **initial deploy** (`--deploy ... synology_dsm`) must run once to import
  the cert into DSM and save the `SYNO_*` creds. After that the renewal task
  only needs `--cron` — acme.sh re-runs the saved deploy hook automatically.
- After deploy, in DSM: Control Panel → Security → Certificate → **Settings**,
  assign `drogo.kornoglab.fr` to the DSM/Login Portal service (otherwise DSM
  keeps serving its default self-signed cert on the web UI).

## Notes / caveats

- The OVH token and DSM password end up stored in `/root/.acme.sh/account.conf`
  and the deploy conf on drogo (root-readable). This is inherent to unattended
  DNS-01 renewal. Keep SSH/root access on drogo locked down accordingly, and
  make sure `/root/.acme.sh` is mode 700 (not world-readable).
- This cert covers **only** `drogo.kornoglab.fr`. If drogo later serves other
  subdomains, add `-d other.kornoglab.fr` to the issue command (still DNS-01).
- DNS: `drogo.kornoglab.fr` already resolves on the LAN via UniFi Local DNS
  (→ `192.168.0.44`). Public DNS is not required for DNS-01 — acme.sh writes the
  `_acme-challenge` TXT record via the OVH API and Let's Encrypt reads it from
  public DNS; the host itself never needs to be reachable.
