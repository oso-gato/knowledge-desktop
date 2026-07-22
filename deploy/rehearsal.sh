#!/usr/bin/env bash
# rehearsal.sh — the AUTOMATED portion of the §6.4 dress rehearsal (WP-21). Owner/host-run.
# Deploys a lineage on THIS real host via setup.sh, then re-proves — on the LIVE deploy, not a
# fenced candidate — every §6.4 clause a script can honestly assert, and prints the REQUIRED MANUAL
# checklist (REHEARSAL.md §§2-4) for the human-observed clauses. It NEVER marks a manual clause PASS.
#
#   ./deploy/rehearsal.sh <roster.json> <xrdp|grd> [--drive-lockout] [--teardown]
#
# HONEST SCOPE (N5 — this proves only what it runs):
#   AUTOMATED here: deploy+health; the CREDENTIAL-FREE baked probes on the running container
#     (kd-health, kd-rdp-check [X.224 handshake is pre-auth, no credential], kd-isolation-check
#     [usernames only]); the on-host listener census (ss -ltn); the recoverability-posture assertion
#     + running-digest record for the rollback drill.
#   NOT automated (by design): the CREDENTIAL round-trips (web mandatory-2FA, VNC login, secrets-scan)
#     — running them here would put REAL roster secrets on this script's argv/env, itself an E1 leak;
#     they are gate-proven (fixture) AND re-proven live by the human login steps (REHEARSAL.md §2).
#     The pixels/one-session/2FA-enroll/resume/geometry/off-host-scan clauses are inherently manual.
set -uo pipefail

die(){ echo "rehearsal.sh: FATAL: $*" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
ROSTER="${1:?usage: rehearsal.sh <roster.json> <xrdp|grd> [--drive-lockout] [--teardown]}"
LINEAGE="${2:?usage: rehearsal.sh <roster.json> <xrdp|grd> [--drive-lockout] [--teardown]}"
case "$LINEAGE" in xrdp|grd) ;; *) die "lineage must be xrdp or grd, got '$LINEAGE'";; esac
DRIVE_LOCKOUT=0; TEARDOWN=0
shift 2 || true
for a in "$@"; do case "$a" in
  --drive-lockout) DRIVE_LOCKOUT=1;; --teardown) TEARDOWN=1;;
  *) die "unknown flag: $a";; esac; done
[ -r "$ROSTER" ] || die "roster not readable: $ROSTER"
command -v podman >/dev/null || die "podman not found"

OWNER="kd-$LINEAGE"; WEB="kd-web-$LINEAGE"
[ -f "$SRC/$WEB.container" ] && UNITS="$OWNER $WEB" || UNITS="$OWNER"

# ---- teardown path -------------------------------------------------------------------------------
if [ "$TEARDOWN" = 1 ]; then
  echo "== teardown: $UNITS =="
  for u in $UNITS; do systemctl --user stop "$u.service" 2>/dev/null || true; done
  podman secret rm kd-roster 2>/dev/null || true
  # the three persistent volumes per unit (nosuid,nodev) — remove for a clean rehearsal re-run
  podman volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^kd-(web-)?$LINEAGE-" \
    | while read -r v; do podman volume rm "$v" 2>/dev/null || true; done
  echo "  torn down (units stopped; kd-roster + kd-$LINEAGE-* volumes removed)."
  exit 0
fi

# ---- roster identities (usernames only — NEVER read the passwords) -------------------------------
read -r ADMIN W1 W2 < <(python3 - "$ROSTER" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
adm=r.get("admin",{}).get("username","kadm")
ws=[w.get("username") for w in r.get("workers",[]) if w.get("username")]
# de-dup preserving order, drop the admin if it recurs, take the first two distinct workers
seen=set(); uniq=[]
for w in ws:
    if w and w not in seen and w!=adm: seen.add(w); uniq.append(w)
print(adm, (uniq+[ "", "" ])[0], (uniq+[ "", "" ])[1])
PY
) || die "could not parse usernames from $ROSTER"
[ -n "$W1" ] && [ -n "$W2" ] || die "roster needs an admin + at least TWO distinct workers for the D2/D3 spot-check"
echo "== rehearsal: lineage=$LINEAGE  admin=$ADMIN  workers=$W1,$W2 =="

pass=0; fail=0
ok(){   echo "  PASS  $*"; pass=$((pass+1)); }
no(){   echo "  FAIL  $*" >&2; fail=$((fail+1)); }
xin(){  podman exec "$OWNER" "$@"; }   # exec inside the desktop (netns-owner) container

# ---- 1. deploy on THIS host + wait healthy (setup.sh owns the prereq asserts + the health wait) --
echo "== 1. deploy via setup.sh =="
"$SRC/setup.sh" "$ROSTER" "$LINEAGE" || die "setup.sh failed — rehearsal cannot proceed"
for u in $UNITS; do
  h="$(podman inspect -f '{{.State.Health.Status}}' "$u" 2>/dev/null || echo none)"
  [ "$h" = healthy ] && ok "deploy: $u healthy" || no "deploy: $u NOT healthy ($h)"
done

# ---- 2. baked-probe re-proof on the LIVE deploy (credential-free probes only) --------------------
echo "== 2. baked-probe re-proof (live, credential-free) =="
xin /usr/local/bin/kd-health >/dev/null 2>&1 && ok "kd-health (live truthful health)" || no "kd-health RED on the live deploy"
# C2: real RDP X.224 handshake on each per-user door (grd 3389/3390/3391; xrdp 3389).
case "$LINEAGE" in
  grd)  RDP_PORTS="3389 3390 3391" ;;
  xrdp) RDP_PORTS="3389" ;;
esac
for p in $RDP_PORTS; do
  xin /usr/libexec/kd/kd-rdp-check 127.0.0.1 "$p" >/dev/null 2>&1 \
    && ok "C2 kd-rdp-check :$p (real X.224 handshake)" || no "C2 kd-rdp-check :$p — no valid handshake"
done
# D2/D3: absolute per-user home privacy incl. no admin supervisory exception (usernames only).
xin /usr/libexec/kd/kd-isolation-check /home "$W1" "$W2" "$ADMIN" >/dev/null 2>&1 \
  && ok "D2/D3 kd-isolation-check ($W1/$W2 mutually private; $ADMIN no supervisory read)" \
  || no "D2/D3 kd-isolation-check — a home was readable across users (isolation broken)"
echo "  NOTE: web mandatory-2FA (A3), VNC login (A13) + secrets-scan (E1) are NOT run here"
echo "        (they need REAL roster secrets on argv — an E1 leak); they are gate-proven (fixture)"
echo "        and re-proven LIVE by the human login steps in REHEARSAL.md §2."

# ---- 3. on-host listener census (runtime companion to the C6 static publish-set lint) -----------
echo "== 3. on-host listener census (ss -ltn) =="
if xin sh -c 'command -v ss >/dev/null'; then
  echo "  --- listeners inside $OWNER ---"; xin ss -ltn 2>/dev/null | sed 's/^/    /'
  echo "  Confirm against REHEARSAL.md: the expected door table is present and NO rogue listener."
  echo "  (This is the on-host half; A2 public-vs-private reachability is the OFF-host scan, §3.)"
  ok "listener census printed for operator confirmation"
else
  echo "  ss absent in $OWNER — census via the off-host scan only (REHEARSAL.md §3)."
fi

# ---- 4. rollback drill — recoverability posture + running digest --------------------------------
echo "== 4. rollback drill (recoverability posture) =="
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
for u in $UNITS; do
  q="$UNIT_DIR/$u.container"
  [ -f "$q" ] || { no "rollback: installed quadlet $q missing"; continue; }
  miss=""
  for k in 'HealthOnFailure=kill' 'AutoUpdate=registry' 'Notify=healthy'; do
    grep -q "^$k" "$q" || miss="$miss $k"
  done
  [ -z "$miss" ] && ok "rollback posture in $u (HealthOnFailure=kill + AutoUpdate=registry + Notify=healthy present)" || no "rollback: $u missing:$miss"
  dg="$(podman inspect -f '{{index .ImageDigest}}' "$u" 2>/dev/null || podman inspect -f '{{.Image}}' "$u" 2>/dev/null || echo unknown)"
  echo "  running digest[$u]: $dg  (record this; the drill = push a bad :latest, observe HealthOnFailure=kill,"
  echo "     then 'podman auto-update' / redeploy this digest restores health — see REHEARSAL.md §1)"
done

# ---- 5. optional: DRIVE the brute-force lockout (wrong password only — E1-safe) ------------------
if [ "$DRIVE_LOCKOUT" = 1 ]; then
  echo "== 5. drive brute-force lockout (A4) — 6 WRONG-password attempts from THIS source =="
  echo "  (a wrong password is not a secret; observe the ban in the web door, then confirm a"
  echo "   legitimate DIFFERENT source is unaffected — REHEARSAL.md §2c)"
  for i in $(seq 1 6); do
    code="$(xin sh -c "curl -sk -o /dev/null -w '%{http_code}' -X POST https://127.0.0.1/guacamole/api/tokens -d username=$W1 -d password=definitely-wrong-$i" 2>/dev/null || echo '000')"
    echo "    attempt $i: HTTP $code"
  done
  echo "  → now observe from a browser that $W1 is banned from THIS source for the ban window."
fi

# ---- summary + the manual checklist -------------------------------------------------------------
echo ""
echo "================ AUTOMATED SUMMARY (lineage $LINEAGE): $pass PASS, $fail FAIL ================"
[ "$fail" = 0 ] && echo "AUTOMATED CLAUSES GREEN — proceed to the REQUIRED MANUAL steps." \
                 || echo "AUTOMATED CLAUSES have FAILURES — fix before the manual steps."
cat <<EOF

REQUIRED MANUAL (this script CANNOT do these — see REHEARSAL.md §§2-4), lineage $LINEAGE:
  [ ] A11   real pixels: web + RDP $( [ "$LINEAGE" = xrdp ] && echo "+ VNC ")→ ONE shared session (marker present on every path)
  [ ] 2FA   TOTP enrollment, then a valid password ALONE draws the challenge (no token)
  [ ] lockout  repeated wrong passwords ban the source ($([ "$DRIVE_LOCKOUT" = 1 ] && echo "driven above; " )observe the ban)
  [ ] resume   gw1 from a second device resumes the SAME session (C2)
  [ ] C4    geometry follows the most-recently-active display, every path$([ "$LINEAGE" = xrdp ] && echo " (record the disclosed xrdp degrade)")
  [ ] A9    log in as $W2 → lands ONLY on $W2's session ($W1's marker absent)
  [ ] A10   $W1 erebus tile reaches Erebus; $ADMIN reaches erebus AND fedora-dev over the tailnet
  [ ] A2    OFF-HOST scan: exactly ONE public endpoint (the web door); private doors absent (REHEARSAL.md §3)

Record each in the REHEARSAL.md §5 sign-off table. Teardown when done:
  ./deploy/rehearsal.sh $ROSTER $LINEAGE --teardown
EOF
[ "$fail" = 0 ] || exit 1
