# /etc/profile.d/kd-tmux.sh (WP-13, A8) — every INTERACTIVE terminal login lands in the user's ONE
# persistent tmux session ("kd"), shared across that user's own devices, never between users:
# nothing sets TMUX_TMPDIR (and the SSH/mosh login path has no logind, so no XDG_RUNTIME_DIR), so
# the socket lives in tmux's default per-user dir /tmp/tmux-$UID — created 0700 and
# ownership-checked by tmux itself, D2/D3. Profile-based (not sshd
# ForceCommand) so it works UNIFORMLY for ssh AND mosh — mosh runs the login shell, ForceCommand
# would pre-empt mosh-server. The session follows the most-recently-active device by tmux's own
# last-attach behaviour; a detached device's session persists (A8 roaming).
#
# Guards: only for interactive shells, only when a real terminal is attached, only once (never
# recurse when already inside tmux), and never for scp/rsync/non-interactive git-over-ssh.
case "$-" in *i*) ;; *) return 2>/dev/null || exit 0;; esac      # interactive only
[ -n "${TMUX:-}" ] && { return 2>/dev/null || exit 0; }          # already in tmux — do not recurse
[ -t 0 ] && command -v tmux >/dev/null 2>&1 || { return 2>/dev/null || exit 0; }

# attach the one session, creating it if absent (-A); exec so the shell IS the tmux client
exec tmux new-session -A -s kd
