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

## Numbering

These numbers are **inherited from the fleet repo** where the contract was designed, and
are intentionally **non-contiguous**: this arc began at 0015, and `0016`–`0017` are
fleet-only host decisions (esphome bulbs, the jmap-bridge repo split) that have no place
here. The original numbers are preserved deliberately — an ADR number is an immutable
identifier, and the same number refers to the same decision in this repo's code comments,
the fleet repo's code and `CONTEXT.md`, and git history across both. They are not
renumbered to close the gap.

Cross-references in these ADRs to ADRs **not** in this repo (e.g. ADR-0002, ADR-0013,
ADR-0014, ADR-0017) appear as plain `ADR-00NN` text rather than links: those decisions live
in the fleet repo. References between the ADRs listed above stay as live links.
