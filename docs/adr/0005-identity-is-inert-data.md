# Identity is inert data, authenticated before any code runs

**Status:** Accepted (2026-08-20). The ordering the greeter rests on; serves
[0004](0004-user-is-self-contained.md).

A greeter takes a stranger's flake URL and must decide whether the person in front of it may log
in. The decision has to happen **before** any of that repo's Nix is evaluated, because

> **Nix evaluation is not a sandbox.**

Evaluating a module runs every module body: import-from-derivation, arbitrary `builtins.fetch*`,
non-termination. Authenticating *after* evaluation means running a stranger's code to decide whether
they are allowed to run code.

## Decision

**A user's identity is a JSON file, `identity.json`, read with `jq` before any Nix runs.**

```
name · email · username        required
gmail · hashedPassword · sshKey · trustedKeys    optional
```

The greeter's ordering is the decision in one list:

1. **Fetch the source and its whole input closure** — `nix flake archive`, no flake *output*
   evaluated, so no user Nix has run.
2. **Authenticate eval-free** — `jq` the identity, re-hash the typed password with libc `crypt`,
   and for a trusted tier verify the tree signature ([0019](0019-host-is-the-trust-anchor.md)).
3. **Only then** evaluate anything the user wrote.

Data, not Nix, purely because of *when it is consumed*: identity is read pre-auth and must be inert;
everything else is read post-auth, when the seat has already decided to evaluate.

## One loader, one resolution site, one value

The identity is read **once** on the Nix side and the same value reaches both the system account and
the home. It was briefly split — the home loading its own file while the binding loaded it for the
account — which let a realized account and its home disagree about who the user is.

The rule tightened twice more as the repo grew. `loadIdentity` fixed *who parses*; `mkMembers` then
fixed *who resolves the path*, because the layout rule had been transcribed independently by the
producer's directory scan, the producer coin and the home builder, so one file was read two or three
times per evaluation by three owners. The rule now reads: **one loader, one resolution site, one
value to every consumer.**

## Consequences

- **The contract owns the `identity.json` convention** — its filename and its schema — and exposes
  both (`identityFile`, `identitySchema`) so a greeter can introspect the shape it authenticates
  against.
- **The loader is a typo-net.** A missing required field or an unknown key is a loud error, not a
  silently-wrong account.
- **The home *holds* its identity, it does not load it.** Identity-driven dotfiles read
  `config.identity.name`; nothing in a home reads a file.

## Considered alternatives

- **Identity in Nix, under `contract.*` with everything else** — genuinely attractive: one file per
  user, one vocabulary, and it would delete the JSON schema projection, the loader, and the
  threading that exists only because the data is JSON. **Rejected on the ordering above**: learning
  a stranger's password hash would require evaluating their Nix first. The aesthetic of total
  consolidation loses to data-before-code.
- **Author in Nix, generate `identity.json`** — the middle ground, and it does not quite work: a
  greeter reads the fetched *source tree*, and reaching a flake output means evaluating the flake.
  The generated file would have to be committed with a drift check — a build artifact in git, for an
  authoring win of four literal fields. Recorded because it is the obvious next proposal.
- **Split the file — credentials inert, descriptive fields in Nix** — rejected: the line is
  defensible but it gives one concept two homes and two vocabularies.
