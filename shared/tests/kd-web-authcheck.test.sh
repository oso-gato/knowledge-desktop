#!/usr/bin/env bash
# kd-web-authcheck.test.sh (WP-20, V9 slice) — IN-BOX unit proof of the web-auth probe's PURE
# response CLASSIFIER (the tricky bit). The LIVE round-trip is host-gate (a running guacamole);
# here we prove that classify() maps every guac /api/tokens response shape to the right verdict —
# so a gate RED/GREEN is trustworthy. Mirrors shared/tests/kd-geometry.test.sh (load the script as
# a module, exercise its pure function against captured/representative fixtures — no boot, no net).
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
from importlib.machinery import SourceFileLoader
import importlib.util as u
loader = SourceFileLoader("kwa", "gate/probe/kd-web-authcheck")
kwa = u.module_from_spec(u.spec_from_loader("kwa", loader)); loader.exec_module(kwa)

fails = []
def ok(cond, msg):
    if not cond: fails.append(msg)

c = kwa.classify

# --- TOKEN: a completed login (200 + authToken) — the ONLY accept ---
tok = '{"authToken":"AAA111","username":"gw1","dataSource":"postgresql","availableDataSources":["postgresql"]}'
ok(c(200, tok) == "TOKEN", "token: 200+authToken -> TOKEN, got %r" % c(200, tok))

# --- CHALLENGE: mandatory second factor. guacamole-auth-totp raises INSUFFICIENT_CREDENTIALS and
#     lists a guac-totp field to supply. Two real shapes: VERIFICATION (enrolled) + ENROLLMENT. ---
verify = ('{"message":"Please enter the authentication code.","type":"INSUFFICIENT_CREDENTIALS",'
          '"expected":[{"name":"guac-totp-code","type":"NUMERIC"}]}')
ok(c(403, verify) == "CHALLENGE", "totp-verify -> CHALLENGE, got %r" % c(403, verify))
enroll = ('{"message":"Scan the QR code.","type":"INSUFFICIENT_CREDENTIALS","expected":['
          '{"name":"guac-totp-init-secret","type":"QR_CODE"},{"name":"guac-totp-code","type":"NUMERIC"}]}')
ok(c(403, enroll) == "CHALLENGE", "totp-enroll -> CHALLENGE, got %r" % c(403, enroll))
# defensive: even if guac ever omitted the type but kept the field name
ok(c(403, '{"expected":[{"name":"guac-totp-code"}]}') == "CHALLENGE", "totp field-only -> CHALLENGE")

# --- REJECT: password refused at the credentials stage — never reaches 2FA, never a token ---
invalid = ('{"message":"Invalid login","type":"INVALID_CREDENTIALS","expected":['
           '{"name":"username","type":"USERNAME"},{"name":"password","type":"PASSWORD"}]}')
ok(c(403, invalid) == "REJECT", "invalid-login -> REJECT, got %r" % c(403, invalid))
ok(c(403, '{"type":"PERMISSION_DENIED","message":"Permission Denied."}') == "REJECT", "perm-denied -> REJECT")
# a bare 403 with no token and no totp marker is still a refusal, not an accept
ok(c(403, '{"message":"nope"}') == "REJECT", "bare-403 -> REJECT, got %r" % c(403, '{"message":"nope"}'))

# --- UNKNOWN: anything the classifier cannot place is NOT a pass (5xx, garbage) ---
ok(c(500, 'Internal Server Error') == "UNKNOWN", "500 -> UNKNOWN, got %r" % c(500, 'x'))
ok(c(200, 'not json and no token') == "UNKNOWN", "200-notoken -> UNKNOWN, got %r" % c(200, 'x'))

# --- the load-bearing DISCRIMINATIONS the gate legs depend on ---
ok(c(200, tok) != c(403, verify), "token and challenge must NOT collide")
ok(c(403, verify) != c(403, invalid), "challenge and reject must NOT collide (the crux)")

if fails:
    print("kd-web-authcheck.test: FAIL")
    for m in fails: print("  - " + m)
    raise SystemExit(1)
print("kd-web-authcheck.test: OK (classifier maps token/challenge/reject/unknown correctly)")
PY
