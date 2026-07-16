# De-risk spike findings (empirical, in-box)

## V4-prep — web-door component availability (2026-07-13)
Query: `dnf repoquery` against the pinned Fedora 44 base.

| Component | Fedora 44 | Design pin | Verdict |
|---|---|---|---|
| guacamole-server | **absent** | class-(c) source build [ADJ-1] | ✅ confirmed necessary |
| freerdp / -devel | **3.24.2, 3.27.1** | vendored <3.15 for guacd [ADJ-3] | ✅ distro is PAST the guacd-1.6 ceiling → vendoring validated |
| xrdp | 0.10.5, **0.10.6** | 0.10.6 | ✅ class-(a) |
| xorgxrdp | 0.10.5 | xorgxrdp-glamor 0.10.5 | ⚠️ VERIFY glamor subpackage exists |
| gnome-remote-desktop | 50.0, **50.2** | grd 50.x (VNC backend) | ✅ class-(a); VERIFY VNC backend compiled in |

Upstream (web, GUACAMOLE-2146): guacd 1.6.0 FreeRDP3 support is real but **experimental** —
`codecs_free` deprecated @ FreeRDP 3.6.0, RAIL/RemoteApp broken on FreeRDP3 (irrelevant to us: the
web tile is a FULL-DESKTOP RDP session, not RemoteApp), and a **3.15 API break** is the hard ceiling.
So the guacd-1.6-compatible FreeRDP window is roughly **[3.0, 3.15)**. Distro 3.24/3.27 is outside it.

## V4 — guacd 1.6.0 vs distro FreeRDP: (spike in progress)

**RESULT (empirical, 2 in-box builds):**
1. guacd 1.6.0 does NOT build on Fedora 44 glibc unmodified: `_XOPEN_SOURCE` redefined (guacd 700
   vs glibc 800) under guacd's `-Werror` → fatal in libguac. Workaround: `configure CFLAGS=-Wno-error`
   (WP-10 shipping build: a scoped source patch is cleaner). ⇒ recipe requirement, recorded.
2. Past that, guacd 1.6.0's RDP plugin does NOT compile against distro FreeRDP **3.27.1**: HARD API
   error `'struct rdp_freerdp' has no member named 'input'` in input-queue.c/keyboard.c — the 3.15
   API break (FreeRDP removed `->input` after 3.14). NOT a deprecation warning; a build failure.

**CONCLUSION:** DESIGN [ADJ-3] VALIDATED — the web door MUST vendor a FreeRDP <3.15 at a private
prefix; the distro freerdp (3.24/3.27, used by grd on L2) is unusable for guacd. Target: newest
FreeRDP 3.14.x. Positive-path proof (vendored 3.14 + guacd builds the RDP plugin) = spike v4c.

**V4c — positive path (vendored FreeRDP 3.14.0 + guacd 1.6.0): DECISION-CRITICAL RESULT = PASS**
- FreeRDP 3.14.0 (newest before the 3.15 break) BUILDS + installs cleanly at /opt/guacamole with:
  deps `cjson-devel uriparser-devel fuse3-devel openssl-devel zlib-devel` (opus optional/warn);
  cmake `-DWITH_SERVER=OFF -DWITH_X11=OFF -DWITH_CLIENT_SDL=OFF -DWITH_KRB5=OFF -DWITH_PCSC=OFF
  -DWITH_CUPS=OFF -DWITH_FFMPEG=OFF -DWITH_SWSCALE=OFF -DBUILD_TESTING=OFF`.
- guacd 1.6.0 `./configure` against it → **`freerdp yes (3.x)` / `RDP yes`** — the RDP plugin is
  ENABLED (guacd's own const-pointer/LoadChannels probes adapt to the 3.14 API). This is the proof
  the design needed: **guacd 1.6.0 IS API-compatible with a vendorable FreeRDP <3.15**, while the
  distro 3.24/3.27 is NOT.
- RESIDUAL (WP-10 build detail, NOT a design risk): guacd's full `make` then hit one further
  compile error (truncated by the spike's `| tail -5`); `-Wno-error` clears the glibc _XOPEN_SOURCE
  issue, the residual is in a later module — resolve at WP-10 with the recipe above (unmask by
  removing the tail, fix the specific file). Decision unaffected.

**BOTTOM LINE (V4 closed for the decision):** the web door is feasible — vendor FreeRDP 3.14.0 at a
private prefix + build guacd 1.6.0 against it (glibc -Wno-error/patch). DESIGN [ADJ-1/2/3] stand.
