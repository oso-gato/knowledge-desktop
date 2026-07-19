# knowledge-desktop — OBJECTIVE (spec of record)

> **The spec of record — the current, owner-approved objective this repo builds to.** The ground
> truth every design, build, validation, and ship decision re-grounds on. The **functional
> requirements** live in the companion [`00-REQUIREMENTS.md`](./00-REQUIREMENTS.md). This states the
> objective **as it now stands**; it changes only with the owner's explicit confirmation, never a
> silent edit. The road travelled — options weighed, paths taken and not taken — lives in
> [`DESIGN.md`](./DESIGN.md), not here.

## 1. Objective

Deliver the owner a **cloud knowledge desktop**: a full graphical Linux desktop running on a
headless internet host — **with or without a GPU (§2 host classes, B4)** — usable from any device,
anywhere.

**The access model.** The desktop is reached through three first-class access paths — a **web
browser door**, **RDP**, and (on the compatibility lineage) **VNC** — and **all of them attach to
the user's one running desktop session**; no path ever forks a second session. Exactly **one** of these is public: the **web
browser door, over HTTPS on the public IP**, usable from any device in any location with zero
client software. Every other door — RDP, VNC, and SSH terminal access — is reachable **only over
the owner's private Tailscale tailnet**, never from the public internet. The desktop **follows the
user across devices**: its display geometry tracks the most recently active screen, so the desktop
is fully usable wherever the user last looked, clicked, or moved the pointer.

**Fleet terminals through the web door (first-class, not an extra).** The web door also gives each
user, by explicit per-user grant, **SSH terminal tiles to endpoints elsewhere on the fleet — hosts
and containers alike (§2)** — over the tailnet. This is how a user reaches the rest of the fleet
from a phone, a tablet, or a borrowed laptop with nothing installed. Grants are per-user,
exact-match and fail-closed; revocation actually revokes; an ungranted user sees nothing. The
endpoint set is **data, not design**: adding an endpoint must never require a change to this
document.

Two jobs, one desktop:
1. **Knowledge work (primary)** — operate and maintain the owner's second brain (the Obsidian
   vault + LLM wiki), with resident Claude agents as live-in librarians working under direction.
2. **Toolset development (secondary)** — the desktop's users, through their resident agents,
   develop **knowledge-management toolsets that run inside the desktop container**. Whether any
   specific toolset exists is not a requirement of this document. The desktop platform itself is
   maintained upstream by the fleet's dev apparatus (§2), not by this box.

It must be **safe to leave exposed to the public internet indefinitely** — exactly one hardened
public door (the web door), with every other door reachable only over the Tailscale tailnet —
**trustworthy with the owner's data** (the vault can never be silently destroyed; collaborators
can't read each other), and **self-maintaining** (patches itself, heals itself, a failed upgrade
rolls back).

**Mandate — two lineages: the forward path and a compatibility hedge.** A **lineage** is a complete,
independently shippable implementation of this entire document — its own image, its own build, its
own validation, deployable on its own. This repo ships **two**. They are not two interchangeable
options; they are a **primary and a fallback**, differing in the remote-desktop stack each is built
on and the desktop session and environment elected with it:

- **LINEAGE 1 — GRD (GNOME Remote Desktop) on a Wayland session, GNOME desktop — the primary, and
  the way forward.** Wayland is the modern display architecture and the one the whole Linux desktop
  is now developed on: Xorg is frozen in maintenance and its session is being retired across the
  ecosystem, while Wayland composites cleanly for GPU-accelerated rendering, fractional and mixed-DPI
  scaling, and per-display geometry (B4, C4), and it **isolates every application by construction**
  rather than leaving the X11 free-for-all in which any client can silently read another's keystrokes
  and screen. GRD is GNOME's own, actively-maintained, RDP-first remote-desktop server. This is the
  lineage the product is built around, and where the desktop is going.
- **LINEAGE 2 — XRDP on an X11 session, XFCE desktop — the compatibility hedge, and the fallback.**
  The X11/xrdp stack is mature and battle-tested, and it buys the one thing the forward path cannot
  yet give: **complete, standards-compliant native VNC**, whose door speaks the plain VNC that every
  stock client on every platform understands. It exists so the product is never hostage to the
  Wayland ecosystem's rough edges — where the primary lacks something today, or should GRD or Wayland
  ever regress, the whole product still ships on a proven foundation.

Both lineages ship, and **each satisfies every requirement in §3 in full, on its own — with exactly
one owner-elected door difference.** **Lineage 1 (GRD)** serves **web, RDP, and SSH — but not native
VNC.** **Lineage 2 (XRDP)** serves all four doors: **web, RDP, VNC, and SSH.** This is the honest
expression of the forward-path-versus-hedge split, not a defect and not a mere preference: GNOME's
headless GRD offers VNC only over a non-standard "anonymous-TLS" security type that **no stock VNC
client on macOS, Windows, or iPadOS speaks**, and stock-package provenance forbids rebuilding GRD to
change it — so on the primary, native VNC is dropped in favour of **RDP**,
which GNOME itself now prefers and which has first-class stock clients on every device (Windows
`mstsc`, Microsoft Remote Desktop on macOS and iPad), alongside the public web door. **A user who
specifically needs a native VNC client runs Lineage 2.** The two owner-elected, user-visible
differences between the lineages are therefore the **desktop environment** (GNOME vs XFCE) and the
**native-VNC door** (Lineage 2 only); any *other* user-visible difference remains a defect. Each
lineage is graded independently against the §6 bar; §5 records that this door difference is the only
approved lineage delta.
