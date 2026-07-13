# knowledge-desktop — DESIGN (synthesis v1.0)

Traces to REQUIREMENTS.md v1.01. Synthesized from six subsystem designs and six adversarial challenges; every confirmed defect is fixed here, every cross-subsystem conflict resolved. Decisions that overrode a subsystem design are marked **[ADJ-n]** and recorded in §9.

---

## 0. Shape of the product

Two lineages, one repo, one requirements document. Each lineage is a complete OCI image (`ghcr.io/oso-gato/knowledge-desktop-xrdp`, `…-grd`), run rootless under podman via a systemd quadlet on two host classes (Erebus: no GPU; Strix: AMD Strix Halo iGPU). Inside each container: N OS users (roster-defined), N prestarted desktop sessions, three doors into each user's ONE session (web/HTTPS public; RDP+VNC+SSH tailnet-only), per-user resident-agent environments, per-user nested rootless podman.

**Base OS (both lineages): Fedora current stable**, base image digest-pinned per build, full installed-NVR manifest resolve-logged as a CI artifact (N1). Rationale **re-derived after challenge L1-#4 refuted the original Debian claim** (trixie ships xrdp 0.10.1, which does have GFX): Fedora still wins on (i) xrdp 0.10.6 + the **xorgxrdp-glamor** subpackage (the entire L1 B4 mechanism as one class-(a) artifact); (ii) grd 50.x with the **VNC backend compiled in** — Debian/Ubuntu disable it, which would kill A7 on L2 outright (decisive); (iii) Ptyxis as a class-(a) distro package; (iv) Mesa 26.x with gfx1151 (Strix Halo) support; (v) legal H.264 via the Fedora-managed Cisco OpenH264 repo. One base policy statement for both lineages **[ADJ-20]**.

---

## 1. Subsystem: session core — Lineage 1 (XRDP / X11 / XFCE)

**Components** (class (a) Fedora unless noted): xrdp 0.10.6; **xorgxrdp-glamor** (0.10.5 — pin corrected per challenge); xorg-x11-server-Xorg; Mesa dri/GL/EGL/gbm; tigervnc-server (x0vncserver); XFCE core set (`xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-settings xfconf thunar`) + **`xfce4-notifyd`** (added — E4's human-visible conflict stop needs a notification daemon; challenge VST-#7); dbus-broker; openh264 (class (b), Fedora-managed Cisco repo); in-repo glue: `xorg.conf` (xrdpdev, `DRMDevice /dev/dri/renderD128`, `DRI3 1`, `DRMAllowList "amdgpu i915 xe msm radeon"`, **`ServerFlags` disabling blanking/DPMS** + `xset s off -dpms` in the session wrapper — challenge L1-#7), `sesman.ini` (`Policy=Default`, `KillDisconnected=false`), `xrdp.ini`, `gfx.toml`, `session-prestarter`, `startwm-kd`, `doors-agent`, `geometry-arbiter`, and the four ops oracle CLIs `kd-sessions`/`kd-geometry`/`kd-marker`/`kd-render-report` (X11 impls: sesadmin wrapper, xrandr, solid-color X client, glxinfo parser — challenge L1-#11).

**Mechanism.**
- **Boot:** kd-provision (see §4) → sesman → xrdp binds **`port=tcp://127.0.0.1:3389` unconditionally, plus `tcp://<tailnet-ip>:3389` added when tailscaled reports the iface** (multi-address `port=` is documented; loopback-first fixes the gate-unbootable BLOCKER, challenge L1-#1) **[ADJ-8]** → session-prestarter loops the roster, `xrdp-sesrun -t Xorg -F <fd>` per user, **invoked by kd-provision with the phrase on an fd** so exactly one component parses the roster (challenge L1-#12).
- **Per session:** sesman launches Xorg (user uid, product xorg.conf) → `startwm-kd` **exports `DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus`** (the systemd user bus — NOT a private `dbus-run-session` bus, so user units like vault-sync can reach the notification daemon; challenge VST-#7) → starts `doors-agent` + `geometry-arbiter` → `xfce4-session`. `doors-agent` starts x0vncserver **loopback instance immediately** (`-localhost`, port 590n) and adds the tailnet listener when the iface appears; `-AlwaysShared -AcceptSetDesktopSize -PasswordFile ~/.kd/vncpasswd` (canonical path `~/.kd/vncpasswd` everywhere — provisioner, door, disable flow; challenge L1-#8).
- **B4:** single static xorg.conf; glamor opens the render node when present (Strix), verified graceful swrast fallback when absent (Erebus). Zero config delta. Encoding: xrdp 0.10 has **no** hardware encode — disclosed, CPU on both classes (N4).
- **Geometry (C4):** arbiter subscribes to XInput2 raw events, attributes RDP-door input (xorgxrdp devices) vs VNC-family input (XTEST). **Any attributed input event claims governance immediately; only the RandR re-assertion is debounced** (fixes the single-click miss, challenge L1-#6). Within the VNC family (native VNC vs web — both XTEST), the family governor is the last SetDesktopSize sender; that residual ambiguity is disclosed, and the previously imposed "web activity ticks" contract is **withdrawn as unimplementable in stock Guacamole** (N4-honest re-scope) **[ADJ-14]**.
- **Ptyxis default:** via exo/helpers `TerminalEmulator` (`kd-ptyxis.desktop` + system `helpers.rc`), not xfconf (mechanism corrected, challenge L1-#10).
- Disclosed A11 edges: same-path RDP×2 = takeover (not sharing); sesman per-⟨User,bpp⟩ fork risk probed (guacd connection rows pinned 32bpp/GFX and included in the bpp probe matrix, challenge WD-#14).

## 2. Subsystem: session core — Lineage 2 (GRD / Wayland / GNOME)

**Components** (class (a) Fedora): systemd as PID 1; gnome-shell + mutter 50.x; gnome-session; gnome-remote-desktop 50.x (RDP+VNC backends, headless mode); freerdp3/libvncserver (deps); mesa-dri-drivers + mesa-vulkan-drivers; xwayland; **nautilus** (added — B1 file management had no component row; challenge L2-#9); ptyxis; in-repo `geometry-governor` (python3 + gobject) + a small **input-attribution GNOME Shell component** (see below); the four ops oracle CLIs (Wayland impls via Mutter D-Bus). **Removed:** libva + mesa-va-drivers (deliver nothing while the encode fork is open; reinstated with the fork — challenge L2-#10). GDM and gnome-keyring stay out (per-user headless daemons; file/TPM credential backend).

**Mechanism.**
- Per-user lingering `systemd --user` managers; drop-in `--headless` on the shell unit; `gnome-remote-desktop-headless.service` per user on per-user port pairs (dconf `rdp.headless`/`vnc.headless`, `negotiate-port=false`). Credentials installed by kd-provision via **stdin/file-backend, never argv** (challenge L2-#8; grdctl piped-prompt behaviour is an early empirical item with a direct file-backend write as fallback). The nonexistent VNC `encryption` gschema knob is **deleted from the design**; the security types the headless VNC server actually offers are recorded empirically and disclosed (challenge L2-#7).
- **A2 on L2 (disclosed delta):** grd **cannot bind a specific address** (verified wildcard `add_inet_port`). Mechanism: ports never published + **kd containers run on a dedicated podman network with no sibling containers**, so non-tailnet reach is empty; the gate's bind-audit carries an L2 expected-listener table marking grd ports wildcard-bound-but-unpublished, and tailnet-side handshake is proven on the gate's real (fenced) tailnet iface (§7). Honest mechanism statement replaces the false "by construction" bind claim **[ADJ-32]**.
- **B4:** Mutter headless auto-selects radeonsi vs llvmpipe by render-node presence; zero config delta. Encode: grd's Vulkan/VA-API AVC path is blocked on Fedora by the patent-stripped Mesa → **OPEN FORK 1** (§10); shipped default = CPU codec pipeline on both classes, honestly scoped.
- **C4/A11-concurrent:** geometry-governor mirrors all attached views onto one logical monitor sized to the governing display via `ApplyMonitorsConfig`. Two adverse facts are now first-class: Mutter clone mode's same-mode constraint, and the absence of any stock per-connection input signal. Therefore: (i) a **pre-build spike** (BUILDPLAN WP-04) tests mirrored config at a forced common mode and `Stop()` as the detach/takeover primitive; (ii) input attribution is implemented by a small shell-side component attributing events by virtual input device (each grd connection is a distinct libei client → distinct device), feasibility-spiked before deep investment. If both mirroring paths fail, the A11+C4-concurrent wording escalates to the owner with the hot-switch fallback (conditional fork, §10).
- **Same-door multi-device:** grd VNC refuses a second client; RDP×2 semantics probed early (source evidence: sessions GList, no single-session refusal). Shipped semantics both lineages: **cross-path concurrency guaranteed; same-door second device = takeover** (L2 implements takeover via the Stop() primitive; stale-TCP variant tested so a slept device never locks out resume — challenge L2-#6) **[ADJ-25]**.
- Provisioning is **two-pass**: derive ALL users' credentials first, THEN enable any linger (closes the boot-window argv/env race, challenge US-#10).

## 3. Subsystem: public web door + fleet tiles (Guacamole gateway)

**Components:**
| Component | Pin | Class | Notes |
|---|---|---|---|
| guacamole-server (guacd) 1.6.0 | exact, GPG-verified Apache dist | (c) | Built with **RDP + VNC + SSH** protocol plugins **[ADJ-1]** (VNC added — L1 desktop transport; telnet/K8s still excluded, N2) |
| **FreeRDP 3.x, exact-pinned, vendored** | newest release compatible with guacd 1.6.0 (< the 3.15 API break, GUACAMOLE-2146), GPG/sha-verified | (c) | Compile-verified **pair** with guacd, private prefix `/opt/guacamole` (no clash with distro freerdp3 used by grd on L2); CI asserts the pair builds; FreeRDP-2 fallback **deleted** (EOL) **[ADJ-3]** |
| guacamole.war + jdbc-postgresql + totp + ban extensions 1.6.0 | exact, GPG-verified | (c) | |
| **Apache Tomcat 9, upstream tarball** | exact pin, GPG-verified | **(c)** | Fedora and Debian ship Tomcat 10 only (javax WAR incompatible) — the class-(a) claim was refuted; 9.0.x maintenance wind-down disclosed, pin bumped on the F3 cadence **[ADJ-2]** |
| PostgreSQL | distro, resolve-logged | (a) | Binds **127.0.0.1 TCP** — pgJDBC is TCP-only; the unix-socket claim was refuted **[ADJ-4]** |
| Caddy | distro, resolve-logged | (a) | :443, ACME TLS-ALPN-01, no port 80 ever |
| kd-web-sync (in-repo) | — | repo | The door's provisioning CLI, **invoked by kd-provision** (never parses the roster itself) **[ADJ-11]** |

**Desktop-tile transport per lineage — the central reconciled fork [ADJ-1]:**
- **L1:** guacd **VNC** client → the user's x0vncserver loopback endpoint (`-AlwaysShared` gives true web+native-VNC+native-RDP concurrency; avoids xrdp's RDP×2 takeover). Consequence: roster-sync stores the **derived 8-char VNC form** in connection rows (a derivation of the one A13 credential, not a second credential; at-rest exposure disclosed in E6) — the "web door never stores a desktop password" trace is updated accordingly.
- **L2:** guacd **RDP** client → the user's grd daemon on the per-user RDP port, with `${GUAC_USERNAME}`/`${GUAC_PASSWORD}` token passthrough (full phrase; A12 re-resolution at the door). L2's "MUST use ScreenCast/libei" imposition is **withdrawn** — Guacamole cannot speak it and grd source evidence indicates concurrent RDP sessions are supported; this is **contingent on the WP-04 spike (grd accepts a concurrent second RDP connection)**. Spike RED ⇒ conditional owner fork (§10).
- Per-lineage connection-parameter sets (transport, port-per-user, `security`, `ignore-cert` on the loopback hop) are internal mechanism, §5-permitted.

**Auth chain:** login = phrase → JDBC verify (**salted SHA-256 — Guacamole's native scheme; the "argon2id-class" contract is relaxed and the gap disclosed in E6**, bounded by A3 TOTP + A4 ban + container/volume perms **[ADJ-5]**) → TOTP (self-enroll first login, QR; per-user attribute AND **group-based disable both asserted absent** every boot — 1.6.0 added group TOTP-disable, challenge WD-#11) → token → tiles. Ban extension 5/300s; Caddy XFF → Tomcat RemoteIpValve with **`internalProxies="127\.0\.0\.1"` pinned exactly** (default 127/8 regex would swallow the per-source test addresses; challenge WD-#12).

**Health (F2) [ADJ-6]:** the failed-login probe is **rejected — it self-bans** (10 failures/300s from 127.0.0.1 at a 30s interval). Deep liveness = an **unauthenticated GET of a webapp API endpoint** asserting a well-formed response through Caddy→Tomcat→webapp→DB, generating zero auth failures. Merged container health = §6.

**Certificates:** production single-lineage: ACME TLS-ALPN-01 on 443 (public DNS name from the roster). **Co-deploy (F4):** the secondary lineage on 8443 serves `tls internal` (container-local CA) during evaluation — TLS-ALPN-01 cannot validate off 443 and no port 80 exists; disclosed; the owner may supply a DNS-01 credential as deploy data to upgrade it **[ADJ-24]**. Gate runs always use `tls internal`.

**Fleet tiles (A10):** guacd native SSH connections over the container's tailnet membership; one connection row per (user, granted endpoint), authenticated by the user's **tile SSH key** (roster-supplied, §4); grants exact-match fail-closed, regenerated each boot; revocation at next boot (D5). **Cross-repo contract with a named owner:** the fleet host repos (Erebus setup / fedora-bootstrap; fedora-dev) install each granted user's tile *public* key — a control-plane BUILDPLAN item, not an assumption (challenge WD-#9).

## 4. Subsystem: users, secrets, agents (kd-provision)

**Single secrets source:** one JSON roster, `podman secret create kd-roster` host-side, quadlet `Secret=kd-roster,mode=0400,uid=0` → `/run/secrets/kd-roster`. **This is the one sanctioned mechanism — the ops `Volume=` env-file contract is superseded** **[ADJ-10]**. Rotation runbook: `podman secret rm && create` (or `--replace`) + `systemctl --user restart <quadlet>` (recreates the container).

**Roster schema v1 (closed set; unknown keys ⇒ D6 rejection), extended per challenges US-#1/WD-#4/VST-#1 [ADJ-11]:**
```json
{ "version": 1,
  "box": {
    "tailnet_authkey": "REQUIRED",
    "public_dns_name": "optional — absent ⇒ web door serves tls-internal",
    "vault_repo": "optional — absent ⇒ vault sync disabled, logged (E2 degrade)",
    "endpoints": { "erebus": {"host":"<tailnet name/ip>","port":22,"user":"..."},
                   "fedora-dev": {"...":"..."} },
    "shared_folder": false },
  "admin": { "username":"...", "password":"xxx-xxxx-xxxx",
             "ssh_authorized_keys":[...], "tile_ssh_key":"optional per-user private key",
             "vcs": {"provider","login","token","git_name","git_email"},
             "tiles": ["erebus","fedora-dev"] },
  "workers": [ ...same shape... ] }
```
Validation severity split unchanged (invalid worker ⇒ excluded + value-free log, boot continues; missing/invalid roster/admin/tailnet key ⇒ fail-fast). **`FailureAction=exit-force`** on kd-provision.service so a required-secret failure exits the container nonzero within seconds — matching the gate's fail-fast observable under PID-1 systemd (challenge US-#7) **[ADJ-13]**.

**kd-provision is the ONLY roster parser.** It drives everything as a consumer-facing interface set: `kd-web-sync` (apply-set/disable-set/grants/endpoints → guac DB; disable preserves TOTP rows — the D5 keystone, verified supported by the JDBC `disabled` flag), per-lineage door credential installers (chpasswd yescrypt; `vncpasswd -f` → `~/.kd/vncpasswd`; grd stdin/file-backend — with a `revoke` verb so L2 disable clears the grd store, challenge US-#11), session-prestarter (phrase via fd), **vault clone creation + vault-sync unit enablement** (previously implemented by nobody — challenge VST-#1), nested-engine subuid bands + storage.conf, seed-image `podman load`, agent env (`vcs.env` 0600 + `gh auth setup-git`), grants files (**0640, root:kd-door** — challenge US-#13). Two-pass apply (all credentials before any linger). Apply-phase failure policy: worker failure ⇒ full rollback of that user + skip + log; admin failure ⇒ abort (E2) — specified and fixtured (challenge US-#14).

**D3 by mechanism:** no sudo; root locked; setuid = {newuidmap, newgidmap} only (owned by `shadow-utils` — attribution corrected, challenge VST-#9); wheel empty; polkit admin default-deny; volumes `nosuid,nodev`; no host socket; outer container rootless. **A8 in-account half owned here [ADJ-15]:** sshd ForceCommand-style attach lands every terminal login in that user's **one persistent tmux session** (the same session hosting the resident Claude Code window); openssh-server + **mosh + tmux** ship as class-(a) rows (previously unshipped — challenge VST-#3); `PasswordAuthentication no`; sshd binds loopback+tailnet, mosh UDP range tailnet-bound.

**E1 discipline, re-scoped honestly (challenge US-#6):** no secret in argv ever, none in journals, none in any *other* uid's process env or any system service env; **a user's own credential inside their own uid's processes (GH_TOKEN in their agent env) is accepted and disclosed** — it is the documented gh headless mechanism. The gate scan covers the re-scoped property plus a **during-boot `/proc/*/cmdline` sampler** for the provisioning window.

## 5. Subsystem: vault, sandbox, toolset

**Toolset (B2):** Obsidian (class (c): official release tar.gz, version+sha256 exact-pinned in-repo, fail-closed at build; **a scheduled CI job proposes version+digest bump PRs** so the pin has an F3 currency mechanism — challenge VST-#13); VS Code (b, Microsoft repo, gpgcheck); Firefox (a); 1Password GUI+CLI (b, vendor repo, repo_gpgcheck); Ptyxis (a); Claude Code (b, Anthropic dnf repo, `latest` channel) with **`DISABLE_UPDATES=1`** in managed settings (not merely the autoupdater flag — `claude update` would plant a home-volume shadow binary defeating provenance; gate probe asserts no `~/.local/bin/claude` shadow — challenge VST-#4 **[ADJ-16]**); git-core; podman/crun/passt/fuse-overlayfs (a); tmux + mosh + openssh-server (a); acl; libnotify + per-lineage notification daemon.

**Agent currency — ONE mechanism [ADJ-16]:** system `claude-code-update.timer` (daily dnf upgrade of that package, boot catch-up, failure non-fatal) — ops's per-user `kd-agent-update.timer` is **deleted**; adoption via a per-user daily `kd-agent-refresh` user timer that respawns the agent *window* inside the persistent tmux server (server survives — A8 persistence kept); adoption test: running agent's `claude --version` == rpm NVR after the cycle.

**Vault (E4):** central git repo (`box.vault_repo`), per-user `~/Vault` clones, 5-min sync timers: stop-flag → guarded commit (bulk-delete bound `max(25,10%)`) → guarded fetch/merge (same bound inbound; **conflict ⇒ `merge --abort`, byte-identical restore, stop-flag, bus-observed desktop notification**) → plain push. Server-side no-rewrite: production GitHub ruleset (block force-push + restrict deletions, no bypass); gate mirrors it with `receive.denyNonFastForwards`+`denyDeletes` on a local bare remote. **Ruleset assertion is fail-SAFE, not fail-fast** (challenge VST-#8): unreachable VCS at boot ⇒ set all stop-flags + loud alert, box serves normally; only an affirmative "ruleset absent" finding blocks sync — never the box. `.gitignore` broadened to all per-device volatile `.obsidian` state; two-user config-churn soak test added (challenge VST-#15). E6 additions: the delete bound is client-path-only (server layer covers history rewrite only); in-app cloud sync (Obsidian Sync/Firefox Sync) runs as the vault owner and is an owner-account-class residual; the "mechanically unable" cloud-sync template is today satisfied vacuously (no general sync service ships) — stated plainly, plus a gate lint that no system unit reaches /home outside the template.

**Sandbox (E5):** `ingest` two-stage pipeline under the user's nested podman. Fetch stage (egress, moves opaque bytes, never parses); process stage: `--network=none --cap-drop=ALL --read-only --rm`, mounts only `/in` (ro) + `/out`, vault/home/secrets ENOENT, env cleared, `timeout(1)` wrapped. **Images are baked into the product image as CI-built, digest-pinned OCI archives and `podman load`ed per user at provision** (no first-use registry pull; gate-compatible — challenge VST-#5 **[ADJ-17]**). Resource flags (`--memory`, `--pids-limit`) get an enforcement test (OOM-kill + fork-bomb fixtures); if cgroup delegation renders them inert in the nested engine, the design re-scopes honestly to `timeout(1)` as the enforced bound (challenge VST-#10). Gate fixture is served on the pasta-reachable gateway address (loopback is not routed into the nested netns — challenge VST-#11).

**Nested podman (B3) — one reconciled host contract [ADJ-12]:** subuid/subgid grant **≥ 2,097,152** per host account (bands `200000 + i*65536`); ONE degraded mode (shrunk bands + `ignore_chown_errors`, documented and gate-sized); `AddDevice=/dev/fuse` in both quadlets; per-user graphroot on the /home volume; **fuse-overlayfs pinned** as mount program (determinism across host classes and gate — resolves the native-overlay-first disagreement in favour of determinism); SELinux: `label=disable` scoped to the product container, disclosed E6-class (fleet precedent); all of it **asserted fail-fast by setup.sh** and present in the shipped quadlets (previously in no deploy artifact — challenges US-#8, VST-#2, OPS-#6).

## 6. Subsystem: ops, deploy contract, CI, health

**Quadlets (`deploy/kd-{xrdp,grd}.container`) — the only sanctioned run contract, byte-identical across host classes:**
`Image=…:latest` · `AutoUpdate=registry` · `Notify=healthy` · `HealthCmd=kd-health` + intervals + `HealthStartPeriod` (calibrated ≥2× measured worst first boot) · `HealthOnFailure=kill` + `Restart=on-failure` · **`AddDevice=-/dev/dri`** (optional-prefix: absent on Erebus, silent) · **`GIDMap=` mapping the host render gid onto the container `render` group** (all roster users are members; `GroupAdd=keep-groups` is **dropped as the GPU mechanism** — setgroups in sesman/user-managers discards leaked unmapped groups, so keep-groups can never reach per-user sessions; fallback if GIDMap × the 2M-subgid arithmetic fails empirically: documented Strix host udev rule, render nodes 0666 — challenges OPS-#2, L1-#5, L2-#3 **[ADJ-9]**) · `AddDevice=/dev/fuse` · `Secret=kd-roster,mode=0400,uid=0` · `PublishPort=443:443` (grd: 8443) · Volumes `kd-<lineage>-{home,state,shared}` **all `nosuid,nodev`** (shared volume added — E3 completeness, challenge OPS-#12) · dedicated podman network (no siblings — L2 A2 mechanism) · `[Install] WantedBy=default.target`.

`setup.sh` (non-interactive, one arg = roster path): asserts podman floor, crun, linger, `ip_unprivileged_port_start≤443`, **subuid/subgid ≥2M, userns enabled, /dev/fuse, SELinux accommodation, render-group/GIDMap prereq iff /dev/dri exists**; `podman secret create`; install quadlet; start; wait healthy. `spin-up.sh` = wizard front-end composing the same roster then exec'ing setup.sh (F1's attended path).

**kd-health (merged definition [ADJ-6]):** two tiers — (i) unconditional: loopback door listeners up, web deep-liveness GET well-formed (no auth failures generated, never accumulates ban state), provision-complete flag, `systemctl --failed` empty; (ii) tailnet tier: tailnet-bound listeners required **iff** the tailnet iface exists. A dead desktop is unhealthy at the next interval; slow first boot is "starting"; in-container `Restart=always` + `HealthOnFailure=kill` are the two self-heal layers.

**CI:** one workflow, lineage matrix; PR = build both + probe image + static lints (quadlet parse, F4 pairwise disjointness, **drift lint: `.live-gate` run options == shipped quadlets including the Secret line**, .live-gate parses); main = build+push `:latest`/`:gSHA`/`:YYYYMMDD` + manifest artifacts; weekly cron rebuild (F3); Obsidian bump-PR job. Probe image: **current supported Fedora, digest-pinned, bumped on the F3 cadence** (fedora:42 was EOL — challenge OPS-#13); packages freerdp, tigervnc, Xvfb, xdotool, ImageMagick, oathtool, curl, python3, iproute, nmap-ncat, openssh-server (tile stand-in), git.

**F3 chain:** weekly rebuild → digest delta → host `podman-auto-update.timer` pulls/restarts → `Notify=healthy` couples restart-success to health → automatic rollback on failure (drilled at rehearsal). Daily: claude-code system timer + per-user agent refresh.

**F4:** names/volumes/ports/tailnet-hostnames disjoint by scheme, PR-linted; each lineage its own tailnet node (standard ports 3389/5900/22 on distinct tailnet IPs); web 443/8443.

## 7. Validation architecture — gate + rehearsal

**The fence gets a real tailnet [ADJ-33, challenge OPS-#1].** The gate harness runs a **headscale control plane on loopback inside the fence**; the candidate's tailscaled joins it with a fixture authkey, acquiring a genuine 100.64/10 tailnet interface. This makes §6-item-2's literal clause — "RDP and VNC each answer a real protocol handshake **on the tailnet interface**" — gate-provable pre-merge, dissolves the tailnet-door/health deadlock under the fence, and removes the silent re-scope. (Doors still bind loopback unconditionally so the box also serves with no tailnet at all — E2 degrade, separately probed.) The probe container shares the candidate's netns for loopback probes.

**Probe catalog (consolidated + corrected):**
| Probe | FRs | Pass criterion (corrected items flagged) |
|---|---|---|
| surface-enum | A2 | Publish set == one web port; full TCP scan from outside the netns → only web; in-netns `ss` audit vs the per-lineage expected-listener table (L2 grd rows: wildcard-but-unpublished); no :80 |
| web-auth-totp | A3,A5,A12 | Valid phrase → TOTP challenge → oathtool → token; **two-path**: enrollment-payload secret preferred, pre-seeded-enrollment fixture accepted (challenge OPS-#14); wrong/unknown rejected identically; plain HTTP never serves |
| lockout-a4 | A4 | **Two-source**: 5 failures from 127.0.0.2 ⇒ .2 refused even with valid creds while 127.0.0.3 logs in concurrently — proves per-source ban through the pinned XFF chain (challenge OPS-#10); runs last |
| rdp-door | A6,A12 | **Per-lineage** (challenge OPS-#4): L1 = full connect + marker capture + `kd-sessions --serving` uid oracle (xrdp has no NLA; `/auth-only` inapplicable); L2 = `/auth-only` with the exit-code self-check |
| vnc-door | A7,A12,A13 | First-8 succeeds; **full 13-char phrase ALSO succeeds — that IS the truncation proof** (RFB clients truncate; the old "full string refused" expectation was protocol-impossible — challenges L1-#3, US-#5, OPS-#3 **[ADJ-7]**); wrong-first-8 and garbage refused |
| ssh-door | A8,A12 | **New** (challenge OPS-#9): key auth as gw1 → lands in gw1's own tmux session (twice ⇒ same session); password auth refused; wrong key refused; mosh handshake if fence permits UDP |
| marker-a11 | A11 | Web+RDP+VNC concurrent, per-lineage web transport (L1 VNC, L2 RDP); all captures show the user's marker; session census == 1 throughout |
| identity-a12 | A12,D2 | Cross-user negative on every door; serving-uid oracle |
| geometry-c4 | C4 | Resize matrix across all three paths ≤5s; **single-click governance transfer**; **governing-display detach → next-most-recent governs**; **marker app never restarts** (apps-undisturbed) — three added cases (challenges L1-#6, L2-#11) |
| roster-d1d6 | D1,D6 | 3 valid + 1 invalid ⇒ exact census, value-free rejection, healthy; admin-only run; **bad-admin run ⇒ container exit nonzero ≤60s** (challenge OPS-#16); duplicate + system-collision fixtures |
| isolation-d2d3 | D2,D3 | EACCES cross-home (admin included); setuid inventory; mount flags nosuid,nodev; tmux socket refusal; nested-store invisibility |
| grants + tile-pipeline | A10,D5 | Set-equality per user; fail-closed; boot revocation; **tile pipeline exercised against an in-netns sshd stand-in** (challenge OPS-#9) |
| nested-build-b3 | B3 | **New**: as gw1, `podman run` seed + 2-line build in-box (challenge OPS-#6) |
| secrets-e1-scan | E1 | **New**: journal + other-uid `/proc` env + image layers grep for roster values (re-scoped per §4) + during-boot argv sampler |
| health-f2 | F2 | starting→healthy with no false unhealthy; healthy never premature; kill drills per core service; wedge drill → container-level restart; **health never accumulates ban state / a banned source never flips health** |
| vault/ingest suite | E4,E5 | Conflict-stop (bus-observed notification asserted, not a log line), bulk-delete both directions, force-push/delete rejected at the bare remote, sandbox containment (lo-only, ENOENT vault, empty env, no residue), end-to-end ingest, cloud-sync template ENOENT+EACCES |
| toolset | B2 | All binaries launch in-session; Electron apps start WITHOUT --no-sandbox (else surfaced, never silent); Ptyxis is the default terminal via the corrected mechanism; no claude shadow binary; idle-blank probe (screen never blanks) |

**Tier split:** L1 iterates Tier-1 in-box (nested engine builds and runs it); **L2 runtime proof is Tier-2 host-gate only** (systemd-PID-1 cannot boot in the nested engine — accepted up front; in-box = build + static assertions). Rehearsal (per §6-item-4): Erebus baseline scripted+human checklist (external scan, reboot-unaided, rollback drill, real clients, TOTP on a phone, tiles → Erebus + fedora-dev, co-deploy F4); **Strix adds the B4 evidence chain**: byte-identical quadlet diff; render node in-container; **per-user-session** renderer string = radeonsi (silent llvmpipe with node present = RED); `gpu_busy_percent` above idle under load; session-server fd on the render node; encode state recorded as found; full probe-set results diff vs Erebus empty modulo performance.

## 8. Credential & identity flow (end-to-end)

One roster (host podman secret) → kd-provision (sole parser) → per user: Unix account (yescrypt shadow ← full phrase, via stdin) · web identity (kd-web-sync ← full phrase → salted SHA-256 + TOTP self-enrolled at first login, preserved across disable) · RDP door (L1 PAM = shadow; L2 grd store via stdin/file backend) · VNC `~/.kd/vncpasswd` (= first 8 chars, DES-obfuscated — protocol-required form) · SSH `authorized_keys` (entry) + tile private key (guac DB, for A10 egress) · VCS identity (`vcs.env` 0600 + gh setup-git; token accepted in the user's own process env, disclosed) · tailnet: box-level authkey → tailscaled (async join, never boot-blocking). Full phrase at the web door forwards via token passthrough to the L2 RDP hop; the L1 web hop uses the stored derived VNC form. Truncation corollary (full phrase opens VNC) disclosed. Rotation = roster edit + secret replace + restart; effects at next boot (D5 verbatim).

## 9. FR TRACE MATRIX

| FR | Satisfied by (observable) |
|---|---|
| A1 | Guacamole HTML5 client over Caddy :443; zero client software; iPad at rehearsal. Probe: web-auth-totp + marker-a11 web leg |
| A2 | Publish-set = {443} only; L1 doors bind loopback+tailnet explicitly; L2 wildcard-unpublished + dedicated network (disclosed mechanism); gate surface-enum + fenced-tailnet handshake + rehearsal external scan |
| A3 | TOTP ext (JDBC-backed), self-enroll, no exemptions: no-admin provisioning + per-user attr AND group-disable asserted absent + every-user-draws-challenge probe |
| A4 | ban ext 5/300s + pinned RemoteIpValve; two-source gate probe |
| A5 | Caddy TLS 1.2+/ACME; in-container loopback hops disclosed as same-trust-domain |
| A6 | L1 xrdp 0.10.6 (loopback+tailnet), L2 per-user grd RDP; rdp-door probe per lineage; stock-client interop at rehearsal |
| A7 | L1 per-user x0vncserver in-session; L2 grd VNC headless (Fedora build compiles it in); first-class, structurally single-user; vnc-door probe |
| A8 | openssh key-only + mosh, tailnet-bound; ForceCommand → user's one persistent tmux session; ssh-door probe |
| A9 | No greeter anywhere; door credential lands in the running session; token passthrough on web |
| A10 | guacd SSH tiles ← grants files ← roster tiles + endpoint map + tile keys; fail-closed; tile-pipeline probe + rehearsal to Erebus & fedora-dev; cross-repo pubkey contract owned (BUILDPLAN WP-15b) |
| A11 | Sessions created only at boot; every door attaches: L1 xorgxrdp/x0vncserver/guacd-VNC; L2 grd RDP(+web)+VNC; marker-a11 probe; same-door 2nd device = takeover (disclosed; L2 Stop() spike) |
| A12 | Per-door identity: PAM / per-user grd daemon / per-user VNC port+secret / SSH key / web JDBC; identity-a12 probe; fail-closed everywhere |
| A13 | One phrase, per-door derivation table (§8); VNC = first 8 (protocol truncation, full-phrase corollary disclosed); vnc-door probe corrected |
| B1 | Full DE server-side: L1 XFCE/Xorg headless; L2 GNOME/Mutter headless (nautilus added); no seat/DM/GPU; boots with zero /dev/dri on every gate run |
| B2 | Toolset table §5, provenance classed; Ptyxis default via corrected per-lineage mechanism; Claude Code daily (timer + refresh + adoption test) |
| B3 | Per-user nested rootless podman; reconciled host contract §5; nested-build-b3 probe both classes |
| B4 | One image, zero config delta: L1 glamor/DRMDevice; L2 Mesa/Mutter auto-select; quadlet `AddDevice=-/dev/dri` + GIDMap; every gate run IS the Erebus class; Strix rehearsal evidence chain (per-user-session renderer); encode honestly scoped (L1: unsupported; L2: FORK 1) |
| C1 | `KillDisconnected=false` / linger-bound units; soak probe |
| C2 | Reconnect → same session, resized to new client; cross-door resume probes |
| C3 | Linger + WantedBy=default.target; gate does zero exec-side setup pre-probe; rehearsal reboot |
| C4 | Native resize (RDP display-control / SetDesktopSize / [MS-RDPEDISP]) + L1 arbiter (immediate input claim) / L2 governor (+input-attribution component, spiked); geometry-c4 incl. single-click, detach, apps-undisturbed; residuals disclosed |
| D1 | Roster-driven loop, no branch; admin-only fixture run |
| D2 | uid isolation + 0700 homes + per-uid daemons/sockets; no supervisory mechanism exists; no in-box root; isolation probe |
| D3 | Absence+mechanism checklist (§4); audit probe |
| D4 | /srv/shared 2770 + default ACLs; explicit-mode edge disclosed + probed; persists (volume added) |
| D5 | Disable-not-delete: web disable preserves TOTP; OS lock; VNC file removed; grd store revoked; grants removed; next-boot semantics; probe + rehearsal TOTP-reinstate |
| D6 | Closed-schema validate-then-apply; per-entry rejection; specified apply-failure policy; fixtures incl. duplicate/collision/bad-admin |
| E1 | Podman secret; stdin discipline; re-scoped own-uid exception disclosed; secrets-e1-scan + boot sampler |
| E2 | exit-force fail-fast on required-missing; optional-missing degrade (SSH keys, shared folder, vault_repo, dns name); tailnet/VCS unreachable ≠ missing (async retry / vault fail-safe) |
| E3 | Volumes home/state/shared; append-only uidmap (no reuse); recreate-preserves probe |
| E4 | git sync + server-side denyNonFastForwards/deletes (gate) / ruleset (prod, fail-safe assert); bounds both directions; conflict-stop with bus-observed notification; scoping disclosures |
| E5 | Two-stage ingest; `--network=none`, credential-free, vault-ENOENT, one-shot; baked images; containment probe set; resource-bound enforcement test |
| E6 | Disclosure register (shipped doc): shared kernel; vault readable by owner; tailnet-membership-as-2FA on private doors; VNC truncation + full-phrase corollary; web verifier salted SHA-256; L1 VNC secret at rest in guac DB; tile keys at rest; grd wildcard bind mechanism; SELinux label=disable; same-door takeover; RFB-cleartext-in-WireGuard; ignore-cert loopback hop; delete-bound client-scope; in-app sync residual; co-deploy secondary internal CA; roster = host crown jewels |
| F1 | setup.sh single-arg non-interactive (asserted prereqs, fail-fast); spin-up wizard front-end; one contract |
| F2 | Merged kd-health two-tier (§6); Notify=healthy; HealthOnFailure=kill; health-f2 drills incl. never-banned |
| F3 | Weekly CI rebuild; auto-update + rollback (drilled); claude timer + agent refresh; Obsidian bump-PR |
| F4 | Disjoint names/volumes/ports/tailnet nodes; PR lint; co-deploy rehearsal; secondary-cert posture decided |
| G1 | Lingering user manager + resident-agent.service (tmux + Claude window) per roster user; census probe |
| G2 | Roster vcs block → gh headless auth per user; attributable PRs; rehearsal scratch-PR test |
| G3 | Same provisioning loop as D1 |
| G4 | secret create + quadlet start = the whole host procedure; everything else boot-time |
| G5 | Extended roster (§4) carries ALL per-user + box material; enters only at deploy |
| H1/H2 | In-desktop dev = toolsets in-box only (B3 substrate); no platform repo write path, no host reach (D3 mechanisms); platform maintained via fedora-dev |
| H3 | Per-user pre-authorized fine-grained tokens; PR-only by the VCS host's require-PR rulesets on toolset repos |
| H4 | require-PR ruleset on this repo's main; poller + fitness (two independent machine gates, fleet apparatus); .live-gate empirical pre-merge (fenced headscale makes §6.2 literal); structured RED self-diagnosis + journal excerpts |

## 10. EMPIRICAL-VALIDATION REGISTER

Tier key: **G** = loopback-fenced gate (automated, pre-merge) · **B** = in-box Tier-1 · **R** = dress rehearsal.

| # | Load-bearing claim | Test | Tier |
|---|---|---|---|
| V1 | grd accepts a concurrent second RDP connection (decides L2 web transport) | two xfreerdp attaches to one user daemon | **G-spike, FIRST** |
| V2 | Mutter mirrored ApplyMonitorsConfig at a forced common mode across grd virtual monitors; Stop() detaches a connection | governor spike script | **G-spike, FIRST** |
| V3 | xorgxrdp RandR accepts external arbitrary modes (VNC-governed resize) | SetDesktopSize → xrandr readback | **G-spike, FIRST** |
| V4 | guacd 1.6.0 + pinned FreeRDP 3.x pair compiles; guacd(GFX)→GRD paints; guacd(VNC)→x0vncserver paints | CI pair-build + WS-tunnel frame probes | G (CI + gate) |
| V5 | L2 input attribution by virtual input device is observable shell-side | attribution spike | G-spike |
| V6 | Doors serve on loopback with NO tailnet; tailnet listeners appear when iface does | fence boot minus headscale; then with | G |
| V7 | Fenced headscale gives the candidate a real tailnet iface; RDP/VNC handshake on it | gate harness | G |
| V8 | VNC truncation semantics (first-8 ✓, full-phrase ✓, wrong-8 ✗) | vnc-door | G |
| V9 | TOTP enrollment API-automatable (else pre-seeded fixture path) | web-auth-totp | G |
| V10 | Per-source ban through pinned XFF chain; health never banned | lockout-a4 + health-f2 | G |
| V11 | A11 tri-path concurrency, per-lineage transports; census==1 | marker-a11 | G |
| V12 | C4 full matrix: 3 paths, ≤5s, single-click, detach, apps-undisturbed, reconnect-resize | geometry-c4 | G |
| V13 | Same-door 2nd device = clean takeover (L1 RDP; L2 RDP/VNC + stale-TCP variant) | takeover probes | G |
| V14 | sesman bpp fork edge (incl. guacd rows pinned 32bpp) | bpp probe | G |
| V15 | GIDMap render-gid mapping gives WORKER-uid session processes an openable render node; glxinfo per user = radeonsi; gpu_busy under load; fallback udev path if GIDMap fails | Strix evidence chain | **R** |
| V16 | Software-fallback boot (no /dev/dri) fully green | every gate run | G |
| V17 | grdctl accepts piped-stdin credentials (else file-backend write) | provision unit test | B/G |
| V18 | Actual VNC security types grd headless offers (records the E6 line) | protocol enum | G |
| V19 | Provision fail-fast: bad roster ⇒ container exit ≤60s; invalid worker ⇒ excluded, boot green | negative runs | G |
| V20 | E1 scan (re-scoped) + during-boot argv sampler zero-hit | secrets-e1-scan | G |
| V21 | D2/D3/D4/D5 mechanism probes (incl. explicit-0600 shared-folder edge; TOTP survives disable) | isolation/roster suite | G (+R for TOTP reinstate) |
| V22 | Nested build/run per user, both classes; subuid arithmetic at N=5 concurrent | nested-build-b3 | G + R |
| V23 | Electron apps start sandboxed (no --no-sandbox) under the container | toolset probe | G |
| V24 | B2 apps render under L2 headless Mutter/Xwayland/llvmpipe; Ptyxis default fires per lineage | toolset probe | G |
| V25 | Vault: conflict-stop restores byte-identical + bus-observed notification; bounds both directions; force-push/delete rejected; config-churn soak | vault suite | G |
| V26 | Production ruleset assert fail-safe semantics; full sync round-trip with real PATs | deploy assert + scratch round-trip | R |
| V27 | Ingest containment (lo-only, ENOENT, empty env, no residue) + end-to-end via pasta-reachable fixture; resource bounds enforced or re-scoped | ingest suite | G |
| V28 | Health: no false unhealthy on cold boot (StartPeriod ≥2× measured); kill/wedge drills; Notify=healthy gating | health-f2 | G |
| V29 | auto-update rollback on bad image | drill tag | R |
| V30 | Claude Code: timer updates; DISABLE_UPDATES blocks self-update; no shadow binary; agent adopts within a day | toolset + adoption probes | G + R |
| V31 | H.264 negotiation L1 (OpenH264 present ⇒ offered; absent ⇒ RFX + log) | codec probe | G |
| V32 | Idle soak: no blanking/DPMS black screens; C1 persistence | idle probe | G |
| V33 | A2 literal: external public scan == {web port}; tiles reach Erebus + fedora-dev; ACME issuance on 443 | rehearsal | R |
| V34 | F4 co-deploy both lineages green; quadlet byte-identity across hosts | rehearsal | R |
| V35 | E3: recreate preserves homes/uids/nested stores/TOTP/grants | upgrade probe | G |
| V36 | N idle sessions RSS on VPS sizing (capacity disclosure) | soak measurement | R |
| V37 | iOS/iPadOS full desktop + keyboard | manual | R |

## 11. OPEN FORKS (owner)

1. **L2 hardware H.264 encode on Strix** — grd's VA-API/Vulkan path needs RPM Fusion `mesa-va-drivers-freeworld` (Fedora strips the codec): a provenance decision only the owner can make (N1 vs the encode half of B4's "where the stack supports it"). **Shipped default: no HW encode, honestly scoped**; rendering acceleration (the demonstrable B4 core) is unaffected.
2. **Conditional only** (escalate if and only if the spike fails, with evidence): (a) V1 RED ⇒ L2 web-desktop transport has no stock path — reopens the gateway choice for L2; (b) V2 RED on both mirror and Stop() ⇒ A11+C4-*concurrent* on L2 degrades to hot-switch ≤5s — wording adjudication with fallback attached.

Everything else formerly floated to the owner (A13 charset — decided: `[a-z0-9]`, shape is the hard rule; A11 same-door reading — decided: takeover, disclosed; co-deploy cert posture — decided: secondary uses internal CA, DNS-01 available as data) is **decided here** and recorded in §9's [ADJ] notes and E6.
