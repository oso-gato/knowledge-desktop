#!/usr/bin/env bash
# kd-entrypoint (WP-01 SKELETON) — PID 1 for lineage-xrdp until kd-provision + doors land
# (BUILDPLAN WP-06/WP-07). Honest minimal health (N4): /run/kd/boot-ok exists ONLY after init
# completed, and is removed on TERM so a dying container is never reported healthy (F2 seed).
set -u
mkdir -p /run/kd
term(){ rm -f /run/kd/boot-ok; exit 0; }
trap term TERM INT
touch /run/kd/boot-ok
echo "kd-entrypoint: skeleton up (WP-01) — capability lands per BUILDPLAN"
# reap-and-sleep loop; `wait` keeps the trap responsive
while :; do sleep 3600 & wait $!; done
