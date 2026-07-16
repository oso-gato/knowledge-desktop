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
# E2 semantics (STRICT, WP-02 — the skeleton-mode branch is RETIRED; E6 R18 deleted):
#   * roster PRESENT + valid    => provision, serve.
#   * roster PRESENT + invalid  => kd-provision exits nonzero => container dies (fail-fast).
#   * roster ABSENT             => kd-provision exits rc=3 => container dies (fail-fast). The box
#     REFUSES TO SERVE without a roster — no zero-user "skeleton" boot. The WP-02 gate mounts a
#     real roster fixture (SECRET_ENV → /run/secrets/kd-roster), so the gate boots a REAL
#     provisioned box; a rosterless boot is a RED (the negative-secrets run asserts exactly this).
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

# WP-13 (A8): the SSH terminal door — generate host keys, then sshd key-only on loopback (the
# tailnet ListenAddress rides the tailnet WP). authorized_keys are kd-provision's (per user).
echo "kd-entrypoint: starting sshd (A8 terminal door, key-only)"
ssh-keygen -A >/dev/null 2>&1 || true
install -d -m 0755 /run/sshd
/usr/sbin/sshd -D &
pids+=($!); SSHD_PID=$!

# Give the RDP loopback door time to come up before provisioning prestarts sessions through it.
# NON-FATAL (F2): xrdp's first boot generates RSA keys, which can be slow on a loaded shared host
# — a hard exit here made a slow keygen a RED (the entrypoint died before kd-health could report).
# kd-health is the health authority: it independently gates on a real :3389 answer, and the host
# gate's poll budget covers a slow first boot. So we WAIT (generously) but never exit — boot-ok is
# still set, and the supervisor keeps xrdp alive while kd-health reports the truth until it answers.
door_up=0
for _ in $(seq 1 60); do
    if timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3389' 2>/dev/null; then door_up=1; break; fi
    sleep 1
done
[ "$door_up" = 1 ] || echo "kd-entrypoint: xrdp not yet answering :3389 after 60s — continuing;" \
    "kd-health will report truth and the supervisor keeps it alive (no fatal exit, F2)"

# STRICT E2: provision UNCONDITIONALLY. kd-provision exits rc=3 when the roster is absent/
# unreadable and rc=2/4 when invalid — any nonzero kills the container (fail-fast, no skeleton).
echo "kd-entrypoint: provisioning from the roster (strict E2 — fail-fast on absent/invalid)"
KD_PRESTART="${KD_PRESTART:-1}" /usr/libexec/kd/kd-provision || exit $?

touch /run/kd/boot-ok
echo "kd-entrypoint: L1 up (WP-07) — sesman=$SESMAN_PID xrdp=$XRDP_PID"

# vault (E4, WP-17): the L1 periodic sync driver. L1 is bash-PID-1 with no systemd --user, so the
# 5-min vault cadence is an entrypoint-supervised loop (the L2 mechanism is a per-user timer, WP-08).
# Fail-safe: the driver's per-user syncs are individually guarded (stop-flag/vault-ready/delete
# bounds); a driver crash is restarted below (F2). It self-idles when no user has a ~/Vault clone.
echo "kd-entrypoint: starting kd-vault-driver (E4)"
/usr/libexec/kd/kd-vault-driver &
pids+=($!); VAULT_PID=$!

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
    if ! kill -0 "$SSHD_PID" 2>/dev/null; then
        echo "kd-entrypoint: sshd died — restarting (F2)"
        /usr/sbin/sshd -D & SSHD_PID=$!; pids+=($!)
    fi
    if ! kill -0 "$VAULT_PID" 2>/dev/null; then
        echo "kd-entrypoint: kd-vault-driver died — restarting (F2)"
        /usr/libexec/kd/kd-vault-driver & VAULT_PID=$!; pids+=($!)
    fi
done
