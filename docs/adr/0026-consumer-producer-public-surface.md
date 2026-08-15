# The consumer/producer public surface: `bindContractUser` / `mkContractUser` / `traceUser`

**Status:** Accepted (2026-08-06). Amends [ADR-0007](0007-user-flake-shape.md) (the binding shapes), [ADR-0008](0008-greeter-is-a-contract-deliverable.md) (the greeter mechanism), [ADR-0016](0016-prebuilt-binding-mode.md) (the pre-built primitives), and [ADR-0025](0025-turnkey-host-side-bind.md) (the turnkey bind). It renames and re-levels the `lib` surface, and **retires** the inline-eval binding path and the unilateral direct-grant posture from the public surface. **Amended in place (2026-08-16)** — the producer data surface swaps `homeAffecting` for `variants` and gains `lib.hostFactsFor`; see the amendment at the end.

The `lib` surface had grown by accretion — a function per issue, each named for the trait that distinguished it *when it was added* rather than for which one a consumer should reach for. By ADR-0025 there were eight public functions across two spellings of "bind" and three of "make," and the two a normal consumer actually wants (`bindUserFromFlake`, `mkUserBindings`) had the longest, least-guessable names, while the plainest name — `bindUser` — was taken by a test-only tracer. The reference host fleet had to locally re-alias `bindUserFromFlake` to `bindUserTurnkey` just to read. A naming review turned into a surface review, because several of the eight had no consumer at all.

## What the trace showed

- **`bindUserModule`** (the inline-eval bind, [ADR-0008](0008-greeter-is-a-contract-deliverable.md)/issue #8) had **zero** callers. `examples/fleet` binds entirely pre-built; the greeter builds the user's own `homeConfigurations.<u>.activationPackage` (never `bindUserModule`); only the conformance suite invoked it. Its stated value — "hard-enforcement," the host evaluating the home live so a denied feature cannot be present — is undercut by the contract's own *program scope* doctrine ([ADR-0017](0017-daemon-restricted-user-package-policy.md)): package restriction was never host-enforceable with daemon access, which is *why* the pre-built mode is "the coherent choice." System effects (grants, groups, privilege) are controlled equally by the pre-built path.
- **`bindContractPackage { grants }`** ([ADR-0016](0016-prebuilt-binding-mode.md)) is the only place a host could write a grant **unilaterally** (grant a feature the user never offered). No reference host does; `examples/fleet` is 100% negotiated (`affordances ∩ offer`, ADR-0025).
- **`mkContractPackage`** / **`mkContractPackageForHome`** are baked *through* by the roster producer; no reference producer calls them directly. Once `bindContractPackage` stops being a public consumer, a bare `contractPackage` they emit has no public consumer either.
- **`mkHostFacts`** projects `{exposed,platform,granted}` from a NixOS host `config` — a config that only exists where a host evaluates a home **inline**. With inline-eval retired, nothing in the pre-built world holds that config (the producer bakes hostFacts by hand; the host binds a pre-built home). Only conformance called it.

## Decision

Fix the public surface at **six** functions, organised on one concept seam — *the public surface speaks in **contract users**; the package-level kernels speak in **contract packages** and stay internal* — and retire the paths that had no consumer.

### The produce/consume coin

| Role | Name | Was |
| --- | --- | --- |
| Produce one user | **`mkContractUser`** | *(new — extracted)* |
| Produce a roster | **`mkContractUsers`** | `mkUserBindings` |
| Consume one user | **`bindContractUser`** | `bindUserFromFlake` |

`mkContractUser` is the **singular** producer — the true per-user twin of `bindContractUser` (*make one contract-user ⇄ bind one*). It bakes one user's variants into the named packages and its `contractUsers.<sys>.<user>` index entry, emitting the ready-to-`inherit … packages contractUsers` flake-output shape, so a single-user repo needs no roster. `mkContractUsers` is now nothing but `mkContractUser` mapped over a roster and merged — the multi-user convenience ([ADR-0020](0020-multi-user-repo-shape.md)). Plural producer ⇄ singular consumer is the honest arity: the producer bakes the whole roster in one call; a host binds one account at a time. Both names mirror the `contractUsers` output, whose `contract` prefix is *forced* — the users flake is itself named `users`, so a bare output would read `users.users.<sys>`.

### `traceUser` — the inspector outside the coin

The ex-`bindUser` tracer becomes **`traceUser`**: the home-manager-free dry-run that harvests a contract-pure home via bare `evalModules` and returns `{ username; home; requests; system }`. It answers "given these grants, what does my home request, and does it bridge?" without a build — the conformance kernel and the public tool a home author inspects with. It deliberately sits *outside* the coin (it takes raw pieces, never the index), so it keeps a plain name, not `traceContractUser`.

### Retired from the public surface

- **Inline-eval bind (`bindUserModule`): deleted.** The build-time path is pre-built only; the greeter builds the user's own home output. [ADR-0008](0008-greeter-is-a-contract-deliverable.md)'s greeter mechanism condition (2) is reworded from "bind via `bindUserModule`" to "build the user's own home output through the contract umbrella."
- **Unilateral direct-grant: retired.** The public grant model is **negotiation-only** — `grant = affordances ∩ offer` via `bindContractUser`. `bindContractPackage` (which takes `grants` verbatim) becomes an **internal kernel**; there is no public path to grant a feature a user did not offer.
- **`bindContractPackage`, `mkContractPackage`, `mkContractPackageForHome`, `mkHostFacts`: internalized.** Not flake outputs. Exposed to the in-repo conformance suite via `kit.internal` so they are still proven in isolation. *(Amendment: `mkHostFacts` was subsequently **deleted** as caller-less — the producer hand-builds the `{exposed,platform,granted}` literal inline, so the config-projector re-derived nothing; re-add it from git history if a host-side-eval caller returns.)*

The resulting public `lib`: `mkContractUser` · `mkContractUsers` · `bindContractUser` · `traceUser` · `loadIdentity` · `renderNixConfig`.

*(Amendment, issue #35 — the **check kit**: `mkConfinementCheck` and `mkIdentityPostureCheck` join the public `lib`, taking it to eight. They pass this ADR's own test — the one it applied to the eight it found: each has a real consumer that cannot get the proof any other way. `mkConfinementCheck` proves a **consumer's own module set** has no system channel (this repo's suite can only prove the umbrella), and `mkIdentityPostureCheck` asserts the **consumer-owned**, conditional ADR-0019 credential posture that `loadIdentity` must not impose. Neither is a second spelling of anything kept, and neither is a bind or a bake: they are the proofs only the consumer can run, which is why they are functions the contract hands over rather than checks it runs. This is surface growth by the front door — the cost being paid deliberately for two ~20-line boilerplates every consumer repo re-types, one of which (the positive control) is silently wrong when forgotten.)*

## Consequences

- **The north star is untouched.** The runtime greeter (any user logs in without being enabled in nix config) consumes only kept surface — `identityFile`, `greeterGrants`, `safeSet`, `renderNixConfig`, `nixosModules.greeter`, and the user's own `homeConfigurations.<u>`. It never called any renamed or removed function. `bindContractUser` is correctly framed as the *build-time* path (operator-managed and privileged accounts the safe-set greeter cannot grant), the opposite posture to the greeter — no longer mis-named as "the" way onto a machine.
- **Solo producers regain ergonomics.** A single-user repo calls `mkContractUser` once rather than faking a one-entry roster — the cost ADR-0025's roster-only producer would otherwise have imposed once the primitives went internal.
- **Loss:** a host can no longer grant a user a feature the user did not offer, nor evaluate a home host-side inline through a contract helper. Both had no reference consumer; both are recoverable by re-exposing the internal kernel if a real need returns (see below).
- Breaking rename of every public consumer/producer call site; landed in lockstep across the contract, conformance, and both reference fleets (no back-compat aliases — the contract is pre-1.0).

## Considered Options

- **Keep all eight, just rename.** Rejected: four had no consumer; carrying them is exactly the accretion this cleans up.
- **`mkUsers` (drop "Contract").** Rejected: collides with `users.users` (the realization's own output) and desyncs from the forced-prefix `contractUsers` output.
- **`mkUser` singular only, arity-matched to `bindUser`.** Rejected: the roster producer is intrinsically plural (that is what makes it turnkey); a singular-only form re-introduces the per-user loop ADR-0025 removed. Shipping *both* the singular partner and the roster convenience is what keeps the arity honest.

## If a retired path should return

Re-exposing is a one-line move from `kit.internal` to `kit.lib`, plus an ADR amendment: `bindContractPackage` for a fleet that genuinely wants unilateral grants, `mkHostFacts` for a host that runs its users' homes through its own home-manager, or a fresh inline bind if hard-enforcement ever becomes enforceable. Nothing here forecloses them; it only stops advertising a surface no one uses.

## Amendment (2026-08-16) — ship the producer's derivations, not the datum they derive from

The data surface exported `homeAffecting`: the feature names whose grant can reach home content. A trace of its consumers — the reference fleet in `examples/users` and the operator's own users repo — found it used for exactly two things, in both, written out by hand in both:

```nix
granted = lib.filterAttrs (f: _: lib.elem f contract.homeAffecting) grants;   # the hostFacts narrowing
variantGrants = map … (lib.foldl' … [ [ ] ] contract.homeAffecting);          # the baked variant set
```

Neither is a consumer *choice*. Both are the contract's own rules, re-derived per repo from a datum, and both fail **silently** when wrong: a mis-written narrowing shows a home a grant it must not see, and a variant set that has fallen behind the registry under-bakes — `bindContractUser` binds the maximal variant that *does* exist and the home simply lacks the new feature's content, which no coupling guard reports. One consumer had resorted to hardcoding its variant set behind an `assert` on `homeAffecting`, which is the tell: the datum was public, the rule was not.

So the surface now carries the **derived forms** and drops the datum:

- **`variants`** — `[{ label; grants; }]`, one entry per combination of the axes. A producer maps over it. `label` travels with `grants`, so the two cannot be paired up wrongly, and the label rule stops being mirrored per repo against the private `variantName`.
- **`lib.hostFactsFor`** — `{ granted, platform, exposed ? false } → hostFacts`, narrowing `granted` to the axes. Deliberately not `mkHostFacts` returning under a new name: that one projected from a NixOS host `config` and is retired above; this one has no host in sight and belongs to the producer.
- **`homeAffecting` leaves the surface.** Its projection survives as `kit.internal.variantAxes`, exposed only so the conformance suite can prove the taxonomy in isolation.

This passes the test this ADR applied to the eight functions it found: each addition has real consumers that cannot get the result any other way, and neither is a second spelling of anything kept. It is also a net *simplification* of every consumer — two hand-written derivations and an assert deleted from each — which is the opposite of the accretion this ADR was written to stop.

**The registry flag is renamed with it: `homeAffecting` → `needsOwnBuild`.** The old name asserted a vague relationship in a system where everything relates to the home, and said nothing about the cost. The new one states the mechanical test — can this grant be applied to a home that is already built? — and its complement is the registry's existing prose: a feature without it *rides the bind*. Saying yes doubles every user's variant count on every architecture, and the name should make an author feel that before they type it.
