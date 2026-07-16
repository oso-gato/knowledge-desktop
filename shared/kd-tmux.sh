# /etc/profile.d/kd-tmux.sh (WP-13, A8) — every INTERACTIVE terminal login lands in the user's ONE
# persistent tmux session ("kd"), shared across that user's own devices, never between users:
# nothing sets TMUX_TMPDIR (and the SSH/mosh login path has no logind, so no XDG_RUNTIME_DIR), so
# the socket lives in tmux's default per-user dir /tmp/tmux-$UID — created 0700 and
# ownership-checked by tmux itself, D2/D3. Profile-based (not sshd
# ForceCommand) so it works UNIFORMLY for ssh AND mosh — mosh runs the login shell, ForceCommand
# would pre-empt mosh-server. The session follows the most-recently-active device by tmux's own
# last-attach behaviour; a detached device's session persists (A8 roaming).
#
# WP-13 (agents, G1): the "kd" session HOSTS THE RESIDENT Claude Code agent. On first login the
# session is seeded with two windows — "agent" (Claude Code via kd-agent-run) and "shell" (a plain
# login shell) — and the user lands on the agent window. The agent lives in the tmux SERVER, so it
# persists across every disconnect and is simply re-attached on later logins (A8). kd-agent-refresh
# respawns the agent window for currency (deferred). A box with no roster `vcs` block still gets the
# window — the agent just runs credential-less (kd-agent-run guards the env source).
#
# Guards: only for interactive shells, only when a real terminal is attached, only once (never
# recurse when already inside tmux), and never for scp/rsync/non-interactive git-over-ssh.
case "$-" in *i*) ;; *) return 2>/dev/null || exit 0;; esac      # interactive only
[ -n "${TMUX:-}" ] && { return 2>/dev/null || exit 0; }          # already in tmux — do not recurse
[ -t 0 ] && command -v tmux >/dev/null 2>&1 || { return 2>/dev/null || exit 0; }

# create-or-attach the ONE persistent session. On CREATION seed the resident agent + shell windows;
# a later login (session already in the server) just re-attaches to the running agent. The create is
# race-guarded: if a concurrent login won the create, has-session is true and we fall through to attach.
if ! tmux has-session -t kd 2>/dev/null; then
    if tmux new-session -d -s kd -n agent /usr/libexec/kd/kd-agent-run 2>/dev/null; then
        tmux new-window -t kd: -n shell 2>/dev/null
        tmux select-window -t kd:agent 2>/dev/null
    fi
fi
exec tmux attach -t kd
