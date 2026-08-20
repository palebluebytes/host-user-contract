# The greeter's runtime flow: data before code, and a standing seat baseline

**Status:** Accepted (2026-08-20). The program [0017](0017-greeter-is-a-contract-deliverable.md)
ships; applies [0005](0005-identity-is-inert-data.md)'s ordering.

## The flow

1. **Prompt** — flake URL, username, password.
2. **Fetch the source and its whole input closure** (`nix flake archive`) — no flake *output* is
   evaluated, so no user Nix has run.
3. **Authenticate eval-free** — `jq` the identity, verify the password with libc `crypt`, and for a
   trusted tier verify the tree signature ([0019](0019-host-is-the-trust-anchor.md)).
4. **Select the mode** — the first line of the stranger's Nix ever to run, and it runs the
   contract's own kernel ([0013](0013-selection.md), [0020](0020-runtime-evaluates-the-kernels.md)).
5. **Build** the user's own published home for that mode, under the pinned eval posture.
6. **Provision** — fully realize the account, then start the session.

The fetch step is what makes step 5 coherent: a restricted eval cannot reach the network, so every
locked input must already be a store path. *Fetch as data, then build restricted* mirrors
*authenticate as data, then run code*.

## Tiers are a parameter, not a fork

The greeter classifies a flake URL into a trust **tier**, and the tier sets knobs — eval strictness,
build limits, home persistence — rather than selecting a code path.

- **Tier 1 — semi-trusted (own identities). Built.** The repo is signed by a host-pinned key. The
  threat is *"my own repo is buggy or stale"*, not adversarial: restricted eval guards accidents,
  builds use the normal daemon sandbox, and the home is persisted. Signing is
  **authenticity and integrity, not safety** — a signed config can still be buggy, so the eval
  posture still applies.
- **Tier 2 — untrusted (anyone). Designed for, deferred.** Hardened eval with restricted builtins
  and resource limits, builds under cgroup and closure limits, and an ephemeral account wiped on
  logout. This is research-grade and explicitly out of scope to build; the design only has to leave
  the knobs where Tier 2 can turn them up.

The question the tier split answers honestly is *"is this for one's own identities roaming across
one's own hosts, or genuinely anyone?"* The first is a tractable personal-fleet feature; the second
is "run arbitrary strangers' Nix on my hardware".

## No per-login rebuild — a standing seat baseline

NixOS accounts are declarative, but a greeter binds at runtime. It does **not** rebuild the system
per login. Every greeter login receives exactly the safe set, which is statically known at the
host's build time, so the system-side effects are **uniform across all greeter users**. A seat
pre-realizes them once, declaratively: the session stacks, the display binding, and a
`greeter-users` group. Provisioning then materializes the account and **enrolls** it.

**The invariant that keeps it rebuild-free:** safe-set membership requires an effect be uniformly
pre-realizable as a seat capability. Anything needing per-login system mutation is build-time-only,
exactly as privilege already is — so the greeter stays rebuild-free by construction.

Per-login `nixos-rebuild` was rejected, and not on safety grounds: it is privilege-safe and
confinement-safe. It is operationally fragile — it mutates the *global* generation, so one bad login
degrades the seat for everyone; it races concurrent logins; and because the runtime user is not in
the operator's flake, the next operator switch **deletes** them. That is the imperative drift the
contract exists to remove.

## Provisioning fully realizes the account

A greeter user is never built into the system, so the build-time realization never runs for them. If
provisioning did no more than `useradd`, the account would have no password — PAM lockout, so a
persisted user could not unlock a screen locker — no keys, no description, and none of its groups.
That would break the promise that a greeter-bound user realizes identically to an operator-bound
one.

So provisioning sets the same hash the auth step already verified, installs the keys, sets GECOS,
adds the session's groups and enrolls the account in the baseline. **Account realization and home
activation both complete before the session starts.**

## Consequences

- **Scope is single-seat personal machines.** greetd serializes the seat, so greeter logins never
  overlap, and a logout→login transition is an ordinary display-server handoff.
- **The contract ships no compositor.** A default one would be heavy, opinionated, and would force a
  desktop on every seat — the session backend is a host binding
  ([0021](0021-display-server-agnostic.md)).
- **Runtime provisioning is genuinely novel work.** A greetd greeter that evaluates a flake and
  provisions an account at login does not exist off the shelf.

## Considered alternatives

- **Build the untrusted tier first** — rejected: research-grade sandboxing would gate the useful
  feature indefinitely.
- **Build only the semi-trusted case** — rejected: cheap now, but it bakes "trusted" into the
  mechanism, so adding strangers later is a rewrite rather than a knob.
- **Account and home only, no system-side effect** — viable today, since logind hands the active
  session its device ACLs, but silently lossy the moment a session shape needs a group. The standing
  baseline subsumes it without a rebuild.
