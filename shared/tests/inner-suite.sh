#!/usr/bin/env bash
# inner-suite (WP-06) — the IN-CONTAINER assertion rows for kd-provision. One row per
# invocation (`inner-suite <row>`); the runner (kd-provision.test.sh) gives each row a fresh
# throwaway container, so rows never share account state. Empirical (N5): every row RUNS the
# real provisioner against a real fixture and asserts real system state (passwd/shadow/files/
# ACLs) — nothing is mocked.
set -uo pipefail

export P=/usr/libexec/kd/kd-provision
export OUT=/tmp/kd-out      # accumulated provisioner output for log asserts + the E1 scan
fails=0
t(){ # t <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "ok   $d"; else echo "FAIL $d"; fails=$((fails+1)); fi
}
prov(){ # prov <roster> [NAME=V ...] — run the provisioner; rc returned, output appended
    local roster="$1"; shift
    env KD_ROSTER="/fixtures/$roster" "$@" timeout 60 "$P" >>"$OUT" 2>&1
}
shadow_field(){ getent shadow "$1" | cut -d: -f2; }
mode_of(){ stat -c %a "$1"; }
owner_of(){ stat -c %U:%G "$1"; }
export -f shadow_field mode_of owner_of

row_mixed(){
    prov roster-mixed.json; local rc=$?
    t "mixed: rc=0"                     [ "$rc" = 0 ]
    # census (D1/D6): exactly adm+gw1+gw2 provisioned at stable uids
    t "census: adm uid 2000"            bash -c '[ "$(id -u kadm)" = 2000 ]'
    t "census: gw1 uid 2001"            bash -c '[ "$(id -u gw1)" = 2001 ]'
    t "census: gw2 uid 2002"            bash -c '[ "$(id -u gw2)" = 2002 ]'
    t "census: gw3 absent (bad A13)"    bash -c '! getent passwd gw3'
    t "census: gw4 absent (unknown key)" bash -c '! getent passwd gw4'
    t "census: gw5 absent (bad tile)"   bash -c '! getent passwd gw5'
    t "census: root untouched (uid 0)"  bash -c '[ "$(id -u root)" = 0 ]'
    t "log: 5 workers excluded, value-free" \
        bash -c '[ "$(grep -c "worker excluded (D6)" "$OUT")" = 5 ]'
    # A13/A12 credentials — empirically derived, stdin-only
    t "shadow: adm set + unlocked"      bash -c '[[ "$(shadow_field kadm)" == \$* ]]'
    t "vnc: file == vncpasswd(first 8)" \
        bash -c 'cmp -s <(printf "%s\n" "adm-aaaa" | vncpasswd -f) /home/kadm/.kd/vncpasswd'
    t "vnc: 0600 kadm:kadm" \
        bash -c '[ "$(mode_of /home/kadm/.kd/vncpasswd)" = 600 ] && [ "$(owner_of /home/kadm/.kd/vncpasswd)" = kadm:kadm ]'
    t "ssh: adm authorized_keys 0600 + fixture key" \
        bash -c '[ "$(mode_of /home/kadm/.ssh/authorized_keys)" = 600 ] && grep -q AAAAfixtureKEYadm /home/kadm/.ssh/authorized_keys'
    t "ssh: gw2 has none (optional)"    bash -c '[ ! -e /home/gw2/.ssh/authorized_keys ]'
    # grants (A10): 0640 root:kd-door, exact-match, resolved endpoint tuples
    t "grants: adm file 0640 root:kd-door" \
        bash -c '[ "$(mode_of /var/lib/kd/grants/kadm)" = 640 ] && [ "$(owner_of /var/lib/kd/grants/kadm)" = root:kd-door ]'
    t "grants: adm = both endpoints" \
        bash -c '[ "$(wc -l < /var/lib/kd/grants/kadm)" = 2 ] && grep -q "^erebus erebus.tail.fixture 22 core$" /var/lib/kd/grants/kadm'
    t "grants: gw1 = erebus only" \
        bash -c '[ "$(cat /var/lib/kd/grants/gw1)" = "erebus erebus.tail.fixture 22 core" ]'
    t "grants: gw2 none (fail-closed)"  [ ! -e /var/lib/kd/grants/gw2 ]
    # D4 shared folder
    t "shared: /srv/shared 2770 kd-share" \
        bash -c '[ "$(mode_of /srv/shared)" = 2770 ] && [ "$(stat -c %G /srv/shared)" = kd-share ]'
    t "shared: default ACL g:kd-share:rwx" \
        bash -c 'getfacl -p /srv/shared 2>/dev/null | grep -q "^default:group:kd-share:rwx"'
    t "shared: umask-proof (umask-077 file still group-writable via ACL)" \
        bash -c 'runuser -u kadm -- bash -c "umask 077; echo hi > /srv/shared/t1" && runuser -u gw1 -- bash -c "echo also >> /srv/shared/t1"'
    t "shared: members adm+gw1+gw2" \
        bash -c 'id -nG kadm | grep -q kd-share && id -nG gw1 | grep -q kd-share && id -nG gw2 | grep -q kd-share'
    t "run flag: provision-complete"    [ -f /run/kd/provision-complete ]
    t "hooks: absent consumers logged loudly" \
        bash -c 'grep -q "hook absent (lands WP-10)" "$OUT" && grep -q "hook absent (lands WP-07/WP-08)" "$OUT"'
    # idempotent re-run (same roster)
    prov roster-mixed.json; rc=$?
    t "re-run: rc=0"                    [ "$rc" = 0 ]
    t "re-run: uids stable, uidmap 3 lines" \
        bash -c '[ "$(id -u gw2)" = 2002 ] && [ "$(grep -c . /var/lib/kd/uidmap)" = 3 ]'
    # D5 disable-not-delete: gw2 leaves the roster
    prov roster-mixed-step2.json; rc=$?
    t "disable: rc=0"                   [ "$rc" = 0 ]
    t "disable: gw2 shadow LOCKED"      bash -c '[[ "$(shadow_field gw2)" == !* ]]'
    t "disable: gw2 vnc secret removed" [ ! -e /home/gw2/.kd/vncpasswd ]
    t "disable: gw2 home PRESERVED"     [ -d /home/gw2 ]
    t "disable: gw2 uid still reserved" bash -c 'grep -q "^gw2 2002$" /var/lib/kd/uidmap'
    t "disable: logged (D5)"            bash -c 'grep -q "disabled (D5, home preserved): gw2" "$OUT"'
    # reinstatement: gw2 returns — SAME uid, unlocked, credentials back
    prov roster-mixed.json; rc=$?
    t "reinstate: rc=0"                 [ "$rc" = 0 ]
    t "reinstate: same uid 2002"        bash -c '[ "$(id -u gw2)" = 2002 ]'
    t "reinstate: gw2 unlocked"         bash -c '[[ "$(shadow_field gw2)" == \$* ]]'
    t "reinstate: gw2 vnc secret back" \
        bash -c 'cmp -s <(printf "%s\n" "gw2-cccc" | vncpasswd -f) /home/gw2/.kd/vncpasswd'
    e1_scan
}

row_admin_only(){
    prov roster-admin-only.json; local rc=$?
    t "admin-only: rc=0"                [ "$rc" = 0 ]
    t "admin-only: census exactly 1" \
        bash -c '[ "$(grep -c . /var/lib/kd/uidmap)" = 1 ] && id -u kadm >/dev/null'
    t "admin-only: no shared folder"    [ ! -d /srv/shared ]
    e1_scan
}

row_fatals(){
    local rc
    prov roster-bad-admin.json; rc=$?
    t "bad-admin: rc=2 fatal"           [ "$rc" = 2 ]
    t "bad-admin: nothing created"      bash -c '! getent passwd kadm'
    prov roster-bad-topkey.json; rc=$?
    t "bad-topkey: rc=2 (closed schema)" [ "$rc" = 2 ]
    prov roster-no-authkey.json; rc=$?
    t "no-authkey: rc=2 (E2 fail-fast)" [ "$rc" = 2 ]
    KD_ROSTER=/fixtures/absent.json timeout 60 "$P" >>"$OUT" 2>&1; rc=$?
    t "missing roster: rc=3 (E2)"       [ "$rc" = 3 ]
    t "fatals: no account ever created" bash -c '! getent passwd kadm && [ ! -e /var/lib/kd/uidmap ]'
    e1_scan
}

row_fail_worker(){
    prov roster-mixed.json KD_TEST_FAIL_APPLY=gw2; local rc=$?
    t "worker apply-fail: boot continues rc=0"   [ "$rc" = 0 ]
    t "worker apply-fail: gw2 rolled back" \
        bash -c '! getent passwd gw2 && [ ! -d /home/gw2 ]'
    t "worker apply-fail: adm+gw1 survive" \
        bash -c 'id -u kadm >/dev/null && id -u gw1 >/dev/null'
    t "worker apply-fail: policy logged" \
        bash -c 'grep -q "rolled back + skipped (policy US-#14): gw2" "$OUT"'
    e1_scan
}

row_fail_admin(){
    prov roster-mixed.json KD_TEST_FAIL_APPLY=kadm; local rc=$?
    t "admin apply-fail: abort rc=4 (E2)"        [ "$rc" = 4 ]
    t "admin apply-fail: adm rolled back"        bash -c '! getent passwd kadm'
    e1_scan
}

e1_scan(){ # E1: no fixture phrase may appear in ANY provisioner output or readable artifact
    local leak=0 v
    for v in adm-aaaa-0000 gw1-bbbb-1111 gw2-cccc-2222 dup-dddd-3333 sys-eeee-4444 \
             gw4-ffff-5555 gw5-gggg-6666; do
        if grep -rqsF "$v" "$OUT" /var/lib/kd /home/*/.ssh 2>/dev/null; then
            echo "LEAK: a fixture phrase surfaced (which one is withheld)"; leak=1
        fi
    done
    t "E1: zero fixture phrases in logs/state" [ "$leak" = 0 ]
}

row="${1:-}"
case "$row" in
    mixed) row_mixed ;; admin_only) row_admin_only ;; fatals) row_fatals ;;
    fail_worker) row_fail_worker ;; fail_admin) row_fail_admin ;;
    *) echo "usage: inner-suite mixed|admin_only|fatals|fail_worker|fail_admin" >&2; exit 2 ;;
esac
echo "=== provisioner output (value-free by contract) ==="; cat "$OUT" 2>/dev/null || true
if [ "$fails" = 0 ]; then echo "ROW PASS: $row"; exit 0; else echo "ROW FAIL: $row ($fails)"; exit 1; fi
