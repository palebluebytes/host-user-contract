# The contract is a standalone flake that depends only on nixpkgs `lib`

**Status:** Accepted (2026-08-20). Makes [0001](0001-host-user-contract.md)'s boundary checkable.

A contract that cannot be evaluated without one of its consumers is not a boundary — it is a shared
header file with extra steps. So the contract is its own public flake, and its dependency list is
the litmus test: **nixpkgs, for `lib`, and nothing else.** No `self`, no `inputs`, no home-manager,
no package set.

## What that forbids, and how each capability is recovered

**No `self`.** The shipped modules take no flake argument. The kit (`kit.nix`) applies every module
to the contract's own registry data, captured in its own scope, so a consumer writes
`imports = [ contract.nixosModules.default ]` and nothing else. Threading the contract through
`specialArgs` was rejected — every consumer and every module would carry the plumbing — as was
re-exporting it into the host's `self`, which hides the boundary at exactly the sites that should
show it.

**No package-ecosystem input.** Overlays and package choices are a *user's* concern, not part of a
neutral interface. The one module that references real packages is the reference greeter, and it
reaches them through the **host's** `pkgs`.

**No home-manager.** This is the rule most often cited and least often stated, so: the contract
*targets* home-manager — a user's home is a home-manager module, and the contract ships modules
that name `home.file` — but it never **builds** one. Authoring a module that names a home-manager
option needs no input; home-manager need only be present where the module is *evaluated*. An input
is required for exactly one thing, `homeManagerConfiguration`, and that is the consumer's to call.

The cost of taking it would not be impurity but **version skew**: an input pushes a home-manager
choice onto every consumer, and `mkIf` cannot suppress unknown-option errors across versions.

## Injection is the pattern everywhere the contract needs a capability it will not depend on

`mkContractHome` composes a home's module list and then applies **the caller's**
`homeManagerConfiguration`, passed verbatim. `mkConfinementCheck` and `mkContractFleet` take a
`buildHome` closure the same way. The contract owns the composition; the consumer owns the builder.

The same split governs everything host-shaped: the contract ships **mechanism**, the host supplies
**bindings** — which seats run a greeter, what a desktop's launch command is, what nixpkgs a home
builds against. A host may narrow a contract rule; it can never widen one.

## Consequences

- **The contract has independent CI.** Its conformance suite runs against synthetic users on
  synthetic systems with no consumer repo present.
- **Anything needing home-manager is proven in the sibling reference flakes**, not here — see
  [0022](0022-oracle-and-reference-fleets.md).
- **The contract holds no secrets and no hostnames**, so it is safe to publish. Being public is what
  makes "enter a flake URL" ([0018](0018-greeter-runtime-flow.md)) coherent: an unrelated user repo
  can reference the same neutral contract.
- A contract change is a commit in this repo and a `nix flake update` in each consumer.

## Considered alternatives

- **Ship the contract as modules inside the host repo** — rejected: the boundary is unverifiable if
  it is never evaluated alone.
- **Take home-manager as an input and ship a reference home builder** — rejected: it buys a
  capability the contract has deliberately given to the consumer, at the cost of a version choice
  imposed on everyone.
- **À-la-carte modules instead of umbrellas** — rejected in general (no host wants the schema
  without the realization) and accepted in exactly one place: `nixosModules.greeter` is separate
  from `default`, because a headless host genuinely wants the second and not the first.
