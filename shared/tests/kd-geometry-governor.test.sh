#!/usr/bin/env bash
# kd-geometry-governor.test.sh (WP-12, C4) — IN-BOX unit proof of the L1 geometry-governor's PURE
# config computation (compute_mirror_config + config_matches), driven by fixture Mutter
# GetCurrentState unpacks. The live ApplyMonitorsConfig round-trip is PROVEN by the V2 gate-keeper
# spike (gate/spikes/FINDINGS.md); the full C4 matrix rides COJOIN (2 stable clients). Here we prove
# the governor computes the RIGHT mirror config: one clone logical monitor at the governing
# resolution, and honestly DROPS a monitor that lacks a shared mode (Mutter clone same-mode
# constraint — DESIGN §2).
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import importlib.util as u
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("gg", "lineage-grd/geometry-governor")
spec = u.spec_from_loader("gg", loader)
gg = u.module_from_spec(spec); loader.exec_module(gg)
fails = []
def ok(c, m):
    if not c: fails.append(m)

def mon(conn, modes):  # modes: list of (id,w,h) ; first is current
    ms = [(mid, w, h, 60.0, 1.0, [1.0], {"is-current": i == 0, "is-preferred": i == 0})
          for i, (mid, w, h) in enumerate(modes)]
    return ((conn, "V", "P", "s"), ms, {})

A   = mon("Meta-0", [("1400x1050@60", 1400, 1050)])                              # sole 1400x1050
B1  = mon("Meta-1", [("1920x1080@60", 1920, 1080)])                             # ONLY 1920x1080
B2  = mon("Meta-1", [("1920x1080@60", 1920, 1080), ("1400x1050@60", 1400, 1050)])  # has a shared mode

# 1) two monitors, B has a matching mode, governing=Meta-0 (1400x1050) -> both clone at 1400x1050, none dropped
st = (10, [A, B2], [], {})
serial, logical, dropped = gg.compute_mirror_config(st, "Meta-0")
ok(serial == 10, "serial passthrough")
ok(logical is not None and len(logical) == 1, "one clone logical monitor")
conns = sorted(s[0] for s in logical[0][5]); ok(conns == ["Meta-0", "Meta-1"], "both monitors in the clone: %r" % conns)
modes = {s[0]: s[1] for s in logical[0][5]}
ok(modes["Meta-0"] == "1400x1050@60" and modes["Meta-1"] == "1400x1050@60", "both pinned to the governing mode: %r" % modes)
ok(dropped == [], "nothing dropped when a shared mode exists: %r" % dropped)

# 2) B has ONLY 1920x1080, governing=Meta-0 (1400x1050) -> B cannot share the mode => dropped (disclosed)
st = (11, [A, B1], [], {})
_, logical, dropped = gg.compute_mirror_config(st, "Meta-0")
ok(dropped == ["Meta-1"], "monitor without the governing mode is DROPPED: %r" % dropped)
modes = {s[0]: s[1] for s in logical[0][5]}
ok(modes["Meta-0"] == "1400x1050@60", "governing monitor keeps its mode")

# 3) governance selects the resolution: governing=Meta-1 (1920x1080), A only has 1400x1050 -> A dropped
st = (12, [A, B1], [], {})
_, logical, dropped = gg.compute_mirror_config(st, "Meta-1")
ok(dropped == ["Meta-0"], "governance drives which resolution wins (A dropped): %r" % dropped)

# 4) no governing file / unknown connector -> the FIRST monitor governs (sole/primary; single C4 works)
st = (13, [A, B2], [], {})
_, logical, dropped = gg.compute_mirror_config(st, None)
ok({s[0]: s[1] for s in logical[0][5]}["Meta-1"] == "1400x1050@60", "default governance = first monitor (A, 1400x1050)")

# 5) empty -> nothing to configure
_, logical, dropped = gg.compute_mirror_config((14, [], [], {}), None)
ok(logical is None, "0 monitors => no config")

# 6) config_matches avoids a redundant re-apply when already a single clone of the same connectors
logmon = (0, 0, 1.0, 0, True, [("Meta-0", "V", "P", "s"), ("Meta-1", "V", "P", "s")], {})
st = (15, [A, B2], [logmon], {})
_, desired, _ = gg.compute_mirror_config(st, "Meta-0")
ok(gg.config_matches(st, desired) is True, "already-mirrored config is detected (no storm)")
st2 = (16, [A, B2], [(0, 0, 1.0, 0, True, [("Meta-0", "V", "P", "s")], {})], {})  # only one monitor in logical
ok(gg.config_matches(st2, desired) is False, "a non-matching layout triggers a re-apply")

if fails:
    print("KD-GEOMETRY-GOVERNOR: FAIL")
    for m in fails: print("  -", m)
    raise SystemExit(1)
print("KD-GEOMETRY-GOVERNOR: GREEN (mirror-config computed; governing-resolution clone; same-mode drop disclosed; no-storm)")
PY