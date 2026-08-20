# Features are atomic, every one of them is privileged, and the safe set is empty

**Status:** Accepted (2026-08-20). Refines the feature half of
[0007](0007-two-registries.md); the security floor a greeter stands on.

## Atomic capabilities, never roles

The registry was atomic everywhere but one entry. `sudo` was "wheel and nothing more";
`virtualization` was the libvirt groups; `nix-daemon` was daemon access. `workstation` was the odd
one out — a **role bundle** conferring `docker` + `podman` + `wheel` at once. Three problems
followed:

1. **It read as ergonomics and meant root, three ways.** `wheel` is sudo; the docker socket is
   passwordless root (`docker run -v /:/host`); a root podman socket is the same. And since docker
   already implies root, bundling `wheel` was redundant on top.
2. **Features overlapped instead of composing.** There was no way to express *"containers without
   sudo"* — the hardened build account.
3. **A role is a host's policy label**, assembled from capabilities. It is not itself a capability.

**A privileged group is conferred by exactly one feature, and a host composes features.** A host
wanting the old bundle writes `sudo` and `containers`; one wanting containers without interactive
root writes `containers` alone.

An earlier draft went further and made container access host-conferred through a raw `extraGroups`
line with no feature at all. Rejected: a second, unclamped source of privilege beside the
affordances, the answer to *"what can this account do?"* split across two places, and invisible to
every guard. Its argument — that container access is a per-host decision — was empty, because **an
affordance is already a per-host decision.**

## Every feature is privileged, and that is a property to read off the file

With the display capability moved to the mode registry ([0007](0007-two-registries.md)), what
remains is exactly the set of powers that need a deliberate, per-person decision:

| feature | groups | why privileged |
| --- | --- | --- |
| `containers` | `docker`, `podman` | the socket runs containers that mount the host fs as root |
| `sudo` | `wheel` | administrative access, and nothing more |
| `virtualization` | `disk`, `libvirtd`, `qemu-libvirtd` | running VMs is a power somebody granted |
| `nix-daemon` | `nix-users` | build derivations and add store paths — see [0016](0016-program-scope.md) |

## Privilege is build-time-only, and the safe set is therefore empty

**Runtime-eligibility is derived, never declared.** A feature is in the `safeSet` iff it confers no
privileged group. Every feature does, so:

```
safeSet = [ ]
```

A greeter confers **nothing at all**. A stranger with a flake URL gets a *session* — because a
session is what the machine runs ([0009](0009-host-declares-modes.md)) — and can never obtain
wheel, docker, or daemon access.

Deriving this rather than flagging it is the point: *what a stranger may have* stays provably tied
to *what confers no privilege*, with nothing to keep in sync. A manual `defaultGranted` flag per
feature was rejected for exactly that reason — it would drift from the real safety property.

## The empty set is load-bearing, so it is asserted brittlely

Conformance carries a deliberately fragile `safeSet == [ ]`. It is **meant to fire**: the emptiness
is why a greeter is safe, and adding a non-privileged feature would quietly make it false. Failing
loudly at the moment somebody adds one is the whole point of the assertion.

## Consequences

- **Affordances compose.** "docker without wheel" and "wheel without docker" are both expressible;
  no feature contains another.
- **The greeter needs no allow-list.** It confers the safe set, and the safe set is derived.
- **A future non-privileged feature is a decision, not an accident** — it would land in the safe set
  automatically, and the tripwire above forces somebody to notice.

## Considered alternatives

- **Keep a role bundle for ergonomics** — rejected: one coarse entry in an atomic registry,
  redundant on `wheel`, and it forecloses combinations a capability vocabulary leaves open.
- **Host-conferred container access with no feature** — rejected: a second unclamped privilege
  channel, and "per-host" is what an affordance already is.
- **Declare runtime-eligibility per feature** — rejected: a flag that can disagree with the groups
  it describes.
