#!/usr/bin/env bash
# setup.sh — the non-interactive deploy contract (F1). ONE arg: the roster JSON path.
# Reads all config from the roster (SECRETS.md), asserts the host prerequisites fail-fast,
# creates the podman secret, installs the quadlets, and starts the lineage. No prompts, no
# manual steps. This is the ONLY sanctioned way to run the image (spin-up.sh wraps it).
#
# Usage:  setup.sh <roster.json> [xrdp|grd]     (default lineage: xrdp)
# Prereqs asserted (per DESIGN §6): rootless podman ≥5, crun, lingering user, subuid/subgid ≥2M,
# userns enabled, /dev/fuse, ip_unprivileged_port_start ≤ 443, and — iff /dev/dri exists — the
# render-group mapping prereq (B4). SELinux accommodation is the quadlet's SecurityLabelDisable.
set -euo pipefail

die(){ echo "setup.sh: FATAL: $*" >&2; exit 1; }
ROSTER="${1:?usage: setup.sh <roster.json> [xrdp|grd]}"
LINEAGE="${2:-xrdp}"
case "$LINEAGE" in xrdp|grd) ;; *) die "lineage must be xrdp or grd, got '$LINEAGE'";; esac
[ -r "$ROSTER" ] || die "roster not readable: $ROSTER"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "== assert host prerequisites (fail-fast, F1/E2) =="
command -v podman >/dev/null || die "podman not found"
ver="$(podman version --format '{{.Client.Version}}' 2>/dev/null || echo 0)"
case "$ver" in 5.*|6.*|7.*|8.*|9.*) ;; *) die "podman >=5 required, found $ver";; esac
command -v crun >/dev/null || die "crun not found (OCI runtime)"
loginctl show-user "$(id -un)" 2>/dev/null | grep -q 'Linger=yes' \
  || die "lingering not enabled for $(id -un): run 'loginctl enable-linger $(id -un)'"

# subuid/subgid >= 2,097,152 (nested rootless podman for B3; DESIGN §5)
sub_ok(){ awk -F: -v u="$(id -un)" '$1==u{n+=$3} END{exit !(n>=2097152)}' "$1"; }
sub_ok /etc/subuid || die "subuid range for $(id -un) < 2,097,152 (nested podman needs it)"
sub_ok /etc/subgid || die "subgid range for $(id -un) < 2,097,152"
[ "$(sysctl -n user.max_user_namespaces 2>/dev/null || echo 0)" -gt 0 ] \
  || die "user namespaces disabled (user.max_user_namespaces=0)"
[ -e /dev/fuse ] || die "/dev/fuse absent (nested rootless storage needs it)"
port_start="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo 1024)"
[ "$port_start" -le 443 ] || die "net.ipv4.ip_unprivileged_port_start=$port_start > 443 (can't bind the web door rootless)"

if [ -e /dev/dri ]; then
  echo "  /dev/dri present — GPU host class (B4): the container's render group must map the host"
  echo "  render gid. Ensure the host render-node group is mapped (setup installs no udev rule;"
  echo "  if GIDMap fails empirically the documented fallback is a host 0666 render-node udev rule)."
else
  echo "  /dev/dri absent — GPU-less host class (Erebus): pure-CPU software rendering (B4). OK."
fi

echo "== create the roster secret (E1; replace if present) =="
podman secret create --replace kd-roster "$ROSTER" >/dev/null
echo "  kd-roster created from $ROSTER"

# [ADJ-34]: a lineage deploys as a PAIR — the desktop unit (netns owner, publishes the web port)
# + its netns-joined web-door sidecar. The L2 sidecar (kd-web-grd) lands with the WP-08 stack, so
# grd installs desktop-only until then (loud below, never silent).
UNITS="kd-$LINEAGE"
if [ -f "$SRC/kd-web-$LINEAGE.container" ]; then
  UNITS="kd-$LINEAGE kd-web-$LINEAGE"
else
  echo "NOTE: no web-door sidecar for lineage '$LINEAGE' yet (kd-web-$LINEAGE.container absent —" \
       "lands with WP-08); installing the desktop unit only."
fi

echo "== install quadlets for lineage: $LINEAGE ($UNITS) =="
mkdir -p "$UNIT_DIR"
for u in $UNITS; do install -m 0644 "$SRC/$u.container" "$UNIT_DIR/"; done
install -m 0644 "$SRC/kd-$LINEAGE.network" "$UNIT_DIR/"
systemctl --user daemon-reload

echo "== start $UNITS =="
# starting the sidecar pulls in the netns owner via its BindsTo/After; start both explicitly
# so a desktop-only lineage also starts.
for u in $UNITS; do systemctl --user start "$u.service"; done

echo "== wait for healthy (Notify=healthy gates this; budget 240s covers the web first boot) =="
for _ in $(seq 1 48); do
  all_healthy=1
  for u in $UNITS; do
    st="$(systemctl --user show -p SubState --value "$u.service" 2>/dev/null || echo unknown)"
    [ "$st" = running ] && h="$(podman inspect -f '{{.State.Health.Status}}' "$u" 2>/dev/null || echo none)" || h=none
    [ "$h" = healthy ] || { all_healthy=0; break; }
  done
  [ "$all_healthy" = 1 ] && { echo "  $UNITS ALL HEALTHY"; exit 0; }
  sleep 5
done
die "not all of [$UNITS] went healthy within budget — check 'journalctl --user -u kd-$LINEAGE.service' and 'journalctl --user -u kd-web-$LINEAGE.service'"
