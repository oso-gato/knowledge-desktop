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

# ---- 1b. every shipped python compiles (kd-provision has no .py suffix: detect by shebang) ----
while IFS= read -r f; do
    head -1 "$f" | grep -q '^#!.*python3' || continue
    python3 -m py_compile "$f" 2>/dev/null || err "py_compile: $f"
done < <(git ls-files)
find . -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null

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
    # WP-02: any inline roster (SECRET_ENV_<t>) must be the SAME roster as the checked-in fixture —
    # single source of truth, so the gate can never drift from what kd-provision's own tests use.
    # Compared as PARSED JSON (key order / whitespace irrelevant); also validates the inline is JSON.
    if command -v python3 >/dev/null 2>&1; then
        while IFS= read -r sekey; do
            t="${sekey#SECRET_ENV_}"; t="${t%%=*}"
            python3 - "$LG" "$t" gate/fixtures/roster-mixed.json <<'PY' || err ".live-gate: SECRET_ENV_${t} does not byte-equal (parsed) gate/fixtures/roster-mixed.json"
import json,sys,re
lg,t,fix=sys.argv[1],sys.argv[2],sys.argv[3]
m=re.search(r"(?m)^SECRET_ENV_%s='(.*)'$"%re.escape(t), open(lg).read())
if not m: sys.exit(1)
try:
    a=json.loads(m.group(1)); b=json.load(open(fix))
except Exception: sys.exit(1)
sys.exit(0 if a==b else 1)
PY
        done < <(grep -oE '^SECRET_ENV_[a-z0-9_]+=' "$LG")
    fi
    # exactly one VNC-door contract: the probe scripts baked into the image must exist in-tree
    for p in gate/probe/kd-vnc-login gate/probe/kd-vnc-check; do
        [ -f "$p" ] || err ".live-gate xrdp PROBE references $p which is not in-tree"
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

    # A2 (C6 — public-surface, BY CONSTRUCTION): podman exposes ONLY PublishPort'd ports to the
    # host/public interface; a container-internal listener (RDP 3389-3391, VNC 5900-5902, SSH 22,
    # the fleet-tile backends) is unreachable from outside unless a quadlet publishes it. So proving
    # the DEPLOY CONTRACT publishes EXACTLY the one web door and NEVER a private door IS the static
    # A2 guarantee — "exactly one endpoint (the web door over HTTPS) reachable from the public
    # internet, every other listener absent". (The live in-candidate listener census — that no ROGUE
    # listener appeared at runtime — is the separate kd-surface-scan probe; this is the by-design
    # half, and unlike a runtime probe it holds for the REAL production deploy contract.) F4's
    # disjointness above only proves the published ports differ across lineages; it never constrained
    # WHICH ports, so a stray `PublishPort=3389:3389` would have passed it. This closes that.
    #   (a) every PublishPort's CONTAINER-side port is 443 — the ONE public door (the Caddy web door)
    #   (b) neither side of any PublishPort is a private door port (RDP 3389-3391 / VNC 5900-5902 / SSH 22)
    #   (c) a netns-JOINED sidecar (Network=<owner>.container) publishes NOTHING — the netns OWNER
    #       declares the door (podman forbids PublishPort on a joined netns; assert the design contract)
    private_ports='3389 3390 3391 5900 5901 5902 22'
    for q in $quadlets; do
        joined=""; grep -qE '^Network=[^=]+\.container$' "$q" && joined=1
        while IFS= read -r pp; do
            [ -n "$pp" ] || continue
            spec="${pp#PublishPort=}"
            # ports are the last two colon-separated fields (an optional leading host-IP is ignored)
            cport="${spec##*:}"; rest="${spec%:*}"; hport="${rest##*:}"
            [ "$cport" = 443 ] || err "A2: $q publishes container port $cport — the only public endpoint is 443 (the web door)"
            for pv in $private_ports; do
                case " $hport $cport " in *" $pv "*) err "A2: $q PublishPort=$spec exposes private door port $pv to the public surface";; esac
            done
            [ -z "$joined" ] || err "A2: $q joins a netns (Network=*.container) yet declares PublishPort=$spec — only the netns OWNER may publish (podman forbids this)"
        done < <(grep '^PublishPort=' "$q")
    done
    for q in $quadlets; do
        grep -q '^Secret=kd-roster' "$q" || err "$q: missing Secret=kd-roster line (drift vs SECRETS.md)"
    done
    # HealthCmd ↔ .live-gate HEALTH drift ([ADJ-34] PR: the old quadlet headers CLAIMED this
    # check existed — now it does). Contract: the .live-gate HEALTH_<target> string must be
    # CONTAINED in the quadlet's HealthCmd line (containment, not equality — the quadlet may
    # shell-wrap it). Present-tolerant per the file-top rule: a quadlet whose target has no
    # HEALTH_<target> key yet is skipped (loud when present, silent when not).
    for q in $quadlets; do
        base="$(basename "$q" .container)"
        case "$base" in
            kd-web-*) tgt="web" ;;
            kd-*)     tgt="${base#kd-}" ;;
            *)        continue ;;
        esac
        health="$(sed -n "s/^HEALTH_${tgt}='\(.*\)'\$/\1/p" "$LG")"
        [ -n "$health" ] || continue
        hc="$(grep '^HealthCmd=' "$q" | head -1)"
        [ -n "$hc" ] || { err "$q: no HealthCmd= line (target $tgt carries a .live-gate HEALTH)"; continue; }
        case "$hc" in
            *"$health"*) ;;
            *) err "$q: HealthCmd drifted from .live-gate HEALTH_${tgt} (must contain: $health)" ;;
        esac
    done
fi

[ "$fail" = 0 ] && echo "LINT PASS" || echo "LINT: failures above"
exit "$fail"
