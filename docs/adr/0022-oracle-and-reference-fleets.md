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

**A one-way seam for FIXTURES.** Conformance may consume realistic atoms from the reference fleet;
never the reverse. The oracle borrows from the reference, the reference never defers to the oracle.

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

**What travels the OTHER way is a shipped surface, and it has its own owner.** One thing does move
oracle→reference: the seat-VM **harness**. The reference host fleet's end-to-end greeter test boots a
contract seat to activate a real home-manager home — which the contract flake cannot build itself
([0002](0002-contract-is-a-standalone-flake.md)) — and the harness the contract's own runtime proofs
are built on lives under `conformance/`. That is not the fixture seam running backwards, because the
fleet consumes a **published output** rather than a file: the contract ships the harness as
`testing.mkSeatHarness`, and `conformance/testing.nix` — the second one-file owner, this one for what
leaves the directory — is the export list behind it. So the suite still owns its own layout, and the
fleet names no path inside it.

It used to interpolate one, and that cost both sides: the suite could not reorganise its directory
without breaking a sibling flake, and the fleet's greeter test was one refactor away from a
hand-rolled seat host that nothing would compare against.

Why a THIRD surface rather than a member of the check kit: the kit hands a consumer the *technique*
for a claim about its own material ([0025](0025-consumer-check-kit.md)), and this hands over a
*machine*. It boots a seat; the claim stays the caller's to write.

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

## The reference host fleet binds from one source

A host is not restricted to one users repo: `source` is per-user with a top-level default
([0015](0015-consumer-surface.md)), so a contractor's own flake can be bound beside the operator's.
The reference host fleet does not demonstrate that with a second repo, and the omission is
deliberate.

A second users flake would add the *composition* of two things already proven apart. That a second
source binds a member the default has never heard of is the oracle's job, and it does it: a fixture
binds `contractor` from an `elsewhere` the default source does not publish, alongside `all = true`.
That a real producer flake is bindable is the fleet's own default bind, on every host. And a bind
reads nothing but `contractUsers.<sys>.<user>`, so no code path can tell one source from two —
there is no behaviour between those two proofs for a second repo to reach. The gap is rhetorical,
not a gap in coverage.

The cost is not the obvious one. A source owes no `checks`, so it need not join the CI matrix; it
would be evaluated transitively when the fleet builds the accounts it binds. What it would cost is a
fourth `flake.lock` to hold in step across three `path:` inputs, and a second home-manager-carrying
mapper whose whole job is to publish one user — bought to teach the flake-input `follows` wiring,
which is the only part of it a consumer copying this fleet does not already have.

So `vault` names the per-user key on one bind and nothing more. That line is not a two-repo
demonstration and must not be described as one. What it is is a live use of a **reserved bind key**,
and its job is that the fleet stops evaluating if the key ever stops being reserved — an
unrecognised bind key is a hard error, so `svc.source` would be read as an unknown affordance. Which
is also why the fleet owes no dedicated claim here: *every host evaluates* already carries it.

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
- **Let the fleet author its own seat host** rather than publishing the harness — rejected: that is
  the drift the raw path at least made visible. Two seat hosts, one of them exercised by every
  runtime proof the contract has and the other by a single fleet check, is one host too many.
- **A second users flake, so the fleet binds two genuinely different repos** — rejected, for the
  reasons above. The reason is *not* that a standalone single-user example flake was once deleted:
  that removal retargeted the oracle's realistic fixture atoms onto the reference user fleet and
  says nothing about what a host fleet may bind.
- **Move the harness out of `conformance/`** to a top-level file, so no export list is needed —
  rejected: ten of its eleven callers are the suite's own VMs, and hoisting a file for its single
  outside consumer moves the ownership away from everyone who uses it. The suite owns the file; the
  output owns the name.
