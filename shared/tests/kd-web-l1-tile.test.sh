#!/usr/bin/env bash
# kd-web-l1-tile.test.sh (WP-11-L1, A11/A9/A12/C4-web) — the Lineage-1 desktop-tile proof against a
# REAL guac schema (the WP-11 schema-real tier, mirroring kd-fleet-tiles). Boots the web image's
# real entrypoint (kd-provision -> kd-web-sync) with KD_DESKTOP_PROTOCOL=rdp — the signal the L1
# (grd) web sidecar sets — and asserts the per-user desktop tiles are guac RDP connections to
# grd's per-user port (3389+uid-2000) with GUAC_USERNAME/GUAC_PASSWORD **token passthrough** (the
# web door stores NO desktop password — A12/E1) + security=nla + ignore-cert, READ-scoped to each
# user's own entity, idempotent, D5-disable-preserving. WP-04 recorded V1 GO (grd accepts the RDP
# login + a concurrent 2nd connection); the live paint/session-stability proof is COJOIN-tier.
# In-box tier: the guac SCHEMA is real; the live web LOGIN through grd RDP is host-gate/COJOIN.
set -uo pipefail
cd "$(dirname "$0")/../.."
IMG="localhost/disposable/kd-web-l1tile:val-$$"
trap 'podman rmi -f "$IMG" >/dev/null 2>&1 || true' EXIT

echo "== build web image =="
podman build --isolation=chroot -q -t "$IMG" -f lineage-web/Containerfile . || { echo "SUITE FAIL: web build"; exit 1; }

echo "== boot with KD_DESKTOP_PROTOCOL=rdp + assert L1 RDP desktop tiles =="
podman run --rm --network=host --pid=host \
  -e KD_DESKTOP_PROTOCOL=rdp \
  -v "$PWD/gate/fixtures/roster-mixed.json:/run/secrets/kd-roster:ro" \
  -v "$PWD/shared/tests/kd-web-l1-tile.inner.sh:/inner.sh:ro" \
  --entrypoint /bin/bash "$IMG" /inner.sh
