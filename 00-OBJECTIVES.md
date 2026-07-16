# knowledge-desktop — OBJECTIVE (spec of record)

> **Owner-approved 2026-07-12 (v1.01, incl. the host-class amendment B4).** This is the durable,
> versioned objective this repo builds to — the ground truth every design, build, validation, and
> ship decision re-grounds on. The **functional requirements** live in the companion
> [`00-REQUIREMENTS.md`](./00-REQUIREMENTS.md). This objective is locked; amendment is a new owner
> confirmation, never a silent edit. (Separated from the founding single `REQUIREMENTS.md` on
> 2026-07-14 — objective and functional requirements split into companion specs of record, **no
> content change**; the `§N` section numbering is preserved across both files so every existing
> cross-reference still resolves.)

## 1. Objective

Deliver the owner a **cloud knowledge desktop**: a full graphical Linux desktop running on a
headless internet host — **with or without a GPU (§2 host classes, B4)** — usable from any device,
anywhere.

**The access model.** The desktop is reached through three first-class access paths — a **web
browser door**, **RDP**, and **VNC** — and **all three attach to the user's one running desktop
session**; no path ever forks a second session. Exactly **one** of these is public: the **web
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

**Mandate — two lineages.** A **lineage** is a complete, independently shippable implementation of
this entire document: its own image, its own build, its own validation, deployable on its own. This
repo ships **two**, differing in exactly one thing — the remote-desktop stack each is built on, and
the desktop environment elected with it:

- **LINEAGE 1 — XRDP, serving an X11 desktop session, with XFCE as the desktop environment.**
- **LINEAGE 2 — GRD (GNOME Remote Desktop), serving a Wayland desktop session, with GNOME as the
  desktop environment.**

Both lineages ship. Each satisfies **every requirement in §3 in full, on its own** — every door,
every FR, no exemptions. **The lineages are functionally equivalent:** the same three doors, the
same one-session invariant, the same toolset (B2), the same geometry behaviour (C4), the same
isolation, the same fleet tiles — every requirement in this document holds identically on both.
The **sole owner-elected, user-visible difference is the desktop environment itself** (XFCE vs
GNOME); any *other* user-visible difference between the two lineages is a defect. Each lineage is
graded independently against the §6 bar; §5 records that no lineage deltas are approved.
