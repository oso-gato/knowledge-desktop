#!/usr/bin/env bash
# kd-provision.test.sh (WP-06) — the IN-BOX empirical suite for the provisioner core.
# Builds a THROWAWAY test image (pinned base + the exact runtime closure) in the nested
# engine and runs each assertion row (shared/tests/inner-suite.sh) in its own fresh
# container, so no row inherits another's account state. This is the roster-d1d6 probe's
# in-box twin (N5): the real provisioner runs against real fixtures and real system state.
#
# Nested-engine notes (fedora-dev capability boundary): build needs --isolation=chroot;
# containers run degraded --network=host --pid=host (own netns/pidns are blocked at this
# nesting depth — no row needs either); /srv rides a tmpfs so setfacl exercises a
# filesystem with ACL support regardless of the fuse-overlayfs backing store.
#
# Usage: bash shared/tests/kd-provision.test.sh   → exit 0 = all rows pass.
set -uo pipefail
cd "$(dirname "$0")/../.."

TAG="localhost/disposable/kd-provision-test:val-$$"
trap 'podman rmi -f "$TAG" >/dev/null 2>&1 || true' EXIT

echo "=== build test image (throwaway, pinned base) ==="
podman build --isolation=chroot -f shared/tests/Containerfile.test -t "$TAG" . || {
    echo "SUITE FAIL: test image build"; exit 1; }

fails=0
ALL_OUT="$(mktemp)"
for row in mixed admin_only fatals fail_worker fail_admin; do
    echo "=== row: $row ==="
    if podman run --rm --network=host --pid=host \
            --mount type=tmpfs,destination=/srv \
            "$TAG" "$row" | tee -a "$ALL_OUT"; then
        echo "--- $row PASS"
    else
        echo "--- $row FAIL"; fails=$((fails+1))
    fi
done

# E1 belt at the RUNNER level too: nothing that crossed the container boundary may carry a
# fixture phrase (the rows scan in-container state; this scans everything they printed).
for v in adm-aaaa-0000 gw1-bbbb-1111 gw2-cccc-2222 dup-dddd-3333 sys-eeee-4444 \
         gw4-ffff-5555 gw5-gggg-6666; do
    if grep -qsF "$v" "$ALL_OUT"; then echo "SUITE FAIL: E1 leak across the boundary"; fails=$((fails+1)); fi
done
rm -f "$ALL_OUT"

if [ "$fails" = 0 ]; then echo "SUITE PASS: kd-provision in-box"; exit 0
else echo "SUITE FAIL: $fails row(s)"; exit 1; fi
