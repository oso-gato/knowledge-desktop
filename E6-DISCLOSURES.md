# E6 — Security-posture disclosure register

REQUIREMENTS.md E6: every accepted residual risk is documented here, honestly, and never papered
over with theater (N4). A change that adds a residual MUST add a row in the same PR. Rows cite
the design element that creates them (DESIGN.md).

| # | Residual | Why accepted |
|---|---|---|
| R1 | **Shared kernel** across all desktop users (one container, one kernel) | §2 actor model: cooperating collaborators, not mutually hostile tenants; per-user isolation is OS-enforced (D2/D3), machine-grade isolation is out of scope |
| R2 | **Vault readable in-box** by the account that owns it (and by anything running as that uid) | The vault must be editable in Obsidian by its owner; E4/E5 bound sync destruction and untrusted-content reach instead |
| R3 | **Privacy from a root-equivalent host operator is a policy ceiling**, not cryptographic | The host operator can read container storage by definition; disclosed rather than theatrically "prevented" (N4) |
| R4 | **Private doors accept tailnet membership in place of a second factor** (A12) | Owner-elected; per-user identity still required per door; a compromised, tailnet-enrolled device holding a user's credential reaches those doors as that user, bounded to their own session |
| R5 | **VNC credential = front 8 chars of the master phrase** (A13) — compromising it partially exposes the master credential; the full phrase also opens VNC (RFB clients truncate) | Protocol ceiling (RFB 8-char limit); VNC is tailnet-only, where membership is the primary boundary |
| R6 | **RFB (VNC) traffic is not TLS-encrypted in-tunnel** | It rides the tailnet's WireGuard encryption; loopback hops stay in-container (same trust domain) |
| R7 | **L1 web transport stores the derived 8-char VNC form at rest** in the gateway DB | Required for the web tile's session attach; DB is loopback-only, volume-permission-bounded; it is a derivation of R5's already-disclosed form |
| R8 | **Per-user tile SSH private keys at rest** in the gateway DB (A10 egress) | The tiles must authenticate outbound; keys are per-user, grant-scoped, revoked by roster edit (D5) |
| R9 | **Web verifier is salted SHA-256** (Guacamole native), not a memory-hard KDF | Bounded by A3 TOTP + A4 lockout + loopback-only DB; disclosed as a gap, not dressed up |
| R10 | **L2 grd listeners bind wildcard** (grd cannot bind an address) | Ports never published + dedicated container network ⇒ non-tailnet reach is empty; gate bind-audit carries the expected-listener table |
| R11 | **Same-door second device = takeover**, not sharing (both lineages) | Stack ceiling (xrdp/grd session semantics); cross-PATH concurrency (A11) is guaranteed; takeover is clean and probed |
| R12 | **SELinux `label=disable` scoped to the product container** | Required for nested rootless podman + passed devices (fleet precedent); host stays enforcing; blast radius bounded by rootless userns |
| R13 | **`ignore-cert` on the gateway's in-container loopback hop** | Both endpoints are the same trust domain (one container); external TLS is Caddy's ACME cert |
| R14 | **Vault delete-bound is client-path-only** | The server layer prevents history rewrite/deletion; a bound on *legitimate-looking* bulk deletes applies at the sync client; in-app cloud sync (e.g. Obsidian Sync) runs as the vault owner — owner-account-class residual |
| R15 | **The roster is the crown jewels** (all credentials + tailnet key in one podman secret) | Single-source is the F1/G4 requirement; host compromise ⇒ roster compromise regardless of splitting |
| R16 | **Co-deployed secondary lineage serves an internal-CA cert** (F4 evaluation posture) | TLS-ALPN-01 can't validate off :443 and no :80 exists; owner may supply a DNS-01 credential as deploy data |
| R17 | **A user's own VCS token lives in that user's process environment** (G2 headless auth) | The documented gh mechanism; scoped to the user's own uid; E1 re-scoped accordingly and gate-scanned |
