#!/usr/bin/env bash
# kd-l1-skeleton.test.sh (WP-07) — the L1 walking skeleton's IN-BOX proof, scoped to what the
# nested dev engine can validate FAITHFULLY (CLAUDE.md tier split):
#
#   Tier A  BUILD      both lineage images build GREEN.
#   Tier B  ASSEMBLY   structural asserts on the built image via `create`+`export` (NO run, so
#                      no namespace/X dependence): the config deltas landed, the glue is in place.
#   Tier C  BOOT       boot L1 (KD_PRESTART=0 — no per-user Xorg, so no shared-netns display
#                      collision) and prove the boot chain reaches kd-health GREEN with a real
#                      roster: sesman+xrdp up, provisioning ran, doors listen, health truthful.
#
# NOT in scope in-box (HOST-GATE tier, DESIGN §7 — the full probe catalog): a real RDP session
# attach + desktop PAINT, A11 same-session, C4 geometry, the warm-session prestart (C3). Those
# need each candidate's OWN network namespace; the nested engine forces --network=host (own
# netns is unavailable here — empirically: the container wedges in `created`), so concurrent
# per-session Xorg displays collide on the shared abstract X socket. The .live-gate boots this
# candidate in the host's own netns and health-gates it; WP-02's fenced harness adds the paint
# round-trip. Tier C SKIPS LOUDLY (never a false PASS) if the shared loopback :3389 is already
# held — e.g. a leaked --pid=host orphan from a prior run polluting the dev box.
#
# Usage: bash shared/tests/kd-l1-skeleton.test.sh   → exit 0 = all RUN rows pass.
set -uo pipefail
cd "$(dirname "$0")/../.."

X="localhost/disposable/kd-l1:val-$$"
G="localhost/disposable/kd-grd:val-$$"
TARF="$(mktemp)"                     # exported rootfs as one tar we OWN (no root-owned files on disk)
CTR="kd-l1-skel-$$"
fails=0
t(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
cleanup(){ podman rm -f "$CTR" >/dev/null 2>&1 || true; podman rmi -f "$X" "$G" >/dev/null 2>&1 || true; rm -f "$TARF"; }
trap cleanup EXIT

echo "STEP A: build both lineage images"
podman build --isolation=chroot -q -f lineage-xrdp/Containerfile -t "$X" . || { echo "SUITE FAIL: xrdp build"; exit 1; }
podman build --isolation=chroot -q -f lineage-grd/Containerfile  -t "$G" . || { echo "SUITE FAIL: grd build"; exit 1; }
t "build: lineage-xrdp GREEN" true
t "build: lineage-grd GREEN"  true

echo "STEP B: assembly asserts (create+export to a tar we own — no run, no on-disk rootfs)"
cid="$(podman create "$X")"
podman export "$cid" > "$TARF" 2>/dev/null
podman rm "$cid" >/dev/null 2>&1
ck(){ local d="$1" f="$2" pat="$3"; if tar -xOf "$TARF" "$f" 2>/dev/null | grep -qE "$pat"; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
xck(){ local d="$1" f="$2"; if tar -tvf "$TARF" "$f" 2>/dev/null | grep -qE '^-..x'; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi; }
ck "xrdp.ini: loopback-first port ([ADJ-8])"      etc/xrdp/xrdp.ini      '^port=tcp://127\.0\.0\.1:3389$'
ck "xrdp.ini: autorun=Xorg"                       etc/xrdp/xrdp.ini      '^autorun=Xorg$'
ck "sesman.ini: DefaultWindowManager=startwm-kd"  etc/xrdp/sesman.ini    '^DefaultWindowManager=/usr/libexec/kd/startwm-kd$'
ck "sesman.ini: KillDisconnected=false (C1)"      etc/xrdp/sesman.ini    '^KillDisconnected=false$'
ck "xorg.conf: no-blank ServerFlags (L1-#7)"      etc/X11/xrdp/xorg.conf '"BlankTime" "0"'
ck "xorg.conf: DRMAllowList includes xe"          etc/X11/xrdp/xorg.conf 'DRMAllowList.*xe'
for f in usr/local/bin/kd-entrypoint usr/local/bin/kd-health \
         usr/libexec/kd/kd-provision usr/libexec/kd/kd-cred \
         usr/libexec/kd/kd-session-enable usr/libexec/kd/startwm-kd; do
    xck "glue present + executable: $(basename "$f")" "$f"
done

echo "STEP C: boot chain -> kd-health GREEN (KD_PRESTART=0, real roster)"
if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3389' 2>/dev/null; then
    echo "SKIP (loud): shared loopback :3389 already held (dev-box --pid=host orphan) — the"
    echo "  boot binds :3389 on the shared netns; the host gate proves boot+health in a clean"
    echo "  namespace. Build + assembly rows above are authoritative and unaffected."
else
    podman run -d --name "$CTR" --network=host --pid=host -e KD_PRESTART=0 \
        --mount type=tmpfs,destination=/srv \
        -v "$(pwd)/gate/fixtures/roster-mixed.json:/run/secrets/kd-roster:ro,Z" "$X" >/dev/null \
        || { echo "FAIL: candidate run"; fails=$((fails+1)); }
    healthy=0
    for _ in $(seq 1 40); do timeout 15 podman exec "$CTR" kd-health >/dev/null 2>&1 && { healthy=1; break; }; sleep 3; done
    t "boot: kd-health GREEN within budget"            [ "$healthy" = 1 ]
    if [ "$healthy" = 1 ]; then
        t "boot: provision-complete (roster applied, E2)"  timeout 15 podman exec "$CTR" test -f /run/kd/provision-complete
        t "boot: accounts adm+gw1+gw2 exist (D1)"          timeout 15 podman exec "$CTR" bash -c 'id kadm && id gw1 && id gw2'
        t "boot: sesman + xrdp both listening"             timeout 15 podman exec "$CTR" bash -c 'pgrep -x xrdp-sesman && pgrep -x xrdp'
        t "health: goes UNHEALTHY when the door is stopped (F2 truth)" \
            bash -c 'timeout 15 podman exec "'"$CTR"'" pkill -x xrdp; sleep 2; timeout 15 podman exec "'"$CTR"'" kd-health && exit 1 || exit 0'
        leak=0; for v in adm-aaaa-0000 gw1-bbbb-1111 gw2-cccc-2222; do podman logs "$CTR" 2>&1 | grep -qsF "$v" && leak=1; done
        t "E1: candidate boot log secret-free"             [ "$leak" = 0 ]
    else
        echo "=== candidate log tail ==="; podman logs --tail 30 "$CTR" 2>&1
    fi
fi

if [ "$fails" = 0 ]; then echo "SUITE PASS: L1 skeleton in-box (build+assembly; boot where the namespace was clean)"; exit 0
else echo "SUITE FAIL: $fails row(s)"; exit 1; fi
