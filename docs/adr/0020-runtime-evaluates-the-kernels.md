# Runtime realization evaluates the contract's own kernels, rather than re-spelling them

**Status:** Accepted (2026-08-20). What makes
[0017](0017-greeter-is-a-contract-deliverable.md)'s "realizes identically" true rather than
aspirational.

Two rules have to hold at both build time and login time:

- **the account rule** — how an identity, a mode and an affordance set become a system account;
- **the mode rule** — how a machine's run set and a user's publication become one mode.

Each was implemented twice: once in Nix for the declarative path, once in `jq` for the greeter. Only
the *inputs* were single-sourced. The **rules themselves lived in two languages**, and both
duplications cost the same three things.

**They had two owners.** A change to either fold had to land in Nix *and* in the shell, or the two
silently diverged.

**The compiler could not see across the boundary.** The spellings were reconciled only by a VM that
booted a machine and diffed the result field-for-field, so every branch of the shell needed its own
drift guard.

**One of them had already drifted.** The Nix selection kernel refuses two rich modes by name; the
`jq` took whichever sorted first and logged a stranger into it.

**And the claim justifying them was false.** The comments said a shell login "cannot call the Nix
function". But both steps run *after* the eval-free auth gate and after the greeter has already run
`nix flake archive` and a home build. Nix is in hand.

## Decision

**The greeter executes the contract's own kernels.** Two small internal, greeter-scoped tools pin
the contract source and a nixpkgs `lib` in-store, re-import the kernel by name, and print the answer:

| tool | evaluates | replaces |
| --- | --- | --- |
| `contract-account-plan` | `accountPlan` | the account fold in `jq` |
| `contract-select-mode` | `selectModeOver` | the selection fold in `jq` |

`provision` becomes a **pure renderer**: it execs the tool and writes GECOS, the password,
`authorizedKeys` and the groups. It owns no combining logic.

Because the kernels close over helper functions rather than data, the tools reconstruct them **from
source** at runtime rather than shipping an applied function or a generated shell — so the registry
and the group filter are single-sourced too, with nothing re-spelled.

The seat's own run set is frozen into the build rather than being a contract constant. It used to be
one, asserting that every seat had a display, so a headless box claimed to run a graphical session.

## `--impure`, and that is honest

The tools read a runtime path and an identity by environment, so the evaluation is impure. It is
**contract-owned code over already-authenticated data**, run after the auth gate: it evaluates no
user Nix, and it touches neither the data-before-code boundary
([0005](0005-identity-is-inert-data.md)) nor the user-code eval posture
([0019](0019-host-is-the-trust-anchor.md)). It is a one-shot login computation, not a reproducible
build, so purity buys nothing.

**Fail-closed.** If an evaluation fails — a malformed identity that slipped past auth, a contract
bug — provisioning aborts before touching the account. No half-realized login.

## Consequences

- **The rules are proven without a boot.** Their guarantees move to a pure eval domain driving the
  kernels directly; the VM's job narrows to proving the **renderer** surfaces the answer faithfully.
- **One `nix eval` per login.** No network, since the closure is already warmed, and sub-second
  against a path that already does an archive and a home build.
- **The interface is the test surface.** Verifying either rule no longer means running two encodings
  and diffing them.
- **The seat marker stays out of the rule.** `accountPlan` remains the seat-agnostic portable
  account; the `greeter-users` marker — the one group a build-time user never gets — is added on the
  render side.

## Considered alternatives

- **Generate the shell from the Nix rule at build time** — rejected: it is still two artifacts, and
  the generated one is the harder to read when it is wrong.
- **Keep the duplication and rely on the parity VM** — rejected: the VM is what the duplication
  *cost*, not what made it safe, and it had already failed to catch a live divergence.
- **Let the seat redefine the account rule** — rejected: the mechanism/binding split
  ([0017](0017-greeter-is-a-contract-deliverable.md)) puts the account rule squarely in mechanism.
