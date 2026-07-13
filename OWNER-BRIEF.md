# knowledge-desktop — consolidated owner brief (working capture, 2026-07-12)

> **STATUS: EXECUTED.** REQUIREMENTS.md v1.0 was owner-approved and finalized 2026-07-12
> (commit 2b48892, pushed to main). **The doc is now the authority, not this brief** — this file
> remains only as the audit trail of the rulings that produced v1.0. Late rulings folded in at
> finalization: R8 (below); the "13 not 14" flag stands owner-unchallenged and shipped as 13.

## R8 — Desktop environments per lineage (finalized 2026-07-12)
- LINEAGE 1 (XRDP/X11): **XFCE** desktop environment.
- LINEAGE 2 (GRD/Wayland): **GNOME** desktop environment.
- Consequence: the mandate's "lineage invisible to the user" was re-scoped to FUNCTIONAL
  equivalence — the DE is the sole owner-elected visible difference; any OTHER visible
  difference is a defect. (§1 Mandate + §5 aligned.)

Original preamble (historic): the rulings below were the source-of-truth checklist while
iterating; where brief and doc disagreed, the brief won.

## R1 — Erase the predecessor (fedora-desktop)
- Remove every reference: the name, Provenance block, "reference tree", "incumbent", "prior gate",
  "v3.2", "owner-approved 2026-07-11", past dates/verdicts/dress-rehearsals, the "three owner
  decisions carried in" block, and §7 Gap register.
- No inherited design/code/implementation. Clean room.
- Must STAND ALONE (cold reader, zero predecessor knowledge). Purely objective + functional:
  WHAT is observably true, never HOW.

## R2 — Two lineages, re-founded (owner-elected)
- LINEAGE 1: XRDP + X11 session.
- LINEAGE 2: GRD (GNOME Remote Desktop) + Wayland session.
- Both ship. Each satisfies every FR in §3 in full. Stack choice INVISIBLE to the user (identical
  observable behaviour). §1 Mandate must NAME and DEFINE both — the doc currently never defines
  what a lineage is (fatal stand-alone gap).

## R3 — Access model (SETTLED)
- PUBLIC: exactly ONE endpoint — the web browser door, HTTPS on public IP. Any device, any
  location, zero client software (every device has a browser → this is what satisfies "any device,
  any location"). Gated by per-user credential + SECOND FACTOR for EVERY user. Brute-force lockout.
- PRIVATE: the private network IS a Tailscale **tailnet** — named explicitly in objective AND
  requirements (elected requirement, NOT leakage). NB: owner wrote "Telnet" = dictation error for
  "tailnet". RDP, VNC, SSH, Mosh are tailnet-ONLY, never public.
- Tailnet membership is sufficient AUTHENTICATION for the private doors → NO second factor there.
- Three first-class DESKTOP access paths: WEB, RDP, VNC — ALL attach to the SAME running session;
  no path forks a second session (new explicit FR — the same-session invariant).
- VNC is NOT a supervisory mirror. Delete the mirror framing everywhere: A7 (arming credential /
  operator observes workers), D2 "sole carve-out", E6 "weak-auth mirror" residual, preamble
  decision (i). VNC becomes a first-class user door.

## R3a — Identity vs authentication on private doors (SETTLED)
- Tailnet replaces the SECOND FACTOR, not IDENTITY. RDP and VNC still establish WHICH user is
  connecting (per-user credential), else any tailnet member could open any user's session —
  breaking D2 (own session) and D3 (no cross-user reach). No TOTP on the private doors; identity
  still required.

## R3b — Privacy (SETTLED)
- Owner does NOT monitor users; respects their privacy. No supervisory observation of any kind.
- State POSITIVELY (testable): no user, admin included, can observe another user's live session;
  no access path grants it; no mechanism for it exists or will be built.
- HONEST CEILING (N4/E6): worker-vs-worker privacy is mechanical (separate sessions/homes, no
  escalation). Privacy FROM a root-equivalent admin on a shared kernel is a disclosed policy
  ceiling, not a cryptographic guarantee — disclose under E6 alongside shared-kernel + in-box vault.
  Do NOT claim mechanical privacy from the admin (that would be theater).

## R4 — Display geometry (NEW FR)
- Desktop session geometry follows the MOST RECENTLY ACTIVE display; display scales to it; last
  device always wins. "Active" = last viewed / clicked / mouse-moved. [JUDGMENT: define "active"
  crisply — proposed: the display of the most recent input event (pointer motion / click / key).
  Owner to confirm.]
- Holds across ALL three paths (web/RDP/VNC) and BOTH lineages (X11 + Wayland). Write as an
  OBSERVABLE OUTCOME, not a mechanism (materially harder on X11 than Wayland).
- Distinct from A8's TERMINAL geometry (see R6) — two layers, both kept, not redundant.
- §6 acceptance test: attach small screen → attach large → assert desktop resized to large; then
  generate input on the small → assert it resized back.

## R5 — SSH fleet access through the web (ELEVATE to objective)
- Web gate hosts per-user-granted SSH terminal tiles to FLEET ENDPOINTS over the tailnet. Elevate
  into the Objective (owner calls it important), not just A10.
- A10 CORRECTION: today says "other fleet HOSTS" — must be fleet ENDPOINTS = hosts AND CONTAINERS.
- Grants per-user, exact-match, fail-closed; revocation actually revokes; ungranted user sees
  nothing. Grant set DYNAMIC — adding an endpoint is not a requirements change.
- DEPLOYMENT CONTEXT (add to §2, currently absent):
  - **Erebus** = the VPS host (repo: fedora-bootstrap).
  - **fedora-dev** = a container on Erebus.
  - **knowledge-desktop (THIS PRODUCT)** = also a container on Erebus, sibling to fedora-dev.
  - Initial required tile set: Erebus (host) + fedora-dev (container).
  - Later: Strix + others.
- "fleet", "tailnet", "Erebus" are legitimate owner vocabulary.

## R6 — SSH sessions: Mosh + tmux (elected named requirements)
- Remote SSH built on Mosh (roaming-resilient shell) + tmux (multiplexer). Name them in A8 (like
  XRDP/GRD/Ptyxis).
- Terminal geometry race (differently-sized clients on one tmux session, last-device-wins) is
  ALREADY SOLVED by tmux — A8 encodes it. Keep. This is NOT the desktop geometry FR (R4).

## R7 — Credential spec (Diceware) + VNC truncation (NEW)
- One per-user credential across all doors (folds in old decision (ii)).
- Password = Diceware-style, pattern `xxx-xxxx-xxxx`: 3-char word · dash · 4-char word · dash ·
  4-char word.
  - FLAG: owner said "14 characters" but the pattern is **13** (11 letters + 2 dashes). 13 is what
    makes the VNC rule land cleanly. Proceeding with 13 unless overruled.
- VNC accepts only an 8-char password → use the FRONT 8 chars = `xxx-xxxx` (first word · dash ·
  second word — exactly 8, lands on the 2nd dash). This is THE RULE.
- E6 DISCLOSURE (honest, N4): the VNC password is a TRUNCATION of the master credential, not an
  independent secret — its first 8 chars ARE the master's first 8 chars. Cracking VNC's 8-char
  password partially exposes the master credential (first two words). Acceptable because VNC is
  tailnet-only (tailnet membership is the real boundary; the 8-char password is secondary), but it
  MUST be disclosed, not implied-away.

## Structural questions the running review will answer (do not pre-empt)
- §5 (Approved lineage deltas): keep as a section, or fold into the Mandate?
- §7 (Gap register): survive in a zero-base doc, or delete? What is lost?
- §G: de-"claudebox" into implementation-free "isolated per-user resident-agent environment,
  zero-intervention from a single secrets source"?
- §H4 (CI / merge pipeline / "two independent machine gates"): a requirement of THIS product, or
  someone else's dev process — cut?
- Preamble "no internal software names" claim is now FALSE (XRDP/GRD/Obsidian/Tailscale/...) —
  amend to something truthful.
- Version/title framing for a true standalone founding doc.
- Dangling cross-refs after deleting §7 / Provenance / decisions block.

## Legitimate named vocabulary (keep) vs suspect leakage (challenge)
- KEEP: Obsidian, VS Code, Firefox, 1Password, Claude Code, Ptyxis, RDP, VNC, SSH, Mosh, tmux,
  HTTPS, XRDP, GRD, X11, Wayland, Tailscale/tailnet, "fleet", Erebus, fedora-dev (as a named
  sibling endpoint), Diceware.
- CHALLENGE: "claudebox", "the ak-private repository", "the secret file", "VoiceID", "oso-gato",
  and any FR prescribing HOW.

## R9 — Two host classes / GPU-adaptive rendering (v1.01, 2026-07-12)
- The desktop runs on BOTH: **Erebus** (VPS, NO GPU — pure-CPU software rendering) and **Strix**
  (home-lab AMD Strix Halo box, repo `strix-ms-s1-bootc`, strong iGPU — the desktop must
  DEMONSTRABLY use the GPU when the host passes /dev/dri into the container).
- New **B4** FR: adaptive — detected/exploited with no code or config change; absence never an
  error (N3 intact); behaviour identical on both classes; both lineages equally.
- §2 gains the two host classes; §6 item 4 gains the Strix GPU-verification rehearsal pass.
- Committed as **v1.01** (fbc788d). Design workflow restarted against v1.01 (was 2/6 into a
  v1.0-based derive; stopped + prompts patched + relaunched).
