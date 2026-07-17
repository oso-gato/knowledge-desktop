#!/usr/bin/env bash
# WP-14 e2e (in-box, the WP-11 precedent): boot the web image's postgres+guac schema via the real
# entrypoint (kd-provision runs at boot: roster -> grants -> kd-web-sync), then assert the FLEET
# TILE rows: per-grant ssh connections + params + key handling + per-user isolation + revocation.
set -u
fail(){ echo "TILES-E2E FAIL: $*"; exit 1; }
Q(){ runuser -u kdweb -- env PGHOST=/run/postgresql PGDATABASE=guacamole_db PGUSER=kdweb psql -qtAX -c "$1"; }

# start the real entrypoint in the background; wait for provisioning to complete
/usr/local/bin/kd-entrypoint > /tmp/boot.log 2>&1 &
for _ in $(seq 1 150); do [ -f /run/kd/provision-complete ] && break; sleep 2; done
[ -f /run/kd/provision-complete ] || { tail -30 /tmp/boot.log; fail "provisioning never completed"; }

echo "== fleet tile rows (from the roster grants: kadm->erebus+fedora-dev, gw1->erebus) =="
n="$(Q "SELECT count(*) FROM guacamole_connection WHERE protocol='ssh' AND connection_name LIKE '%-tile-%';")"
[ "$n" = 3 ] || fail "expected 3 ssh tiles, got $n"
for c in kadm-tile-erebus kadm-tile-fedora-dev gw1-tile-erebus; do
  Q "SELECT 1 FROM guacamole_connection WHERE connection_name='$c' AND protocol='ssh';" | grep -q 1 || fail "missing tile $c"
done
echo "  OK 3 ssh tiles: kadm-tile-erebus kadm-tile-fedora-dev gw1-tile-erebus"

echo "== params (host/port/user from the grants line) =="
h="$(Q "SELECT parameter_value FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name='gw1-tile-erebus' AND p.parameter_name='hostname';")"
[ "$h" = "erebus.tail.fixture" ] || fail "gw1 tile hostname=$h"
u="$(Q "SELECT parameter_value FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name='gw1-tile-erebus' AND p.parameter_name='username';")"
[ "$u" = "core" ] || fail "gw1 tile username=$u"
echo "  OK gw1-tile-erebus -> erebus.tail.fixture:22 as core"

echo "== key handling: gw1 HAS tile_ssh_key (fixture) -> private-key param; kadm has none =="
k="$(Q "SELECT count(*) FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name='gw1-tile-erebus' AND p.parameter_name='private-key';")"
[ "$k" = 1 ] || fail "gw1 tile lacks private-key param (got $k)"
Q "SELECT parameter_value FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name='gw1-tile-erebus' AND p.parameter_name='private-key';" | grep -q 'BEGIN' || fail "gw1 private-key content wrong"
ka="$(Q "SELECT count(*) FROM guacamole_connection_parameter p JOIN guacamole_connection c ON c.connection_id=p.connection_id WHERE c.connection_name LIKE 'kadm-tile-%' AND p.parameter_name='private-key';")"
[ "$ka" = 0 ] || fail "kadm (keyless) unexpectedly has private-key params ($ka)"
echo "  OK key present for gw1, absent for keyless kadm (interactive fallback)"

echo "== isolation (A10/A9): each tile READ-visible to its OWN entity only =="
x="$(Q "SELECT count(*) FROM guacamole_connection_permission perm JOIN guacamole_connection c ON c.connection_id=perm.connection_id JOIN guacamole_entity e ON e.entity_id=perm.entity_id WHERE c.connection_name='gw1-tile-erebus' AND e.name <> 'gw1';")"
[ "$x" = 0 ] || fail "gw1's tile visible to another entity"
x="$(Q "SELECT count(*) FROM guacamole_connection_permission perm JOIN guacamole_connection c ON c.connection_id=perm.connection_id JOIN guacamole_entity e ON e.entity_id=perm.entity_id WHERE c.connection_name='kadm-tile-erebus' AND e.name <> 'kadm';")"
[ "$x" = 0 ] || fail "kadm's tile visible to another entity"
echo "  OK per-entity isolation holds"

echo "== desktop tiles unaffected =="
d="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE '%-desktop';")"
[ "$d" = 3 ] || fail "expected 3 desktop tiles, got $d"
echo "  OK 3 desktop tiles intact"

echo "== idempotent re-apply (no duplicates) =="
printf 'adm-aaaa-0000\n' | /usr/libexec/kd/kd-web-sync apply-user kadm 2000 >/dev/null 2>&1
n2="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE 'kadm-tile-%';")"
[ "$n2" = 2 ] || fail "re-apply changed kadm tile count to $n2"
echo "  OK re-apply keeps exactly 2 kadm tiles"

echo "== REVOCATION (A10/D5): shrink kadm's grants to erebus only -> fedora-dev tile deleted =="
printf 'erebus erebus.tail.fixture 22 core\n' > /var/lib/kd/grants/kadm
chmod 640 /var/lib/kd/grants/kadm; chown root:kd-door /var/lib/kd/grants/kadm
printf 'adm-aaaa-0000\n' | /usr/libexec/kd/kd-web-sync apply-user kadm 2000 >/dev/null 2>&1
Q "SELECT 1 FROM guacamole_connection WHERE connection_name='kadm-tile-erebus';" | grep -q 1 || fail "kept tile vanished"
r="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name='kadm-tile-fedora-dev';")"
[ "$r" = 0 ] || fail "revoked tile still present"
d2="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name='kadm-desktop';")"
[ "$d2" = 1 ] || fail "revocation touched the desktop tile"
echo "  OK revoked fedora-dev tile deleted; erebus + desktop intact"

echo "== full revocation: NO grants file -> all kadm tiles gone, others untouched =="
rm -f /var/lib/kd/grants/kadm
printf 'adm-aaaa-0000\n' | /usr/libexec/kd/kd-web-sync apply-user kadm 2000 >/dev/null 2>&1
z="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name LIKE 'kadm-tile-%';")"
[ "$z" = 0 ] || fail "full revocation left $z kadm tiles"
g1="$(Q "SELECT count(*) FROM guacamole_connection WHERE connection_name='gw1-tile-erebus';")"
[ "$g1" = 1 ] || fail "another user's tile was collateral-deleted"
echo "  OK full revocation clean; gw1's tile untouched"

echo "TILES-E2E: GREEN"
