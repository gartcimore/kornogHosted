#!/usr/bin/env bash
# Asks for the relay mailbox address and password without echo and writes postfix/relay.env
# (mode 600). Nothing is put on the command line, in the environment of another process,
# or in shell history. Run it in a terminal on the desktop.
set -euo pipefail
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out="$dir/relay.env"
if [[ ! -t 0 ]]; then
  echo "Run this in a terminal: the values are read without echo." >&2
  exit 1
fi
if [[ -e $out ]]; then
  read -r -p "$out exists. Replace it? [y/N] " yn
  [[ $yn == [yY] ]] || { echo "Nothing changed."; exit 0; }
fi
read -r -s -p "Mailbox address (full address, hidden): " user; echo
read -r -s -p "Password (app password for Gmail, hidden): " pass; echo
read -r -s -p "Password again: " pass2; echo
if [[ $pass != "$pass2" ]]; then echo "The two passwords differ. Nothing written." >&2; exit 1; fi
if [[ ! $user =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "That does not look like a full email address. Nothing written." >&2; exit 1
fi
if [[ -z $pass || $pass =~ [[:cntrl:]] || $pass == " "* || $pass == *" " ]]; then
  echo "The password is empty, has control characters, or starts or ends with a space. Nothing written." >&2; exit 1
fi
umask 077
tmp=$(mktemp "$dir/.relay.env.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'RELAY_USER=%s\nRELAY_PASSWORD=%s\n' "$user" "$pass" > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$out"
trap - EXIT
unset user pass pass2
echo "Written: $out (mode 600). Next, from the repo root:"
echo "  git secret add postfix/relay.env"
echo "  git secret hide"
echo "  git add postfix/relay.env.secret .gitsecret/paths/mapping.cfg   # then commit"
