#!/usr/bin/env bash
# spin-up.sh — the ATTENDED spin-up path (F1): a thin wizard that COMPOSES a roster by asking,
# then delegates to setup.sh (the single source of runtime truth — this script writes no run
# logic of its own). For unattended deploy, skip this and call setup.sh <roster.json> directly.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "knowledge-desktop spin-up (attended). Ctrl-C to abort."
read -rp "Lineage [xrdp|grd] (default xrdp): " LINEAGE; LINEAGE="${LINEAGE:-xrdp}"
read -rp "Tailnet auth key (tskey-…): " TSKEY
read -rp "Public DNS name (blank ⇒ tls-internal cert): " DNS
read -rp "Admin username: " ADMIN_USER
read -rsp "Admin password (Diceware xxx-xxxx-xxxx): " ADMIN_PW; echo
read -rp "Admin authorized SSH key (ssh-…): " ADMIN_KEY

ROSTER="$(mktemp)"; trap 'rm -f "$ROSTER"' EXIT
cat > "$ROSTER" <<JSON
{ "version": 1,
  "box": { "tailnet_authkey": "$TSKEY", "public_dns_name": "$DNS",
           "endpoints": {}, "shared_folder": false },
  "admin": { "username": "$ADMIN_USER", "password": "$ADMIN_PW",
             "ssh_authorized_keys": ["$ADMIN_KEY"], "tiles": [] },
  "workers": [] }
JSON
echo "composed a single-admin roster; handing off to setup.sh (workers/tiles/vcs: edit the roster for those)"
exec "$SRC/setup.sh" "$ROSTER" "$LINEAGE"
