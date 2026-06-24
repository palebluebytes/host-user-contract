# The host is the sole authority for Tier-1 signing trust; a repo cannot vouch for itself

**Status:** Accepted; amends [ADR-0022](0022-anyhost-greeter-runtime-binding.md) (which placed the signing key in `identity.json`).

[ADR-0022](0022-anyhost-greeter-runtime-binding.md)'s Tier-1 flow said the greeter "verifies the repo signature against the key in `identity.json`." That is **circular**: Tier 1 means "operator-trusted / *my own* repos," but if the repo supplies the very key it is verified against, a hostile repo names its own key, signs with it, and **self-certifies into Tier 1** — collapsing Tier 1 into Tier 2's "anyone" threat model. A signature proves integrity (this tree is internally consistent), not *authenticity relative to this host*.

## Decision

The **host** is the sole Tier-1 trust anchor. The operator pins the allowed signers (`custom.greeter.trustedSigners`), and a repo is Tier-1 iff its `contract.sig` (an SSH signature over a manifest of the whole tree) verifies against an **operator-pinned** key. `identity.json.trustedKeys` is **not** consulted for tier classification — those are SSH **login** keys (consumed by `realization.nix` for `authorizedKeys`), a different purpose. A repo cannot assert its own trust tier.

## Considered Options

- **Verify against the repo's key in `identity.json`** ([ADR-0022](0022-anyhost-greeter-runtime-binding.md) literal) — rejected: self-certification, which defeats the point of a tier.
- **Intersection (host signers ∩ `identity.json.trustedKeys`, "both must vouch")** — rejected: the repo-side key is attacker-controlled, so requiring it vouches for nothing; it only adds a failure mode (an operator-trusted repo that forgot to list the key fails). Strictly worse than host-only.
- **Host-pinned signers (chosen)** — the operator is the trust anchor, matching Tier 1's "my own / operator-trusted" definition.

## Consequences

- `greeter.nix`'s auth verifies the tree-manifest signature against the host signers file **alone** — the code was already correct; the prior comment claiming a host∩repo "intersection" was wrong and is fixed.
- `identity.json` need not carry the signing public key at all; if present it is informational. The operator's pinned set is authoritative.
- The terms are kept distinct: **`trustedSigners`** (host-pinned, the Tier-1 signing authority) vs **`trustedKeys`** (repo-declared SSH login keys). Conflating them was the original error.
