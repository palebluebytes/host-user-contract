# An identity describes a person, never their powers

**Status:** Accepted (2026-08-20). Closes the last self-escalation channel opened by
[0001](0001-host-user-contract.md)'s trust boundary.

Every field of an identity is descriptive (`name`, `email`, `gmail`) or a login credential
(`hashedPassword`, `sshKey`, `trustedKeys`). Nothing in it decides what an account may **do**.

That was not always true. The identity carried `extraGroups`: a list of group names the user wrote
into their own public file, which the host materialized. It was protected by a **clamp** — a
deny-list of privileged names (`wheel`, `docker`, `libvirtd`, …) filtered out of the user's list and
restored only by a host decision.

The clamp was correct and it was not enough. It is a **deny-list**, so anything not on it passed
through unconditionally. `networkmanager` is the worked example: not privileged by the contract's
reckoning, materialized on every host that bound the user, chosen entirely by the user. On the
greeter path that means a stranger putting themselves in a group by editing their own repo.

## Decision

**`identity.extraGroups` is deleted. A user cannot name a group at all.**

An account's groups now come from exactly two sources, and both are decisions somebody else made:

| source | what it is | who decides |
| --- | --- | --- |
| `modes.<m>.groups` | what the **session** needs in order to run | the contract's registry |
| the affordances at the bind | what the **host** conferred on this person | the host operator |

A graphical session needs its input devices by virtue of being graphical — nobody should have to
decide that per person — so those ride the **mode**. A privileged power is a judgement about an
individual, so it rides the **bind**.

There is no third source, and no untrusted group input left to filter.

## The clamp survives, pointed at something else

`withoutPrivileged` still runs over the **mode's** groups, and that is not vestigial. The mode
registry is contract-owned, so a privileged group added there is a contract bug rather than an
attack — but without the filter it would reach every account in that mode with no affordance at all.
The conformance suite catches such an addition loudly; the clamp makes the same failure **safe** as
well as loud. Defence in depth, at the one layer that still has an input to defend.

## Consequences

- **The account audit becomes trivial.** Every identity field is inert or a credential; the only
  source of privilege is what the host afforded.
- **The escape hatch is unchanged and stays an escape hatch.** NixOS is open — a host can always
  write `users.users.<u>.extraGroups` directly for a group the contract models no feature for. That
  is the emergency valve, deliberately not the sanctioned path for a capability the contract can
  name.
- The realization no longer has an untrusted-input story to tell, because it no longer has untrusted
  input.

## Considered alternatives

- **Keep `extraGroups` and widen the clamp to an allow-list** — rejected: an allow-list of
  non-privileged groups is a catalog to maintain forever, wrong the moment a user wants a group it
  does not know, and it still lets a user choose from it unilaterally on every host.
- **Keep `extraGroups` for build-time binds only, deny it at a greeter** — rejected: two rules for
  one field, and the build-time path is exactly where a bad group is *most* durable.
