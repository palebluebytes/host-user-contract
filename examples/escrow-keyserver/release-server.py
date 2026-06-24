#!/usr/bin/env python3
# Reference escrow release server (issue #13, ADR-0031) — an EXAMPLE, not contract code.
#
# It is the user's own key-release service that the greeter's `keyFetcher` host binding talks to. It
# composes the prior-art patterns the grill settled on (see ADR-0031 update):
#
#   - one-time, requester-bound release token  (Vault/OpenBao response-wrapping):  /request mints a
#       random token; the key is collected ONCE via GET /key/<token> and then destroyed — so a race on
#       /key cannot steal it and a stale request self-expires (TTL).
#   - number-matching                          (Duo Verified Push):  /request mints a short number shown
#       on the SEAT; the phone approval must echo that number, so a user cannot be spammed into
#       blind-approving an attacker's request.
#   - phone push                               (ntfy):  the approval prompt is pushed to the phone; the
#       phone authorizes by signing the server's challenge (registered ed25519 key = the "passkey").
#
# Two seams keep it composable rather than bespoke:
#   - STORAGE — where the user's wrapped key lives. The demo uses an in-memory store seeded from a file;
#       in PRODUCTION back this with OpenBao (store the wrapped key; `bao kv` + response-wrapping gives
#       the one-time token for free). See README.
#   - PUSH    — how the phone is notified. If NTFY_URL is set, POST the prompt to ntfy; otherwise write
#       it to NTFY_CAPTURE (used by the test as a stand-in for the phone's inbox).
#
# Approval factor is configurable (APPROVAL = number-match | tap | passkey); the default is number-match.
# The wrapped key is opaque bytes — the server never sees the user's plaintext (that is the seat's job,
# on a trusted Tier-1 host only).

import base64
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.request
from http.server import BaseHTTPRequestHandler
from socketserver import TCPServer, ThreadingMixIn

PORT = int(sys.argv[1])
PHONE_PUBKEY = sys.argv[2]  # PEM ed25519 public key of the registered phone
APPROVAL = os.environ.get("APPROVAL", "number-match")  # number-match | tap | passkey
TTL_SECONDS = int(os.environ.get("RELEASE_TTL", "120"))
NTFY_URL = os.environ.get("NTFY_URL", "")  # production: an ntfy topic URL
NTFY_CAPTURE = os.environ.get("NTFY_CAPTURE", "")  # test: a file the "phone" reads


# --- STORAGE seam: the user's wrapped key. Demo = in-memory from a file; prod = OpenBao (see README). ---
class Store:
    def __init__(self, path):
        self.keys = {}
        if path and os.path.exists(path):
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    user, b64 = line.split(":", 1)
                    self.keys[user] = base64.b64decode(b64)

    def wrapped_key(self, user):
        return self.keys.get(user)


STORE = Store(sys.argv[3] if len(sys.argv) > 3 else "")

# pending releases, keyed by the one-time token
PENDING = {}  # token -> {user, challenge, number, expires, released, key}


def push(user, number, token):
    # The phone prompt. number-match shows the number to enter; tap/passkey just approve.
    body = "Approve key release for %s" % user
    if APPROVAL == "number-match":
        body += " — match number %s" % number
    payload = json.dumps(
        {"user": user, "number": number, "token": token, "approval": APPROVAL}
    )
    if NTFY_URL:
        req = urllib.request.Request(
            NTFY_URL, data=body.encode(), headers={"X-Title": "key release"}
        )
        urllib.request.urlopen(req, timeout=5).read()
    if NTFY_CAPTURE:
        with open(NTFY_CAPTURE, "w") as f:
            f.write(payload)


def verify_sig(challenge, sig):
    cf = tempfile.NamedTemporaryFile(delete=False)
    cf.write(challenge)
    cf.close()
    sf = tempfile.NamedTemporaryFile(delete=False)
    sf.write(sig)
    sf.close()
    r = subprocess.run(
        [
            "openssl",
            "pkeyutl",
            "-verify",
            "-pubin",
            "-inkey",
            PHONE_PUBKEY,
            "-rawin",
            "-in",
            cf.name,
            "-sigfile",
            sf.name,
        ],
        capture_output=True,
    )
    os.unlink(cf.name)
    os.unlink(sf.name)
    return r.returncode == 0


def reap():
    now = time.time()
    for tok in [t for t, p in PENDING.items() if p["expires"] < now]:
        PENDING.pop(tok, None)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        return

    def reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def body_bytes(self):
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n) if n else b""

    def do_POST(self):
        reap()
        p = self.path.strip("/").split("/")
        if len(p) == 2 and p[0] == "request":
            user = p[1]
            if STORE.wrapped_key(user) is None:
                return self.reply(404, b"no key for user")
            token = secrets.token_urlsafe(24)
            number = "%02d" % secrets.randbelow(100)
            challenge = secrets.token_bytes(32)
            PENDING[token] = {
                "user": user,
                "challenge": challenge,
                "number": number,
                "expires": time.time() + TTL_SECONDS,
                "released": False,
                "key": None,
            }
            push(user, number, token)
            # The seat shows `number` to the user for matching; `challenge` is what the phone signs.
            return self.reply(
                200,
                json.dumps(
                    {
                        "token": token,
                        "number": number,
                        "challenge": base64.b64encode(challenge).decode(),
                    }
                ).encode(),
            )
        if len(p) == 2 and p[0] == "approve":
            token = p[1]
            st = PENDING.get(token)
            if not st:
                return self.reply(404)
            try:
                msg = json.loads(self.body_bytes())
                sig = base64.b64decode(msg.get("signature", ""))
                number = msg.get("number", "")
            except Exception:
                return self.reply(400)
            if APPROVAL == "number-match" and number != st["number"]:
                return self.reply(403, b"number mismatch")
            if APPROVAL in ("number-match", "passkey") and not verify_sig(
                st["challenge"], sig
            ):
                return self.reply(403, b"bad signature")
            st["released"] = True
            st["key"] = STORE.wrapped_key(st["user"])
            return self.reply(200, b"approved")
        return self.reply(404)

    def do_GET(self):
        reap()
        p = self.path.strip("/").split("/")
        if len(p) == 2 and p[0] == "challenge":
            st = PENDING.get(p[1])
            if not st:
                return self.reply(404)
            return self.reply(200, base64.b64encode(st["challenge"]))
        if len(p) == 2 and p[0] == "key":
            token = p[1]
            st = PENDING.get(token)
            if st and st["released"]:
                key = st["key"]
                PENDING.pop(token, None)  # ONE-TIME: destroy after collection
                return self.reply(200, key)
            return self.reply(404)
        return self.reply(404)


class Server(ThreadingMixIn, TCPServer):
    allow_reuse_address = True
    daemon_threads = True


Server(("127.0.0.1", PORT), Handler).serve_forever()
