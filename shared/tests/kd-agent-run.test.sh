#!/usr/bin/env bash
# WP-13 (agents) engine-free proof of kd-agent-run: the resident agent launcher sources the user's
# own agent env, runs Claude Code in $HOME, and ALWAYS drops to a login shell on exit so the tmux
# window (and the A8 session) never dies. Pure bash — no engine, no tmux. (The session-structure
# seed in kd-tmux.sh is proven container-tier — real tmux — in the WP-13-resident PR notes.)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
AR="$HERE/kd-agent-run"
pass=0; fail=0
ok(){ printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# a stub `claude` that reports the env it was launched with, then exits (so the run reaches the
# shell fallback deterministically); a claude-free bin dir for the no-claude path.
mkdir -p "$WORK/stub" "$WORK/nobin"
printf '#!/bin/sh\necho "CLAUDE token=[$GH_TOKEN] cwd=[$PWD]"\n' > "$WORK/stub/claude"; chmod +x "$WORK/stub/claude"
for t in bash sh env cat; do ln -sf "$(command -v "$t")" "$WORK/nobin/" 2>/dev/null; done

# 1. with vcs.env + claude: env sourced, claude runs in $HOME, then shell fallback (exec /bin/bash)
H="$WORK/h1"; mkdir -p "$H/.config/kd"; printf 'export GH_TOKEN=SECRETxyz\n' > "$H/.config/kd/vcs.env"; chmod 600 "$H/.config/kd/vcs.env"
o1="$(HOME="$H" PATH="$WORK/stub:$PATH" bash "$AR" </dev/null 2>&1)"
printf '%s' "$o1" | grep -q 'CLAUDE token=\[SECRETxyz\]' && ok "sources vcs.env → GH_TOKEN reaches claude" || no "vcs.env not sourced"
printf '%s' "$o1" | grep -qF "cwd=[$H]" && ok "runs claude in \$HOME" || no "not run in \$HOME"

# 2. no vcs.env: runs credential-less, no crash (empty token)
H2="$WORK/h2"; mkdir -p "$H2"
o2="$(HOME="$H2" PATH="$WORK/stub:$PATH" bash "$AR" </dev/null 2>&1)"
printf '%s' "$o2" | grep -q 'CLAUDE token=\[\]' && ok "credential-less run when no vcs.env (empty token, no crash)" || no "credential-less path failed"

# 3. no claude on PATH: prints the fallback notice and reaches a shell (window never dies)
o3="$(HOME="$H2" PATH="$WORK/nobin" bash "$AR" </dev/null 2>&1)"
printf '%s' "$o3" | grep -q 'dropping to a shell' && ok "no-claude → fallback notice + shell (window stays alive)" || no "no-claude fallback failed"

# 4. the fallback shell is an ABSOLUTE path (robust to bare/empty \$SHELL)
grep -q 'exec /bin/bash -l' "$AR" && ok "fallback shell is absolute (/bin/bash)" || no "fallback shell not absolute"

echo; echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] && echo "KD-AGENT-RUN: GREEN" || { echo "KD-AGENT-RUN: RED"; exit 1; }
