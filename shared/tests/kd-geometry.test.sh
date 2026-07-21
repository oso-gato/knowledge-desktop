#!/usr/bin/env bash
# kd-geometry.test.sh (WP-12, C4) — IN-BOX unit proof of the geometry oracle's PURE parsers (X11
# xrandr + Wayland Mutter GetCurrentState). The live query is host-gate/COJOIN; here we prove the
# parsing that turns each lineage's raw state into the C4 observable WxH.
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import importlib.util as u
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("kg", "shared/kd-geometry")
kg = u.module_from_spec(u.spec_from_loader("kg", loader)); loader.exec_module(kg)
fails = []
def ok(c, m):
    if not c: fails.append(m)

# --- X11: parse Screen 0 current size from a real xrandr dump (incl. the rdp0/xorgxrdp shape) ---
xr = ("Screen 0: minimum 256 x 256, current 1234 x 789, maximum 16384 x 16384\n"
      "rdp0 connected 1234x789+0+0 339mm x 271mm\n   1234x789     50.00*\n")
ok(kg.parse_x11_geometry(xr) == "1234x789", "x11: current size parsed: %r" % kg.parse_x11_geometry(xr))
ok(kg.parse_x11_geometry("no screen line here") is None, "x11: no-match -> None")

# --- Wayland: logical monitor size from a Mutter GetCurrentState unpack ---
def mon(conn, w, h):
    return ((conn, "V", "P", "s"),
            [("%dx%d@60" % (w, h), w, h, 60.0, 1.0, [1.0], {"is-current": True, "is-preferred": True})], {})
def logmon(primary, conns):
    return (0, 0, 1.0, 0, primary, [(c, "V", "P", "s") for c in conns], {})

# one logical monitor (the mirrored clone the governor applies) over a 1400x1050 virtual monitor
st = (7, [mon("Meta-0", 1400, 1050)], [logmon(True, ["Meta-0"])], {})
ok(kg.logical_size_from_state(st) == "1400x1050", "wayland: single logical size: %r" % kg.logical_size_from_state(st))

# two monitors mirrored onto ONE logical monitor at 1400x1050 (both connectors on the logical) ->
# reports the governing/primary drawing area
st2 = (8, [mon("Meta-0", 1400, 1050), mon("Meta-1", 1400, 1050)], [logmon(True, ["Meta-0", "Meta-1"])], {})
ok(kg.logical_size_from_state(st2) == "1400x1050", "wayland: mirrored clone size: %r" % kg.logical_size_from_state(st2))

# prefers the PRIMARY logical monitor when several exist
st3 = (9, [mon("Meta-0", 1920, 1080), mon("Meta-1", 1024, 768)],
       [logmon(False, ["Meta-0"]), logmon(True, ["Meta-1"])], {})
ok(kg.logical_size_from_state(st3) == "1024x768", "wayland: picks the PRIMARY logical: %r" % kg.logical_size_from_state(st3))

# no logical monitors (headless, no client attached) -> None
ok(kg.logical_size_from_state((10, [], [], {})) is None, "wayland: no logical -> None")

if fails:
    print("KD-GEOMETRY: FAIL")
    for m in fails: print("  -", m)
    raise SystemExit(1)
print("KD-GEOMETRY: GREEN (x11 xrandr + wayland Mutter parsers; primary-logical drawing area)")
PY