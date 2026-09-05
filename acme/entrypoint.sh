#!/bin/sh
set -e

DOMAIN="kornoglab.fr"
CERT_DIR="/certs"

# Issue cert if not already done
if [ ! -f "/acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer" ]; then
  echo "No existing cert found, issuing new certificate..."
  acme.sh --set-default-ca --server letsencrypt
  acme.sh --issue --dns dns_ovh \
    -d "${DOMAIN}" \
    -d "*.${DOMAIN}"
fi

# Install certs to shared volume (also registers the deploy for renewals)
echo "Installing certs to ${CERT_DIR}..."
acme.sh --install-cert -d "${DOMAIN}" \
  --cert-file "${CERT_DIR}/cert.pem" \
  --key-file "${CERT_DIR}/key.pem" \
  --fullchain-file "${CERT_DIR}/fullchain.pem"

# Deploy to Synology DSM (also registers for auto-deploy on renewal)
# SYNO_INSECURE=1 skips SSL verification (DSM uses self-signed cert on 5001)
export SYNO_Insecure=1
echo "Deploying cert to Synology DSM..."
acme.sh --deploy -d "${DOMAIN}" --deploy-hook synology_dsm --insecure

# Start the daemon (handles auto-renewal + re-deploy)
echo "Starting acme.sh daemon..."
exec crond -f
