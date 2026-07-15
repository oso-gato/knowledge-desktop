#!/usr/bin/env bash
# kd-entrypoint (LINEAGE 1 — bash PID 1; DESIGN §1, WP-07). The real L1 boot chain, replacing
# the WP-01 skeleton:
#
#   dirs → xrdp-sesman → xrdp (loopback-first, [ADJ-8]) → kd-provision (accounts, credentials,
#   grants, then pass-2 session PRESTART via kd-session-enable/sesrun — phrase on fd, L1-#12)
#   → /run/kd/boot-ok → supervise (F2 self-heal: a dead core daemon is restarted; health stays
#   truthful because kd-health asserts live processes + a real TCP answer, not this flag).
#
# Ordering note (C3 + "exactly one roster parser"): sesman/xrdp start BEFORE kd-provision so
# that pass 2 can prestart sessions through sesman; an RDP connect landing in the window
# before provisioning completes is refused (no users yet) — fail-closed, never fail-open.
#
# E2 semantics at THIS work package (honest, disclosed in E6-DISCLOSURES.md):
#   * roster PRESENT + invalid  => kd-provision exits nonzero => container dies (fail-fast,
#     PROVEN by the in-box suite).
#   * roster ABSENT             => SKELETON MODE: loud log + /run/kd/skeleton-mode marker;
#     doors serve but refuse everyone (zero users). This exists ONLY because the pre-WP-02
#     host gate boots candidates with no secret mechanism; WP-02 (gate roster fixtures)
#     replaces this branch with the strict E2 fail-fast the requirements demand.
set -u

mkdir -p /run/kd /run/xrdp /run/xrdp/sockdir /var/lib/kd
chmod 0755 /run/xrdp; chmod 1777 /run/xrdp/sockdir

pids=()
term(){
    rm -f /run/kd/boot-ok
    for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
    exit 0
}
trap term TERM INT

echo "kd-entrypoint: starting xrdp-sesman"
/usr/sbin/xrdp-sesman --nodaemon &
pids+=($!); SESMAN_PID=$!

echo "kd-entrypoint: starting xrdp (loopback-first, ADJ-8)"
/usr/sbin/xrdp --nodaemon &
pids+=($!); XRDP_PID=$!

# wait for the RDP loopback door before provisioning prestarts sessions through it
for _ in $(seq 1 30); do
    timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3389' 2>/dev/null && break
    sleep 1
done
timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3389' 2>/dev/null \
    || { echo "kd-entrypoint: FATAL — xrdp never answered on loopback :3389"; exit 1; }

if [ -e /run/secrets/kd-roster ] || [ -n "${KD_ROSTER:-}" ]; then
    echo "kd-entrypoint: roster present — provisioning (fail-fast on invalid, E2)"
    KD_PRESTART="${KD_PRESTART:-1}" /usr/libexec/kd/kd-provision || exit $?
else
    echo "kd-entrypoint: SKELETON MODE — no roster mounted; provisioning skipped; all doors" \
         "refuse (zero users). Disclosed pre-WP-02 gate residual (E6); strict E2" \
         "fail-fast-on-absent arms with the WP-02 gate roster fixtures."
    touch /run/kd/skeleton-mode
fi

touch /run/kd/boot-ok
echo "kd-entrypoint: L1 up (WP-07) — sesman=$SESMAN_PID xrdp=$XRDP_PID"

# supervise (F2 self-heal): restart a dead core daemon; kd-health independently reports truth.
# xrdp's listener can outlive a SIGKILL briefly; wait for :3389 to free before rebind so the
# restart doesn't fail EADDRINUSE (the container-level HealthOnFailure=kill is the outer layer).
wait_port_free(){ for _ in $(seq 1 10); do
    timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3389' 2>/dev/null || return 0; sleep 1
done; }
while :; do
    sleep 10 & wait $! || true
    if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
        echo "kd-entrypoint: xrdp-sesman died — restarting (F2)"
        /usr/sbin/xrdp-sesman --nodaemon & SESMAN_PID=$!; pids+=($!)
    fi
    if ! kill -0 "$XRDP_PID" 2>/dev/null; then
        echo "kd-entrypoint: xrdp died — waiting for :3389 to free, then restarting (F2)"
        wait_port_free
        /usr/sbin/xrdp --nodaemon & XRDP_PID=$!; pids+=($!)
    fi
done
