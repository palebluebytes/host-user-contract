# Runtime grant effects are a standing greeter-seat baseline, not a per-login rebuild

**Status:** Accepted; refines [ADR-0022](0022-anyhost-greeter-runtime-binding.md) (the runtime binding flow) and builds on [ADR-0024](0024-greeter-is-a-contract-deliverable.md) (the greeter is a contract deliverable).

A greeter binds a user at **runtime**, but NixOS users are **declarative**: the build-time path turns a grant into system-side account effects through the realization (a granted gui user gets the `uinput` group and the host's gui surface — `realization.nix`). The question this settles is *how a runtime greeter login obtains those effects*, given it cannot re-author the operator's flake.

## Decision

**The greeter does not rebuild the system per login.** Every greeter login receives *exactly* `greeterGrants` (default-open over the safe set, ADR-0024), and the safe set is statically known at the host's build time, so the grant's system-side effects are **uniform across all greeter users**. A seat therefore **pre-realizes them once, declaratively** — a standing *greeter-seat baseline*: the safe-set group memberships as a `greeter-users` group, both session stacks installed, the session/display backend bound. Runtime `provision` then only materializes the (Tier-1 persisted) account, activates the home, and **enrolls** the account into that standing baseline.

**Invariant that keeps it rebuild-free:** safe-set membership requires an effect be *uniformly pre-realizable as a seat capability*. Anything that would need per-login system mutation is build-time-only — exactly as privilege already is — so the greeter stays rebuild-free by construction.

**Session launch (ADR-0022 step 8):** the greeter **selects** the session type from the bound home's `gui.session` — contract *mechanism*, conformance-checkable. The **host binds the session backend** per type (`custom.greeter.session.{wayland,x11}`, null-default, like `homeBuilder` and the display backend), and a user's home may override with its own compositor (ADR-0022: packages are the user's self-contained concern). Host-as-primary so a minimal, contract-pure home still gets a session. The contract ships no compositor (package-free, [ADR-0020](0020-extract-contract-flake.md)).

**Scope: single-seat personal machines** (laptop / single-monitor desktop). greetd serializes `seat0`, so greeter logins never overlap; on a logout→login transition the greetd + logind teardown/setup hands off the GPU (a Wayland session releasing DRM master before the next X11 session acquires it), both stacks being standing seat properties.

## Considered Options

- **Per-login `nixos-rebuild` to apply the grant** — rejected. It is *privilege-safe* (the safe set bounds what any application mechanism can confer) and *confinement-safe* (the user's home has no system channel, so its eval cannot inject system config), but operationally fragile: it mutates the **global** generation, so one bad login degrades the seat for everyone; it races concurrent logins; and because the runtime user is not in the operator's flake, the next operator switch **deletes** it — the imperative drift the contract exists to remove.
- **Account + home only, no system-side effect** — viable *today* (logind hands the active session its device ACLs; greetd launches the session), but silently lossy if a future safe-set feature needs a group. The baseline subsumes it without a rebuild.
- **Ship a default compositor in the greeter** — rejected: a compositor is a heavy, opinionated package; shipping one breaks package-free and forces one desktop on every seat. The session backend is a host binding, like the display backend.

## Consequences

- `provision` gains an **enroll** step (add the account to `greeter-users`) and, as the next slice, the **session-launch** (step 8) that reads `gui.session` and execs the host-bound session backend. Until that lands, the bind-script comment claiming "start the session" is ahead of the code.
- A greeter seat must **declare the baseline** (both session stacks + the bound backend) to host any runtime user; a headless host declares none — incapacity, not a ban ([ADR-0018](0018-user-confinement-manifest-greeter.md)).
- The Wayland↔X11 transition is a logind/backend concern (DRM-master handoff), the same host-binding boundary as the SDDM rendering: the contract decides the session *type*, the host renders it.
