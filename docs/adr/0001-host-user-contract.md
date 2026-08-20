# Hosts and users live in separate repos, bound by a shared contract

**Status:** Accepted (2026-08-20). The founding decision; every other record refines it.

The goal is that **any host can enable any user, and that user transparently works** — login,
dotfiles, the session they need — while the host keeps an absolute say over what that account may
*do*. That cannot hold while a user *is* part of one host's repo: the user's identity, home and
credential are coupled to that host's `self`, its inputs, its secrets store and its module set.

The decision is **two repos joined by a third**, and the third is the point.

- A **contract** flake declares the vocabulary both sides agree on: who a person is, what session
  shapes exist, what powers exist, and the shape of the artifact that passes between them. Both a
  host repo and a users repo depend on it.
- A **users repo** declares its people: an identity, and the session shapes each runs in with a
  home for each. It never names a host, a secrets backend, or anybody's `self`.
- A **host repo** consumes the contract, states what the machine can run, binds the users it wants,
  and decides what each of them may do.

A self-contained user flake with no third party was rejected, and the reason is the whole design:
*"deny this user containers"* is a **negotiated interface**. It needs a shared vocabulary of names
both sides use, which only an agreed third schema can provide. Without it a host can refuse a user
entirely but cannot refuse one *thing* about them.

## The two rules that make the boundary real

**Default-closed.** A host confers only what it explicitly affords. "Deny" is the absence of an
affordance, not a veto that must be remembered. The alternative — user powers on by default, host
vetoes — was rejected: a new power would silently activate on every machine in the fleet until each
one wrote a refusal, and a fleet-wide blast radius is the opposite of host sovereignty.

**Treat every user-declared value as untrusted input.** Any field the host reads that confers
host-side power is an escalation vector. The contract's answer has hardened over time from *clamp
the dangerous values* to *the user cannot express them at all* — see
[0006](0006-identity-describes-a-person.md).

## The boundary is a type boundary, not a trust boundary

A repo that exports arbitrary NixOS modules can set `users.users.root`, `security.sudo`, or an
activation script — outside every gate. With raw modules, "deny" is cosmetic and enabling a user
means trusting that repo as root.

The contract's answer is that a user's surface is **not a NixOS module**. It is a typed declaration
([0010](0010-user-declares-session-shapes.md)) whose only free-form content is a *home*, and a home
physically cannot write system state. The confinement is a property the boundary already has rather
than one the contract polices.

## Consequences

- **"Enable a user" and "afford a power" are two distinct acts.** The first is mechanical and
  crypto-free. The second is a deliberate, per-person decision.
- **The contract is a dependency of both repos**, so a vocabulary change is breaking across the
  boundary and must be pinned like any other flake input.
- **The realization lives in the contract, once.** Every host mapping an identity to `users.users`
  itself is the drift this exists to remove.

## Considered alternatives

- **A self-contained user flake, no contract** — rejected: no shared names, so no per-power refusal.
- **Default-open veto** — rejected: fleet-wide blast radius; a host is sovereign by construction or
  it is not sovereign.
- **Each host owns the identity → account mapping** — rejected: identical boilerplate per host, and
  the drift returns the moment two hosts disagree.
- **A rich `specialArgs` bundle from host to user** — rejected: `specialArgs` are not type-checked,
  so it becomes a second, unwritten contract whose missing field is a late `attribute missing`
  rather than an option error.
- **The user exports arbitrary modules** — rejected as the target: a module can set any option
  outside any gate, so denial is unenforceable.
- **The user exports flat data only** — rejected: enforceable, but it collapses the user's config
  power to literal file payloads. A typed declaration carrying an opaque *home* gets both.
