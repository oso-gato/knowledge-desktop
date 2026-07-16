#!/usr/bin/env bash
# WP-13 (agents) engine-free proof of kd-agent-env: per-user git identity + GitHub credential from a
# stdin token. Pure git-config + file writes — no engine, no network. Asserts the E1 property too
# (the secret token must not appear on stdout / in any argv the script issues).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
AENV="$HERE/kd-agent-env"
pass=0; fail=0
ok(){ printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
chk(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"; mkdir -p "$H"
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM   # let `git config --global` write $HOME/.gitconfig
TOKEN='ghp_SECRETtoken1234567890abcdef'      # the sentinel secret — must never leak
LOGIN='alice'; GNAME='Alice Example'; GEMAIL='alice@example.com'

out="$(printf '%s\n' "$TOKEN" | env -i HOME="$H" PATH="$PATH" "$AENV" "$LOGIN" "$GNAME" "$GEMAIL" github 2>&1)"; rc=$?

echo "== identity + credential =="
name="$(HOME="$H" git config --global user.name)"; email="$(HOME="$H" git config --global user.email)"
helper="$(HOME="$H" git config --global credential.helper)"
chk "rc 0" "[ $rc -eq 0 ]"
chk "git user.name set" "[ \"\$name\" = '$GNAME' ]"
chk "git user.email set" "[ \"\$email\" = '$GEMAIL' ]"
chk "credential.helper = store" "[ \"\$helper\" = store ]"

echo "== ~/.git-credentials =="
cred="$H/.git-credentials"
chk ".git-credentials exists" "[ -f '$cred' ]"
chk ".git-credentials is 0600" "[ \"\$(stat -c %a '$cred')\" = 600 ]"
chk ".git-credentials has https://login:token@github.com" "grep -qxF 'https://$LOGIN:$TOKEN@github.com' '$cred'"
chk "provider 'github' mapped to host github.com" "grep -q '@github.com\$' '$cred'"

echo "== ~/.config/kd/vcs.env =="
envf="$H/.config/kd/vcs.env"
chk "vcs.env exists" "[ -f '$envf' ]"
chk "vcs.env is 0600" "[ \"\$(stat -c %a '$envf')\" = 600 ]"
chk "vcs.env exports GH_TOKEN" "grep -q '^export GH_TOKEN=$TOKEN\$' '$envf'"
chk "vcs.env exports GITHUB_TOKEN" "grep -q '^export GITHUB_TOKEN=$TOKEN\$' '$envf'"
chk ".config/kd dir is 0700" "[ \"\$(stat -c %a '$H/.config/kd')\" = 700 ]"

echo "== E1: the token must NOT leak to stdout/stderr =="
if printf '%s' "$out" | grep -qF "$TOKEN"; then no "E1: TOKEN appeared in kd-agent-env output"; else ok "E1: token absent from all output"; fi
echo "  (status line was: $out)"

echo "== gitlab provider maps to gitlab.com =="
H2="$WORK/home2"; mkdir -p "$H2"
printf '%s\n' "$TOKEN" | env -i HOME="$H2" PATH="$PATH" "$AENV" bob 'Bob' 'bob@x.io' gitlab >/dev/null 2>&1
chk "gitlab provider -> gitlab.com host" "grep -q '@gitlab.com\$' '$H2/.git-credentials'"

echo
echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] && echo "KD-AGENT-ENV: GREEN" || { echo "KD-AGENT-ENV: RED"; exit 1; }
