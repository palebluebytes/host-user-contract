# Architecture Decision Records

The design narrative for the host↔user contract. Start with
[`0015`](0015-host-user-contract.md) (the contract itself), then
[`0020`](0020-extract-contract-flake.md) (why it's this repo), then
[`0022`](0022-anyhost-greeter-runtime-binding.md) / [`0023`](0023-user-flake-shape.md) /
[`0024`](0024-greeter-is-a-contract-deliverable.md) (the greeter + user-flake shape the
contract ships).

| ADR | Decision |
| --- | --- |
| [0015](0015-host-user-contract.md) | Hosts and users live in separate repos, bound by a shared contract |
| [0018](0018-user-confinement-manifest-greeter.md) | A user is a home-manager module: requests, feature modules, and the anyHost greeter |
| [0019](0019-feature-configuration-aggregates.md) | Host-affecting feature configuration aggregates across granted users (the gui-session union) |
| [0020](0020-extract-contract-flake.md) | The contract lives in its own flake, delivered as a registry-baked kit |
| [0021](0021-platform-backend-agnostic-secrets.md) | The platform interface abstracts secret *provisioning*, not just file location |
| [0022](0022-anyhost-greeter-runtime-binding.md) | The anyHost greeter: tiered runtime binding of a user from a flake URL |
| [0023](0023-user-flake-shape.md) | The user flake shape and `bindUser` |
| [0024](0024-greeter-is-a-contract-deliverable.md) | The greeter is a contract deliverable: `bindUser` in `lib` + a reusable greeter module |
| [0025](0025-binduser-single-identity-loader.md) | `bindUser` is the single identity loader; the home holds its identity, it does not load it |
| [0026](0026-greeter-seat-baseline-not-per-login-rebuild.md) | Runtime grant effects are a standing greeter-seat baseline, not a per-login rebuild |
| [0027](0027-host-is-sole-tier1-signing-authority.md) | The host is the sole authority for Tier-1 signing trust; a repo cannot vouch for itself |

## Numbering

These numbers are **inherited from the fleet repo** where the contract was designed, and
are intentionally **non-contiguous**: this arc began at 0015, and `0016`–`0017` are
fleet-only host decisions (esphome bulbs, the jmap-bridge repo split) that have no place
here. The original numbers are preserved deliberately for traceability: within *this* repo
an ADR number is an immutable identifier, stable across its code comments and git history,
and the same number traces back to the fleet history where the arc was authored. Two
caveats keep this short of a clean cross-repo identity, both intentional and harmless:

- the arc's ADRs were **deleted from the fleet on extraction** — they live only here now, so
  most of these numbers no longer resolve to anything in the fleet repo; and
- `0023` **collides** — here it is the user-flake shape, but in the fleet `0023` is a
  different, still-live decision (matrix-hookshot). The repos are separate so nothing breaks,
  but "ADR-0023" is ambiguous in cross-repo conversation.

The numbers are not renumbered to close the gap or the collision.

Cross-references in these ADRs to ADRs **not** in this repo (e.g. ADR-0002, ADR-0013,
ADR-0014, ADR-0017) appear as plain `ADR-00NN` text rather than links: those decisions live
in the fleet repo. References between the ADRs listed above stay as live links.
