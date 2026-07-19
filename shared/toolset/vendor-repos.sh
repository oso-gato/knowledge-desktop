#!/usr/bin/env bash
# shared/toolset/vendor-repos.sh (WP-15, B2) — writes the vendor dnf repos for the class-(b)
# toolset packages. EVERY repo is gpgcheck=1 with a pinned vendor key (the tool-install
# hierarchy: vendor RPM repo, never COPR/curl|sh). Run BEFORE the toolset dnf install.
#   VS Code   — Microsoft repo (challenge: `code` is class-b, gpg-verified)
#   1Password — vendor repo (GUI + CLI, repo_gpgcheck)
#   Claude Code — Anthropic `latest` channel (kept current daily by F3; DISABLE_UPDATES pins
#                 the binary to the dnf-managed one — see claude-managed-settings.json)
set -euo pipefail

KEYDIR=/etc/pki/rpm-gpg

# Keys are fetched ONCE here with retries and imported from the local file; the repos point
# gpgkey= at that file. rpm's url helper and dnf both fetch remote gpgkey URLs single-shot,
# so one TCP reset from a vendor CDN fails the whole image build (observed: packages.microsoft.com
# reset during the WP-08 grd gate). A failed fetch after retries still fails the build (fail-closed).
fetch_key(){ # <url> <dest>
    curl --fail --silent --show-error --location --globoff \
         --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 15 \
         -o "$2" "$1"
}

fetch_key https://packages.microsoft.com/keys/microsoft.asc        "$KEYDIR/RPM-GPG-KEY-microsoft"
fetch_key https://downloads.1password.com/linux/keys/1password.asc "$KEYDIR/RPM-GPG-KEY-1password"
fetch_key https://downloads.claude.ai/keys/claude-code.asc         "$KEYDIR/RPM-GPG-KEY-claude-code"

write_repo(){ # <id> <name> <baseurl> <gpgkey> [extra_line...]
    local id="$1" name="$2" baseurl="$3" gpgkey="$4"; shift 4
    { echo "[$id]"; echo "name=$name"; echo "baseurl=$baseurl"; echo "enabled=1"
      echo "gpgcheck=1"; echo "repo_gpgcheck=1"; echo "gpgkey=$gpgkey"
      for l in "$@"; do echo "$l"; done
    } > "/etc/yum.repos.d/$id.repo"
}

write_repo vscode "Visual Studio Code" \
    "https://packages.microsoft.com/yumrepos/vscode" \
    "file://$KEYDIR/RPM-GPG-KEY-microsoft"

write_repo 1password "1Password Stable Channel" \
    "https://downloads.1password.com/linux/rpm/stable/\$basearch" \
    "file://$KEYDIR/RPM-GPG-KEY-1password"

write_repo claude-code "Claude Code" \
    "https://downloads.claude.ai/claude-code/rpm/latest" \
    "file://$KEYDIR/RPM-GPG-KEY-claude-code"

# import the keys now so the install is non-interactive + fail-closed on a bad signature
rpm --import "$KEYDIR/RPM-GPG-KEY-microsoft"
rpm --import "$KEYDIR/RPM-GPG-KEY-1password"
rpm --import "$KEYDIR/RPM-GPG-KEY-claude-code"
echo "vendor-repos: VS Code + 1Password + Claude Code repos written (gpgcheck=1, keys imported)"
