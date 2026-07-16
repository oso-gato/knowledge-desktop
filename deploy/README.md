# deploy/ — the run contract (WP-03)

The **only sanctioned way to run the image** (F1). Byte-identical across host classes (B4).

| File | Role |
|---|---|
| `setup.sh` | Non-interactive deploy: `setup.sh <roster.json> [xrdp\|grd]`. Asserts host prereqs fail-fast, creates the `kd-roster` secret, installs the quadlet+network, starts + waits healthy. |
| `spin-up.sh` | Attended wizard — composes a single-admin roster by asking, then `exec`s `setup.sh`. Writes no run logic of its own. |
| `kd-xrdp.container` / `kd-grd.container` | systemd quadlets, one per lineage. `Secret=kd-roster`, `AddDevice=-/dev/dri` (GPU optional, B4) + `/dev/fuse`, three persistent volumes (`nosuid,nodev`), `PublishPort` (443 / 8443), `Notify=healthy`, `HealthOnFailure=kill`, `AutoUpdate=registry`. grd carries the systemd-PID-1 `PodmanArgs` (cgroup wiring + the User=-transition cap set proven on PR #1). |
| `kd-xrdp.network` / `kd-grd.network` | Dedicated per-lineage podman network — no siblings (the L2 A2 mechanism, DESIGN §2). |

**Health depth**: WP-03 health mirrors the `.live-gate` per-lineage HEALTH verbatim (gate/lint.sh
drift-checks the `Secret=` line today; the check widens as the contract grows). It deepens to
`kd-health` (F2 two-tier) in the PR that lands `kd-health` (WP-06/07).

**Not yet wired** (later WPs, by design): tailnet join from the roster authkey, per-user
provisioning (`kd-provision`, WP-06), the desktop stack (WP-07/08). WP-03 ships the *contract*;
the capability fills in behind it.
