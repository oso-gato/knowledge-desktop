#!/usr/bin/env bash
# kd-sessions.test.sh — in-box unit proof of the WP-12 A11 census oracle. Exercises the PURE parser
# and the full CLI against FIXTURE `ps` output (the live enumeration is host-gate/COJOIN tier: a real
# session needs a real door attachment). Covers the A11 assertions the rehearsal depends on — census
# ==1 for one shared session, and the VIOLATION case where a path forked a second session — plus the
# process-pattern SELF-MATCH trap that would silently inflate every count.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ORACLE="${KD_SESSIONS:-$here/../kd-sessions}"
[ -f "$ORACLE" ] || { echo "FATAL: kd-sessions not found at $ORACLE" >&2; exit 2; }

python3 - "$ORACLE" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("kd_sessions", sys.argv[1]).load_module()

fails = []
def check(label, got, want):
    if got == want: print("PASS[%s]" % label)
    else: print("FAIL[%s]: got %r want %r" % (label, got, want)); fails.append(label)

HDR = "USER                             UID   PID COMMAND\n"

# --- L2/xrdp: ONE session per user (the A11-correct state) -------------------------------------
L2_ONE = HDR + (
    "root                               0     1 kd-entrypoint\n"
    "root                               0    42 xrdp\n"
    "root                               0    43 xrdp-sesman\n"
    "gw1                             2001   210 Xorg\n"
    "gw1                             2001   215 xfce4-session\n"
    "kadm                            2000   310 Xorg\n"
    "kadm                            2000   315 xfce4-session\n"
)
s = m.parse_sessions(L2_ONE, m.LEADERS_X11)
check("L2 one-session parse", sorted(s), [("gw1", 2001, 210, "Xorg"), ("kadm", 2000, 310, "Xorg")])
check("L2 census gw1 == 1 (A11 holds)", m.census(s, "gw1"), 1)
check("L2 census kadm == 1", m.census(s, "kadm"), 1)
check("L2 census gw2 == 0 (not connected)", m.census(s, "gw2"), 0)

# --- L2: a path FORKED a second session for gw1 (the A11 VIOLATION the rehearsal must catch) ----
L2_FORKED = L2_ONE + "gw1                             2001   410 Xorg\n"
s2 = m.parse_sessions(L2_FORKED, m.LEADERS_X11)
check("L2 forked-session census == 2 (A11 VIOLATION detected)", m.census(s2, "gw1"), 2)
check("L2 forked: other user unaffected", m.census(s2, "kadm"), 1)

# --- SELF-MATCH TRAP: args mentioning a leader must NOT count (comm is matched EXACTLY) ---------
# A naive `ps | grep Xorg` / pgrep -f would count all three of these and inflate the census.
L2_DECOYS = L2_ONE + (
    "root                               0   900 kd-sessions\n"        # THIS oracle
    "root                               0   901 grep\n"               # `grep Xorg`
    "gw1                             2001   902 bash\n"               # `bash -c '... Xorg ...'`
    "gw1                             2001   903 Xorg-wrapper\n"       # near-miss comm, NOT a leader
)
s3 = m.parse_sessions(L2_DECOYS, m.LEADERS_X11)
check("self-match guard: decoys do NOT inflate the census", m.census(s3, "gw1"), 1)

# --- L1/grd: the per-user headless compositor IS the session ------------------------------------
L1 = HDR + (
    "root                               0     1 systemd\n"
    "gw1                             2001   500 gnome-shell\n"
    "gw1                             2001   501 gnome-remote-des\n"
    "kadm                            2000   600 gnome-shell\n"
)
s4 = m.parse_sessions(L1, m.LEADERS_WAYLAND)
check("L1 census gw1 == 1", m.census(s4, "gw1"), 1)
check("L1 parse finds both users", len(s4), 2)
check("L1 X11 leaders find nothing here", m.parse_sessions(L1, m.LEADERS_X11), [])

# --- header + malformed lines are skipped -------------------------------------------------------
check("header alone yields nothing", m.parse_sessions(HDR, m.LEADERS_X11), [])
check("malformed lines skipped", m.parse_sessions("garbage\n\nx y\n" + HDR, m.LEADERS_X11), [])

# --- long usernames are not truncated (user:32 field) -------------------------------------------
LONG = HDR + "a-very-long-worker-username-x   2005   700 Xorg\n"
check("long username intact", m.parse_sessions(LONG, m.LEADERS_X11)[0][0], "a-very-long-worker-username-x")

# --- CLI end-to-end against fixture ps (monkeypatch the live enumeration) -----------------------
def run(argv, ps_out, leaders=None):
    m._ps = lambda _o=ps_out: _o
    if leaders is not None:
        m._leaders_for_this_box = lambda _l=leaders: _l
    import io, contextlib
    out, err = io.StringIO(), io.StringIO()
    sys.argv = ["kd-sessions"] + argv
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = m.main()
    return rc, out.getvalue().strip(), err.getvalue().strip()

rc, out, _ = run(["--census", "gw1"], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --census one session -> rc0 '1'", (rc, out), (0, "1"))
rc, out, _ = run(["--census", "gw1"], L2_FORKED, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --census forked -> rc0 '2'", (rc, out), (0, "2"))
rc, out, _ = run(["--census", "gw2"], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --census absent user -> rc0 '0'", (rc, out), (0, "0"))
rc, out, _ = run(["--serving", "gw1"], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --serving -> rc0 'uid pid leader'", (rc, out), (0, "2001 210 Xorg"))
rc, _, err = run(["--serving", "gw2"], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --serving absent -> rc1", rc, 1)
rc, _, err = run(["--serving", "gw1"], L2_FORKED, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI --serving ambiguous -> rc3 (never silently picks one)", rc, 3)
check("CLI --serving ambiguous is self-diagnosing", "A11 VIOLATION" in err, True)
rc, _, _ = run(["--bogus", "x"], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI usage error -> rc2", rc, 2)
rc, out, _ = run([], L2_ONE, (m.LEADERS_X11, m.FALLBACK_X11))
check("CLI list -> both sessions", out, "gw1 2001 210 Xorg\nkadm 2000 310 Xorg")

# --- lineage fallback: an X11 box whose primary leader is absent falls back, never double-counts -
NO_XORG = HDR + "gw1                             2001   800 xfce4-session\n"
rc, out, _ = run(["--census", "gw1"], NO_XORG, (m.LEADERS_X11, m.FALLBACK_X11))
check("fallback leader used when no primary -> 1 (not 0)", (rc, out), (0, "1"))
BOTH = HDR + ("gw1                             2001   210 Xorg\n"
              "gw1                             2001   215 xfce4-session\n")
rc, out, _ = run(["--census", "gw1"], BOTH, (m.LEADERS_X11, m.FALLBACK_X11))
check("primary present -> fallback NOT added (no double-count)", (rc, out), (0, "1"))

print("----")
if fails: print("kd-sessions.test.sh: %d FAILURE(S): %s" % (len(fails), ", ".join(fails))); sys.exit(1)
print("kd-sessions.test.sh: ALL GREEN"); sys.exit(0)
PY
