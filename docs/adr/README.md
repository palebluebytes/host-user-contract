# Architecture Decision Records

The design narrative for the host↔user contract. Start with
[`0001`](0001-host-user-contract.md) (the contract itself), then
[`0004`](0004-extract-contract-flake.md) (why it's this repo), then
[`0006`](0006-anyhost-greeter-runtime-binding.md) / [`0007`](0007-user-flake-shape.md) /
[`0008`](0008-greeter-is-a-contract-deliverable.md) (the greeter + user-flake shape the
contract ships).

| ADR | Decision |
| --- | --- |
| [0001](0001-host-user-contract.md) | Hosts and users live in separate repos, bound by a shared contract |
| [0002](0002-user-confinement-manifest-greeter.md) | A user is a home-manager module: requests, feature modules, and the anyHost greeter |
| [0003](0003-feature-configuration-aggregates.md) | Host-affecting feature configuration aggregates across granted users — the gui-session union (superseded by [0021](0021-contract-display-server-agnostic.md)) |
| [0004](0004-extract-contract-flake.md) | The contract lives in its own flake, delivered as a registry-baked kit |
| [0005](0005-platform-backend-agnostic-secrets.md) | The platform interface abstracts secret *provisioning*, not just file location (superseded by [0023](0023-contract-handles-no-secrets.md) — the contract handles no secrets) |
| [0006](0006-anyhost-greeter-runtime-binding.md) | The anyHost greeter: tiered runtime binding of a user from a flake URL |
| [0007](0007-user-flake-shape.md) | The user flake shape and `bindUser` |
| [0008](0008-greeter-is-a-contract-deliverable.md) | The greeter is a contract deliverable: `bindUser` in `lib` + a reusable greeter module |
| [0009](0009-binduser-single-identity-loader.md) | `bindUser` is the single identity loader; the home holds its identity, it does not load it |
| [0010](0010-greeter-seat-baseline-not-per-login-rebuild.md) | Runtime grant effects are a standing greeter-seat baseline, not a per-login rebuild |
| [0011](0011-host-is-sole-tier1-signing-authority.md) | The host is the sole authority for Tier-1 signing trust; a repo cannot vouch for itself |
| [0012](0012-runtime-provisioning-is-shell-side-realization.md) | Runtime provisioning is the shell-side realization: fully realize the account before the session |
| [0013](0013-per-user-desktop-choice-host-offered.md) | A greeter login is a per-user desktop choice; the seat offers desktops, the contract carries the name |
| [0014](0014-tier1-restricted-eval-posture.md) | The contract pins the Tier-1 restricted-eval posture; the greeter applies it, the repo cannot widen it |
| [0015](0015-greeter-secret-provisioning.md) | Greeter secret provisioning is one seam with a staged strength spectrum (superseded by [0023](0023-contract-handles-no-secrets.md) — the greeter activates secret-free) |
| [0016](0016-prebuilt-binding-mode.md) | Pre-built binding mode: user CI produces `contractPackage`; the host pins, reads, and activates it |
| [0017](0017-daemon-restricted-user-package-policy.md) | Daemon-restricted users and host-built package profiles: the `nix-daemon` feature, package policy, and graceful degradation |
| [0018](0018-session-type-derives-from-desktop.md) | Session type derives from the desktop (superseded by [0021](0021-contract-display-server-agnostic.md) — session type is not a contract concern) |
| [0019](0019-login-credential-travels-with-the-user.md) | The login credential travels with the user as public data; visibility picks the hash strength |
| [0020](0020-multi-user-repo-shape.md) | The `users` repo: a multi-user grouping of the operator's own accounts (extends 0007) |
| [0021](0021-contract-display-server-agnostic.md) | The contract is display-server-agnostic; the seat owns session type and launch (supersedes 0018 + the gui-session union of 0003) |
| [0022](0022-reference-fleets-and-the-test-split.md) | Reference user + host fleets as sibling flakes; the synthetic suite is the adversarial oracle, the fleet a positive-space reference that borrows atoms one-way |
| [0023](0023-contract-handles-no-secrets.md) | The contract handles no secrets beyond the login credential (supersedes 0005 + 0015; retires ADR-0001's secret-bearing mechanisms) |
| [0024](0024-split-workstation-into-atomic-capabilities.md) | Split the `workstation` role into atomic capability features (`sudo` + `containers`); a privileged group is conferred by exactly one feature |
| [0025](0025-turnkey-host-side-bind.md) | Turnkey host-side bind: `grant = affordances ∩ offer`, variant selection from the baked set, the ADR-0016 coupling guard enforced (extends 0016/0020/0007) |
| [0026](0026-consumer-producer-public-surface.md) | The public surface is the coin `mkContractUser`/`mkContractUsers`/`bindContractUser` + `traceUser`; retires inline-eval and unilateral direct-grant, internalizes the package kernels (amends 0007/0008/0016/0025) |
| [0027](0027-runtime-provision-evaluates-the-shared-rule.md) | Runtime provision *evaluates* the shared `accountPlan` (via `contract-account-plan`) instead of re-spelling it in jq; the rule has one source, the clamp is proven without a boot (extends 0012, completes #30/#31) |

## Numbering

The ADRs are numbered **contiguously, `0001`–`0027`** — the numbering used throughout the
current tree: the files above, their code comments, and the conformance suite.

The arc was renumbered to this clean sequence on 2026-07-06, from an earlier sparse scheme
(`0015`, then `0018`–`0033`). Commits made before that date still cite the old numbers; that
prior git history is left as-is rather than rewritten.

References appear both as links and as bare `ADR-00NN` text. A **link** always resolves to an
ADR in this set. A bare citation usually names an ADR above by its number — but the contiguous
scheme reuses the low numbers, so where a bare number could also mean a decision recorded
outside this set, the in-repo use is written as a link. Follow the link rather than the bare
number.
