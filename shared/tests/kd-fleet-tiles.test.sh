#!/usr/bin/env bash
# kd-fleet-tiles.test.sh (WP-14, A10/D5) — the fleet-tile provisioning proof. Builds the web
# image, boots its real entrypoint (kd-provision → grants → kd-web-sync) against a roster whose
# admin+gw1 carry tiles + gw1 a tile_ssh_key, then asserts the guac SSH connection rows: one per
# GRANTED endpoint, host/port/user from the grants line, per-user PRIVATE-KEY (present iff
# roster tile_ssh_key), per-entity READ isolation (A9/A10), idempotent re-apply, and revocation
# by regeneration (D5 — a shrunk/emptied grants set deletes exactly that user's now-ungranted
# tiles, never the desktop tile or another user's rows). In-box tier (the WP-11 precedent): the
# guac SCHEMA is real; the live web LOGIN through the tile is host-gate/manual (V11 tri-path).
set -uo pipefail
cd "$(dirname "$0")/../.."
IMG="localhost/disposable/kd-web-tiles:val-$$"
RF="$(mktemp)"; trap 'podman rmi -f "$IMG" >/dev/null 2>&1 || true; rm -f "$RF"' EXIT
# fixture: roster-mixed + gw1 tile_ssh_key
python3 - "$RF" <<'PY'
import json,sys
d=json.load(open('gate/fixtures/roster-mixed.json'))
d['workers'][0]['tile_ssh_key']="-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTUREkeyMATERIALnotREAL\n-----END OPENSSH PRIVATE KEY-----\n"
json.dump(d, open(sys.argv[1],'w'))
PY
echo "== build web image =="
podman build --isolation=chroot -q -t "$IMG" -f lineage-web/Containerfile . || { echo "SUITE FAIL: web build"; exit 1; }
echo "== boot + assert fleet tiles =="
podman run --rm --network=host --pid=host -v "$RF:/run/secrets/kd-roster:ro" \
  -v "$PWD/shared/tests/kd-fleet-tiles.inner.sh:/inner.sh:ro" \
  --entrypoint /bin/bash "$IMG" /inner.sh
