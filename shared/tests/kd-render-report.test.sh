#!/usr/bin/env bash
# kd-render-report.test.sh — in-box unit proof of the WP-12 B4/V15 render oracle. Exercises the PURE
# node discovery, fd-holder extraction, verdict logic and report formatting, plus the CLI contract
# (including that the GPU-less baseline is a PASS, not a failure). Reading a live session's fds is
# host-gate/rehearsal tier.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
RR="${KD_RENDER_REPORT:-$here/../kd-render-report}"
[ -f "$RR" ] || { echo "FATAL: kd-render-report not found at $RR" >&2; exit 2; }

python3 - "$RR" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("kd_render", sys.argv[1]).load_module()

fails = []
def check(label, got, want):
    if got == want: print("PASS[%s]" % label)
    else: print("FAIL[%s]: got %r want %r" % (label, got, want)); fails.append(label)

# --- render_nodes: ONLY renderD*, sorted; card*/others ignored ---------------------------------
check("render nodes found + sorted",
      m.render_nodes(["card0", "renderD129", "by-path", "renderD128"]),
      ["/dev/dri/renderD128", "/dev/dri/renderD129"])
check("card nodes are NOT render nodes", m.render_nodes(["card0", "card1"]), [])
check("empty /dev/dri (GPU-less baseline)", m.render_nodes([]), [])
check("junk names ignored", m.render_nodes(["renderDX", "render", "renderD"]), [])

# --- held_nodes: extract render nodes from /proc/<pid>/fd targets -------------------------------
check("held from fd targets",
      m.held_nodes(["/dev/dri/renderD128", "/dev/null", "socket:[123]", "/dev/dri/card0", None, ""]),
      ["/dev/dri/renderD128"])
check("dedupes repeated fds on one node",
      m.held_nodes(["/dev/dri/renderD128"] * 4), ["/dev/dri/renderD128"])
check("no render fds -> empty", m.held_nodes(["/dev/null", "pipe:[9]"]), [])

# --- verdict: the four honest states ------------------------------------------------------------
N = ["/dev/dri/renderD128"]
check("no node -> ABSENT (the CORRECT GPU-less baseline)", m.verdict([], None, []), "ABSENT")
check("node held -> IN-USE", m.verdict(N, True, N), "IN-USE")
check("node unopenable by user -> PRESENT-UNOPENABLE (V15/GIDMap failure)",
      m.verdict(N, False, []), "PRESENT-UNOPENABLE")
check("node openable but unused -> AVAILABLE-NOT-USED", m.verdict(N, True, []), "AVAILABLE-NOT-USED")
check("held wins even if openability unknown", m.verdict(N, None, N), "IN-USE")

# --- report formatting names the holders --------------------------------------------------------
rep = m.format_report("gw1", N, True, N, [("510", "gnome-shell", "/dev/dri/renderD128")])
for frag in ("user=gw1", "render-nodes=/dev/dri/renderD128", "openable-by-user=yes",
             "held-by-session=/dev/dri/renderD128", "holder pid=510 comm=gnome-shell", "gpu=IN-USE"):
    check("report contains %r" % frag, frag in rep, True)
rep0 = m.format_report("gw1", [], None, [], [])
check("GPU-less report says ABSENT", "gpu=ABSENT" in rep0, True)
check("GPU-less report marks openability n/a", "openable-by-user=n/a" in rep0, True)

# --- CLI contract -------------------------------------------------------------------------------
import io, contextlib
def run(argv, listing, openable, holders):
    m._listing = lambda _l=listing: _l
    m._can_open_as = lambda u, n, _o=openable: _o
    m._session_holders = lambda u, _h=holders: _h
    out, err = io.StringIO(), io.StringIO()
    sys.argv = ["kd-render-report"] + argv
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = m.main()
    return rc, out.getvalue(), err.getvalue()

# The GPU-less Erebus baseline MUST be a clean rc0 — 'no GPU' is correct there, not a failure.
rc, out, _ = run(["--user", "gw1"], [], None, [])
check("CLI GPU-less baseline -> rc0", rc, 0)
check("CLI GPU-less baseline reports ABSENT", "gpu=ABSENT" in out, True)

# Strix: node present, held by the session -> IN-USE, and --require-gpu passes
holders = [("510", "gnome-shell", "/dev/dri/renderD128")]
rc, out, _ = run(["--user", "gw1"], ["renderD128", "card0"], True, holders)
check("CLI GPU in use -> rc0 IN-USE", (rc, "gpu=IN-USE" in out), (0, True))
rc, out, _ = run(["--user", "gw1", "--require-gpu"], ["renderD128"], True, holders)
check("CLI --require-gpu with GPU in use -> rc0", rc, 0)

# --require-gpu must FAIL (rc1) on every non-IN-USE state, self-diagnosing which link broke
for label, listing, openable, hold in (
        ("absent", [], None, []),
        ("unopenable", ["renderD128"], False, []),
        ("available-not-used", ["renderD128"], True, [])):
    rc, out, err = run(["--user", "gw1", "--require-gpu"], listing, openable, hold)
    check("CLI --require-gpu %s -> rc1" % label, rc, 1)
    check("CLI --require-gpu %s is self-diagnosing" % label, "gpu=" in err, True)

for bad in (["--bogus"], ["--user"], ["--user", "gw1", "extra"]):
    rc, _, _ = run(bad, [], None, [])
    check("CLI usage error %r -> rc2" % (bad,), rc, 2)

print("----")
if fails: print("kd-render-report.test.sh: %d FAILURE(S): %s" % (len(fails), ", ".join(fails))); sys.exit(1)
print("kd-render-report.test.sh: ALL GREEN"); sys.exit(0)
PY
