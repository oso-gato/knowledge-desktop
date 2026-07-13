# knowledge-desktop — agent rules for this repo

## Document hierarchy (binding)

1. **REQUIREMENTS.md** — the measuring stick (v1.01, owner-approved). Every design, build,
   validation, and ship decision is graded against it. It changes ONLY with the owner's explicit
   approval — never as part of a feature PR.
2. **DESIGN.md** — the architecture. TRACES to REQUIREMENTS.md; never constrains it. Contains the
   FR trace matrix, the empirical-validation register (V1–V37), and the [ADJ] decision log.
   Design changes ride normal PRs but must keep the trace matrix complete.
3. **BUILDPLAN.md** — the ordered work packages (WP-00…WP-22), each one PR. Update the plan in the
   same PR that completes or reshapes a WP.
4. **OWNER-BRIEF.md** — historic audit trail of the rulings that produced v1.0/v1.01. Read-only.

## Zero-base rule (binding)

This is a clean-room build. The predecessor tree (`fedora-desktop`) is NOT a design source — do
not read it for design, do not copy from it, do not treat its choices as evidence. Apparatus
INTERFACE contracts (`.live-gate` format, CI/GHCR conventions, fleet host integration) may be
consulted in the fleet repos.

## How work ships (H4 — binding)

- Every change: branch → PR → `live-validate` label → host Gate B (fenced candidate incl.
  headscale tailnet) → independent fitness review → the fleet poller merges GREEN+PASS.
  The interactive agent NEVER merges (`gh pr merge` is a managed-settings deny).
- Control-plane class (governance, `.live-gate`, quadlets, CI, gate harness) ships STANDALONE
  (N6), never bundled with features.
- The PR is the ticket. State lives in the PR/verdict stream, not in local files.

## Validation tiers (from DESIGN.md §7)

- **Lineage 1 (xrdp)**: iterate Tier-1 IN-BOX (the dev box's nested engine builds AND runs it),
  then host-gate for the full probe catalog.
- **Lineage 2 (grd)**: systemd-PID-1 — the nested engine CANNOT boot it. In-box = build + static
  assertions only; ALL runtime proof is host-gate. Do not burn iterations trying to run it in-box.
- Spikes WP-04/WP-05 are GATE-KEEPERS: WP-11/WP-12 must not start before their GO/NO-GO is
  recorded on the PR. A NO-GO triggers the conditional forks in DESIGN.md §11 — surface, don't
  silently rework.

## Repo layout (WP-01)

`shared/` (kd-provision, kd-health, oracle CLIs, common config) · `lineage-xrdp/` ·
`lineage-grd/` · `gate/` (probes, fixtures, .live-gate) · `deploy/` (quadlets, setup.sh,
spin-up.sh) · `.github/workflows/` (build matrix).

## Honesty rules carried from the requirements

- N4: never claim a property a mechanism cannot deliver; every accepted residual lands in the E6
  disclosure register.
- N5: runtime behaviour is proven by running it — a claim without a probe/V-item is a wish.
- E1: no secret in any layer, commit, argv, or log. Roster material via podman secret only.
