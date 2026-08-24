# The oracle and the reference fleets

**Status:** Accepted (2026-08-20). How everything above is proven, given
[0002](0002-contract-is-a-standalone-flake.md)'s constraints.

The contract ships a **synthetic conformance suite** — fabricated users on fabricated systems, no
consumer repo, independent CI. It also ships two **reference fleets**, a users repo and a host
fleet, that consume it for real.

The tempting move is to make the reference fleets *be* the fixtures. That is a category error.

| | the synthetic suite | a reference fleet |
| --- | --- | --- |
| kind | **adversarial, negative space** | **positive space** |
| its fixtures exist to prove | the refusal *fires*, the filter *drops*, an option is *unexpressible* | the idiomatic correct consumer works |

You cannot drive *"the refusal fires"* from a fleet that, being correct, never trips it. The two are
different **kinds** of artifact, not two fidelities of one.

## The split

- **`conformance/`** — the adversarial oracle. Domains per concern: the declaration, the
  realization, selection, the matrix, the account plan, the package seam, the greeter, confinement,
  plus VM tests for the runtime paths.
- **`examples/users/`** — the reference users repo. Seven people, each teaching one thing: the
  portable user who runs both modes, the person afforded containers, the break-glass account, the
  terminal-only service account that is the whole of the user-side veto, and a pair sharing a module
  by choice.
- **`examples/fleet/`** — the reference host fleet. A seat, a non-exposed host, an exposed one — the
  contract's reason to exist, two independently-owned repos meeting at a bind.

**A one-way seam.** Conformance may consume realistic atoms from the reference fleet; never the
reverse. The oracle borrows from the reference, the reference never defers to the oracle.

**And the seam has ONE owner:** `conformance/toolkit.nix`, the only file under `conformance/` that
knows where `examples/` is or which of the people in it the suite borrows. (Reference names still
appear elsewhere as synthetic fixture data — a refusal's expected message, a diagnostic's subject —
but nothing there reads the reference fleet.) It names every atom the suite
borrows — the users directory, a member set derived over it through the contract's own `mkMembers`,
a per-role member record (its directory, identity and declaration), the home modules the
composition domain compares — and each carries the one line a caller needs, so a domain never opens
the reference fleet to know what it got. A domain asks by ROLE ("the user who runs cli alone"),
never by person. That keeps the reference fleet free to change shape — a rename is a one-file edit
on the oracle's side — and makes the debt visible from the side that would pay it: the fleet can
read one screen and see which of its atoms the oracle leans on.

## The suite's own discipline

Three rules, each learned from a fixture that reported green while proving nothing:

1. **Every negative claim carries a positive control.** *"This is refused"* is worthless without
   *"and the almost-identical thing is accepted"* — otherwise the refusal may be firing for the
   wrong reason.
2. **Every empty-input case is a hard error.** An empty member set would bake, publish and check
   nothing while every output stayed green. A fixture that proves nothing is worse than no fixture,
   because it reports success.
3. **A load-bearing constant is asserted brittlely.** The empty safe set
   ([0008](0008-features-are-atomic-and-privileged.md)) has an assertion meant to fire.

## Why the fleets are separate flakes

They need home-manager and real package sets, which [0002](0002-contract-is-a-standalone-flake.md)
forbids the contract flake from taking. So they live in sibling flakes with their own `checks`, and
running everything means `nix flake check` in three targets. The package-free rule constrains the
**shipped contract**, never `examples/`.

That is also the boundary for anything needing a real home: the proof that a real home-manager
evaluation accepts the contract's composition lives with the reference fleet, while the contract's
own suite proves the composition itself against a **recording stub** — a builder that returns its own
arguments — so the module list and its order are asserted with no home-manager anywhere.

## The reference users share nothing, except where sharing is the lesson

There is nothing *universal* to factor across them: what a home does with the contract's signal is
per-person application policy. Each is self-contained, which also keeps it a clean teaching artifact.

The one exception is deliberate and narrow — a pair that imports a shared module and a shared
overlay, to demonstrate that an operator **may** enforce a common setup across their own accounts.
It is a permitted arrangement rather than an obligation, so it gets a live fixture instead of only
prose, and it is *additive*: the other five are untouched, because one of them is evaluated by the
conformance suite against the bare umbrella with no home-manager and no package set, and a shared
module setting a home-manager option would break that.

## Consequences

- **CI walks three targets.** The contract's suite is the gate that can run anywhere; the fleets
  prove the composition where the dependencies exist.
- **The reference fleets are teaching artifacts first.** Most of their length is prose explaining
  which decision each fixture embodies.
- **A fleet check is a smoke and coherence check** — every host evaluates, every account realizes,
  the same person lands on different homes on different machines — never a re-basing of the oracle.

## Considered alternatives

- **One suite, using the reference fleet as fixtures** — rejected: a correct fleet cannot drive an
  adversarial claim.
- **Move the whole suite into the sibling flakes** so it can use home-manager — rejected: the
  contract would lose the independent CI that makes
  [0002](0002-contract-is-a-standalone-flake.md)'s boundary checkable.
