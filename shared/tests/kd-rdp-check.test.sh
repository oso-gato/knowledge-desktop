#!/usr/bin/env bash
# kd-rdp-check.test.sh — in-box unit proof of the WP-20 RDP-handshake probe (C2). Spins stdlib mock
# servers and asserts kd-rdp-check's rc-exact contract, INCLUDING the crux that motivated it: a bare
# TCP listener (which the retired `exec 3<>/dev/tcp` connect passed identically to a real server) now
# FAILS (rc 1), while a server that speaks a valid X.224 Connection Confirm passes (rc 0). The CC-mode
# mocks also VALIDATE the client's Connection Request, so a GREEN also proves kd-rdp-check emits a
# well-formed TPKT/X.224 CR. No container, no root, no network fixture.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
PROBE="${KD_RDP_CHECK:-$here/../../gate/probe/kd-rdp-check}"
[ -f "$PROBE" ] || { echo "FATAL: kd-rdp-check not found at $PROBE" >&2; exit 2; }

srv="$(mktemp)"; trap 'rm -f "$srv"' EXIT
cat > "$srv" <<'PY'
import socket, sys, struct
mode = sys.argv[1]
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(1)
print(srv.getsockname()[1], flush=True)          # tell the harness the ephemeral port


def cc(neg):                                       # build a TPKT-framed X.224 Connection Confirm
    x = struct.pack("!BHHB", 0xD0, 0, 0, 0) + neg  # CC-CDT=0xD0, DST/SRC-REF=0, CLASS=0
    x = bytes([len(x)]) + x                         # prepend LI
    return struct.pack("!BBH", 0x03, 0x00, 4 + len(x)) + x


c, _ = srv.accept()
try:
    req = c.recv(64)
    # A well-formed RDP CR is TPKT 0x03 ... X.224 CR-CDT 0xE0 at offset 5. For the CC modes, reply
    # only to a valid CR — a malformed CR draws silence, so the test fails loudly if our CR is wrong.
    valid_cr = len(req) >= 6 and req[0] == 0x03 and req[5] == 0xE0
    if mode == "negrsp" and valid_cr:
        c.sendall(cc(struct.pack("<BBHI", 0x02, 0, 8, 0x00000001)))   # rdpNegRsp selected=SSL
    elif mode == "negfail" and valid_cr:
        c.sendall(cc(struct.pack("<BBHI", 0x03, 0, 8, 0x00000002)))   # rdpNegFailure (still a CC)
    elif mode == "plaincc" and valid_cr:
        c.sendall(cc(b""))                                            # old-style plain CC, no neg
    elif mode == "bare":
        pass                                                          # accept, say nothing (dumb listener)
    elif mode == "garbage":
        c.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")                # a non-RDP service
    # (any unmatched mode / invalid CR: send nothing)
finally:
    c.close()
PY

fails=0
one() {  # <mode> <expected_rc> <label>
    local mode="$1" exp="$2" label="$3" pf port="" i rc
    pf="$(mktemp)"
    python3 "$srv" "$mode" >"$pf" 2>/dev/null &
    local spid=$!
    for i in $(seq 1 60); do port="$(head -1 "$pf" 2>/dev/null)"; [ -n "$port" ] && break; sleep 0.05; done
    if [ -z "$port" ]; then echo "FAIL[$label]: mock server did not start"; fails=$((fails+1)); rm -f "$pf"; return; fi
    "$PROBE" 127.0.0.1 "$port" >/dev/null 2>&1; rc=$?
    wait "$spid" 2>/dev/null
    rm -f "$pf"
    if [ "$rc" = "$exp" ]; then echo "PASS[$label]: rc=$rc"; else echo "FAIL[$label]: expected rc=$exp got rc=$rc"; fails=$((fails+1)); fi
}

# real RDP servers (a valid X.224 CC in three shapes) -> rc 0
one negrsp  0 "real-RDP rdpNegRsp -> accepted"
one negfail 0 "real-RDP rdpNegFailure -> accepted (a Failure CC still proves RDP)"
one plaincc 0 "real-RDP plain CC (no neg) -> accepted"
# the crux: a bare listener the old connect passed, and a non-RDP banner -> rc 1 (not a false pass)
one bare    1 "bare TCP listener -> NOT RDP (the retired connect passed this)"
one garbage 1 "non-RDP HTTP banner -> NOT RDP"
# nothing listening -> rc 2 (a connection error never masquerades as a clean not-RDP)
closed_port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
"$PROBE" 127.0.0.1 "$closed_port" >/dev/null 2>&1; crc=$?
if [ "$crc" = 2 ]; then echo "PASS[closed port -> CONN ERROR]: rc=2"; else echo "FAIL[closed port]: expected rc=2 got rc=$crc"; fails=$((fails+1)); fi

echo "----"
if [ "$fails" = 0 ]; then echo "kd-rdp-check.test.sh: ALL GREEN"; exit 0; fi
echo "kd-rdp-check.test.sh: $fails FAILURE(S)"; exit 1
