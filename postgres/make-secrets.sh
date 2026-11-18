#!/usr/bin/env bash
# Creates postgres/db-passwords.env (git-ignored, mode 600) with one random
# 64-character alphanumeric password per service, without ever displaying one.
# Existing keys are never changed: running it again only adds missing keys.
# Usage: postgres/make-secrets.sh [--file PATH] [service ...]   (default: infisical authelia)
set -euo pipefail
umask 077
file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db-passwords.env"
if [[ ${1:-} == --file ]]; then
  [[ -n ${2:-} ]] || { echo "--file needs a path" >&2; exit 2; }
  file=$2
  shift 2
fi
services=("$@")
((${#services[@]})) || services=(infisical authelia)
[[ -e $file ]] || install -m 600 /dev/null "$file"
chmod 600 "$file"
for s in "${services[@]}"; do
  [[ $s =~ ^[a-z][a-z0-9_]*$ ]] || { echo "invalid service name: $s" >&2; exit 2; }
  key="PG_PASSWORD_${s^^}"
  if grep -q "^${key}=." "$file"; then
    echo "$key: already set, kept"
  else
    sed -i "/^${key}=\$/d" "$file"
    pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64 || true)
    [[ ${#pw} -eq 64 ]] || { echo "could not read random data" >&2; exit 1; }
    printf '%s=%s\n' "$key" "$pw" >> "$file"
    echo "$key: created"
  fi
done
echo "File: $file (mode $(stat -c %a "$file"))"
