#!/usr/bin/env bash
# gate/lint.sh — static lints (WP-01; CI `lint` job + local pre-PR check).
# Present-tolerant by design: sections for artifacts of LATER work packages (deploy/*.container,
# WP-03) run only when those files exist — loud when present, silent when not (never a stub PASS).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
err(){ echo "LINT FAIL: $*" >&2; fail=1; }

# ---- 1. every shipped shell script parses ----------------------------------------------------
while IFS= read -r f; do
    bash -n "$f" || err "bash -n: $f"
done < <(git ls-files '*.sh')

# ---- 2. .live-gate: parsed-not-sourced schema shape ------------------------------------------
LG=".live-gate"
if [ ! -f "$LG" ]; then
    err ".live-gate missing (the host gate's structural guard needs it)"
else
    # every effective line is a single inert KEY=VALUE assignment
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue;; esac
        printf '%s' "$line" | grep -qE '^[A-Z][A-Za-z0-9_]*=' || err ".live-gate non-assignment line: $line"
    done < "$LG"
    # no cross-variable references (values must be inline; $() inside single quotes is candidate-side)
    grep -nE '="[^"]*\$' "$LG" && err '.live-gate: $-reference inside a double-quoted value (inline it)'
    # every declared target has a CFILE that exists
    targets="$(sed -n 's/^LIVE_GATE_TARGETS="\(.*\)"/\1/p' "$LG")"
    [ -n "$targets" ] || err ".live-gate: LIVE_GATE_TARGETS missing/empty"
    for t in $targets; do
        cf="$(sed -n "s/^CFILE_${t}=\"\(.*\)\"/\1/p" "$LG")"
        [ -n "$cf" ] || { err ".live-gate: CFILE_${t} missing"; continue; }
        [ -f "$cf" ] || err ".live-gate: CFILE_${t}=$cf does not exist"
        grep -q "^HEALTH_${t}=" "$LG" || err ".live-gate: HEALTH_${t} missing"
    done
fi

# ---- 3. Containerfiles: digest-pinned base (N1) -----------------------------------------------
while IFS= read -r cf; do
    grep -qE '^FROM .*@\$\{?FEDORA_DIGEST' "$cf" || err "$cf: FROM is not FEDORA_DIGEST-pinned"
    grep -qE '^ARG FEDORA_DIGEST=sha256:[0-9a-f]{64}$' "$cf" || err "$cf: ARG FEDORA_DIGEST malformed"
done < <(git ls-files '*Containerfile*')

# ---- 4. quadlets (WP-03+): parse + F4 disjointness + .live-gate drift ------------------------
quadlets=$(git ls-files 'deploy/*.container' 2>/dev/null || true)
if [ -n "$quadlets" ]; then
    # F4: PublishPort + Volume names pairwise disjoint across lineage quadlets
    ports=$(grep -h '^PublishPort=' $quadlets | sort); dup=$(echo "$ports" | uniq -d)
    [ -z "$dup" ] || err "F4: duplicate PublishPort across quadlets: $dup"
    vols=$(grep -h '^Volume=' $quadlets | cut -d: -f1 | sort); dupv=$(echo "$vols" | uniq -d)
    [ -z "$dupv" ] || err "F4: duplicate Volume across quadlets: $dupv"
    for q in $quadlets; do
        grep -q '^Secret=kd-roster' "$q" || err "$q: missing Secret=kd-roster line (drift vs SECRETS.md)"
    done
fi

[ "$fail" = 0 ] && echo "LINT PASS" || echo "LINT: failures above"
exit "$fail"
