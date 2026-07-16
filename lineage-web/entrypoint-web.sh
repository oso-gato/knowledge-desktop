#!/usr/bin/env bash
# kd-entrypoint (WEB DOOR; DESIGN §3, WP-10). Boots the gateway: PostgreSQL (loopback) ->
# guacd -> Tomcat (guacamole webapp) -> Caddy (:443 public). All secrets generated at boot
# (E1: none in the image). First boot loads the guacamole schema + disables the default
# guacadmin; subsequent boots reuse the persisted DB (E3, on the state volume at prod).
#
# TIER NOTE (N5): kd-health's two legs (an unauth API GET proving Caddy->Tomcat->webapp servlet,
# plus a real SELECT 1 proving postgres answers) are the Tier-1/host-gate live proof, run by the
# .live-gate `web` target on a clean engine. The live per-user auth round-trip (A3/A4/A11) is the
# manual/browser tier above it.
set -u
# Caddy (root PID 1) stores its `tls internal` CA + autosave under $XDG_DATA_HOME/caddy and
# $XDG_CONFIG_HOME/caddy. The default ($HOME/.local/share) lands in /root, which Fedora ships
# dr-xr-x--- (0550) — root cannot create there without DAC_OVERRIDE, which is INEFFECTIVE under the
# rootless-userns cap floor (that was a gate RED: "mkdir /root/.local: permission denied"). Pin the
# XDG dirs to a root-OWNED, root-WRITABLE path (a prod deploy can bind-mount a volume here to persist
# the internal CA; at the gate it is ephemeral tls-internal, which is fine).
export HOME="${HOME:-/root}"
export XDG_DATA_HOME=/var/lib/caddy-data XDG_CONFIG_HOME=/var/lib/caddy-data
mkdir -p "$XDG_DATA_HOME"
export GUACAMOLE_HOME=/etc/guacamole CATALINA_HOME=/opt/tomcat
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
PGDATA=/var/lib/pgsql/data
RUN=/run/kd
mkdir -p "$RUN" /var/lib/kd
# PostgreSQL's default unix_socket_directories is /var/run/postgresql; without systemd-tmpfiles
# (we are bash-PID-1, not systemd) nothing creates it, so postgres FATALs on the socket lock file.
# Create it owned by kdweb so both the server and the default-socket psql clients find it.
mkdir -p /run/postgresql && chown kdweb:kdweb /run/postgresql

log(){ echo "kd-web: $*"; }
run_pg(){ runuser -u kdweb -- "$@"; }

# teardown: caddy is root (same uid, no CAP_KILL needed); java runs as kdweb, so signal it AS
# kdweb (run_pg) rather than root→kdweb, which would need CAP_KILL under the gate's cap-drop floor.
term(){ rm -f "$RUN/boot-ok"; pkill -TERM caddy 2>/dev/null; run_pg pkill -TERM java 2>/dev/null
        run_pg /usr/bin/pg_ctl -D "$PGDATA" stop -m fast 2>/dev/null; exit 0; }
trap term TERM INT

# ---- 1. PostgreSQL (loopback only) ----
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    log "initdb (first boot)"
    run_pg /usr/bin/initdb -D "$PGDATA" --auth-local=peer --auth-host=scram-sha-256 -U kdweb >/dev/null
    # append config AS kdweb (who owns PGDATA after initdb) — root writing a kdweb-owned file needs
    # CAP_DAC_OVERRIDE, which is INEFFECTIVE in the rootless userns (verified); kdweb writing its own
    # files needs no cap at all.
    printf "listen_addresses = '127.0.0.1'\nport = 5432\n" \
        | run_pg tee -a "$PGDATA/postgresql.conf" >/dev/null
    printf 'host all all 127.0.0.1/32 scram-sha-256\n' \
        | run_pg tee -a "$PGDATA/pg_hba.conf" >/dev/null
    FIRST_BOOT=1
fi
log "starting postgres"
run_pg /usr/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/pg.log" -w -t 60 start >/dev/null \
    || { log "FATAL: postgres failed to start"; tail -20 "$PGDATA/pg.log" 2>/dev/null; exit 1; }

# The loopback DB credential lives INSIDE the pg volume ($PGDATA/kdweb-dbpass, 0600 kdweb) so it
# SURVIVES container recreation with the DB it unlocks — guacamole.properties is an image-layer
# file that resets on every recreation, so on the old scheme (append at first boot only) a
# recreated container had a persisted DB but no credential line: Tomcat could never auth (E3 bug,
# found by tracing recreation). Generated first boot, synced into the props EVERY boot.
DBPASS_FILE="$PGDATA/kdweb-dbpass"
if [ "${FIRST_BOOT:-0}" = 1 ]; then
    log "creating DB + guacamole role + loading schema"
    DBPASS="$(openssl rand -hex 24)"        # loopback DB credential — generated, never in image (E1)
    printf '%s\n' "$DBPASS" | run_pg tee "$DBPASS_FILE" >/dev/null
    run_pg chmod 0600 "$DBPASS_FILE"
    # connect to the built-in `postgres` DB — initdb makes no DB named after the kdweb superuser,
    # so a bare psql (which defaults to dbname=$USER) would FATAL on 'database "kdweb" does not exist'
    run_pg /usr/bin/psql -v ON_ERROR_STOP=1 -q -d postgres <<SQL || { log "FATAL: DB init"; exit 1; }
CREATE DATABASE guacamole_db;
CREATE USER guacamole WITH PASSWORD '${DBPASS}';
SQL
    cat /opt/guac-schema/*.sql | run_pg /usr/bin/psql -v ON_ERROR_STOP=1 -q -d guacamole_db \
        || { log "FATAL: schema load"; exit 1; }
    run_pg /usr/bin/psql -v ON_ERROR_STOP=1 -q -d guacamole_db <<SQL
GRANT ALL ON ALL TABLES IN SCHEMA public TO guacamole;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO guacamole;
-- disable the schema's default guacadmin (kd users come from the roster; A12 fail-closed)
UPDATE guacamole_user u SET disabled = TRUE FROM guacamole_entity e
  WHERE u.entity_id = e.entity_id AND e.name = 'guacadmin';
SQL
    unset DBPASS
fi

# EVERY boot: sync the persisted credential into guacamole.properties (image-layer, fresh each
# recreation). Done AS kdweb — the file is kdweb-owned (build chown); root writing it would need
# the userns-ineffective DAC_OVERRIDE.
if run_pg test -s "$DBPASS_FILE"; then
    { grep -v '^postgresql-password:' "$GUACAMOLE_HOME/guacamole.properties" 2>/dev/null || true; } \
        | run_pg tee "$GUACAMOLE_HOME/guacamole.properties.new" >/dev/null
    printf 'postgresql-password: %s\n' "$(run_pg cat "$DBPASS_FILE")" \
        | run_pg tee -a "$GUACAMOLE_HOME/guacamole.properties.new" >/dev/null
    run_pg mv "$GUACAMOLE_HOME/guacamole.properties.new" "$GUACAMOLE_HOME/guacamole.properties"
    run_pg chmod 0600 "$GUACAMOLE_HOME/guacamole.properties"
else
    log "FATAL: no DB credential at $DBPASS_FILE (persisted DB without its credential?)"; exit 1
fi

# ---- 1b. provision (WP-11): roster -> guac users + desktop tiles ----
# kd-provision (the sole roster parser, [ADJ-11] — runs PER-CONTAINER over the same secret)
# drives kd-web-sync: web identity + TOTP posture + the L1 VNC tile row per user. Unix accounts
# are created here too — the uid IS the tile-port derivation (5900 + uid - 2000), and the
# append-only uidmap on the state volume (E3) keeps it in parity with the desktop container
# (same roster history + same rule => same uids; divergence is an E6-disclosed residual probed
# at WP-20). Desktop-only hooks (kd-cred, kd-session-enable) are absent in this image —
# kd-provision logs each loudly and continues (its designed optional-hook contract).
# Roster semantics mirror L1 (E6 R18): present+invalid => fail-fast; ABSENT => skeleton mode.
if [ -e /run/secrets/kd-roster ] || [ -n "${KD_ROSTER:-}" ]; then
    log "roster present — provisioning web identities + tiles (fail-fast on invalid, E2)"
    /usr/libexec/kd/kd-provision || exit $?
else
    log "SKELETON MODE — no roster mounted; provisioning skipped; the gateway serves with zero" \
        "users (guacadmin disabled at boot, A12 fail-closed). Disclosed pre-WP-02 gate residual (E6 R18)."
    touch /run/kd/skeleton-mode
fi

# ---- 2. guacd (loopback; vendored FreeRDP via rpath) ----
log "starting guacd"
run_pg /opt/guacamole/sbin/guacd -b 127.0.0.1 -l 4822 -f >"$RUN/guacd.log" 2>&1 &
GUACD_PID=$!

# ---- 3. Tomcat (guacamole webapp; 127.0.0.1:8080) ----
log "starting tomcat (java $JAVA_HOME)"
run_pg env JAVA_HOME="$JAVA_HOME" GUACAMOLE_HOME="$GUACAMOLE_HOME" \
    "$CATALINA_HOME/bin/catalina.sh" run >"$RUN/tomcat.log" 2>&1 &
TOMCAT_PID=$!

# ---- 4. Caddy (:443 public door) ----
log "starting caddy (:443)"
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >"$RUN/caddy.log" 2>&1 &
CADDY_PID=$!

# ---- wait for the webapp to deploy (deep liveness), THEN mark boot-ok ----
# boot-ok is truthful (N4/N5): it is written ONLY once the webapp actually answers, never
# unconditionally. If the first boot is slow, the supervise loop below sets it late; until then
# kd-health reports UNHEALTHY (which is the truth) rather than a premature green.
webapp_live(){ curl -fsS -o /dev/null "http://127.0.0.1:8080/guacamole/" 2>/dev/null; }
LIVE=0
for _ in $(seq 1 60); do webapp_live && { LIVE=1; break; }; sleep 2; done
if [ "$LIVE" = 1 ]; then
    touch "$RUN/boot-ok"
    log "web door up (WP-10) — guacd=$GUACD_PID tomcat=$TOMCAT_PID caddy=$CADDY_PID"
else
    log "WARN: webapp not live within 120s — entering supervise; kd-health stays UNHEALTHY until it answers"
fi

# supervise (F2): a dead core service is restarted — POSTGRES INCLUDED (the fitness review's
# concrete failure mode: postgres dies post-boot, everything else alive, logins dead and nothing
# restarts it; kd-health's DB leg now catches it AND this loop now heals it). A still-deploying
# webapp is marked live when it finally answers. kd-health reports the truth throughout.
while :; do
    sleep 10 & wait $! || true
    if [ ! -f "$RUN/boot-ok" ] && webapp_live; then touch "$RUN/boot-ok"; log "web door reached liveness (late) — boot-ok set"; fi
    run_pg /usr/bin/pg_ctl -D "$PGDATA" status >/dev/null 2>&1 \
        || { log "postgres died — restart (F2)"; run_pg /usr/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/pg.log" -w -t 60 start >/dev/null 2>&1 || log "postgres restart FAILED (kd-health stays red)"; }
    kill -0 "$GUACD_PID"  2>/dev/null || { log "guacd died — restart (F2)";  run_pg /opt/guacamole/sbin/guacd -b 127.0.0.1 -l 4822 -f >>"$RUN/guacd.log" 2>&1 & GUACD_PID=$!; }
    kill -0 "$CADDY_PID"  2>/dev/null || { log "caddy died — restart (F2)";  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >>"$RUN/caddy.log" 2>&1 & CADDY_PID=$!; }
    kill -0 "$TOMCAT_PID" 2>/dev/null || { log "tomcat died — restart (F2)"; run_pg env JAVA_HOME="$JAVA_HOME" GUACAMOLE_HOME="$GUACAMOLE_HOME" "$CATALINA_HOME/bin/catalina.sh" run >>"$RUN/tomcat.log" 2>&1 & TOMCAT_PID=$!; }
done
