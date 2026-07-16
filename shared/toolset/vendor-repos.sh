#!/usr/bin/env bash
# shared/toolset/vendor-repos.sh (WP-15, B2) — writes the vendor dnf repos for the class-(b)
# toolset packages. EVERY repo is gpgcheck=1 with a pinned vendor key (the tool-install
# hierarchy: vendor RPM repo, never COPR/curl|sh). Run BEFORE the toolset dnf install.
#   VS Code   — Microsoft repo (challenge: `code` is class-b, gpg-verified)
#   1Password — vendor repo (GUI + CLI, repo_gpgcheck)
#   Claude Code — Anthropic `latest` channel (kept current daily by F3; DISABLE_UPDATES pins
#                 the binary to the dnf-managed one — see claude-managed-settings.json)
set -euo pipefail

write_repo(){ # <id> <name> <baseurl> <gpgkey> [extra_line...]
    local id="$1" name="$2" baseurl="$3" gpgkey="$4"; shift 4
    { echo "[$id]"; echo "name=$name"; echo "baseurl=$baseurl"; echo "enabled=1"
      echo "gpgcheck=1"; echo "repo_gpgcheck=1"; echo "gpgkey=$gpgkey"
      for l in "$@"; do echo "$l"; done
    } > "/etc/yum.repos.d/$id.repo"
}

write_repo vscode "Visual Studio Code" \
    "https://packages.microsoft.com/yumrepos/vscode" \
    "https://packages.microsoft.com/keys/microsoft.asc"

write_repo 1password "1Password Stable Channel" \
    "https://downloads.1password.com/linux/rpm/stable/\$basearch" \
    "https://downloads.1password.com/linux/keys/1password.asc"

write_repo claude-code "Claude Code" \
    "https://downloads.claude.ai/claude-code/rpm/latest" \
    "https://downloads.claude.ai/keys/claude-code.asc"

# import the keys now so the install is non-interactive + fail-closed on a bad signature
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://downloads.1password.com/linux/keys/1password.asc
rpm --import https://downloads.claude.ai/keys/claude-code.asc
echo "vendor-repos: VS Code + 1Password + Claude Code repos written (gpgcheck=1, keys imported)"
