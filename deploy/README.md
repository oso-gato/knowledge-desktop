# deploy/

The sanctioned run contracts land here per BUILDPLAN **WP-03**: `kd-xrdp.container` +
`kd-grd.container` (systemd quadlets — byte-identical across host classes), `setup.sh`
(non-interactive, one arg = roster path) and `spin-up.sh` (attended wizard wrapping the same
contract). Until then this directory is intentionally empty; `gate/lint.sh`'s quadlet section
activates automatically when the files appear.
