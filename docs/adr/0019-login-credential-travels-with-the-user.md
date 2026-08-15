# The login credential travels with the user as public data; visibility picks the hash strength

**Status:** Accepted. Refines the "hashedPassword handling by repo visibility" note of the repo-split capstone (issue #1) and constrains the greeter ([ADR-0006](0006-anyhost-greeter-runtime-binding.md), issue #2). No contract change: `hashedPassword` already rides `identity.json` ([ADR-0007](0007-user-flake-shape.md)) and `realization.nix` already sets `users.users.<u>.hashedPassword` from it.

A user is **completely self-contained, including their login credential** — the load-bearing
invariant behind the north star's **any host × any user** ([ADR-0018](0018-session-type-derives-from-desktop.md) names the north star; [ADR-0006](0006-anyhost-greeter-runtime-binding.md) is the roaming path). A user roams to a seat it has **never met**, carrying only a flake URL + username + password. The instant a *host* owns any part of a user — its password, a re-keyed secret — that host must have known the user in advance, and a stranger-seat can no longer serve them. **No host may own a user artifact.**

This forces where the login credential can live. The greeter authenticates **eval-free** ([ADR-0006](0006-anyhost-greeter-runtime-binding.md), data-before-code): `contract-greeter-auth` runs `jq -r '.hashedPassword' identity.json` and re-hashes the typed password with libc `crypt` — *before* evaluating any of the user's Nix. The only inputs present at a fresh seat are **the user's public repo + the password the person types**. So the credential must be **data the user carries**, verifiable with nothing else.

## The tension, and why the host-anchored escapes are closed

A public/shared user repo that carries `hashedPassword` **publishes an offline-crackable hash**. The instinct is to encrypt it. But every way to encrypt the *login* hash breaks the invariant or is vacuous:

- **Host-supplied** (`hashedPasswordFile` from the seat's own secret store) — the host owns the credential ⇒ it must pre-know the user ⇒ no roaming.
- **User-repo sops re-keyed to binding-host keys** — the same border crossing, hidden: the user's password file names specific host age keys as recipients, so the user can only be bound on seats whose keys were baked in ahead of time. A greeter holds a *password, not the seat's private key*, so a roamed-to seat can never be a recipient.
- **Encrypt the hash to something password-derived** — vacuous: anyone with the password decrypts it, and the hash's one job is to verify that same password.

There is no cryptographic escape: at a strange seat the hash must be verifiable from public data + the password alone, which means the hash is, in effect, **public**.

## Decision

**The login credential travels with the user in `identity.json` as data, on both binding paths. Repo visibility selects the hash *strength* and the key-wrapping *posture*, not the credential's location.**

- **Private repo** — any libc-`crypt` hash (`$6$` sha512crypt is fine); enabling the user stays crypto-free (no key management).
- **Public / shared repo** — **yescrypt** (`$y$`): a deliberately memory-hard, expensive KDF, so the public hash resists offline cracking. **And** the seat runs `separatePassphrase = true` ([ADR-0015](0015-greeter-secret-provisioning.md)) so the login password does **not** also wrap the user's age key — the age key is passphrase-wrapped independently (`greeter/unlock.nix`), stronger than the login secret.

The public hash is **correct, not a leak**. It verifies a password; it **decrypts nothing**. The user's actual secrets — feature secrets like `signing` — stay **user-key-encrypted** in the user's own secrets store (issue #1 T2), and the age key that unlocks them is passphrase-wrapped. "Protect the user's secrets with sops" applies to *those*, never to the login hash.

This **refines** issue #1's shorthand "sops + yescrypt for a public repo": the *yescrypt* part stands; the *sops* part belongs to the user's feature secrets and passphrase-wrapped age key, not to the login hash, which sops cannot protect without re-introducing a host border crossing.

## Consequences

- The contract is unchanged; there is no `hashedPasswordFile` seam (it would have been a host-owned credential — precisely the border crossing this forbids).
- The visibility decision is a **user-repo authoring** choice (which hash algorithm `identity.json` ships) plus the **seat's** `separatePassphrase` default — no host ever holds the credential.
  *(Amendment, issue #35: because the posture is conditional and repo-owned, `loadIdentity` imposes **no** hash policy — baking yescrypt into the loader would impose a public repo's posture on every consumer, including the untrusted roaming single-user flakes the greeter exists for. The contract instead ships `lib.mkIdentityPostureCheck { identities; require; pkgs }`, an **opt-in** check a repo calls over its own roster with the posture it has chosen (`require = "yescrypt"` for a public one). No decision changes here; the check only makes this ADR's rule enforceable in one line per repo instead of a hand-typed prefix test.)*
- For `inkpotmonkey` (public): re-hash the password `$6$ → $y$` with `mkpasswd -m yescrypt` and ship it in `identity.json`; the seat keeps `separatePassphrase = true`.
- The greeter (issue #2) needs no special case for a public-repo user: `identity.json.hashedPassword` is present exactly as its eval-free auth already expects.
