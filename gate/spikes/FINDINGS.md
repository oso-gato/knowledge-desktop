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

## V1 — grd accepts a concurrent second RDP connection (WP-04, host-gate, 2026-07-19)

DESIGN line 210 / [ADJ-1] line 55: L1's web-desktop transport is RDP (guacd RDP → grd), **contingent
on V1** — does grd's headless RDP accept an authenticated login and a concurrent second connection, or
does it single-session-refuse like its VNC ([ADJ-25])? A RED reopens the L1 gateway (DESIGN §10 fork).

**Method.** A transient `grdspike` `.live-gate` target reused the production grd image (`CFILE_grd`,
zero shipped surface) with a throwaway RDP client (`freerdp` 3.29 + `Xvfb`) BAKED at build time — the
host-gate fence has **no runtime egress** (probe-time `dnf` cannot resolve Fedora mirrors), a reusable
fact for future host-gate probes. The probe drove `xfreerdp` attaches to `grd` on `kadm:3389`
(NLA, `/cert:ignore`). Nine iterations (draft PR #27); the target + bake block were removed before merge.

**DECISION-CRITICAL RESULT = V1 GO (transport viable), with a session-stability risk deferred to the
real client.**
- **grd RDP login WORKS** (`nla-exit=0`; a session authenticates and loads real channels — `rdpgfx`,
  `disp`, `rdpsnd`, `ainput`). This also closes WP-08's deferred RDP-login round-trip (the credential
  path — `kd-cred`'s `grdctl rdp set-credentials <user>` + stdin phrase — authenticates; V17 fine).
- **grd ACCEPTS a concurrent second connection** — two staggered attaches BOTH reached channel-load
  (`A-markers>0 && B-markers>0`). grd does **not** single-session-refuse (DESIGN's "sessions GList, no
  refusal" hypothesis CONFIRMED). So L1 web=RDP has a stock path → **NOT a §10 fork**.
- **BUT sessions do not HOLD under this test client**: shortly after channel-load grd's per-user RDP
  daemon goes down (`port-after=down`; client dies SIGPIPE/`Connection reset by peer`), then the next
  connect is `Connection refused` while systemd restarts it. The trigger chain is entangled with
  **three artifacts of THIS test setup, none shared by production**: (a) Fedora FreeRDP **3.29**'s
  experimental `WITH_GFX_AV1=ON` build ("might crash the application") on BOTH endpoints; (b) the
  client's **cliprdr FUSE mount** denied by the fence (`fusermount3: mount failed: Operation not
  permitted`); (c) software rendering / Xvfb. Production L1 uses guacd's vendored **FreeRDP 3.14**
  (no AV1, no client-side cliprdr-FUSE, buffer rendering) — a DIFFERENT client.

**Faithful limit.** A stock-client stability + concurrency proof needs the REAL guacd client via a
COJOIN web+grd co-boot — the fedora-bootstrap gate-harness capability (control-plane, out of the
workload's scope) that WP-11-L2 already defers its paint/marker-a11 proof to. `xfreerdp` 3.29 cannot
stand in for guacd 3.14 here; more iterations would not reach the production answer.

**Design inputs recorded for WP-11-L1 (do NOT re-litigate V1):**
1. The per-user guac **RDP connection** should pin **conservative params** — disable GFX/AV1
   (`enable-gfx`/RemoteFX off) and clipboard/drive redirection — to avoid the observed instability
   path; validate the exact param set when the real client runs.
2. Session **stability + true concurrency** (A11) get their faithful proof with the guacd client at
   the **COJOIN tier** (same deferral as WP-11-L2), NOT from this xfreerdp spike.
3. RISK carried forward (top item for the COJOIN proof): if grd's RDP daemon crashes server-side even
   with guacd 3.14 / a stock client (mstsc), L1's primary door needs a mitigation (a grd-side codec/env
   pin, provenance-clean) — surface then, with evidence, if it reproduces with the real client.

## V3 — xorgxrdp RandR REJECTS external screen-resize (WP-12 gate-keeper, host-gate, 2026-07-20)

DESIGN V3 (V-register): does xorgxrdp's RandR accept external arbitrary modes, so the L2
geometry-arbiter can re-assert the governing display's geometry (C4)? Host-gate spike (transient
`xrdpgeom` target, draft PR #31, 8 iterations) on the REAL provisioned xrdp box, probing kadm's warm
prestarted session (`:10`, `-auth /home/kadm/.Xauthority`) via `xrandr`.

**DECISION-CRITICAL RESULT: mode DEFINITION is accepted; every external SCREEN-RESIZE is REJECTED.**
- `xrandr --newmode` + `--addmode` **succeed** (an arbitrary 1234x789 mode is defined + added to the
  `rdp0` output — `nm=0 am=0`, the mode shows in the readback).
- `--output rdp0 --mode <arbitrary>`, `--fb <shrink>`, AND `--fb <grow>` **all fail**, every one with
  the IDENTICAL X error: **`BadMatch (invalid parameter attributes)` on `RRSetScreenSize` (RandR
  140/7)**. The screen never leaves its client-negotiated 1280x1024.
- ⇒ the L2 X-screen size is **client-negotiation-driven** (the RDP/VNC client's SetDesktopSize) and
  **cannot be set externally** by an in-session actor via xrandr/RRSetScreenSize.

**Design implication (why this is a fork, not a note):**
- BASE C4 holds by xorgxrdp's own design: a client's viewport change → its SetDesktopSize →
  xorgxrdp resizes the session (single/sequential display-tracking — xrdp's core dynamic-resize;
  the client round-trip is the faithful proof, host-gate/COJOIN).
- The DESIGN's L2 arbiter **"RandR re-assertion"** (DESIGN §2 L2 / line 23 — force the governing
  display's geometry) is **NOT viable**: the arbiter can attribute input governance (XInput2) but
  **cannot enforce geometry**, because it cannot resize the X screen. There is **no server-side
  geometry-enforcement path on L2** (RDP display-control + VNC SetDesktopSize are both client→server;
  a server→client VNC DesktopSize push would itself need the rejected RRSetScreenSize).
- Consequence for **C4-CONCURRENT on L2** (2+ displays on one session, governing-by-INPUT should
  win): the session geometry is the LAST SetDesktopSize sender (resize-driven), which the arbiter
  cannot override to match the most-recently-active-by-input display. C4's "geometry = most recently
  active display, follows ≤5s" is therefore **not deliverable for the concurrent case on L2** as the
  arbiter was designed. This EXTENDS the already-disclosed "last SetDesktopSize sender is the family
  governor" residual (line 23) from the VNC-family to all of L2.

**Owner fork (§11-class — C4-concurrent-on-L2):** the choices are (a) accept C4-concurrent on L2 as
last-client-resize (a disclosed E6 residual — sequential C4 works; concurrent governing-by-input
does not force geometry), or (b) reconsider. Decide alongside the **L1/grd V2** result (Mutter
`ApplyMonitorsConfig` CAN force a monitor config, so the PRIMARY lineage may satisfy C4-concurrent —
V2 is the next spike). Reusable host-gate facts: xrdp's Xorg uses `-auth .Xauthority` RELATIVE
(→ absolute `/home/<user>/.Xauthority`); the gate surfaces PID-1 stdout, so a probe writes decisive
lines to `/proc/1/fd/1`.
