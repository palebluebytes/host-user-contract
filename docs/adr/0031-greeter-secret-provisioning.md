# Greeter secret provisioning is one seam — "make the user's key available for the session" — with a staged strength spectrum

**Status:** Accepted (the scope, the seam, and the v1 mechanism); the phone-gated upgrade is planned and the hardware binding is recorded **on-demand only**. Implements issue #4; Tier-1-only refinement of [ADR-0022](0022-anyhost-greeter-runtime-binding.md), gated by [ADR-0015](0015-host-user-contract.md)'s exposed-host ban and built on the [ADR-0021](0021-platform-backend-agnostic-secrets.md) platform seam.

The greeter authenticates on a **password, not a key** (ADR-0022 "data before code"). So a roaming user's **own home secrets** (their sops — API keys, git-annex, a self-managed signing key) cannot decrypt at a greeter login: they need the user's **private key**, which a host the user has never provisioned does not have. Today the greeter degrades gracefully (ADR-0022 Q4) — secret-bearing parts go dormant, the user gets a clean secret-free baseline. This ADR records how a Tier-1 user gets their secrets **back** without weakening the model.

Two clarifications frame everything:

- **This is *not* about contract secret-features** (`signing`, …). Those are secret-bearing ⇒ excluded from the safe set ⇒ build-time-only ([ADR-0018](0018-user-confinement-manifest-greeter.md)), and stay that way — they involve **host** re-key/recipients. This ADR is the *other* kind: the **user's own home sops**, which decrypt with the **user's** key. The safe set and `greeterGrants` do **not** change.
- **The trusted seat sees the decrypted plaintext.** It builds and activates the home, so it necessarily holds the secrets *for the session*. No mechanism below changes that. Hardware/phone protect the **key** (it can't be stolen or used without you), not the **session plaintext** from a malicious trusted seat. This is why the whole feature is **trusted-seat-only**, full stop.

## Decision

**1. Scope — Tier-1, trusted seat, never exposed.**
Secret provisioning is a **Tier-1** concern only (own, *signed* repo, ADR-0022/0027). It is **refused on exposed/agent hosts** (the ADR-0015 exposed-host ban is absolute — an agent box must never hold user key material) and **refused at Tier-2** (a stranger's session stays ephemeral + secret-free). It is opt-in per seat and off by default.

**2. The seam — one step, behind the platform binding.**
The contract ships exactly one new step: **"make the user's age identity available to home activation for this session,"** then activate the home (which sops decrypts) as `provision` already does. *How* the identity is obtained is a **platform binding** (ADR-0021), so the contract stays package-free and backend-neutral (sops today, agenix later). The user's repo carries the material as **inert data the eval-free auth path already reads** (a `wrappedKey` convention, the same posture as `identity.json`). Every mechanism below is just a different binding for this one step — so strength is a per-user/per-seat choice, not a redesign.

**3. The v1 mechanism — password-unlocked age key.**
Default, because it needs **no infrastructure** and **travels with the identity** (the portable-user north star, ADR-0028): the repo carries the user's age private key **encrypted with argon2id(passphrase)**; post-auth the greeter derives the key and decrypts it, then home activation proceeds. Two guardrails on it:
- **Decouple login from unlock.** The login password is also a brute-force target (it backs `hashedPassword`), and the wrapped key is *public* (offline-brute-forceable). Support a **separate, stronger unlock passphrase** prompted after auth; allow reuse for convenience but default to distinct + heavy argon2id.
- It is **acceptable only for your-own-Tier-1 with a strong passphrase** — its security *is* the passphrase + KDF cost.

**4. The strength spectrum — same seam, opt into stronger.**

| Binding | Brute-force resistant | Carry | Roams with | Status |
| --- | --- | --- | --- | --- |
| Password-wrapped key (a) | ✗ (passphrase only) | nothing | URL + password | **v1 default** |
| Phone-gated escrow (c/e) | ✓ (online, rate-limited) | phone | URL + phone | **planned upgrade** |
| FIDO2 / YubiKey (d) | ✓ (offline, hardware) | a token | URL + token | **idea — on demand only** |

- **Phone-gated escrow** is the recommended upgrade for high-value keys: the wrapped key (or a share) lives on the user's **own trusted server**, released to the seat only after a **phone approval** (a WebAuthn/passkey assertion — phones do this well — or a tapped push). This removes the public key entirely (no offline brute-force, online rate-limiting) while still roaming with something you already carry.
- **FIDO2 / YubiKey** (via `age-plugin-fido2-hmac` or `age-plugin-yubikey`) is the strongest — the key never leaves the device, decryption needs physical presence + touch + PIN, and both emit ordinary age identities that drop straight into the sops convention. It is **recorded here as a future binding and implemented ON DEMAND only**: it requires carrying a dedicated token, which partly defeats "roam to any host with just a URL + password," so it is not built proactively. (Using a *phone* as the direct decryption device — the WebAuthn **PRF** analogue of `hmac-secret` — is emerging but not yet dependable cross-device, so the phone's role is the **gate** in escrow, not the key store.)

## Consequences

- A new bind step (e.g. `contract-greeter-unlock`) sits between auth and provision; like every greeter script it references crypto tools (argon2, age) from the **seat's** `pkgs`, so the contract flake stays lib-only (ADR-0020).
- The `wrappedKey` convention joins `identity.json` as contract-owned, jq-readable inert data — never evaluated as Nix.
- The proof reuses the **[[bind-loop]]** VM infrastructure (ADR-0022, `conformance/bind-loop-vm.nix`): a fixture home with a sops secret + a password-wrapped key, asserting the secret **decrypts and lands in the activated home** at login — plus negative tests that it **refuses on an exposed host** and **at Tier-2**.
- The platform binding (ADR-0021) gains a "user session key" responsibility (where to place the decrypted age identity for activation), composing cleanly with its existing secret-path role.
- The contract secret-features (`signing`) and the safe set are **unchanged** — this ADR adds a parallel, user-owned path, it does not relax the build-time grant model.

## Considered Options

The full menu is enumerated in issue #4; the decision picks (a) as v1 and stages the rest behind the shared seam.

- **(a) Password-unlocked key in the repo** — chosen as v1: self-contained, portable, no infrastructure. Cost: password-compromise ⇒ key-compromise and an offline-brute-forceable public blob, mitigated by a separate strong passphrase + heavy KDF.
- **(b) Password-derived key (no stored key)** — rejected for v1: same password=key exposure as (a) but rotating the password re-keys everything; (a)'s stored-wrapped-key is more operable.
- **(c)/(e) Fetch / escrow from the user's trusted store, phone-gated** — adopted as the **planned upgrade**: removes the public key and rate-limits release. Cost: needs the user's server reachable + a release-auth (a phone passkey/push is the clean fit).
- **(d) Hardware second factor (FIDO2 / YubiKey)** — **on-demand only**: strongest, but requires carrying a token, which cuts against roam-with-URL+password. Recorded as a ready binding to add when a user asks for it, not built proactively.
- **Provision secrets on any seat / Tier-2** — rejected outright: the trusted seat sees plaintext, so this is indefensible on an exposed or stranger host (ADR-0015).

## Update (2026-06-24) — escrow refined by a design grill (issue #11/#13)

The first escrow cut shipped a contract HTTP client (`contract-greeter-fetch-key` pinning `POST /request` + poll `GET /key`). A grill against the domain model and the prior art reshaped it:

- **The fetch is a host-bound `keyFetcher` command, not a contract-pinned protocol.** Every other backend the contract does not own is a host binding (`homeBuilder`, the display backend, the `platform` interface) — a *command/interface*, never a wire format. Escrow follows suit: the contract calls `keyFetcher <username>` → the wrapped key on stdout; the request/poll HTTP loop drops to the **reference example** (and stays as the conformance fixture, labelled "test stub, not production"). The contract no longer dictates any server's wire format.
- **The reference server composes audited pieces, it is not bespoke crypto.** No single drop-in does "phone-approved, number-matched, one-time-token release" turnkey, but the hard halves exist: **[OpenBao](https://openbao.org/)** (the open Vault fork) gives **response-wrapping** = a one-time, short-TTL, *requester-bound* release token + storage for free; **[ntfy](https://ntfy.sh/)** gives the **push + tap-to-approve** (HTTP action buttons). The reference (#13) is a thin orchestrator gluing them, with the only bespoke bit being **number-matching** + the `keyFetcher` endpoints. (A workflow engine like n8n/Dagu is a no-code alternative glue.)
- **Hardened per prior art.** Two holes the naive protocol has — push-harassment/blind-approve and a post-release polling race — are fixed by **number-matching** ([Duo Verified Push](https://duo.com/blog/verified-duo-push-makes-mfa-more-secure)/[CISA](https://www.cisa.gov/sites/default/files/publications/fact-sheet-implement-number-matching-in-mfa-applications-508c.pdf)) and a **one-time requester-bound token** ([Vault response-wrapping](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping)). Approval factor is a choice: **`number-match` (default), `tap` (opt-down, convenience), `passkey` (opt-up, WebAuthn)**. The gold standard — a server that **holds no usable secret** ([Tang/Clevis McCallum-Relyea](https://access.redhat.com/articles/6987053)) — is noted as a future hardening; v1 holds the *wrapped* key (server-gate + passphrase = two factors).
- **Degradation fails closed on SECRETS, never on the login.** When the server is unreachable: the **default degrades to a secret-free session** (ADR-0022 Q4) — it can only *deny* you your secrets, never leak them, so it does not weaken escrow. **No in-repo passphrase fallback is offered for an escrow user** — that *would* undermine escrow (a downgrade attack: block the server to force the public brute-forceable blob). An optional **`requireSecrets`** policy hard-fails the login for workloads that must not run secret-free — an *availability* choice, not a confidentiality one (the session is gated by the login password, secrets by escrow; they are separate gates).
