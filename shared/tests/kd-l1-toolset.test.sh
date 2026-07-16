#!/usr/bin/env bash
# kd-l1-toolset.test.sh (WP-15, B2) — in-box assembly proof for the L1 toolset. Builds the xrdp
# image and asserts the toolset is present + provenanced + provenance-safe, entirely from the
# built image's metadata (no session needed). The RUNTIME probes (apps launch in-session, Electron
# sans --no-sandbox, idle-blank, claude adoption) are host-gate/WP-02 session tier — NOT here
# (the nested engine can't run an isolated X session; the skeleton gate has no session).
#
# Usage: shared/tests/kd-l1-toolset.test.sh   (run from the repo root; drives the nested engine)
set -uo pipefail
cd "$(dirname "$0")/../.."
IMG="localhost/kd-xrdp:toolset-test"
fail=0; ok(){ echo "  PASS  $*"; }; bad(){ echo "  FAIL  $*"; fail=1; }

echo "== build =="
podman build --isolation=chroot -t "$IMG" -f lineage-xrdp/Containerfile . >/tmp/kd-tool-build.log 2>&1 \
    && ok "image builds (toolset asserts are in-Containerfile, fail-closed)" \
    || { bad "build failed — see /tmp/kd-tool-build.log"; tail -5 /tmp/kd-tool-build.log; exit 1; }

run(){ podman run --rm --network=host --pid=host --entrypoint /bin/bash "$IMG" -c "$1" 2>/dev/null; }

echo "== B2 binaries present =="
for b in firefox ptyxis code 1password op obsidian; do
    run "command -v $b >/dev/null" && ok "$b on PATH" || bad "$b missing"
done
run "test -x /usr/bin/claude" && ok "claude at /usr/bin (dnf-managed)" || bad "claude missing"

echo "== provenance (class-b vendors) =="
run 'rpm -q --qf "%{VENDOR}" code'      | grep -q Microsoft   && ok "code ← Microsoft"        || bad "code vendor"
run 'rpm -q --qf "%{VENDOR}" claude-code'| grep -qi Anthropic && ok "claude ← Anthropic"      || bad "claude vendor"
run 'rpm -q --qf "%{VENDOR}" 1password' | grep -qi 1Password  && ok "1password ← 1Password"   || bad "1password vendor"

echo "== provenance safety (ADJ-16: no home shadow; V23: setuid sandboxes) =="
run 'test ! -e /root/.local/bin/claude' && ok "no claude home shadow" || bad "claude shadow present"
run 'grep -q "\"DISABLE_UPDATES\": *\"1\"" /etc/claude-code/managed-settings.json' && ok "DISABLE_UPDATES=1" || bad "claude update-lock missing"
for s in /usr/share/code/chrome-sandbox /opt/1Password/chrome-sandbox /opt/obsidian/chrome-sandbox; do
    run "test -u $s" && ok "setuid sandbox: $s" || bad "not setuid (V23): $s"
done

echo "== Ptyxis default (exo helpers, L1-#10) =="
run 'grep -q "^TerminalEmulator=kd-ptyxis" /etc/xdg/xfce4/helpers.rc' && ok "Ptyxis is the XFCE default terminal" || bad "Ptyxis default not wired"

podman rmi "$IMG" >/dev/null 2>&1 || true
echo; [ "$fail" = 0 ] && echo "kd-l1-toolset: ALL GREEN" || { echo "kd-l1-toolset: FAILURES ABOVE"; exit 1; }
