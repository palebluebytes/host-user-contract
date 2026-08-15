# The host↔user contract lives in its own flake, delivered as a registry-baked kit

**Status:** Accepted (implemented — this repo). The user-repo split it defers is carried by [ADR-0007](0007-user-flake-shape.md). **Amended in place (2026-08-16)** — this ADR is routinely cited for "the contract does not depend on home-manager" ([ADR-0008](0008-greeter-is-a-contract-deliverable.md), [ADR-0013](0013-per-user-desktop-choice-host-offered.md), [ADR-0014](0014-tier1-restricted-eval-posture.md), and several code comments), but the "depends only on nixpkgs `lib`" bullet below decides something narrower. The corollary holds; its reasons are elsewhere. See the amendment at the end.

[ADR-0001](0001-host-user-contract.md) stood the contract up **in-repo** as a shared
module set on `self.contract`, deliberately framing the eventual repo split as "a URL
change, not a re-wire." The feature-registry refactor (the [ADR-0002](0002-user-confinement-manifest-greeter.md)-review
cleanup) made that real: the contract is now one registry with everything projected
from it, depending on nothing but nixpkgs `lib`. So the contract is extracted into a
standalone **public** flake (`palebluebytes/host-user-contract`, matching the
`jmap-bridge` precedent of ADR-0017), consumed here as a
`github:` input with `inputs.nixpkgs.follows = "nixpkgs"`. This is **slice 07a** — the
behaviour-neutral relocation; the heavier user-repo split + request channel stays with
the greeter ([ADR-0002](0002-user-confinement-manifest-greeter.md)) because that work and
the greeter define each other.

The extraction is the litmus test that the host↔user boundary is real: the contract must
evaluate with **no host coupling**, and the whole-fleet config fingerprint (groups,
display flags, insecure permits, safe set) must be **byte-identical** before and after.

## How the kit is delivered

- **Modules close over their own registry (not `self`).** Today `realization.nix` reads
  `self.contract.privilegedGroups` — where `self` is the *consuming host* flake. The
  contract flake instead builds `nixosModules.default` by applying its modules to its own
  registry data, captured from the flake's own scope. The shipped modules drop the `self`
  argument entirely: they read contract data from the closure and host config from
  `config`. The consumer just `imports = [ inputs.contract.nixosModules.default ]`.
  *(Rejected: threading the contract as a `mkSystem` specialArg — every consumer and every
  module would carry the plumbing; and re-exporting `self.contract = inputs.contract…` —
  brittle, leaks the contract into the host's `self`.)*
- **One umbrella kit per eval-side.** `nixosModules.default` (the `custom.users` schema +
  `custom.platform` interface + `custom.host.exposed` + the exposed-host assertion +
  realization + the insecure-package aggregator + feature modules) and
  `homeModules.default` (identity + home-profiles). Plus `lib` (the contract *functions*)
  and a data surface (`features`, `featureGroups`, `privilegedGroups`, `safeSet`) the host
  reads where it wires grants. (`featureMeta`, the platform interface, and the recipient
  derivation were removed by [ADR-0023](0023-contract-handles-no-secrets.md).)
  À-la-carte modules buy nothing — no host wants the schema without the realization.
- **The contract depends only on nixpkgs `lib`.** The single package-ecosystem coupling —
  the emacs overlay in `features/gui.nix` — is **moved out**: it is a user's package
  choice, not part of the neutral interface, and is reapplied host-side where a gui user
  actually wants it. The contract flake takes no `emacs-overlay` input.
- **`lib` splits along intrinsic-vs-fleet.** The contract flake's `lib` holds
  `runtimeEligibleFeature`, `mkFeatureRecipients` (the *algorithm*), `exposedHostOffenders`,
  `mkHostFacts`; the host keeps the secrets resolvers, `mkPkgs`, `mkSystem`/`mkPiSystem`,
  overlays, the mbsync helpers — and `featureRecipients = mkFeatureRecipients
  self.nixosConfigurations`, the algorithm *applied to this fleet*. Call sites reference
  `inputs.contract.*` **explicitly** (no re-export into `self.lib`): the whole point is to
  make the boundary visible at every use, which a re-export would hide.
- **The conformance suite splits the same way.** The contract flake ships the **generic**
  suite — the matrix (synthetic users × archetypes), grant/deny, the gui-union *decision*
  (the session surface asserted at **eval**), and the gui-union **rendering VM** (a booted
  single-seat host proving the decision renders to two coexisting plasma sessions) — using
  only synthetic manifests it defines itself, plus a **test-only display binding** the
  suite supplies to render the otherwise backend-agnostic decision (the shipped contract
  names no display backend; the *test* picks one). It gains independent CI (testable with
  no host repo). The host keeps only a thin **coherence gate**: every *real* host's
  trait-tuple is covered by an archetype, and the real user manifest realizes.
- **The platform binding stays host-side.** *(Retired by [ADR-0023](0023-contract-handles-no-secrets.md): the contract handles no secrets, so the platform secret interface was removed. Read this bullet as history.)* The contract shipped only the typed `platform`
  *interface*; the host supplied the *binding* (`config.custom.platform = …`, which reads
  `inputs.secrets`) via a small host-side module — one per eval-side. That kept every
  secret path out of the contract, and is a second litmus test: the contract must evaluate
  with the platform *unbound*. The interface itself is made backend-agnostic first — see
  [ADR-0005](0005-platform-backend-agnostic-secrets.md).

## Consequences

- A contract change is a commit+push in the contract repo, then `nix flake update contract`
  here — the same two-repo workflow already in force for `secrets` (ADR-0002)
  and `jmap-bridge` (ADR-0017). No new mental model.
- Developed behind a `path:` input for a fast inner loop (no push+relock per change), then
  flipped to `github:` once the fingerprint is byte-identical — literally the "URL change"
  ADR-0001 promised. Public + `github:` means no SSH at eval and a cache-friendly fetch.
- The contract repo holds zero secrets and zero hostnames — pure schema, realization, and
  security model — so it is safe to publish, and being public aligns with the greeter's
  "enter a flake URL" premise: external user repos can reference the same neutral contract.
- This proves the boundary but does **not** yet separate a *user* into its own repo. The
  user-repo split, the `contract.requests` channel, and any re-key ride with the greeter
  ([ADR-0002](0002-user-confinement-manifest-greeter.md)), since the external-user-repo
  shape and the greeter's trust model define each other.

## Amendment (2026-08-16) — the scope of "depends only on nixpkgs `lib`"

The bullet above decides one thing: the contract takes **no package-ecosystem input**. Its whole
argument is the emacs overlay in `features/gui.nix` — "a user's package choice, not part of the
neutral interface" — and what it buys is the property this ADR is named for: the contract evaluates
and tests with no host repo and no package set.

It is now also the standing citation for a **different** rule — that the contract takes no
**home-manager** input. That rule is real and is followed consistently, but this ADR never states
it, and a reader who comes here to check it will not find it. Recording the actual reasoning:

- **The rule is about *building* homes, not about *targeting* home-manager.** The user surface
  *is* a home-manager module — that is [ADR-0002](0002-user-confinement-manifest-greeter.md)'s
  title — and the contract ships one that sets a home-manager option (`homeModules.greeterDesktop`
  writes `home.file`, [ADR-0013](0013-per-user-desktop-choice-host-offered.md)). Authoring a module
  that names `home.file` requires no home-manager *input*; home-manager need only be present where
  the module is *evaluated*, in the consumer's home eval. A flake input is required for exactly one
  thing: calling `home-manager.lib.homeManagerConfiguration` to build a home.
- **The contract deliberately never builds one.** The build is the host's `homeBuilder` binding
  ([ADR-0008](0008-greeter-is-a-contract-deliverable.md)); a reference builder was considered and
  rejected in [ADR-0014](0014-tier1-restricted-eval-posture.md) for the same reason. So the input
  would buy a capability the contract has decided belongs to the consumer.
- **The cost of taking it would be version skew, not impurity.**
  [ADR-0001](0001-host-user-contract.md) mechanic 3: `mkIf` cannot suppress unknown-option errors
  across home-manager versions, so features touching divergent options must be conditionally
  *imported*; [ADR-0002](0002-user-confinement-manifest-greeter.md) records that the contract's
  feature modules pin the **host's** home-manager. An input would push a version choice onto every
  consumer.
- **Two things it is *not* about.** It is not what keeps the contract self-testable: the proofs
  that need home-manager live in the sibling reference flakes by deliberate design
  ([ADR-0022](0022-reference-fleets-and-the-test-split.md)), and CI walks all three targets. Nor is
  it what keeps `homeModules.default` tracer-pure for `traceUser`: that is a property of the
  *module* — the default umbrella declares no `home.*` options at all — which
  [ADR-0013](0013-per-user-desktop-choice-host-offered.md) already enforces by splitting
  `greeterDesktop` out. Neither property would be threatened by a flake input; both would be
  threatened by putting `home.*` options in the default umbrella.

Cite this amendment, or ADR-0008, for the home-manager rule; cite the bullet above for
package-ecosystem neutrality.
