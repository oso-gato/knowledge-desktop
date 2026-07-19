# knowledge-desktop — FUNCTIONAL REQUIREMENTS (spec of record)

> **The spec of record — the current, owner-approved functional requirements.** Companion to
> [`00-OBJECTIVES.md`](./00-OBJECTIVES.md) (the objective this requirement set delivers). This
> document is the **measuring stick**: every design, build, validation, and ship decision in this
> repo is graded against it. It states **WHAT must be observably true as it now stands** — not the
> history of how it got here (that is [`DESIGN.md`](./DESIGN.md)); it changes only with the owner's
> explicit confirmation, never as part of a feature PR. (§1 Objective lives in `00-OBJECTIVES.md`;
> §2–§6 are here.)

It states WHAT must be observably true, not HOW. It prescribes no build mechanism and fixes no
port numbers, config keys, or file paths. A proper name appears here only where the name itself is
the requirement: an owner-elected product or tool (Obsidian, VS Code, Firefox, 1Password, Claude
Code, Ptyxis, Mosh, tmux), a standard protocol (HTTPS, RDP, VNC, SSH), an owner-elected stack,
desktop environment, scheme, or overlay network (XRDP, GRD, X11, Wayland, XFCE, GNOME, Diceware,
Tailscale), or a named fleet member (Erebus, fedora-dev, Strix). No internal repository, build-tooling, secrets-store, or component name appears
here — those are design, and design may not be smuggled in as a requirement. The design layer (the
code and the repo's design documents) must TRACE to this document but never constrains it.

## 2. Actors & environment

**Actors**

- **Owner/admin** — full desktop, full toolset, their own resident agent. The owner is also the
  **operator**: the party who deploys and runs the product. **There is no separate operator role,
  and no party — the owner/admin/operator included — has any standing at runtime to enter,
  observe, or read another user's session, home, or data.**
- **Workers (a dynamic set, defined at deploy)** — invited collaborators: desktop + vault work,
  each with their own resident agent. They are cooperating, not mutually hostile: all users share
  one operating-system kernel, so isolation between users is enforced by the operating system
  rather than by separate machines. This ceiling is accepted and honestly disclosed (E6).
- **Resident agents (one per user)** — maintain the wiki/vault under direction; build
  knowledge-management toolsets; contribute changes as pull requests under their own identity.

**Deployment context** (load-bearing — several requirements refer to it)

- **The product runs on TWO HOST CLASSES**, and must run on both with identical behaviour (B4):
  - **Erebus** — the internet **VPS host**: headless, **no GPU**, no monitor, no login seat,
    holding the public IP address.
  - **Strix** — the **home-lab server** (an AMD Strix Halo box): headless, no monitor, no login
    seat, with a **strong integrated GPU** available for acceleration.
- **This product — the knowledge desktop — is a CONTAINER that runs on such a host** (initially
  Erebus; Strix as a deployment target as it joins the fleet).
- **fedora-dev** is another container running on Erebus, a **sibling** of this product: the
  fleet's development environment, where the desktop **platform** is maintained (H2). It is not
  part of this product, and this product neither builds nor operates it.
- The **fleet** is the owner's set of cooperating machines and containers — hosts such as Erebus
  and Strix, containers such as fedora-dev and this desktop. The fleet **grows**: further
  endpoints join later.

**The private network is a Tailscale tailnet**

- Every member is a tailnet node: the owner's phones, tablets and laptops; the fleet's **hosts**
  (Erebus, Strix); and the fleet's **containers** (fedora-dev, and this desktop).
- The tailnet is this product's **private surface**. **RDP, VNC and SSH are reachable from the
  tailnet and from nowhere else** — never from the public internet, by construction.
- **Tailnet membership is sufficient authentication for the private doors:** no second factor is
  required on RDP, VNC or SSH. It is **not** an identity, however — establishing *which* user is
  connecting still requires a per-user credential on those doors (A12).
- Erebus's **public IP** carries exactly one thing: this product's web door over HTTPS (A2).
  Nothing else of this product is ever published to it.
- **Fleet endpoints the web door must reach** (per-user grant, A10): **hosts and containers**.
  Initially required: **Erebus** (the host) and **fedora-dev** (the container); **Strix** and
  others follow. The endpoint set is **data, not design** — adding an endpoint requires no change
  to this document and no code change.

## 3. Functional requirements

### A. Access

| FR | Requirement |
|---|---|
| A1 | The full desktop is usable from a **standard web browser over HTTPS, from anywhere, with zero client software** (including iOS/iPadOS). |
| A2 | **Exactly one network endpoint is public: the browser door (A1)**, reachable over HTTPS from the public internet. Every other access path — **RDP (A6), VNC (A7 — Lineage 2 only), SSH terminal (A8)** — is reachable **only over the Tailscale tailnet**, never from the public internet. This holds **by construction, not by convention**. |
| A3 | The public door requires, **for every user without exception — the admin and every worker alike — a strong per-user credential PLUS a second factor** that works with standard authenticator apps, with **self-service enrollment at first login**. No user, role, or configuration setting exempts anyone from the second factor on the public door. |
| A4 | The public door **locks out brute force automatically** (repeated failed logins ⇒ temporary source ban). |
| A5 | The public door is **encrypted in transit**; no credential ever crosses the network in the clear. |
| A6 | The desktop is also reachable **natively via standard RDP from the Tailscale tailnet** (interoperable with stock Windows/macOS/FreeRDP clients), never from the public internet. Tailnet membership is sufficient authentication (no second factor); the door still establishes **which** user is connecting (A12) and attaches only to that user's own running session (A11, A9). |
| A7 | The desktop is reachable natively via **standard VNC** (interoperable with stock VNC clients) — **over the Tailscale tailnet only**, never from the public internet. VNC is a **first-class user access path to the user's own desktop**: it attaches to that user's single running session (A11), never forking a second session. It is **not a mirror and not a supervisory channel** — no operator, admin, or other user may observe any user's session through it. The door establishes **which** user is connecting (A12, using the A13-derived credential) and attaches only to that user's own session. Tailnet membership is sufficient authentication — no second factor. **Required on Lineage 2 (XRDP/X11) only.** Lineage 1 (GRD/Wayland/GNOME) does **not** provide native VNC — GNOME's headless GRD serves VNC only over a non-standard security type that no stock VNC client speaks, and stock-package provenance forbids a custom GRD; on Lineage 1, native desktop access is **RDP (A6) + the web door (A1)**. See the §1 two-lineage mandate (and DESIGN for how this was established). |
| A8 | **SSH terminal access over the Tailscale tailnet only** — never from the public internet: key-only **SSH**, plus **Mosh** for roaming resilience (survives changes of network address and device sleep). Tailnet membership is sufficient authentication (no second factor); the door still establishes **which** user is connecting (A12). Every terminal login by a user lands in **that user's own persistent tmux session** — one per user, shared across that user's own devices and **never** between users (A9, D2, D3) — which **follows the most recently active device** and remains legible at every screen size it is viewed from. |
| A9 | **One login, one desktop (SSO):** authenticating at any door lands the user on **their own** session without re-authenticating to a second layer; no user can reach another user's session. |
| A10 | The browser door hosts **per-user-granted SSH terminal tiles to fleet endpoints — hosts and containers alike (§2)** — over the tailnet, including at minimum **Erebus** (the host) and the **fedora-dev** container. Grants are per-user, exact-match, fail-closed, and **revocation actually revokes**; an ungranted user sees nothing. The granted endpoint set is **dynamic** — adding an endpoint is a grant change, never a requirements change. |
| A11 | **Same-session invariant.** The first-class desktop access paths — web (A1), RDP (A6), and — on Lineage 2 — VNC (A7) — **all attach to the SAME running session.** For a given user there is exactly **one** desktop session. Every path that user opens — in any combination, concurrently or in sequence, from any device — attaches to that one session, showing the same running applications and the same live screen. **No access path may create, fork, or serve a second session for that user**, and closing or losing one path never ends the session (C1). |
| A12 | **Every door resolves the user before it serves anything.** On every access path — public and private alike — the connection is resolved to exactly **one** defined user before any pixels, shell, or session are served, and it attaches only to **that** user's own session and home (A9, D2). A connection that cannot be resolved to exactly one defined user is **refused (fail-closed)**. On the private doors (RDP, VNC, SSH), **tailnet membership is sufficient authentication — no second factor is required** (the A3 second factor is a public-door property only); tailnet membership discharges the second factor, it does **not** identify the user and never substitutes for the per-user identity each private door must still establish (RDP/VNC by the user's own per-user credential, SSH by the user's own key per A8). **No tailnet member may reach a session or home that is not their own** (D2, D3). |
| A13 | **Credential format (owner-elected).** Each user's password is a **Diceware-style phrase of the fixed shape `xxx-xxxx-xxxx`** — a 3-character word, a 4-character word, and a 4-character word, dash-separated (13 characters). It is the **one credential** that user presents at every door (with the A3 second factor added on the public door only). Where a door's protocol cannot carry the full credential — **Lineage 2's VNC door accepts at most 8 password characters** — that door takes **exactly the first 8 characters of the same credential (`xxx-xxxx`)**: a truncation rule, not a second credential — nothing separate to issue, rotate, or forget. The security consequence of the truncation is disclosed in E6. |

### B. Desktop & workloads

| FR | Requirement |
|---|---|
| B1 | A **complete graphical desktop** (windowing, file management, terminal) rendered **entirely server-side, with no monitor or login seat, and with no GPU ever required** — headless is a hard prerequisite, never a tunable. A GPU, when present, accelerates (B4); its absence changes nothing but performance. |
| B2 | Ships the owner's toolset: **Obsidian** (vault editor), **VS Code**, **Firefox**, **1Password** (GUI + CLI), **Ptyxis** (the specifically selected terminal, the default on both lineages), and **Claude Code** (the resident agent, kept current daily). |
| B3 | A user's agent environment can **build and test its toolsets — including in nested, unprivileged containers — entirely inside the box**, without any host access. |
| B4 | **Host-class adaptive rendering.** The desktop runs on **both host classes (§2)**: on a **GPU-less host** (Erebus) every pixel is rendered in software on the CPU; on a **GPU-accelerated host** (Strix) the desktop **demonstrably uses the GPU** for rendering — and, where the stack supports it, for encoding — when the host makes the GPU available to the container. GPU presence is detected and exploited **with no code or configuration change to the product**; GPU absence is never an error (N3: a GPU is never required). **Behaviour is identical on both host classes** — the same doors, the same session model, the same toolset, every FR unchanged; only performance may differ. Both lineages satisfy this equally. |

### C. Sessions

| FR | Requirement |
|---|---|
| C1 | A session **survives disconnect indefinitely** — apps keep running unattended. |
| C2 | **Cross-device resume:** disconnect on device A, reconnect on device B (different network address, different screen size, different access path) ⇒ the **same** session, every application still running and in the same state, and the desktop sized to device B per **C4**. |
| C3 | Sessions come up **without any server-side manual action** — a freshly booted box serves every access path unaided. |
| C4 | **Last display wins — desktop geometry.** A desktop session's geometry is always set by its **governing display**: the most recently active of the displays currently attached to that session (the last display to view, click, move the pointer, type on, or change its viewport). Observably, the desktop's drawing area matches the governing display's viewport — the whole desktop is visible, fills that viewport, and is **not** letterboxed, cropped, panned, scrollable, or left at any other display's size. When a different attached display becomes the most recently active, the desktop follows and scales to it **within 5 seconds**, without restarting the session and without disturbing any running application. When the governing display detaches, the next-most-recently-active still-attached display governs; when the last display detaches the session keeps running (C1) and adopts the geometry of the next display that attaches. This holds on **every desktop access path that lineage serves — web, RDP, and (Lineage 2) VNC, including when two or more are attached to the one session at once — and identically on both lineages (Lineage 1 Wayland, Lineage 2 X11).** Stated as an observable outcome, not a mechanism. |

### D. Multi-user

| FR | Requirement |
|---|---|
| D1 | One always-present admin plus a **dynamic set of workers defined solely by the per-user roster the operator supplies at deploy** (§G): define N users ⇒ N are provisioned, with no code or configuration change. **Zero workers ⇒ behaviour identical to a single-user box.** |
| D2 | Per user: **their own credential** (one per user, used to establish that user's identity at every door, per A13), **their own second factor** (public door only), **their own desktop session**, and **their own persistent home** — private from every other user, including workers vs the admin's data. **Per-user privacy is absolute:** no user — the operator/admin included — may observe, attach to, record, or otherwise reach another user's live session, persistent home, or data at rest, by any door or any mechanism. **There is no supervisory exception.** |
| D3 | **Workers hold no platform power by construction**: no admin escalation, no host or platform administration, no reach into any other user's home, session, or agent environment — enforced by mechanism, not policy prose. |
| D4 | Optional **shared folder**: full read-write collaboration for all desktop users regardless of their file-creation defaults, without weakening private homes. |
| D5 | Removing a user **disables** their web identity (preserving second-factor enrollment for reinstatement); a grant downgrade takes effect at next boot. |
| D6 | Invalid user definitions are **rejected fail-closed** (no phantom account, no phantom web login) without breaking the boot. |

### E. Data & safety

| FR | Requirement |
|---|---|
| E1 | **No secret or personal identity in any image or commit** — secrets enter only at deploy time, survive container restarts, and are never echoed to logs. |
| E2 | Missing **required** secrets ⇒ the box refuses to serve (fail-fast). Missing **optional** ones ⇒ clean degradation with a logged notice. |
| E3 | **All user data persists** across container recreation and image upgrades. |
| E4 | **Vault safety:** automated vault sync is non-destructive (append-only history, no forced overwrites, conflicts stop safely for a human) and general cloud sync is **mechanically unable** to touch the vault; bulk-delete accidents are bounded and recoverable. |
| E5 | **Untrusted-content processing** (feeding web content to the wiki) runs with no credentials, no vault access, and no network — a leak-proof one-shot sandbox. |
| E6 | The security posture is **honestly disclosed**: every accepted residual risk is documented and never papered over with theater — including the **shared kernel** across cooperating users; the **vault being readable in-box** by the account that owns it; the fact that the **private doors (RDP, VNC, SSH) accept tailnet membership in place of a second factor** (per-user identity is still required on each private door per A12, so a compromised tailnet device holding a user's credential reaches those doors as that user, bounded to that user's own session and never another's); and the fact that the **VNC credential is a truncation of the master credential (A13)** — its 8 characters ARE the master's first 8, so compromising the VNC password partially exposes the master credential; accepted because VNC is reachable only from the tailnet, where membership is the primary boundary and the password is secondary. |

### F. Operations

| FR | Requirement |
|---|---|
| F1 | **Deploy is zero-intervention** end-to-end: the host's setup reads all configuration from the single secrets source (§G) and brings up the full product — containers, users, agent environments — with no prompts and no manual steps. An **attended, by-hand spin-up path also remains available**; the **non-interactive deploy contract is the only sanctioned way to run the image.** |
| F2 | **Truthful health:** a dead desktop is never reported healthy; a slow first boot is never falsely unhealthy; death of any core service self-heals by restart. |
| F3 | **Self-maintaining:** the image is rebuilt on a fixed cadence with current patches; every agent environment updates daily; the host can pull-refresh the running box with **automatic rollback** on health failure. |
| F4 | Both lineages are **co-deployable on one host** without collisions. |

### G. Per-user resident-agent environments

| FR | Requirement |
|---|---|
| G1 | **Every desktop user — the admin and every worker — has their own running, isolated resident-agent environment**: exactly one per user. |
| G2 | Each environment acts under its **own distinct, pre-authorized identity** to the version-control host, so it contributes **attributably** and needs **no interactive authentication at spin-up**. |
| G3 | The environment count is **dynamic, driven entirely by the users defined in the single secrets source**: N users defined ⇒ N environments provisioned, with no code or configuration change. |
| G4 | **Provisioning these environments on the host is completely zero-intervention**: the host's setup reads every user definition from the **single operator-controlled secrets source** and creates each environment automatically — no prompts, no manual steps. |
| G5 | The single secrets source supplies **all per-user provisioning material** — the pre-authorized version-control identity, the tailnet-enrollment details, the per-user password (A13), and the username — entering the box **only at deploy time** (per E1). |

### H. Development scope & platform governance

| FR | Requirement |
|---|---|
| H1 | The in-desktop development function exists to build and maintain **toolsets that run inside the desktop container in support of knowledge-management work**. Whether any specific toolset exists is not a requirement of this document. |
| H2 | It does **NOT** develop the knowledge-desktop platform repository and does **NOT** build or operate other container environments. Platform development belongs to the fleet's dev apparatus. |
| H3 | Toolset changes land as **attributable, least-privilege contributions to the version-control host under the acting user's own distinct, pre-authorized identity** — reviewed before they take effect (no direct writes). |
| H4 | The desktop **platform** itself ships through the fleet pipeline: PR-only by mechanism; every change **empirically validated pre-merge** (a disposable candidate is built and actually run, its access paths functionally exercised, on infrastructure that can truly boot it); merged autonomously via **two independent machine gates**; failed validations are **self-diagnosing**. |

## 4. Constraints (bind every design; still not the design)

| # | Constraint |
|---|---|
| N1 | **Provenance:** every installed artifact comes from an official source and is integrity-verified fail-closed; pinned, or resolve-logged where pinning is impossible. |
| N2 | **Minimalism:** no package without a recorded justification; minimal footprint relative to the chosen capability. |
| N3 | **Headless invariant:** no design may ever require a GPU, display, or seat. |
| N4 | **No theater:** a guard or check that cannot deliver what it implies is removed or honestly re-scoped. |
| N5 | **Empiricism:** runtime behavior is proven by running it, never by reasoning about it. |
| N6 | **Control-plane discipline:** guardrail changes ship standalone and conspicuous, never bundled with features. |

## 5. Approved lineage deltas

**Two, both owner-elected.** Beyond these, both lineages must satisfy §3 in full; no other
per-lineage exception is approved and this document grants none. The permitted differences between
the two lineages are internal mechanism plus:

1. **The desktop environment** (§1): **GNOME on Lineage 1** (GRD/Wayland), **XFCE on Lineage 2**
   (XRDP/X11).
2. **The native-VNC door (A7): Lineage 2 only.** Lineage 1 (GRD) does not serve native VNC —
   GNOME's headless GRD offers VNC only over a non-standard security type that no stock client
   speaks and stock provenance forbids a custom GRD; Lineage 1's native access is web (A1) + RDP
   (A6). See the §1 mandate (DESIGN records how this was established).

Every *other* requirement, door, and behaviour in this document holds **identically on both**, on
every access path each lineage serves (A11).

## 6. Acceptance bar — "shipped" means

For **each lineage independently**:

1. **Build green** from a clean tree (CI).
2. **Automated pre-merge gate GREEN**: a disposable candidate **boots headless and every required
   access path is functionally exercised** — the browser door serves AND a real authentication
   round-trip proves the credential+second-factor chain live (valid credentials draw a
   second-factor challenge; invalid are rejected); **RDP and VNC each answer a real protocol
   handshake on the tailnet interface and are absent from the public interface (A2)**; a real
   authentication round-trip on each private door proves **per-user identity** — a user's own
   credential (VNC using the A13-derived form) attaches that user to their own already-running
   session, and another user's credential never reaches that session (A12); **a single user
   connecting over web, RDP and VNC lands on ONE shared session — the same applications, the same
   live screen, no second forked session (A11)**; the **public surface is enumerated end-to-end
   and exactly one endpoint — the web door over HTTPS — is reachable from the public internet,
   every other listener (RDP, VNC, SSH, fleet-tile backends) confirmed absent from the public
   interface (A2)**; the desktop session is actually rendering **and its geometry tracks the most
   recently active display across all three access paths (C4)**; multi-user provisioning +
   isolation hold; health is truthful. A RED verdict is self-diagnosing (H4).
3. **Image published** to the registry by CI.
4. **Live-deploy dress rehearsal** on a real host — for each lineage independently: real pixels
   painted through **all three first-class access paths (the browser door, native RDP, and native
   VNC), with all three demonstrably attaching to the SAME running session — no path forks a
   second session (A11)**; second-factor enrollment + login on the public door; brute-force
   lockout observed; cross-device resume observed (C2); **the desktop session's geometry follows
   the most recently active display and scales to it, observed on every path (C4)**; per-user
   session privacy spot-checked (D2/D3/A9) — a second user's credential lands only on that user's
   own session on every path and reaches no other user's session; worker lockdown spot-checked
   (D3); per-user-granted SSH tiles reach the required fleet endpoints over the tailnet — at
   minimum **the Erebus host AND the fedora-dev container (A10)**; and the **public surface
   carries exactly one reachable endpoint (A2)**. The GPU-less host class (Erebus) is the
   rehearsal baseline; **on the GPU-accelerated host class (Strix), a rehearsal pass additionally
   verifies the desktop demonstrably uses the GPU (B4), with behaviour identical to the GPU-less
   baseline.**
