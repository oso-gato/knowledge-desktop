# REHEARSAL.md — the §6.4 live-deploy dress rehearsal (WP-21)

The **ship gate**. §6.2's automated pre-merge gate proves each lineage in a *fenced candidate*;
this rehearsal proves it **live on a real host**, for each lineage independently, against the
§6.4 bar. A lineage is **shippable** only when every row of the sign-off checklist below is
recorded PASS on the **Erebus baseline** (GPU-less). The **Strix** GPU pass is WP-22 (the delta
section at the end).

> **Who runs this:** the host/owner. The dev box (Nox) authors this runbook + `rehearsal.sh` but
> cannot execute it — the rehearsal *operates a real host*, drives *real RDP/VNC/web clients*, and
> needs a *TOTP phone*. `rehearsal.sh` automates every part that a script honestly can (deploy, the
> baked-probe re-proof on the live deploy, the on-host listener census, the rollback drill); the
> human-observed clauses (real pixels, one-shared-session, 2FA enrollment, cross-device resume,
> geometry-follows-display, the off-host surface scan) are **REQUIRED MANUAL** steps below — the
> script prints them and never marks them PASS on your behalf.

---

## 0. Prerequisites (both the host and the props)

**Host** (setup.sh asserts the machine ones fail-fast; listed so you can pre-flight):
- rootless podman ≥5, crun; the deploy user has `loginctl enable-linger`;
  `/etc/sub{u,g}id` ≥ 2,097,152; `user.max_user_namespaces > 0`; `/dev/fuse`;
  `net.ipv4.ip_unprivileged_port_start ≤ 443`.
- Erebus baseline: **no** `/dev/dri`. Strix (WP-22): `/dev/dri` present + the render-gid mapping.
- On the tailnet (headscale/tailscale up), so A10 tiles can reach Erebus + fedora-dev.
- The published images exist: `ghcr.io/oso-gato/knowledge-desktop-{xrdp,grd,web}:latest`
  (CI publishes on merge to `main`).

**Roster** — a real `roster.json` (SECRETS.md schema) with **at least**:
- one `admin` (kadm),
- **two** workers (gw1, gw2) — needed for the D2/D3 cross-user privacy spot-check,
- gw1 granted a tile to `erebus`, kadm granted `erebus` + `fedora-dev` (A10),
- a real `tailnet_authkey`.

**Props (human-in-the-loop):**
- a phone with a TOTP app (Aegis / Google Authenticator) for the 2FA enrollment + login,
- a real RDP client (e.g. FreeRDP `xfreerdp`, Windows `mstsc`, Remmina),
- a real VNC client (e.g. TigerVNC `vncviewer`) — **xrdp lineage only** (grd native VNC is disabled),
- a browser for the web door,
- a **second device** (phone/laptop) for the cross-device resume (C2) observation,
- an **off-host vantage** (another tailnet node AND, ideally, a public-internet host) for the A2
  external surface scan.

---

## 1. Run the automated portion — `rehearsal.sh`

For **each** lineage independently:

```sh
# on the host, as the deploy user:
./deploy/rehearsal.sh <roster.json> xrdp     # then, separately:
./deploy/rehearsal.sh <roster.json> grd
```

`rehearsal.sh` performs, and records PASS/FAIL for, the **scriptable** clauses:
- **deploy** the lineage pair (desktop + web sidecar) via `setup.sh`, wait healthy;
- **baked-probe re-proof on the LIVE deploy** (`podman exec` the same probes the gate baked into
  the image — `kd-health`, `kd-isolation-check`, `kd-secrets-scan`, `kd-rdp-check`,
  `kd-web-authcheck`, and `kd-vnc-check` on xrdp): the §6.2 clauses (C2 RDP handshake, D2/D3
  isolation, E1 no-secret-leak, the web auth-chain) now re-proven on the real host, not a fence;
- **on-host listener census** (`ss -ltn` inside the candidate) — the door table is present and no
  rogue listener appeared (the runtime companion to the C6 static publish-set lint);
- **rollback drill** — record the running digest and confirm the recoverability posture
  (`HealthOnFailure=kill` + `AutoUpdate=registry` + `Notify=healthy`) is in force. The destructive
  step — push a bad `:latest`, observe `HealthOnFailure=kill`, then `podman auto-update` / redeploy
  the recorded digest to restore health — is the **operator's** to run (the script records the
  posture + digest; it does not itself push a bad image).

It then **prints the REQUIRED MANUAL checklist** (§§2–4) and exits. It never marks a manual clause
PASS. Copy its final summary block into the sign-off table (§5).

---

## 2. REQUIRED MANUAL — the human-observed §6.4 clauses

Do these **per lineage**, with the deploy from §1 still running.

### 2a. Real pixels on all three paths → ONE shared session (A11) — the core clause
1. As **gw1**, open the **web door** (`https://<host>/` → guacamole → gw1's desktop tile), log in
   (credential + the 2FA from §2b). Launch a visible marker — e.g. open a terminal and run
   `echo A11-MARKER-$(date +%s)`; leave it on screen.
2. From the **RDP client**, connect as gw1 (`<tailnet-host>:3390` for grd — gw1's uid-derived port;
   xrdp: `<tailnet-host>:3389`). **Expected:** you attach to the **same** live session — the marker
   terminal is **already there**, same windows, same screen. **A11 FAIL** if a fresh empty desktop
   appears (a second forked session).
3. **xrdp only:** from the **VNC client**, connect as gw1 (`<tailnet-host>:5901`, password = the
   A13-derived form). **Expected:** same session again, marker still present.
4. **RECORD:** `A11 <lineage>: PASS` only if every path showed the *same* live session.

### 2b. Second-factor enrollment + login (A3/A5) — public door
1. First web login as gw1 draws the **TOTP enrollment** challenge (no token yet). Scan the QR with
   the phone, enter the 6-digit code → session granted.
2. Log out; log in again → the door **demands** the second factor (a valid password alone must
   **not** issue a token). **RECORD:** `2FA <lineage>: PASS`.

### 2c. Brute-force lockout (A4)
1. From the web door, attempt gw1 with a **wrong** password repeatedly (≥ the ban threshold, default
   5). **Expected:** the source is **banned** (subsequent attempts refused even with the *right*
   password, for the ban window). Confirm a legitimate *different* source is unaffected.
2. **RECORD:** `lockout <lineage>: PASS`. (`rehearsal.sh` can drive the repeated attempts if you
   pass `--drive-lockout`; you still observe the ban.)

### 2d. Cross-device resume (C2)
1. With the gw1 session live on device A, connect as gw1 from **device B** (any path). **Expected:**
   you resume the *same* session (per A11); disconnecting device A does not kill it.
2. **RECORD:** `resume <lineage>: PASS`.

### 2e. Geometry follows the most-recently-active display + scales (C4)
1. Connect two clients to gw1's session at **different resolutions** (e.g. web at 1920×1080, RDP at
   2560×1440). Make one **active** (move the mouse / focus). **Expected:** within a few seconds the
   session geometry **tracks the most-recently-active** display and scales to it, observed on every
   path. **Note the L2/xrdp delta** (DESIGN §5 / V3): xrdp degrades to last-client-resize — record
   the observed behaviour honestly against the disclosed residual.
2. **RECORD:** `C4 <lineage>: PASS` (or the disclosed-degrade note for xrdp).

### 2f. Per-user privacy spot-check (D2/D3/A9)
1. Log in as **gw2** (web or RDP). Confirm you land **only** on gw2's own session — gw1's marker is
   **absent**. gw2 cannot read gw1's home (`ls /home/gw1` → Permission denied), and admin has **no**
   supervisory read of a worker's home. (`rehearsal.sh` re-proves this non-interactively via the
   baked `kd-isolation-check`; the manual step confirms it end-to-end through a real login.)
2. **RECORD:** `D2/D3 <lineage>: PASS`.

### 2g. Per-user SSH tiles reach the fleet over the tailnet (A10)
1. In **gw1's** session, open the granted **erebus** tile → it SSHes to the Erebus host over the
   tailnet and lands a shell. In **kadm's** session, both **erebus** and **fedora-dev** tiles work.
   A worker with no grant to a host has **no** such tile.
2. **RECORD:** `A10 <lineage>: PASS` (erebus reached; kadm also reaches fedora-dev).

---

## 3. REQUIRED MANUAL — external surface scan (A2), from OFF the host

The C6 static lint proves the deploy contract *publishes* only the web door; this proves it **live
from outside**. `rehearsal.sh`'s on-host census is necessary but **not sufficient** for A2 — you
must scan from a vantage that is **not** the host:

1. From **another tailnet node**, scan the host: `nmap -Pn -p 22,443,3389,3390,3391,5900,5901,8443
   <tailnet-host>`. **Expected reachable:** the web door only (`443` xrdp / `8443` grd). The private
   doors (RDP 3389-3391, VNC 5900-5901, SSH 22) answer **only** to the users/paths by design — they
   must **not** be open to an arbitrary scanner; confirm the intent per DESIGN §2/A2.
2. From a **public-internet** host (no tailnet), scan the host's public address. **Expected:**
   **exactly one** reachable endpoint — the web door over HTTPS. Everything else: filtered/closed.
3. **RECORD:** `A2 <lineage>: PASS` (exactly one public endpoint; private doors absent from public).

---

## 4. Teardown

`rehearsal.sh` leaves the deploy running so you can do §§2–3. When done, per lineage:

```sh
./deploy/rehearsal.sh <roster.json> <lineage> --teardown   # stops units, removes the secret + volumes
```

---

## 5. Sign-off checklist — a lineage ships only when ALL are PASS on Erebus

| Clause | xrdp | grd | Source |
|---|---|---|---|
| deploy healthy | ☐ | ☐ | rehearsal.sh |
| baked-probe re-proof (C2/D2/D3/E1/web-auth) | ☐ | ☐ | rehearsal.sh |
| on-host listener census (no rogue) | ☐ | ☐ | rehearsal.sh |
| rollback drill | ☐ | ☐ | rehearsal.sh |
| A11 one shared session, all 3 paths (2 on grd) | ☐ | ☐ | §2a manual |
| 2FA enrollment + mandatory login | ☐ | ☐ | §2b manual |
| brute-force lockout | ☐ | ☐ | §2c manual |
| cross-device resume (C2) | ☐ | ☐ | §2d manual |
| geometry follows active display (C4) | ☐ | ☐* | §2e manual |
| per-user privacy (D2/D3/A9) | ☐ | ☐ | §2f manual + probe |
| SSH tiles → Erebus + fedora-dev (A10) | ☐ | ☐ | §2g manual |
| A2 external scan — one public endpoint | ☐ | ☐ | §3 manual |

\* grd/xrdp C4 delta is a disclosed residual (DESIGN §5/V3) — record the observed behaviour, not an
idealized PASS.

---

## 6. WP-22 delta — Strix (GPU host class, B4)

Re-run the **byte-identical** quadlet on a `/dev/dri`-present host and, in addition to a full pass
of §§1–5 with **behaviour identical to the Erebus baseline**, record the **GPU evidence chain**:
- the per-user compositor selects a **GPU renderer** (not llvmpipe) — capture the renderer string;
- `gpu_busy` / render-node activity rises under a painting session;
- the compositor holds **open fds** on the render node.
Record the encode state and the **GIDMap-vs-udev** render-gid mapping decision (per setup.sh's
render-gid note). A Strix PASS requires the GPU evidence AND parity with Erebus.
