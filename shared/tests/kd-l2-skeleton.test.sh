#!/usr/bin/env bash
# kd-l2-skeleton.test.sh (WP-08) — the L2 walking skeleton's IN-BOX proof, scoped to what the
# nested dev engine can validate FAITHFULLY (CLAUDE.md tier split — L2 is systemd-PID-1, which
# the nested engine CANNOT boot, so in-box = BUILD + ASSEMBLY static asserts ONLY; every runtime
# claim — boot, provisioning, per-user GNOME/grd doors, health — is HOST-GATE tier and rides
# the .live-gate grd target):
#
#   Tier A  BUILD      lineage-grd builds GREEN (--isolation=chroot).
#   Tier B  ASSEMBLY   structural asserts via `create`+`export` (NO run): the GRD stack landed,
#                      the unit graph is enabled (system + --global user symlinks), the A8 door
#                      config + toolset + glue are in place, dconf compiled.
#
# Usage: bash shared/tests/kd-l2-skeleton.test.sh   → exit 0 = all rows pass.
set -uo pipefail
cd "$(dirname "$0")/../.."

G="localhost/disposable/kd-grd:val-$$"
TARF="$(mktemp)"
fails=0
t(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
cleanup(){ podman rmi -f "$G" >/dev/null 2>&1 || true; rm -f "$TARF"; }
trap cleanup EXIT

echo "STEP A: build lineage-grd"
podman build --isolation=chroot -q -f lineage-grd/Containerfile -t "$G" . || { echo "SUITE FAIL: grd build"; exit 1; }
t "build: lineage-grd GREEN" true

echo "STEP B: assembly asserts (create+export — no run; PID-1 boot is host-gate tier)"
cid="$(podman create "$G")"
podman export "$cid" > "$TARF" 2>/dev/null
podman rm "$cid" >/dev/null 2>&1
ck(){ local d="$1" f="$2" pat="$3"; if tar -xOf "$TARF" "$f" 2>/dev/null | grep -qE -- "$pat"; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
xck(){ local d="$1" f="$2"; if tar -tvf "$TARF" "$f" 2>/dev/null | grep -qE '^-..x'; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
lck(){ local d="$1" f="$2"; if tar -tvf "$TARF" "$f" 2>/dev/null | grep -q '^l'; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
fck(){ local d="$1" f="$2"; if tar -tf "$TARF" "$f" >/dev/null 2>&1; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }

# the GRD/GNOME stack is physically present
xck "gnome-shell present"            usr/bin/gnome-shell
xck "grdctl present (V17 fires)"     usr/bin/grdctl
xck "dbus-broker present"            usr/bin/dbus-broker
xck "wireplumber present (0x904)"    usr/bin/wireplumber
xck "nautilus present (B1)"          usr/bin/nautilus

# the boot chain is ENABLED (symlinks — the build's own asserts double-checked structurally)
lck "kd-provision.service enabled"   etc/systemd/system/multi-user.target.wants/kd-provision.service
lck "sshd.service enabled (A8)"      etc/systemd/system/multi-user.target.wants/sshd.service
lck "gnome-shell-headless --global"  etc/systemd/user/default.target.wants/gnome-shell-headless.service
# grd IS --global enabled: `grdctl --headless enable` configures a RUNNING daemon, so grd must
# auto-start at linger; the unconfigured-start is resolved by kd-session-enable's `restart` (re-read).
lck "grd-headless --global (grdctl enable needs the running daemon)" etc/systemd/user/default.target.wants/gnome-remote-desktop-headless.service

# the unit graph content landed
ck "compositor unit: headless + pinned socket" etc/systemd/user/gnome-shell-headless.service '--headless --wayland-display wayland-grd'
ck "grd override: requires the compositor"     etc/systemd/user/gnome-remote-desktop-headless.service.d/override.conf 'Requires=gnome-shell-headless.service'
ck "grd override: sw EGL (no hw mix)"          etc/systemd/user/gnome-remote-desktop-headless.service.d/override.conf 'MESA_LOADER_DRIVER_OVERRIDE=swrast'
ck "grd override: self-heal the compositor race (Restart=on-failure)" etc/systemd/user/gnome-remote-desktop-headless.service.d/override.conf '^Restart=on-failure$'
ck "grd override: no start-limit trap"         etc/systemd/user/gnome-remote-desktop-headless.service.d/override.conf '^StartLimitIntervalSec=0$'
ck "kd-session-enable: grd started config-first (restart, not start)" usr/libexec/kd/kd-session-enable 'systemctl --user restart gnome-remote-desktop-headless.service'
ck "kd-session-enable: waits for mutter RemoteDesktop before grd" usr/libexec/kd/kd-session-enable 'org.gnome.Mutter.RemoteDesktop'
ck "environment.d: session class (no 120s dbus timeouts)" etc/environment.d/20-kd-session.conf '^XDG_SESSION_CLASS=user$'
ck "environment.d: GTK4 off Vulkan (GSK gl)"   etc/environment.d/30-kd-display.conf '^GSK_RENDERER=gl$'
fck "user@ cgroup-EBUSY drop-in shipped"       etc/systemd/system/user@.service.d/99-cgroup-fix.conf
ck "kd-provision.service: boot-order deps (linger needs dbus+logind)" usr/lib/systemd/system/kd-provision.service 'After=dbus-broker.service systemd-logind.service'
ck "kd-provision.service: E2 exit-force"       usr/lib/systemd/system/kd-provision.service '^FailureAction=exit-force$'
ck "kd-provision.service: has [Install] (enable is real, not a no-op)" usr/lib/systemd/system/kd-provision.service '^WantedBy=multi-user.target$'
# gdm (an irreducible hard dep of Fedora's gnome-shell) must NEVER run on this seatless lineage
lck "default target = multi-user (seatless)"   etc/systemd/system/default.target
if tar -tvf "$TARF" etc/systemd/system/gdm.service 2>/dev/null | grep -q 'gdm.service -> /dev/null'; then echo "ok   gdm masked (never runs)"; else echo "FAIL gdm not masked"; fails=$((fails+1)); fi

# the A8 door config (key-only, roots-out)
ck "sshd: key-only"                  etc/ssh/sshd_config.d/10-kd.conf '^PasswordAuthentication no'
ck "sshd: no root"                   etc/ssh/sshd_config.d/10-kd.conf '^PermitRootLogin no'
fck "tmux A8 profile shipped"        etc/profile.d/kd-tmux.sh

# the toolset (B2, one set both lineages) + the GNOME terminal-default mechanism
xck "firefox present"                usr/bin/firefox
xck "ptyxis present"                 usr/bin/ptyxis
fck "obsidian /opt tree present"     opt/obsidian/obsidian
ck "dconf source: ptyxis default (V24, GNOME mechanism)" etc/dconf/db/local.d/00-kd-terminal "exec='ptyxis'"
fck "dconf db compiled"              etc/dconf/db/local
ck "claude update-lock ([ADJ-16])"   etc/claude-code/managed-settings.json '"DISABLE_UPDATES": *"1"'

# the glue (provisioning + session hooks + agents). NO VNC probes: this primary lineage serves no
# native VNC (grd VNC disabled — DESIGN §2 note (j)), so kd-vnc-login/kd-vnc-check are NOT shipped.
for f in usr/libexec/kd/kd-provision usr/libexec/kd/kd-cred usr/libexec/kd/kd-session-enable \
         usr/local/bin/kd-health usr/libexec/kd/kd-agent-env usr/libexec/kd/kd-agent-run; do
    xck "glue present + executable: $(basename "$f")" "$f"
done
# grd VNC is DROPPED: kd-session-enable disables it and the VNC probe tools are not shipped
ck "kd-session-enable disables grd VNC (RDP-native lineage)" usr/libexec/kd/kd-session-enable 'grdctl --headless vnc disable'
if tar -tf "$TARF" usr/libexec/kd/kd-vnc-login >/dev/null 2>&1; then echo "FAIL VNC probe leaked into an RDP-only lineage"; fails=$((fails+1)); else echo "ok   no VNC probe (native VNC dropped)"; fi
# kd-health is this lineage's own (not the Lineage-2 xrdp-hardcoded shared file)
ck "kd-health is the systemd/GRD tier (systemd authority)" usr/local/bin/kd-health 'is-system-running'
# Lineage-2 (XRDP) pieces must NOT leak in (an UNTRUE assembly)
if tar -tf "$TARF" usr/local/bin/kd-entrypoint >/dev/null 2>&1; then echo "FAIL XRDP entrypoint leaked into the GRD lineage"; fails=$((fails+1)); else echo "ok   no XRDP entrypoint leak"; fi
if tar -tf "$TARF" usr/libexec/kd/doors-agent >/dev/null 2>&1; then echo "FAIL XRDP doors-agent leaked into the GRD lineage"; fails=$((fails+1)); else echo "ok   no XRDP doors-agent leak"; fi

echo
if [ "$fails" -eq 0 ]; then echo "KD-L2-SKELETON: GREEN (build + assembly; runtime = host-gate)"; else echo "KD-L2-SKELETON: RED ($fails failed)"; exit 1; fi
