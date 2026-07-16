# SECRETS — the roster contract (schema v1)

The **single secrets source** (G3–G5, F1, D1): one JSON roster, delivered as a podman secret —
never a file in this repo, never an env var, never in any image layer (E1).

```sh
# host-side (Erebus / Strix), as the rootless user:
podman secret create kd-roster /path/to/roster.json   # then delete the plaintext file
```

The quadlet mounts it `Secret=kd-roster,mode=0400,uid=0` → `/run/secrets/kd-roster`.
`kd-provision` (PID-1-adjacent, boot) is the **only** component that parses it.

## Schema v1 (closed set — unknown keys are a D6 rejection)

```json
{
  "version": 1,
  "box": {
    "tailnet_authkey": "REQUIRED — tskey-…; missing ⇒ fail-fast (E2)",
    "public_dns_name": "optional — absent ⇒ web door serves tls-internal",
    "vault_repo": "optional — absent ⇒ vault sync disabled + logged (E2 degrade)",
    "endpoints": {
      "erebus":     { "host": "<tailnet name/ip>", "port": 22, "user": "core" },
      "fedora-dev": { "host": "<tailnet name/ip>", "port": 22, "user": "core" }
    },
    "shared_folder": false
  },
  "admin": {
    "username": "…",
    "password": "xxx-xxxx-xxxx",
    "ssh_authorized_keys": ["ssh-ed25519 …"],
    "tile_ssh_key": "optional — private key used ONLY for A10 tile egress",
    "vcs": { "provider": "github", "login": "…", "token": "…",
             "git_name": "…", "git_email": "…" },
    "tiles": ["erebus", "fedora-dev"]
  },
  "workers": [ { "…": "same shape as admin" } ]
}
```

## Rules

- **Password shape (A13):** Diceware-style `xxx-xxxx-xxxx` — 3-char word, 4-char word, 4-char
  word, dash-separated, 13 chars, charset `[a-z0-9-]`. The VNC door receives EXACTLY the first 8
  characters (`xxx-xxxx`) — a derivation, not a second credential.
- **Validation severity (D6/E2):** missing/invalid roster, admin block, or `tailnet_authkey` ⇒
  the container exits nonzero fail-fast. An invalid WORKER entry ⇒ that user is excluded with a
  value-free log line; boot continues.
- **Rotation:** edit roster → `podman secret rm kd-roster && podman secret create …` (or
  `--replace`) → restart the quadlet. Effects land at next boot (D5).
- **Never in logs (E1, re-scoped per DESIGN §4, gate-scanned):** no roster SECRET — password,
  token, key, authkey — may appear in any journal, argv, image layer, or another uid's
  environment. Secrets travel exclusively via stdin/fd. Disclosed residuals (E6): usernames
  (identities, not secrets) appear in provisioning logs; an unknown-KEY rejection echoes the
  offending key names.
- The roster is the box's **crown jewels** (disclosed in E6): whoever holds it holds every
  user's credential and the tailnet key. Guard the host accordingly.
