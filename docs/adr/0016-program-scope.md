# Program scope: the `nix-daemon` feature and the package policy

**Status:** Accepted (2026-08-20). Follows from
[0011](0011-prebuilt-binding-mode.md)'s "packages are advisory".

[0011](0011-prebuilt-binding-mode.md) establishes that a user owns their package versions. This
records the complementary question: what happens when a host wants to restrict which **programs**
appear in a session at all.

The insight that frames the answer: **packages are only advisory because the user has daemon
access.** A user with the daemon socket can `nix shell nixpkgs#anything` and bypass any
home-config-level policy. Hard restriction therefore requires removing daemon access at the OS
level, not configuring it at the home level. Once it is removed, the programs reachable in the store
are bounded by what the host placed there.

The threat being closed is precisely **a user running software that was not in their home config at
all** — distinct from, and far easier than, restricting transitive dependencies.

## Decision

### 1. `nix-daemon` is a feature

It confers `nix-users`, and the host wires `nix.settings.allowed-users = [ "@nix-users" ]`. A user
without it is **daemon-restricted**: they cannot build derivations, install packages, or add store
paths beyond what the host placed there when activating their home.

`nix-users` is privileged, so this is build-time-only and **a greeter never confers daemon access**
([0008](0008-features-are-atomic-and-privileged.md)). It needed no new mechanism — the groups path
already existed.

### 2. The package policy is an inclusion list

```nix
contract.packagePolicy.allowedPrograms = [ "firefox" "vim" "git" ];
```

The effective profile is the **intersection** of that list with the user's package manifest: what
the user declared *and* the host allows. Programs the user declared but the host does not allow are
absent; programs the host allows but the user did not declare are not imposed.

One canonical version per program — whatever is in the host's nixpkgs. The host's update cadence
*is* the version policy; no multi-pin negotiation.

### 3. A non-compliant home always deploys

A home declaring programs off the list is **not rejected**. It activates as written and the
unapproved programs are simply absent. Config generated for them (`~/.config/nvim/` from an enabled
editor whose binary is off the list) is present but inert.

That is the correct behaviour: the user's expressed configuration is respected as fully as the
host's policy allows. Rejection is harsh and could leave a person without a working session — and
this is the *degradation* posture, in contrast to the mode mismatch of
[0013](0013-selection.md), which is a refusal because nobody can rescue it.

## The residual risk is accepted and named

A capable daemon-restricted user can execute a program by absolute store path without it appearing
on `PATH`. What is reachable that way is bounded by their own activation package's transitive
closure — software the host audited when it updated the pin.

Closing that needs OS-level mechanisms (Landlock, mount namespaces) with complexity equivalent to
lightweight containers, and is out of scope. The threat this record closes is fully closed; the
residual is documented rather than hidden.

## Consequences

- **The realization needs no new logic** — `nix-users` is handled exactly as any other conferred
  group.
- **`allowedPrograms` is a host binding**, consistent with every other host-supplied binding: the
  contract ships the mechanism, the host supplies the list.
- The vocabulary — *program scope*, *daemon-restricted user*, *inclusion list* — is stable.

## Considered alternatives

- **Reject non-compliant homes** — rejected: worse experience for no security gain, since the
  binaries are absent either way.
- **Filter the package set the home evaluates against, so unapproved programs fail to build** —
  rejected with the inline-eval path it required ([0011](0011-prebuilt-binding-mode.md)): it
  reintroduces user-Nix evaluation on the host to close a residual that daemon restriction already
  bounds.
- **Version negotiation across multiple pins** — rejected: complexity with no consumer; the host's
  single pin is a comprehensible policy.
