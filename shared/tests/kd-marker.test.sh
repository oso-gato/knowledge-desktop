#!/usr/bin/env bash
# kd-marker.test.sh — in-box unit proof of the WP-12 A11 marker oracle. Exercises the PURE colour
# derivation, the colour<->rgba conversions, the XFCE backdrop-base discovery and the GSettings
# read-back parser, plus the CLI contract. Applying/reading a LIVE session is host-gate/COJOIN tier
# (a real desktop must exist), so the live paths are exercised through injected fakes.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
MARKER="${KD_MARKER:-$here/../kd-marker}"
[ -f "$MARKER" ] || { echo "FATAL: kd-marker not found at $MARKER" >&2; exit 2; }

python3 - "$MARKER" <<'PY'
import sys, re
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("kd_marker", sys.argv[1]).load_module()

fails = []
def check(label, got, want):
    if got == want: print("PASS[%s]" % label)
    else: print("FAIL[%s]: got %r want %r" % (label, got, want)); fails.append(label)
def ok(label, cond):
    check(label, bool(cond), True)

# --- colour_for: deterministic, well-formed, VIVID, and token-discriminating --------------------
c1, c2 = m.colour_for("A11-alpha"), m.colour_for("A11-alpha")
check("deterministic: same token -> same colour", c1, c2)
ok("well-formed #RRGGBB", re.fullmatch(r"#[0-9A-F]{6}", c1))
ok("different tokens -> different colours", m.colour_for("A11-alpha") != m.colour_for("A11-beta"))
# VIVIDNESS is the load-bearing property: a full-saturation/value colour always has one channel at
# 0xFF and one at 0x00, so it can never be confused with a default grey/black/white desktop.
for tok in ("a", "b", "gw1-2026", "A11-MARKER-1753200000", "x" * 64):
    v = m.colour_for(tok); ch = [int(v[i:i+2], 16) for i in (1, 3, 5)]
    ok("vivid (max=255,min=0) for %r -> %s" % (tok[:12], v), max(ch) == 255 and min(ch) == 0)
try:
    m.colour_for(""); fails.append("empty token must raise"); print("FAIL[empty token must raise]")
except ValueError: print("PASS[empty token raises]")

# --- hex <-> rgba round-trip --------------------------------------------------------------------
check("hex_to_rgba red", m.hex_to_rgba("#FF0000"), (1.0, 0.0, 0.0, 1.0))
check("rgba_to_hex red", m.rgba_to_hex(["1.0", "0.0", "0.0", "1.0"]), "#FF0000")
for hx in ("#FF0000", "#00FF00", "#0000FF", "#123456", "#ABCDEF"):
    check("round-trip %s" % hx, m.rgba_to_hex([str(x) for x in m.hex_to_rgba(hx)]), hx)
check("rgba_to_hex accepts 3 values", m.rgba_to_hex(["0", "1", "0"]), "#00FF00")
check("rgba_to_hex clamps out-of-range", m.rgba_to_hex(["-1", "2", "0.5"]), "#00FF80")
for bad in ("FF0000", "#FFF", "#GGGGGG", "", "#FF00000"):
    try:
        m.hex_to_rgba(bad); fails.append("bad hex %r" % bad); print("FAIL[bad hex %r accepted]" % bad)
    except ValueError: print("PASS[bad hex %r rejected]" % bad)

# --- XFCE backdrop-base discovery (per-monitor, de-duplicated, sorted) --------------------------
XFCONF_L = """/backdrop/screen0/monitorrdp0/workspace0/color-style
/backdrop/screen0/monitorrdp0/workspace0/image-style
/backdrop/screen0/monitorrdp0/workspace0/rgba1
/backdrop/screen0/monitorrdp0/workspace1/color-style
/backdrop/screen0/monitorVNC-0/workspace0/rgba1
/backdrop/single-workspace-mode
/general/something-else
"""
check("backdrop bases discovered + deduped + sorted", m.backdrop_bases(XFCONF_L), [
    "/backdrop/screen0/monitorVNC-0/workspace0",
    "/backdrop/screen0/monitorrdp0/workspace0",
    "/backdrop/screen0/monitorrdp0/workspace1"])
check("no backdrop props -> empty", m.backdrop_bases("/general/x\n/other/y\n"), [])
check("empty listing -> empty", m.backdrop_bases(""), [])

# --- GSettings read-back parser -----------------------------------------------------------------
check("gsettings quoted value", m.parse_gsettings_colour("'#ff8800'\n"), "#FF8800")
check("gsettings double-quoted", m.parse_gsettings_colour('"#00FF00"'), "#00FF00")
check("gsettings non-colour -> None", m.parse_gsettings_colour("'some-uri'"), None)
check("gsettings empty -> None", m.parse_gsettings_colour(""), None)

# --- CLI contract -------------------------------------------------------------------------------
import io, contextlib
def run(argv, fake=None, wayland=False):
    if fake is not None: m._run = fake
    m._is_wayland = lambda _w=wayland: _w
    out, err = io.StringIO(), io.StringIO()
    sys.argv = ["kd-marker"] + argv
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = m.main()
    return rc, out.getvalue().strip(), err.getvalue().strip()

class R:                       # a fake subprocess result
    def __init__(self, rc=0, out=""): self.returncode, self.stdout, self.stderr = rc, out, ""

rc, out, _ = run(["expect", "A11-alpha"])
check("CLI expect -> the derived colour (PURE, no session)", (rc, out), (0, m.colour_for("A11-alpha")))
for bad in ([], ["set"], ["get", "x"], ["bogus", "t"], ["expect"]):
    rc, _, _ = run(bad)
    check("CLI usage error %r -> rc2" % (bad,), rc, 2)

# set on X11: xfconf lists backdrop props and every write succeeds
calls = []
def fake_ok(cmd):
    calls.append(cmd)
    return R(0, XFCONF_L) if cmd[-1] == "-l" else R(0)
rc, out, _ = run(["set", "A11-alpha"], fake_ok)
check("CLI set (x11) -> rc0 echoes the colour", (rc, out), (0, m.colour_for("A11-alpha")))
ok("set wrote rgba1 for every discovered base",
   sum(1 for c in calls if any(x.endswith("/rgba1") for x in c) and "-s" in c) == 3)
ok("set pinned solid colour-style", any("color-style" in " ".join(c) and "0" in c for c in calls))
ok("set cleared the wallpaper (image-style 0)", any("image-style" in " ".join(c) for c in calls))

# set on X11 with NO backdrop properties (no session) -> rc1, self-diagnosing
rc, _, err = run(["set", "A11-alpha"], lambda cmd: R(0, "/general/x\n"))
check("CLI set with no session -> rc1", rc, 1)
ok("set failure is self-diagnosing", "refused" in err or "session" in err)
# xfconf itself failing (no DISPLAY) -> rc1, never a silent pass
rc, _, _ = run(["set", "A11-alpha"], lambda cmd: R(1, ""))
check("CLI set when xfconf fails -> rc1", rc, 1)

# get on X11 reads rgba1 back and converts to hex
def fake_get(cmd):
    if cmd[-1] == "-l": return R(0, XFCONF_L)
    return R(0, "1.000000\n0.000000\n0.000000\n1.000000\n")
rc, out, _ = run(["get"], fake_get)
check("CLI get (x11) -> #RRGGBB", (rc, out), (0, "#FF0000"))
rc, _, err = run(["get"], lambda cmd: R(0, "/general/x\n"))
check("CLI get with no marker -> rc1", rc, 1)

print("----")
if fails: print("kd-marker.test.sh: %d FAILURE(S): %s" % (len(fails), ", ".join(fails))); sys.exit(1)
print("kd-marker.test.sh: ALL GREEN"); sys.exit(0)
PY
