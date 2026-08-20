# A user is self-contained, and the login credential travels with them

**Status:** Accepted (2026-08-20). The invariant behind *any host × any user*; constrains
[0005](0005-identity-is-inert-data.md) and [0018](0018-greeter-runtime-flow.md).

The north star is that a person roams to a seat they have **never met**, carrying a flake URL, a
username and a password, and gets their own session. The instant a *host* owns any part of a
user — their password, a re-keyed secret, a pre-registered account — that host must have known them
in advance, and a stranger-seat can no longer serve them.

> **No host may own a user artifact.**

This forces where the login credential can live. A greeter authenticates before it evaluates
anything ([0005](0005-identity-is-inert-data.md)), and the only inputs present at a fresh seat are
**the user's public repo and the password the person types**. So the credential must be data the
user carries, verifiable with nothing else.

## The tension, and why every escape is closed

A public users repo carrying `hashedPassword` **publishes an offline-crackable hash**. The instinct
is to encrypt it. Every way of doing so either breaks the invariant or is vacuous:

- **Host-supplied** (a `hashedPasswordFile` from the seat's own secret store) — the host owns the
  credential, so it must pre-know the user. No roaming.
- **Encrypted in the user repo to binding-host keys** — the same border crossing, hidden. The user's
  credential names specific host keys as recipients, so they can only be bound on seats chosen in
  advance. A greeter holds a *password*, never the seat's private key, so a roamed-to seat can never
  be a recipient.
- **Encrypted to something password-derived** — vacuous: anyone with the password decrypts it, and
  the hash's one job is to verify that same password.

There is no cryptographic escape. At a strange seat the hash must be verifiable from public data
plus the password alone, which means the hash is, in effect, **public**.

## Decision

**The login credential travels with the user as data. Repo visibility selects the hash *strength*,
never the credential's location.**

- **Private repo** — any libc-`crypt` hash. Enabling a user stays crypto-free.
- **Public or shared repo** — **yescrypt** (`$y$`): deliberately memory-hard, so a published hash
  resists offline cracking.

The public hash is **correct, not a leak**: it verifies a password and decrypts nothing.

## The posture is the consumer's, and the contract will not impose it

`loadIdentity` imposes **no** hash policy. Baking yescrypt into the loader would impose a public
repo's posture on every consumer, including the private single-user flakes a greeter also serves.
Instead the contract ships `mkIdentityPostureCheck { identities; require; pkgs }` — an **opt-in**
check a repo runs over its own members with the posture it has chosen. The rule becomes enforceable
in one line per repo without the contract deciding for anyone.

## Consequences

- There is no `hashedPasswordFile` seam, and there will not be one: it is a host-owned credential by
  construction.
- **A shared users repo makes every member's hash public together.** A person needing a different
  visibility posture does not belong in it — they get their own repo, which is a literal directory
  move, because nothing in the layout links a user to their neighbours.
- A greeter needs no special case for a public-repo user: the hash is present exactly where its
  eval-free auth already looks.

## Considered alternatives

- **Encrypt the credential, any of the three ways above** — rejected: each either hands a host
  ownership of a user artifact or is circular.
- **Put the credential outside the user repo entirely** (a fleet-side account store) — rejected: it
  is the host-owned case wearing a different name, and it makes "any host" false by construction.
