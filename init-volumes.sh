#!/usr/bin/env bash
# Creates the volumes directory tree expected by docker-compose services.
# Run once after cloning, or whenever a new service is added.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOLUMES_DIR="$SCRIPT_DIR/volumes"

dirs=(
  acme/acme-data
  acme/certs
  core-keeper/data
  core-keeper/server
  librespeed
  postgres
  speedtest-tracker
  valkey
)

for d in "${dirs[@]}"; do
  mkdir -p "$VOLUMES_DIR/$d"
done

echo "Created volume directories under $VOLUMES_DIR"
