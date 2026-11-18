#!/usr/bin/env bash
# Copies ONE service's password to the Wayland clipboard without printing it.
# It can be pasted once and the clipboard is cleared afterwards (wl-copy --paste-once).
# Usage: postgres/copy-password.sh <service> [--file PATH]
set -euo pipefail
service=${1:-}
[[ $service =~ ^[a-z][a-z0-9_]*$ ]] || { echo "usage: $0 <service> [--file PATH]" >&2; exit 2; }
file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db-passwords.env"
[[ ${2:-} == --file && -n ${3:-} ]] && file=$3
[[ -r $file ]] || { echo "$file not found or not readable (run make-secrets.sh, or git secret reveal)" >&2; exit 1; }
key="PG_PASSWORD_${service^^}"
grep -q "^${key}=." "$file" || { echo "no password for '$service' in $file" >&2; exit 1; }
sed -n "s/^${key}=//p" "$file" | head -n 1 | tr -d '\n' | wl-copy --paste-once --sensitive
echo "Password of $service copied. Paste it once."
