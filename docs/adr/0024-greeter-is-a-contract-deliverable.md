# The greeter is a contract deliverable: `bindUser` in `lib` + a reusable greeter module

**Status:** Accepted. **Amends** [ADR-0022](0022-anyhost-greeter-runtime-binding.md) and [ADR-0023](0023-user-flake-shape.md), which placed `bindUser` and the greeter host-side; the mechanism moves into the contract. The *threat model* (tiers, untrusted-eval) is unchanged.

[ADR-0022](0022-anyhost-greeter-runtime-binding.md) and [ADR-0023](0023-user-flake-shape.md)
described the greeter as a **consumer**: "the host repo exposes `bindUser`," and "a seat host
enables a `greeter` profile" authored fleet-side. That was the in-repo-migration framing carried
over from when host and contract shared one repo. It is wrong for the published contract, for the
same reason the realization and feature modules are contract-shipped and not re-authored per host
([ADR-0015](0015-host-user-contract.md) mechanic 5, [ADR-0020](0020-extract-contract-flake.md)):
**"any host runs a greeter" is the contract's north star ([ADR-0018](0018-user-confinement-manifest-greeter.md)),
and making every fleet reimplement `greetd` + `bindUser` reintroduces exactly the drift the
contract exists to remove.**

## The decision

**The greeter is part of the contract.** The contract ships the generic mechanism; the host
supplies only bindings — the same split already used for the `platform` interface.

- **`bindUser` moves into the contract's `lib`.** Its logic is generic and contract-shaped: it
  imports `homeModules.default` + the user's home module, injects `pkgs` + `hostFacts`, and
  harvests `config.contract.requests`, applying the **granted** ones. Nothing in it names a host.
  It joins `mkFeatureRecipients` / `mkHostFacts` as a contract function, called by **both** binding
  paths (build-time and runtime) exactly as [ADR-0023](0023-user-flake-shape.md) intended — only
  the home of the function changes.
- **The contract ships a reusable `greeter` NixOS module.** `nixosModules.greeter` carries the
  `greetd` service, the eval-free auth flow ([ADR-0022](0022-anyhost-greeter-runtime-binding.md):
  fetch source → `jq` `identity.json` → verify password/signature → classify tier → `bindUser` with
  `grants = safeSet` → build → provision), and the privileged **runtime-provisioning helper** that
  materialises the account from the built home-activation package. A seat host **enables** it; it
  does not author it.
- **The host supplies only bindings**, never mechanism: *which* seat hosts enable the greeter, the
  display/theme binding, the trust-tier **policy** (is this host Tier 1 only, or does it accept Tier
  2?), and the `platform` secrets binding the provisioning step may use. Headless hosts simply never
  enable the module — **incapacity, not a ban** ([ADR-0018](0018-user-confinement-manifest-greeter.md)).
- **`safeSet`, `homeModules.default`, the `contract.requests` namespace, and the `identity.json`
  convention** — the surface `bindUser` composes — are already contract-owned (the in-flight
  scaffolding, this repo's issue #5). They feed the contract `bindUser` directly.

The runtime binding stays a *parameter* over the build-time mechanism, not a fork: a greeter-bound
user and an operator-granted user realize identically because both go through the one contract
`bindUser`.

## What stays host-side

Bindings only — never mechanism: the seat-host *enable* decision, the display/theme, the per-host
trust-tier policy, and the `platform` secrets binding. The contract evaluates with the greeter
module present but **unbound** (no seat host enabled, no theme) exactly as it evaluates with the
`platform` unbound ([ADR-0020](0020-extract-contract-flake.md)'s second litmus test).

## Consequences

- **Supersedes the placement** in [ADR-0023](0023-user-flake-shape.md) ("the host repo exposes
  `bindUser`") and [ADR-0022](0022-anyhost-greeter-runtime-binding.md) ("a seat host enables a
  `greeter` profile" authored fleet-side). `hosts/default.nix` now *calls* the contract's `bindUser`
  and *enables* `nixosModules.greeter`; it authors neither.
- **The conformance suite gains a greeter dimension** — the headless `bindUser` tracer (issue #5)
  becomes a contract test, and the greeter module's eval-free auth + safe-set grant are proven
  against synthetic users with no host repo, the same way the realization and gui-union already are.
- **`nixosModules` is no longer a single `default`.** The contract ships `nixosModules.default`
  (schema + realization + features + platform) and `nixosModules.greeter` (opt-in). À-la-carte is
  justified here precisely because a headless host wants the former and not the latter.
- **The untrusted-eval threat model ([ADR-0022](0022-anyhost-greeter-runtime-binding.md)) is
  unaffected by this move** — Tier 1 builds now, Tier 2 stays deferred; the hardening knobs live in
  the contract module rather than a fleet profile, but the security question ("own identities vs
  anyone?") and its answer are identical.
- **Issue re-scope:** the greeter epic (#2) and greeter-secret provisioning (#4) are now legitimately
  this repo's work, not the fleet's; #5 (the `bindUser` surface) is their foundation. The fleet repo
  keeps only the *binding* (which hosts, which theme, which tier policy).

## Considered Options

- **Greeter as a consumer (ADR-0022/0023 as written)** — rejected now: it re-authors `greetd` +
  `bindUser` per fleet, the drift the contract exists to remove, and contradicts "*any* host runs a
  greeter" being a contract promise rather than a per-fleet rebuild.
- **`bindUser` in the contract but the greeter module host-side** — rejected: it splits one
  mechanism across the boundary, so the runtime path is half-contract/half-fleet and the eval-free
  auth flow (the security-critical part) is re-authored per host.
- **Greeter as a contract deliverable (chosen)** — `bindUser` in `lib`, a reusable
  `nixosModules.greeter`, host supplies bindings. One mechanism, host policy at the edges, the
  realization/platform pattern applied to the runtime path.
