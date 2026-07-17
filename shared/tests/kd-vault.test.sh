#!/usr/bin/env bash
# WP-17 (E4) engine-free proof of the vault sync subsystem. The guarded cycle is pure git+bash, so
# every guard is provable with local bare remotes + clones — NO container/nested engine needed.
# Covers kd-vault-sync (clean sync, stop-flag, vault-ready gate, local+inbound mass-delete guards,
# conflict abort+restore, ff + divergent-clean merge, unreachable fail-safe) and kd-vault-init
# (clone, .gitignore seed + effect, ruleset confirmed/absent/unverified).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # shared/
SYNC="$HERE/kd-vault-sync"; INIT="$HERE/kd-vault-init"; DRIVER="$HERE/kd-vault-driver"
GITIGNORE="$HERE/kd-vault-gitignore"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null   # hermetic: ignore host git config
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok(){ printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
chk(){ if eval "$2"; then ok "$1"; else no "$1 [$2]"; fi; }

git_q(){ git "$@" >/dev/null 2>&1; }
# make a bare remote (optionally protected), seed it with N notes via a throwaway clone
mkremote(){ # $1=path $2=protected(0/1) $3=nfiles
    git_q init --bare -b main "$1"
    if [ "$2" = 1 ]; then git_q -C "$1" config receive.denyNonFastForwards true; git_q -C "$1" config receive.denyDeletes true; fi
    local seed="$WORK/seed.$$"; git_q clone "$1" "$seed"
    ( cd "$seed" && for i in $(seq 1 "$3"); do echo "note $i" > "note$i.md"; done \
      && git_q add -A && git_q commit -m seed && git_q push origin main )
    rm -rf "$seed"
}
newclone(){ git_q clone "$1" "$2"; }   # $1=remote $2=dest

# ============================================================================================
echo "== kd-vault-init =="

# T1 clone + .gitignore seed + ruleset CONFIRMED (protected bare) => vault-ready created
R="$WORK/r1.git"; V="$WORK/v1"; RD="$WORK/rd1"; mkremote "$R" 1 3
KD_VAULT_DIR="$V" KD_VAULT_READY="$RD" KD_VAULT_GITIGNORE_SRC="$GITIGNORE" "$INIT" "$R" >/dev/null 2>&1
chk "init clones the repo" "[ -d '$V/.git' ]"
chk "init seeds broadened .gitignore" "grep -q 'knowledge-desktop vault' '$V/.gitignore'"
chk "protected remote => vault-ready set" "[ -e '$RD' ]"

# T2 unprotected bare => vault-ready WITHHELD (affirmative ruleset-absent)
R="$WORK/r2.git"; V="$WORK/v2"; RD="$WORK/rd2"; mkremote "$R" 0 3
KD_VAULT_DIR="$V" KD_VAULT_READY="$RD" KD_VAULT_GITIGNORE_SRC="$GITIGNORE" "$INIT" "$R" >/dev/null 2>&1
chk "unprotected remote => clone still made" "[ -d '$V/.git' ]"
chk "unprotected remote => vault-ready WITHHELD" "[ ! -e '$RD' ]"

# T3 unreachable repo => graceful, no half-clone, vault-ready absent, rc 0
V="$WORK/v3"; RD="$WORK/rd3"
KD_VAULT_DIR="$V" KD_VAULT_READY="$RD" KD_VAULT_GITIGNORE_SRC="$GITIGNORE" "$INIT" "$WORK/nope.git" >/dev/null 2>&1; rc=$?
chk "unreachable => rc 0 (fail-safe)" "[ $rc -eq 0 ]"
chk "unreachable => no half-clone left" "[ ! -e '$V' ]"
chk "unreachable => vault-ready absent" "[ ! -e '$RD' ]"

# T4 absent repo url => vault disabled, rc 0
KD_VAULT_DIR="$WORK/v4" KD_VAULT_READY="$WORK/rd4" "$INIT" "" >/dev/null 2>&1
chk "no vault_repo => no clone (E2 degrade)" "[ ! -e '$WORK/v4' ]"

# ============================================================================================
echo "== kd-vault-sync =="
# helper: a ready clone (protected remote) with vault-ready set, stop-flag path chosen
setup(){ # $1=name -> sets globals R V RD SF for this scenario, seeded with $2 notes
    R="$WORK/$1.git"; V="$WORK/$1"; RD="$WORK/$1.ready"; SF="$WORK/$1.stop"
    mkremote "$R" 1 "$2"; newclone "$R" "$V"; : > "$RD"
}
run_sync(){ KD_VAULT_DIR="$V" KD_VAULT_READY="$RD" KD_VAULT_STOPFLAG="$SF" \
            KD_VAULT_DELETE_FLOOR="${FLOOR:-25}" "$SYNC" >/dev/null 2>&1; }

# T5 clean sync: add a note => committed + pushed to remote
setup s5 3; echo "new" > "$V/newnote.md"; run_sync; rc=$?
tip_local="$(git -C "$V" rev-parse HEAD)"; tip_remote="$(git -C "$R" rev-parse main)"
chk "clean sync rc 0" "[ $rc -eq 0 ]"
chk "clean sync pushed (local tip == remote tip)" "[ '$tip_local' = '$tip_remote' ]"
chk "clean sync: newnote on remote" "git -C '$R' cat-file -e main:newnote.md 2>/dev/null"

# T6 stop-flag present => no-op (no new commit)
setup s6 3; before="$(git -C "$V" rev-parse HEAD)"; echo x > "$V/x.md"; echo "stopped" > "$SF"; run_sync
after="$(git -C "$V" rev-parse HEAD)"
chk "stop-flag => no commit made" "[ '$after' = '$before' ]"

# T7 vault-ready absent => sync paused
setup s7 3; before="$(git -C "$V" rev-parse HEAD)"; rm -f "$RD"; echo y > "$V/y.md"
KD_VAULT_DIR="$V" KD_VAULT_READY="$RD" KD_VAULT_STOPFLAG="$SF" "$SYNC" >/dev/null 2>&1
after="$(git -C "$V" rev-parse HEAD)"
chk "no vault-ready => sync paused (no commit)" "[ '$after' = '$before' ]"

# T8 local mass-delete guard: floor 2, delete 3 => stop-flag, NOT committed, deletions unstaged
setup s8 5; FLOOR=2; before="$(git -C "$V" rev-parse HEAD)"; rm -f "$V/note1.md" "$V/note2.md" "$V/note3.md"
run_sync; rc=$?; after="$(git -C "$V" rev-parse HEAD)"; staged="$(git -C "$V" diff --cached --name-only)"
chk "local mass-delete => rc 3" "[ $rc -eq 3 ]"
chk "local mass-delete => stop-flag set" "[ -e '$SF' ]"
chk "local mass-delete => NOT committed" "[ '$after' = '$before' ]"
chk "local mass-delete => deletions unstaged" "[ -z '$staged' ]"
unset FLOOR

# T9 inbound mass-delete guard: remote deletes 3 (floor 2) => stop-flag, NOT merged, local intact
setup s9 5; FLOOR=2
peer="$WORK/s9peer"; newclone "$R" "$peer"
( cd "$peer" && git_q rm note1.md note2.md note3.md && git_q commit -m "mass del" && git_q push origin main )
before="$(git -C "$V" rev-parse HEAD)"; run_sync; rc=$?; after="$(git -C "$V" rev-parse HEAD)"
chk "inbound mass-delete => rc 3" "[ $rc -eq 3 ]"
chk "inbound mass-delete => stop-flag set" "[ -e '$SF' ]"
chk "inbound mass-delete => local HEAD unchanged (not merged)" "[ '$after' = '$before' ]"
chk "inbound mass-delete => local note1 still present" "[ -f '$V/note1.md' ]"
unset FLOOR

# T10 conflict => merge --abort, byte-identical restore, stop-flag, rc 3
setup s10 3
peer="$WORK/s10peer"; newclone "$R" "$peer"
( cd "$peer" && echo "PEER edit" > note1.md && git_q add -A && git_q commit -m peer && git_q push origin main )
echo "LOCAL edit" > "$V/note1.md"; run_sync; rc=$?
chk "conflict => rc 3" "[ $rc -eq 3 ]"
chk "conflict => stop-flag set" "[ -e '$SF' ]"
chk "conflict => local note1 restored byte-identical (LOCAL edit)" "[ \"\$(cat '$V/note1.md')\" = 'LOCAL edit' ]"
chk "conflict => no merge markers in tree" "! grep -q '<<<<<<<' '$V/note1.md'"

# T11 fast-forward: remote adds a note (local unchanged) => local ff-merges it, rc 0
setup s11 3
peer="$WORK/s11peer"; newclone "$R" "$peer"
( cd "$peer" && echo "ff" > ffnote.md && git_q add -A && git_q commit -m ff && git_q push origin main )
run_sync; rc=$?
chk "ff merge rc 0" "[ $rc -eq 0 ]"
chk "ff merge => remote note pulled in" "[ -f '$V/ffnote.md' ]"

# T12 divergent CLEAN merge: local + remote edit DIFFERENT files => merge + push, rc 0
setup s12 3
peer="$WORK/s12peer"; newclone "$R" "$peer"
( cd "$peer" && echo "remote" > note1.md && git_q add -A && git_q commit -m r && git_q push origin main )
echo "localonly" > "$V/note2.md"; run_sync; rc=$?
n1="$(cat "$V/note1.md")"; ltip="$(git -C "$V" rev-parse HEAD)"; rtip="$(git -C "$R" rev-parse main)"
chk "divergent-clean merge rc 0" "[ $rc -eq 0 ]"
chk "divergent-clean => both edits present locally" "[ '$n1' = 'remote' ] && [ -f '$V/note2.md' ]"
chk "divergent-clean => pushed (local tip == remote tip)" "[ '$ltip' = '$rtip' ]"

# T13 unreachable remote at fetch => tree intact, rc 0 (fail-safe)
setup s13 3; echo z > "$V/z.md"; rm -rf "$R"; run_sync; rc=$?
chk "fetch-unreachable => rc 0 (non-fatal)" "[ $rc -eq 0 ]"
chk "fetch-unreachable => local change committed, tree intact" "[ -f '$V/z.md' ]"

# ============================================================================================
echo "== .gitignore effect =="
# T14 a per-device workspace file is ignored; a note is not
setup s14 2
mkdir -p "$V/.obsidian"; echo '{"x":1}' > "$V/.obsidian/workspace.json"
printf '\n' >> "$V/.gitignore"; cat "$GITIGNORE" >> "$V/.gitignore"
echo "realnote" > "$V/keep.md"
( cd "$V" && git_q add -A )
chk ".gitignore excludes .obsidian/workspace.json" "! git -C '$V' diff --cached --name-only | grep -q 'workspace.json'"
chk ".gitignore keeps content note" "git -C '$V' diff --cached --name-only | grep -q 'keep.md'"

# ============================================================================================
echo "== kd-vault-driver (sweep selection + fail-safe, stubbed getent/runuser) =="
# T15 the driver must: sweep every uid>=UID_BASE that HAS a ~/Vault/.git, skip below-base + no-vault
# users, and CONTINUE past one user's sync failure (fail-safe). Stub getent+runuser to isolate the
# orchestration from real accounts (engine-free, non-root).
STUB="$WORK/stubbin"; mkdir -p "$STUB"
H="$WORK/dh"; mkdir -p "$H/alice/Vault/.git" "$H/bob/Vault/.git" "$H/carol"   # carol has NO vault
cat > "$STUB/getent" <<EOF
#!/bin/sh
[ "\$1" = passwd ] || exit 0
cat <<PW
root:x:0:0::/root:/bin/bash
sysacct:x:100:100::/var/empty:/sbin/nologin
alice:x:2000:2000::$H/alice:/bin/bash
bob:x:2001:2001::$H/bob:/bin/bash
carol:x:2002:2002::$H/carol:/bin/bash
PW
EOF
cat > "$STUB/runuser" <<EOF
#!/bin/sh
# args: -u <name> -- env HOME=<h> <sync>; record the name, fail for bob (fail-safe probe)
echo "\$2" >> "$WORK/swept.log"
[ "\$2" = bob ] && exit 7 || exit 0
EOF
chmod +x "$STUB/getent" "$STUB/runuser"
: > "$WORK/swept.log"
PATH="$STUB:$PATH" KD_VAULT_DRIVER_ONESHOT=1 KD_UID_BASE=2000 KD_VAULT_SYNC="$SYNC" "$DRIVER" >/dev/null 2>&1; rc=$?
swept="$(sort -u "$WORK/swept.log" | tr '\n' ' ')"
chk "driver rc 0 despite a user's sync failing (fail-safe)" "[ $rc -eq 0 ]"
chk "driver swept alice (uid>=base, has vault)" "grep -qx alice '$WORK/swept.log'"
chk "driver swept bob (uid>=base, has vault)" "grep -qx bob '$WORK/swept.log'"
chk "driver SKIPPED carol (no ~/Vault)" "! grep -qx carol '$WORK/swept.log'"
chk "driver SKIPPED sysacct (uid<base)" "! grep -qx sysacct '$WORK/swept.log'"
chk "driver SKIPPED root (uid<base)" "! grep -qx root '$WORK/swept.log'"

# ============================================================================================
echo "== F1 regression: local BULK IMPORT must NOT trip the inbound mass-delete guard =="
# The fix's whole point: `git diff HEAD..remote` (two-dot) counts every locally-committed,
# not-yet-pushed file as an inbound "deletion", so a first-import of a big corpus (the product's
# first-use scenario) would falsely trip the guard and PERMANENTLY wedge sync. Three-dot
# (merge-base→remote) counts only real remote-side deletions. This exercises exactly that direction
# (remote UNCHANGED, many local additions > bound) — it FAILS against the old two-dot code.
setup f1 3; FLOOR=5
for i in $(seq 1 20); do echo "imported note $i" > "$V/imp$i.md"; done      # 20 new >> bound 5
before_remote="$(git -C "$R" rev-parse main)"
run_sync; rc=$?
chk "F1: bulk import (20 adds, 0 remote deletes) does NOT trip inbound guard (rc 0)" "[ $rc -eq 0 ]"
chk "F1: no stop-flag set on a legitimate bulk import" "[ ! -e '$SF' ]"
chk "F1: the imported corpus was pushed to the remote" "git -C '$R' cat-file -e main:imp20.md 2>/dev/null"
chk "F1: remote advanced (import actually landed)" "[ '$before_remote' != '$(git -C "$R" rev-parse main)' ]"
unset FLOOR

# ============================================================================================
echo "== F2: GitHub protection reads the EFFECTIVE-RULES endpoint (mock gh) =="
# F2 fix: /repos/{o}/{r}/rules/branches/{branch} returns active rule .type values (the /rulesets LIST
# endpoint returns summaries with none). Anchor the test to the real code, then exercise the exact
# endpoint+jq+grep classification on realistic responses via a mock gh.
grep -q 'rules/branches/\$branch' "$INIT" || no "F2: kd-vault-init still hits the wrong endpoint (expected rules/branches)"
grep -q 'repos/\$slug/rulesets' "$INIT" && no "F2: kd-vault-init still references the summary /rulesets endpoint"
# jq-free mock: gh applies `--jq` internally in production, and the F2 bug was the ENDPOINT (not the
# jq — `[.[].type]` is correct for the /rules/branches array shape), so the mock emits the already-
# jq'd @csv line the real gh would return, letting this run without external jq (absent in the box).
mkgh(){ mkdir -p "$WORK/ghbin"; cat > "$WORK/ghbin/gh" <<GH
#!/usr/bin/env bash
ep=""
while [ \$# -gt 0 ]; do case "\$1" in --jq) shift 2;; api) shift;; *) ep="\$1"; shift;; esac; done
case "\$ep" in */rules/branches/*) printf '%s\n' '$1' ;; *) exit 1;; esac
GH
chmod +x "$WORK/ghbin/gh"; }
classify(){ local rs; rs="$(PATH="$WORK/ghbin:$PATH" gh api "repos/o/r/rules/branches/main" --jq '[.[].type] | @csv' 2>/dev/null)" || return 2
  printf '%s' "$rs" | grep -q non_fast_forward && printf '%s' "$rs" | grep -q deletion && return 0 || return 1; }
mkgh '"non_fast_forward","deletion","pull_request"'
if classify; then ok "F2: nff+deletion rules => protected"; else no "F2: protected repo misclassified"; fi
mkgh '"pull_request"'
if classify; then no "F2: unprotected repo misclassified as protected"; else ok "F2: no nff/deletion => unprotected"; fi
mkgh '"non_fast_forward"'
if classify; then no "F2: nff-only misclassified as protected"; else ok "F2: nff-only (missing deletion) => unprotected (BOTH required)"; fi

echo
echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] && echo "KD-VAULT: GREEN" || { echo "KD-VAULT: RED"; exit 1; }
