# The greeter is a contract deliverable

**Status:** Accepted (2026-08-20). Makes [0001](0001-host-user-contract.md)'s north star the
contract's promise rather than each fleet's rebuild.

*"Any host runs a greeter that takes a flake URL, a username and a password, and transparently
enables that person"* is the contract's north star. Describing the greeter as a **consumer**
concern — every fleet authoring its own greetd wiring and its own binding flow — reintroduces
exactly the drift the contract exists to remove, and on the one path where the security-critical
code lives.

## Decision

**The contract ships the greeter.** `nixosModules.greeter` is a separate module a seat host enables;
the host supplies only bindings.

The split is drawn to keep the security-critical part uniform while letting the heavy, opinionated
part be a reference a host can replace — and, deliberately, to keep the contract's hard dependency
package-free ([0002](0002-contract-is-a-standalone-flake.md)).

| | what | where |
| --- | --- | --- |
| **Canonical & mandatory** | the eval-free auth ordering, the mode-selection rule, the account rule, the derived safe set | pure `lib`/modules, no package |
| **Reference & replaceable** | the greetd integration, the UI, the privileged provisioning helper | the module a host may swap |

A replacement greeter is **conformant** iff it (1) authenticates eval-free on inert identity data
before any user Nix runs, (2) builds the user's own published home through the contract, and
(3) confers at most the safe set. Those three are the contract; everything else about a greeter is
the host's to change.

A host **cannot weaken** the canonical half: it is the contract, not the program.

## What stays host-side

Bindings only, never mechanism: which seats enable it, the display and theme, the trust-tier policy,
the desktops offered and each one's launch command, and the `homeBuilder` that actually builds a
home (which needs home-manager, and so cannot be the contract's).

A headless host simply never enables it — **incapacity, not a ban**. That distinction carries
weight: a host with no display cannot run a greeter, which is not a security decision; *prohibition*
is the security verb and must not be diluted by modelling "no screen" as one.

The contract evaluates with the greeter module present but **unbound**, which is the second litmus
test of [0002](0002-contract-is-a-standalone-flake.md).

## Consequences

- **A greeter-bound user and an operator-bound user realize identically**, because both go through
  the same rules — see [0020](0020-runtime-evaluates-the-kernels.md).
- **The conformance suite gains a greeter dimension** proven against synthetic users with no host
  repo: the auth flow is executed, the eval posture is asserted, and the provisioning helper runs in
  a VM against a stub.
- **The end-to-end proof lives where home-manager does** — the reference fleets
  ([0022](0022-oracle-and-reference-fleets.md)) — because the contract cannot build a home.

## Considered alternatives

- **The greeter as a fleet-authored profile** — rejected: it re-authors the security-critical auth
  flow per fleet, and contradicts *"any host runs a greeter"* being a promise rather than a rebuild.
- **The binding logic in the contract but the greeter module host-side** — rejected: it splits one
  mechanism across the boundary, so the runtime path is half-contract and half-fleet.
- **A single non-replaceable greeter baked in** — rejected: it makes the contract ship a bespoke
  privileged binary as a *hard* dependency and forces one greetd/UI choice on every fleet. Shipping
  it as an overridable reference keeps the mechanism canonical while the program stays replaceable.
- **Ship the rules and a spec, no reference greeter** — rejected: it abandons the north star and
  makes every fleet re-derive the auth flow. A tested reference is the point; replaceability is the
  escape hatch, not the default.
