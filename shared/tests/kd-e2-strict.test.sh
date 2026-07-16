#!/usr/bin/env bash
# kd-e2-strict.test.sh (WP-02) — the strict-E2 in-box proof: a ROSTER-ABSENT boot must FAIL FAST
# (container exits nonzero), never a zero-user "skeleton" that reads healthy. This is the exact
# observable the negative-secrets gate run (PR 3) asserts at host tier; here it is proven in-box
# for L1 (build + a bounded run — the entrypoint dies before any X session, so no isolated-X need)
# and for web. Retires E6 R18 (L1/web); grd's interim skeleton is the narrow R18 successor.
#
# Usage: shared/tests/kd-e2-strict.test.sh   (from repo root; drives the nested engine)
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0; ok(){ echo "  PASS  $*"; }; bad(){ echo "  FAIL  $*"; fail=1; }

echo "== build =="
podman build --isolation=chroot -t localhost/kd-xrdp:e2test -f lineage-xrdp/Containerfile . >/tmp/e2-l1.log 2>&1 \
    && ok "L1 builds" || { bad "L1 build — see /tmp/e2-l1.log"; exit 1; }
podman build --isolation=chroot -t localhost/kd-web:e2test  -f lineage-web/Containerfile  . >/tmp/e2-web.log 2>&1 \
    && ok "web builds" || { bad "web build — see /tmp/e2-web.log"; exit 1; }

# A rosterless boot: no SECRET mount, no KD_ROSTER. kd-provision exits rc=3 → the entrypoint's
# `|| exit $?` kills the container. We assert it EXITS nonzero within a bounded wait (never healthy).
neg_run(){ # <image> <name> <budget-s>
    local img="$1" name="$2" budget="$3"
    podman rm -f "$name" >/dev/null 2>&1
    podman run -d --name "$name" --network=host --pid=host --cap-drop=ALL \
        --cap-add SETUID --cap-add SETGID --cap-add SETPCAP --cap-add CHOWN \
        --cap-add FOWNER --cap-add FSETID --cap-add DAC_OVERRIDE --cap-add KILL \
        --cap-add NET_BIND_SERVICE "$img" >/dev/null 2>&1
    local st code
    for _ in $(seq 1 "$budget"); do
        st="$(podman inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo gone)"
        [ "$st" = exited ] && break
        sleep 1
    done
    code="$(podman inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null || echo 999)"
    echo "    ($name: status=$st exit=$code)"
    podman logs "$name" 2>&1 | grep -iE 'roster|E2|fail' | tail -2 | sed 's/^/      /'
    podman rm -f "$name" >/dev/null 2>&1
    [ "$st" = exited ] && [ "$code" != 0 ]
}

echo "== L1 roster-absent => fail-fast (nonzero) within 60s =="
neg_run localhost/kd-xrdp:e2test kd-e2-l1 60 && ok "L1 refuses to serve without a roster (strict E2)" \
    || bad "L1 did NOT fail-fast on absent roster (skeleton mode not retired?)"

echo "== web roster-absent => fail-fast (nonzero) within 120s =="
neg_run localhost/kd-web:e2test kd-e2-web 120 && ok "web refuses to serve without a roster (strict E2)" \
    || bad "web did NOT fail-fast on absent roster"

podman rmi localhost/kd-xrdp:e2test localhost/kd-web:e2test >/dev/null 2>&1 || true
echo; [ "$fail" = 0 ] && echo "kd-e2-strict: ALL GREEN (R18 retired for L1+web)" || { echo "kd-e2-strict: FAILURES ABOVE"; exit 1; }
