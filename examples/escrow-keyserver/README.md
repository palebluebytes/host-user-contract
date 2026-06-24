# Reference escrow keyserver

A reference implementation of the **escrow** source for greeter secret provisioning (issue #13,
[ADR-0031](../../docs/adr/0031-greeter-secret-provisioning.md)). It is an **example, not contract
code** — the contract ships only the `keyFetcher` *seam* (ADR-0020); this is one way to fill it.

When a roaming user picks `secretProvisioning.method = "escrow"`, their wrapped age key lives **off
their repo**, on their own server, and is released to a seat only after a **phone approval**. That
removes the public, offline-brute-forceable blob the passphrase method (#10) carries. The fetched key
is still passphrase-unlocked, so escrow is **two factors: the phone gate + the passphrase**.

## The two pieces

- **`key-fetcher`** — the seat side. Bind it to `custom.greeter.secretProvisioning.keyFetcher`; the
  greeter calls it `key-fetcher <username>` and captures stdout. It requests a release, shows the
  user a **match number**, and polls the one-time key endpoint — streaming bytes through a file, so a
  binary wrapped key is never corrupted.
- **`release-server.py`** — the user's release service. Holds wrapped keys, pushes an approval to the
  phone, and releases a key only after a valid, **number-matched**, signed approval — via a
  **one-time, requester-bound token** so a stale request expires and a race on the key cannot steal it.

## What it composes (don't hand-roll these in production)

| Concern | Pattern | Production backend |
| --- | --- | --- |
| storage + one-time release token | Vault/OpenBao response-wrapping | **[OpenBao](https://openbao.org/)** — store the wrapped key; `bao` response-wrapping gives the one-time token for free |
| push to the phone | action-button notification | **[ntfy](https://ntfy.sh/)** — set `NTFY_URL` to your topic |
| approve binds to *this* request | Duo Verified Push number matching | built in (`APPROVAL=number-match`, the default) |

The demo server uses an in-memory store and an in-process token table to make the pattern runnable and
testable; in production swap the storage seam for OpenBao and the push seam for ntfy (both are seams in
`release-server.py`).

## Deploy (sketch)

1. **Register the phone**: generate an ed25519 keypair on/for the phone; give the server its public
   key (PEM). The phone signs the server's challenge to authorize a release (a passkey/WebAuthn
   assertion in a real app).
2. **Store the user's wrapped key**: `printf 'alice:%s\n' "$(base64 -w0 alice-key.wrapped)" >> store`
   (or, in production, `bao kv put …`).
3. **Run the server** behind **HTTPS** (the wrapped key crosses the network):
   `NTFY_URL=https://ntfy.example/alice-keys python3 release-server.py 8443 phone.pub store`.
4. **Wire the seat** (a trusted Tier-1 host only — never an exposed/agent host):

   ```nix
   custom.greeter.secretProvisioning = {
     enable = true;
     method = "escrow";
     keyFetcher = "${./key-fetcher}";   # + CONTRACT_KEYFETCHER_URL=https://keys.example in its env
     # requireSecrets = true;           # optional: refuse the login if the key can't be obtained
   };
   ```

## Approval factor

`APPROVAL` selects the gate: **`number-match`** (default — match a code shown on the seat, defeats
push-fatigue), **`tap`** (just approve — simplest, weaker), **`passkey`** (WebAuthn assertion —
strongest). All keep the one-time token + signed approval.

## Posture & guarantees

- **Trusted Tier-1 seat only.** The seat decrypts the key into the home; an exposed/agent host must
  never run this (the greeter refuses it — ADR-0015/ADR-0031).
- **HTTPS required** by `key-fetcher` (loopback is allowed only for the demo/test).
- **Fail closed on secrets**: if the server is unreachable / no approval, the login degrades to a
  secret-free session (or fails if `requireSecrets`). There is no in-repo fallback (a downgrade attack).

## Test

`nix build .#checks.x86_64-linux.escrow-keyserver` runs `gate-test.nix`: a keypair-controlled "phone"
proves a valid number-matched approval releases the key **byte-exact**, while a wrong number, an
attacker signature, and a reused one-time token are all refused — no real phone needed.
