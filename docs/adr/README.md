# Architecture Decision Records

The design narrative for the host↔user contract, in order. Each record is self-contained and
describes the design as it stands — there are no amendment chains and no superseded records. Where a
decision was reversed, the record that stands carries the reversal and the reasoning that produced
it, under *Considered alternatives*.

Read [0001](0001-host-user-contract.md) and [0007](0007-two-registries.md) first; between them they
carry the whole shape.

**Numbers are chronological; the sections below are thematic.** A record written later can land in
an earlier section — read the sections, not the number ranges.

## I — Why the contract exists

| ADR | Decision |
| --- | --- |
| [0001](0001-host-user-contract.md) | Hosts and users live in separate repos, bound by a shared contract |
| [0002](0002-contract-is-a-standalone-flake.md) | The contract is a standalone flake that depends only on nixpkgs `lib` |
| [0003](0003-no-secrets-beyond-the-credential.md) | The contract handles no secrets beyond the login credential |

## II — What a user is

| ADR | Decision |
| --- | --- |
| [0004](0004-user-is-self-contained.md) | A user is self-contained, and the login credential travels with them |
| [0005](0005-identity-is-inert-data.md) | Identity is inert data, authenticated before any code runs |
| [0006](0006-identity-describes-a-person.md) | An identity describes a person, never their powers |

## III — The two vocabularies

| ADR | Decision |
| --- | --- |
| [0007](0007-two-registries.md) | Two registries: a mode is a machine capability, a feature is a power over a person |
| [0008](0008-features-are-atomic-and-privileged.md) | Features are atomic, every one is privileged, and the safe set is empty |
| [0009](0009-host-declares-modes.md) | A host declares the modes the machine runs; affordances ride each bind |
| [0010](0010-user-declares-session-shapes.md) | A user declares the session shapes they run in |

## IV — The seam between the repos

| ADR | Decision |
| --- | --- |
| [0011](0011-prebuilt-binding-mode.md) | The pre-built binding mode: the producer builds homes, the host activates them |
| [0012](0012-homes-are-keyed-by-mode.md) | Homes are keyed by mode, and the manifest freezes it |
| [0013](0013-selection.md) | Selection: `runs ∩ published`, the richest mode wins, the floor is the fallback |
| [0014](0014-producer-surface.md) | The producer surface, and one name per value |
| [0015](0015-consumer-surface.md) | The consumer surface: one bind for a whole fleet |
| [0016](0016-program-scope.md) | Program scope: the `nix-daemon` feature and the package policy |

## V — The greeter

| ADR | Decision |
| --- | --- |
| [0017](0017-greeter-is-a-contract-deliverable.md) | The greeter is a contract deliverable |
| [0018](0018-greeter-runtime-flow.md) | The greeter's runtime flow: data before code, and a standing seat baseline |
| [0019](0019-host-is-the-trust-anchor.md) | The host is the sole trust anchor: pinned signers and a pinned eval posture |
| [0020](0020-runtime-evaluates-the-kernels.md) | Runtime realization evaluates the contract's own kernels |
| [0021](0021-display-server-agnostic.md) | The contract is display-server agnostic; the seat offers desktops |

## VI — Proof, and one closed question

| ADR | Decision |
| --- | --- |
| [0022](0022-oracle-and-reference-fleets.md) | The oracle and the reference fleets |
| [0023](0023-no-classification-of-home-content.md) | Negative result: the contract does not classify home content |
| [0025](0025-consumer-check-kit.md) | The contract ships proofs a consumer runs over its own repo |

## VII — Publication

| ADR | Decision |
| --- | --- |
| [0024](0024-versioned-releases.md) | The contract has one version, and it is the release version |

## Writing a new record

- **One decision per record**, stated in the title as a claim rather than a topic.
- **Say what was rejected and why.** The rejected alternatives are the part a later reader cannot
  reconstruct, and several here exist mainly to stop a bad idea being re-proposed.
- **Amend by rewriting.** If a decision changes, rewrite the record it changes and renumber nothing.
  A record that describes the design as it *was*, with a header explaining how to read it as
  history, is the shape this set was rewritten to remove — git holds the history.
