#!/usr/bin/env bash
# WP-11-L1 e2e (in-box, the WP-11 schema-real tier): boot the web image's postgres+guac schema via
# the real entrypoint with KD_DESKTOP_PROTOCOL=rdp, then assert the per-user DESKTOP tiles are guac
# RDP connections to grd (3389+uid-2000) with GUAC_USERNAME/GUAC_PASSWORD token passthrough (no
# stored desktop password), per-entity READ isolation, idempotent, D5-disable-preserving.
set -u
fail(){ echo "L1-TILE-E2E FAIL: $*"; exit 1; }
Q(){ runuser -u kdweb -- env PGHOST=/run/postgresql PGDATABASE=guacamole_db PGUSER=kdweb psql -qtAX -c "$1"; }
P(){ # param value for a desktop connection: P <conn> <param>
  Q "SELECT parameter_value FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name='$1' AND p.parameter_name='$2';"; }

# boot the real entrypoint (kd-provision runs at boot: roster -> kd-web-sync with rdp protocol)
/usr/local/bin/kd-entrypoint > /tmp/boot.log 2>&1 &
for _ in $(seq 1 150); do [ -f /run/kd/provision-complete ] && break; sleep 2; done
[ -f /run/kd/provision-complete ] || { tail -30 /tmp/boot.log; fail "provisioning never completed"; }

echo "== 3 desktop tiles, ALL protocol=rdp (Lineage 1) =="
n="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE '%-desktop';")"
[ "$n" = 3 ] || fail "expected 3 desktop tiles, got $n"
r="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE '%-desktop' AND protocol='rdp';")"
[ "$r" = 3 ] || fail "expected 3 rdp desktop tiles, got $r"
v="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE '%-desktop' AND protocol='vnc';")"
[ "$v" = 0 ] || fail "unexpected vnc desktop tile(s) under rdp lineage: $v"
echo "  OK kadm/gw1/gw2 desktop tiles are all rdp"

echo "== per-user grd RDP port arithmetic (3389 + uid - 2000) =="
[ "$(P kadm-desktop port)" = 3389 ] || fail "kadm port=$(P kadm-desktop port) (want 3389)"
[ "$(P gw1-desktop  port)" = 3390 ] || fail "gw1 port=$(P gw1-desktop port) (want 3390)"
[ "$(P gw2-desktop  port)" = 3391 ] || fail "gw2 port=$(P gw2-desktop port) (want 3391)"
[ "$(P kadm-desktop hostname)" = 127.0.0.1 ] || fail "kadm hostname=$(P kadm-desktop hostname)"
echo "  OK kadm:3389 gw1:3390 gw2:3391 @ 127.0.0.1"

echo "== security posture: nla + ignore-cert (grd CredSSP over a self-signed loopback) =="
[ "$(P kadm-desktop security)" = nla ]     || fail "kadm security=$(P kadm-desktop security) (want nla)"
[ "$(P kadm-desktop ignore-cert)" = true ] || fail "kadm ignore-cert=$(P kadm-desktop ignore-cert)"
echo "  OK security=nla ignore-cert=true"

echo "== TOKEN PASSTHROUGH (A12/E1): username/password are guac tokens, NOT a stored password =="
[ "$(P kadm-desktop username)" = '${GUAC_USERNAME}' ] || fail "kadm username=$(P kadm-desktop username) (want the GUAC_USERNAME token)"
[ "$(P kadm-desktop password)" = '${GUAC_PASSWORD}' ] || fail "kadm password param is not the GUAC_PASSWORD token"
# the phrase (or its first-8 VNC form) must NOT appear in ANY desktop tile param — no stored desktop pw
leak="$(Q "SELECT count(*) FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name LIKE '%-desktop' AND p.parameter_value IN ('adm-aaaa-0000','adm-aaaa','gw1-bbbb-1111','gw1-bbbb','gw2-cccc-2222','gw2-cccc');")"
[ "$leak" = 0 ] || fail "a desktop tile stored the phrase/first-8 (token passthrough broken): $leak hit(s)"
echo "  OK username=\${GUAC_USERNAME} password=\${GUAC_PASSWORD}; no phrase stored anywhere"

echo "== per-entity READ isolation (A9/A12): each desktop tile visible to its OWN entity only =="
for u in kadm gw1 gw2; do
  x="$(Q "SELECT count(*) FROM guacamole_connection_permission perm JOIN guacamole_connection c ON c.connection_id=perm.connection_id JOIN guacamole_entity e ON e.entity_id=perm.entity_id WHERE c.connection_name='${u}-desktop' AND e.name <> '${u}';")"
  [ "$x" = 0 ] || fail "${u}-desktop visible to another entity ($x)"
  own="$(Q "SELECT count(*) FROM guacamole_connection_permission perm JOIN guacamole_connection c ON c.connection_id=perm.connection_id JOIN guacamole_entity e ON e.entity_id=perm.entity_id WHERE c.connection_name='${u}-desktop' AND e.name='${u}' AND perm.permission='READ';")"
  [ "$own" = 1 ] || fail "${u} lacks READ on its own desktop tile ($own)"
done
echo "  OK each user READs exactly their own desktop tile"

echo "== idempotent re-apply (no dup, still rdp) =="
printf 'adm-aaaa-0000\n' | /usr/libexec/kd/kd-web-sync apply-user kadm 2000 >/dev/null 2>&1
n2="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name='kadm-desktop';")"
[ "$n2" = 1 ] || fail "re-apply changed kadm-desktop count to $n2"
[ "$(Q "SELECT protocol FROM guacamole_connection WHERE connection_name='kadm-desktop';")" = rdp ] || fail "re-apply changed protocol"
echo "  OK re-apply keeps exactly one rdp kadm-desktop"

echo "== D5 disable preserves the tile (a disabled user cannot log in to reach it) =="
/usr/libexec/kd/kd-web-sync disable-user kadm >/dev/null 2>&1
[ "$(Q "SELECT disabled FROM guacamole_user u JOIN guacamole_entity e ON e.entity_id=u.entity_id WHERE e.name='kadm';")" = t ] || fail "kadm not disabled"
[ "$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name='kadm-desktop';")" = 1 ] || fail "disable deleted the desktop tile (must preserve, D5)"
echo "  OK disable preserves the tile"

echo
echo "KD-WEB-L1-TILE: GREEN (rdp desktop tiles, token passthrough, isolation, idempotent, D5)"
