# knowledge-desktop

A **cloud knowledge desktop**: a full graphical Linux desktop on a headless internet host — with
or without a GPU — usable from any device, anywhere. Built for knowledge work on the owner's
second brain (Obsidian vault + LLM wiki) with resident Claude agents, shared with invited
collaborators under absolute per-user privacy.

**Status: pre-implementation.** Requirements are finalized (v1.01); design and build plan are in
place; the build is underway per [BUILDPLAN.md](BUILDPLAN.md).

## The shape

- **Three doors, one session**: a public **web door** (HTTPS + per-user 2FA), and tailnet-only
  **RDP** and **VNC** — all attaching to the same running desktop session. SSH/Mosh/tmux terminal
  access and per-user **SSH tiles to fleet endpoints** ride the web door too.
- **Two lineages**, one repo, functionally equivalent — the desktop environment is the only
  visible difference:
  - `knowledge-desktop-xrdp` — XRDP serving an X11 session, **XFCE**
  - `knowledge-desktop-grd` — GNOME Remote Desktop serving a Wayland session, **GNOME**
- **Two host classes, one image**: GPU-less (VPS) renders in software; GPU hosts (AMD Strix Halo)
  are detected and used automatically. A GPU is never required.
- **Multi-user by roster**: one JSON secrets roster provisions N users — sessions, credentials,
  2FA enrollment, per-user resident-agent environments, nested rootless podman — with zero
  manual steps.
- **Trustworthy with data**: non-destructive vault sync, a leak-proof one-shot sandbox for
  untrusted content, honest disclosure of every accepted residual risk.

## Documents

| Doc | Role |
|---|---|
| [00-OBJECTIVES.md](00-OBJECTIVES.md) | The objective — the cloud knowledge desktop this repo delivers (owner-approved spec of record) |
| [00-REQUIREMENTS.md](00-REQUIREMENTS.md) | WHAT must be observably true (v1.01, owner-approved) — the measuring stick |
| [DESIGN.md](DESIGN.md) | The architecture: components, mechanisms, FR trace, empirical-validation register |
| [BUILDPLAN.md](BUILDPLAN.md) | Ordered work packages, each one PR |
| [CLAUDE.md](CLAUDE.md) | Rules for the agents building this repo |

Ships through the fleet pipeline: PR-only, empirically live-gated pre-merge, merged by two
independent machine gates, published to GHCR by CI.
