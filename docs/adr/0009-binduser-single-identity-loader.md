# bindUser is the single identity loader; the home holds its identity, it does not load it

**Status:** Accepted. **Amends** [ADR-0007](0007-user-flake-shape.md), which said the home module "loads it (`fromJSON`) so it owns it." `bindUser` now loads `identity.json` once and injects the value into both the system account and the home. **Amended (2026-08-16, issue #57)** — the single loader gains a single *resolution site*, `mkContractRoster`; see the amendment at the end.

[ADR-0007](0007-user-flake-shape.md) gave the user's home module the job of loading its own
`identity.json` ("so it owns it"), while `bindUser` separately loaded the same file for the
system account. Building the `bindUser` surface (issue #5) showed that this splits the read in
two: the account and the home each parse `identity.json` independently, so a divergence (a
stale or differently-loaded read) could let the realized account and the home disagree about
who the user is. A contract-pure home module also has no `loadIdentity` to call unless the
binding injects one — so "the home loads it" was never quite true anyway.

## The decision

**`bindUser` is the single reader of `identity.json` on the Nix side.** It loads the file
once (via `loadIdentity`) and injects that one value into both the system account
(`custom.users.<u>.identity`, where the realization materializes the account) and the home
evaluation (a module setting the contract's `identity` options). The home **holds** its
identity — it reads `config.identity.{name,email,…}` for its dotfiles — but never loads the
file itself. One file, one loader, one value to both sides, so the account and the home can
never disagree.

The standalone-dev path (the user flake's own `homeConfigurations`, ADR-0007) mirrors this: it
sets `identity = loadIdentity ./identity.json` in its module list — exactly what `bindUser`
injects when the user is bound.

## Consequences

- This amends ADR-0007's "the home module loads it": the home *holds* its identity (injected),
  rather than loading it. The `identity.json` data-file convention and the **eval-free auth**
  flow are unchanged — the host/greeter still read the file with `jq` before any eval
  ([ADR-0006](0006-anyhost-greeter-runtime-binding.md)); this ADR is only about who performs
  the *Nix-side* load for the *bound* home.
- Identity-driven dotfiles (`programs.git.userName = config.identity.name`) read
  `config.identity`, so they materialize in the **full home build** (the host's home-manager,
  or the example flake's standalone `homeConfigurations`). `bindUser`'s own harvest eval reads
  only `contract.requests`, so the injected identity is observed there for consistency (the
  conformance tracer asserts the home holds it) but used by the dotfiles only in the full build.

## Amendment (2026-08-16) — one loader, and now one resolution *site* (issue #57)

This ADR fixed **who parses** `identity.json`: `loadIdentity`, once, its value injected into both
sides. It said nothing about **who names the file**, and by the time the producer coin
(`mkContractUser`), the home builder (`mkContractHome`) and every producer's own directory scan each
resolved the [ADR-0020](0020-multi-user-repo-shape.md) path for themselves, one loader was being
called from three owners two or three times per user per evaluation. Same loader, three sites — which
is the drift this ADR exists to prevent, one level up.

`mkContractRoster` (ADR-0020's own amendment) closes it: the roster resolves each member's identity
once, and everything downstream takes the resolved **member** rather than a path. The rule now reads:
one loader, one resolution site, one value to every consumer of it.
