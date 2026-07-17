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
# grd is DELIBERATELY NOT --global enabled (WP-08 door fix): it must never auto-start UNCONFIGURED
# at the linger instant (empty store => doors dark, and a later `start` no-ops it). kd-session-enable
# is the SOLE, config-first starter. Assert the auto-start symlink is ABSENT.
if tar -tf "$TARF" etc/systemd/user/default.target.wants/gnome-remote-desktop-headless.service >/dev/null 2>&1; then echo "FAIL grd must NOT be --global enabled (config-first design)"; fails=$((fails+1)); else echo "ok   grd NOT --global enabled (config-first; kd-session-enable starts it)"; fi

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

# the glue (provisioning + L2 hooks + reused VNC probes + agents)
for f in usr/libexec/kd/kd-provision usr/libexec/kd/kd-cred usr/libexec/kd/kd-session-enable \
         usr/local/bin/kd-health usr/libexec/kd/kd-agent-env usr/libexec/kd/kd-agent-run \
         usr/libexec/kd/kd-vnc-login usr/libexec/kd/kd-vnc-check; do
    xck "glue present + executable: $(basename "$f")" "$f"
done
# the L2 kd-health is the L2 one (not the L1-hardcoded shared file)
ck "kd-health is the L2 tier (systemd authority)" usr/local/bin/kd-health 'is-system-running'
# L1-only pieces must NOT leak in (an UNTRUE assembly)
if tar -tf "$TARF" usr/local/bin/kd-entrypoint >/dev/null 2>&1; then echo "FAIL L1 entrypoint leaked into L2"; fails=$((fails+1)); else echo "ok   no L1 entrypoint leak"; fi
if tar -tf "$TARF" usr/libexec/kd/doors-agent >/dev/null 2>&1; then echo "FAIL L1 doors-agent leaked into L2"; fails=$((fails+1)); else echo "ok   no L1 doors-agent leak"; fi

echo
if [ "$fails" -eq 0 ]; then echo "KD-L2-SKELETON: GREEN (build + assembly; runtime = host-gate)"; else echo "KD-L2-SKELETON: RED ($fails failed)"; exit 1; fi
