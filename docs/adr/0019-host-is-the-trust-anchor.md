# The host is the sole trust anchor: pinned signers and a pinned eval posture

**Status:** Accepted (2026-08-20). Two applications of one rule to
[0018](0018-greeter-runtime-flow.md)'s tiers.

> **A repo cannot vouch for itself.**

The rule shows up twice, in two places that look unrelated until they are stated together.

## 1. Classification — the operator pins the signers

The first design had the greeter verify a repo's signature against a key **carried in that repo**.
That is circular: a hostile repo names its own key, signs with it, and self-certifies into the
trusted tier, collapsing it into "anyone".

A signature proves *integrity* — this tree is internally consistent — never *authenticity relative
to this host*.

So the operator pins the allowed signers (`contract.greeter.trustedSigners`), and a repo is
trusted-tier iff its signature verifies against an **operator-pinned** key. The repo's own key list
is not consulted for classification.

The terms stay distinct, and conflating them was the original error:

| term | who owns it | what it is for |
| --- | --- | --- |
| `trustedSigners` | the **host** | the tier-1 signing authority |
| `identity.trustedKeys` | the **repo** | SSH **login** keys, realized as `authorizedKeys` |

An intersection — *"both must vouch"* — was rejected as strictly worse than host-only: the
repo-side key is attacker-controlled, so requiring it vouches for nothing, and it only adds a
failure mode where an operator-trusted repo forgot to list a key.

## 2. Evaluation — the contract pins the posture, and the repo cannot widen it

The same hole reappears through eval policy. A flake's own `nixConfig` is honoured by default, so a
repo could set `allow-import-from-derivation = true`, add substituters, and **relax the very
settings meant to contain it** — self-certification, applied to evaluation instead of to
classification.

The contract pins the posture as data (`tier1EvalConfig`), the greeter applies it, and the repo
cannot widen it:

```
accept-flake-config           = false   # the un-widenable linchpin
restrict-eval                 = true    # no reading /etc/shadow, no eval-time fetch
allow-import-from-derivation  = false   # eval cannot force a build and import its output
sandbox                       = true    # the build itself is isolated
```

`accept-flake-config = false` is the one that makes the other three mean anything.

The greeter renders this (`renderNixConfig`, single-sourced) and hands it to the host's `homeBuilder`
as `NIX_CONFIG`, which **augments** the seat's own configuration — so a naive `nix build` binding
inherits the floor for free. A host may **add** restrictions; it cannot remove these. The value is
exposed read-only for operator audit, fixed to the contract's.

## Consequences

- **Two seats running the same signed repo evaluate it under the same rules.** Before, the posture
  was the host's to invent.
- **Defence in depth, at three independent layers**: what an identity may say
  ([0006](0006-identity-describes-a-person.md)), what may be conferred
  ([0008](0008-features-are-atomic-and-privileged.md)), and now what evaluation itself may touch.
- **Tier 2 will pin a stricter posture** — the data shape generalizes — but stays deferred.

## Considered alternatives

- **Verify against a key in the repo** — rejected: self-certification, which defeats the point of a
  tier.
- **Leave the eval posture to the host** — rejected: no canonical floor, no enforcement, and the
  repo could widen its own eval.
- **Trust a signed repo fully and skip restricted eval** — rejected: a signature vouches for
  provenance, not for the repo being free of accidents or later compromise. The floor is cheap
  insurance.
- **A reference `homeBuilder` that enforces the posture itself** — rejected: building needs
  home-manager, which the contract does not ship. Pinning the posture as data and exporting it as
  `NIX_CONFIG` delivers the floor to whatever builder a host binds.
