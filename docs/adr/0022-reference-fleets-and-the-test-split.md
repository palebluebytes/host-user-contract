# Reference fleets, and the oracle/reference test split

**Status:** Accepted; **partially overtaken by [ADR-0023](0023-contract-handles-no-secrets.md)** — the contract now handles no secrets, so `mkFeatureRecipients` and the `secretBearing`/`signing` coverage this ADR describes no longer exist; `ben` is now a plain cli reference user. The reference-fleet *split* (oracle vs positive-space reference) stands; read the secret-coverage details as history. **Builds on** [ADR-0004](0004-extract-contract-flake.md) (the contract's
synthetic, host-repo-free conformance suite), [ADR-0007](0007-user-flake-shape.md) /
[ADR-0020](0020-multi-user-repo-shape.md) (the user-flake and multi-user shapes), and
[ADR-0016](0016-prebuilt-binding-mode.md) (the per-user `contractPackage` output).

## Context

The repo shipped two proofs of the contract: the **synthetic conformance suite** — fabricated users
on fabricated systems, no host repo, the contract's independent CI ([ADR-0004](0004-extract-contract-flake.md) Q5) — and a single **reference user** (`examples/user/`), a real home-manager home built through the contract. What it did *not* ship was a reference **host fleet**: a machine fleet that actually consumes the contract by binding real users. As a result `mkFeatureRecipients` and `mkHostFacts` — functions that only mean anything across a *multi-host* `nixosConfigurations` — were shipped but exercised nowhere, and a consumer had no canonical picture of two independently-owned repos (hosts, users) meeting at the binding.

The tempting move was to make a reference fleet *be* the test fixtures. That is a category error.
The synthetic suite is **adversarial, negative-space**: its fixtures exist to prove the exposed-host
ban *fires*, the privileged-group clamp *drops*, an ungranted request is *inert*, an out-of-universe
option is *unexpressible*. A reference fleet is **positive-space by definition** — the idiomatic
*correct* consumer, the thing that passes. You cannot drive "the ban fires" from a fleet that, being
correct, never trips it. The two are different *kinds* of artifact, not two fidelities of one.

## Decision

**Add two reference fleets as sibling flakes, and keep them a layer *beside* the synthetic suite,
never a replacement for it.**

1. **`examples/users/`** — the reference **user fleet** ([ADR-0020](0020-multi-user-repo-shape.md)
   shape): the operator's own accounts in one flake, each exported as a per-user
   `<u>-contractPackage` output ([ADR-0016](0016-prebuilt-binding-mode.md)). The former single
   `examples/user/` is folded in as one member. Roster: `ada` (portable — gui on one host, cli on
   another), `ben` (secret-bearing signing), `cleo` (privileged-group clamp), `svc` (cli-only
   automation), `admin` (break-glass — the minimal `sudo`/wheel grant).

2. **`examples/fleet/`** — the reference **host fleet**: `nixosConfigurations` (`desk` seat,
   `vault` non-exposed, `agent` exposed) that bind the user fleet's outputs. It shows the contract's
   reason to exist — two independently-owned repos meeting at `bindContractPackage`.

3. **The oracle/reference split.** The synthetic suite remains the **adversarial oracle** (unchanged,
   host-repo-free). The reference fleet is a **positive-space artifact** with its own
   *smoke/coherence* checks: every host evaluates, every account realizes, `ada`'s gui↔cli divergence
   holds across hosts, `cleo`'s `docker` comes only via the grant, the exposed-host ban stays *clean*
   on the real exposed host, and `mkFeatureRecipients` runs over a genuine fleet. The reference never
   re-bases the oracle.

4. **A one-way seam.** Conformance may **consume realistic atoms** from the reference fleet (it
   imports `ada`'s contract-pure home + her `identity.json` as fixture atoms), never the reverse —
   oracle borrows from reference, reference never defers to oracle.

5. **One consumption convention.** Every user is consumed only as a **flake output of the user
   fleet**, never a bespoke standalone flake — **declaratively** via its `<u>-contractPackage`
   (`bindContractPackage` at eval), and at **runtime** via its greeter-home output (the greeter
   builds/activates `<u>-greeter` at login, a sibling output built from the same user). The tool and
   the specific output differ between the two paths; what is uniform is that both consume the user
   fleet's per-user outputs. The roaming stranger is the same user fleet's output consumed at runtime.

## Consequences

- **The fleet checks do not run under the contract flake's `nix flake check`.** They need
  home-manager and a platform binding, which [ADR-0004](0004-extract-contract-flake.md) forbids the
  contract flake from inputting, so they live in the *sibling* flakes' `checks` — exactly the
  boundary `examples/user/` already sat behind. Running everything means `nix flake check` in three
  targets (`.`, `examples/users`, `examples/fleet`); a CI matrix walks all three.
- **No shared home modules in `examples/users/`.** The contract stops at handing the home a *signal*
  (`config.identity`, the read-only `hostFacts.granted` projection); what a home *does* with it (git,
  mail, a signing backend) is application policy that varies per user, so there is nothing universal
  to factor. Each reference user is **self-contained** (identity + home, secrets only where needed) —
  which also keeps it a clean standalone teaching artifact. (This does not contradict
  [ADR-0020](0020-multi-user-repo-shape.md)'s "shared code, per-user data": that is a real operator
  repo's *ergonomics*; a reference example's job is to demonstrate the *contract*.)
- **The fleet-facing helpers gain coverage.** `mkFeatureRecipients` is exercised over a real fleet —
  vacuous today (no feature declares `secretFiles`; `signing` rides the user's own home sops), lighting
  up the moment one does. `mkHostFacts` — the other previously-uncovered helper — gains a conformance
  assertion proving its projection is self-scoped and secret-free (no `hostName`, no secret; ADR-0002).
- **Silent degradation is shown positively, on both sides.** The *same* `ada-contractPackage`, bound
  with gui on `desk` and without on `agent`, yields opposite account realizations (bind-level);
  and `ben`'s home reaction wires a signing marker only where granted (home-side) — together the
  positive face of [ADR-0002](0002-user-confinement-manifest-greeter.md)'s silent-degradation promise,
  which the adversarial suite proves only from the deny side.
