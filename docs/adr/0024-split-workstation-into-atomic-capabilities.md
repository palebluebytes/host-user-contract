# Split the `workstation` role into atomic capability features (`sudo` + `containers`)

**Status:** Accepted (2026-08-05). Retires the `workstation` feature of [ADR-0001](0001-host-user-contract.md)'s registry, replacing it with the atomic `containers` feature alongside the existing `sudo`. A companion to [ADR-0004](0004-extract-contract-flake.md) (the contract as a reusable artifact).

The feature registry was atomic everywhere but one entry. `sudo` is "wheel and nothing more", `virtualization` is the libvirtd groups, `nix-daemon` is daemon access — each a single-purpose capability. `workstation` was the odd one out: a **role bundle** conferring `docker` + `podman` + `wheel` at once. Three problems followed from that:

1. **It read as ergonomics but meant root, three ways.** `wheel` is sudo; the `docker` socket is passwordless root (`docker run -v /:/host`); a root `podman` socket is the same. Granting `workstation.enable = true` looked like "dev conveniences" but conferred root-equivalent access three independent ways — and since `docker` already implies root, *also* bundling `wheel` was redundant.
2. **Features overlapped instead of composing.** `workstation ⊇ sudo` on the `wheel` axis (the code comment apologised for it), and there was **no way to express "docker without sudo"** — the hardened CI/build-user case. A role bundle forecloses the combinations a capability vocabulary leaves open.
3. **It sat oddly in "the reusable artifact" (ADR-0004).** The contract's grant vocabulary should be *composable capabilities*, not hard-coded personas. "Workstation" is a host's policy label, assembled from capabilities — not itself a capability.

An earlier draft of this decision went further and made container access **host-conferred** — `docker`/`podman` reserved-privileged with *no* feature, conferred by a raw `users.users.<u>.extraGroups` line. That was rejected: it introduced a second, unclamped source of privilege beside the grant matrix (a host could confer *any* group that way, bypassing the "grant is the sole source of privilege" invariant), split the answer to "what can this account do?" across two places, and broke the pre-built binding convention (container access would be invisible to `bindContractPackage`'s grant coupling). The "per-host decision" argument for it was empty — a **grant is already a per-host decision**. There is no principled line that keeps `sudo` (a bare privileged group the contract wires nothing structural for) a feature while denying `containers` (the same shape) one.

## Decision

**Replace the `workstation` role with atomic capability features. A privileged group is conferred by exactly one feature, and a host composes features rather than granting a role.**

- **Remove `workstation`.**
- **Add `containers`**: `privilegedGroups = [ "docker" "podman" ]`. Container-runtime access, and nothing else.
- **`wheel` stays on the existing `sudo`.**

A host that wants the old workstation bundle now writes `grants = { sudo.enable = true; containers.enable = true; }`. A host that wants containers *without* interactive root writes `grants = { containers.enable = true; }` — newly expressible. `docker`/`podman` remain privileged (so self-declaration in `identity.extraGroups` is still clamped) purely by virtue of being some feature's `privilegedGroups`; `reservedPrivilegedGroups` is untouched (`kvm` only) and the clamp mechanism (ADR-0001) is unchanged.

## Consequences

- **Grants stay the sole source of privilege.** Everything a user can do is still derivable from `identity` + `grants` in one place — no side channel. The pre-built binding path (`bindContractPackage { grants }`) covers container access for free, baked into the manifest's grant coupling like any other feature.
- **The proofs move mechanically, and one strengthened.** The clamp/isolation proofs switch `workstation`→`containers` and keep proving the same promises (a self-declared `docker` is clamped; the `containers` grant's docker/podman reach only the granted account, not co-residents; a new assertion proves `containers` confers *both* docker and podman). The safe-set exclusion now enumerates every privileged feature (`containers`, `sudo`, `virtualization`, `nix-daemon`).
- **Grants compose.** "docker without wheel" and "wheel without docker" are both expressible; no feature contains another.
- **The raw-`extraGroups` hatch still exists — as an emergency hatch, not the pattern.** A host *can* always add a group to `users.users.<u>.extraGroups` directly (NixOS is open); for a group the contract deliberately models no feature for, that remains the escape valve. It is deliberately not the sanctioned path for a capability the contract *can* name.
- **Downstream migration.** Any consumer that granted `workstation` splits it into `sudo` and/or `containers`. In this repo that is `examples/fleet` (done — `cleo` is granted `containers`). The external `~/code/nixos` fleet (`kelpy` and the `prebuilt-bind-external` checks) migrates when it next updates its `contract` pin.

## Considered Options

- **Keep `workstation` as-is** — rejected: the one coarse role-bundle in an atomic registry, redundant on `wheel`, and blocks "docker without sudo".
- **Host-conferred containers** (reserved-privileged, no feature, raw `extraGroups`) — rejected for the reasons above: a second unclamped privilege channel, split source of truth, broken pre-built convention, and a justification ("per-host") that a grant already satisfies.
- **Atomic `containers` feature (chosen)** — consistent with `sudo`/`virtualization`/`nix-daemon`, keeps grants the sole source of privilege, composes cleanly, and lets the contract *express* container access as a first-class capability.

## If the split should merge again

Reversible by a new ADR: fold `containers` back into a role (or rename it), migrate the grant sites, and adjust the proofs. Nothing here is load-bearing beyond the registry entry and its grant sites.
