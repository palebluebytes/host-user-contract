# The contract ships proofs a consumer runs over its own repo

**Status:** Accepted (2026-08-21). The consumer-side counterpart to
[0022](0022-oracle-and-reference-fleets.md), constrained by
[0002](0002-contract-is-a-standalone-flake.md).

[0022](0022-oracle-and-reference-fleets.md) records how the *contract* is proven: a synthetic
adversarial oracle, plus two reference fleets that consume it for real. Neither can say anything
about a **third-party** consumer's repo, and three claims are only checkable where that repo's own
material lives:

| claim | the material it needs |
| --- | --- |
| this module set has no system channel | the consumer's **actual imports** |
| these credentials carry the posture this repo chose | the consumer's **actual identities** |
| every published home evaluates | the consumer's **actual per-system homes** |

`conformance/confinement.nix` proves the contract **umbrella** is confined. That is the right proof
for the contract's own suite and exactly half the promise: it says nothing about whether a shared
home module, a sops-nix backend or an overlay's module smuggled a system channel back in. That
half can only be proven where those imports are.

## Decision

**The contract ships the technique, not the verdict.** `check-kit.nix` exposes four proof functions
a consumer calls in its own `checks`:

| function | proves |
| --- | --- |
| `mkConfinementCheck` | the consumer's real module set cannot name a system option |
| `mkIdentityPostureCheck` | every identity carries the repo's chosen credential posture |
| `mkHomeEvalCheck` | one user's every published home evaluates on every system baked |
| `mkMemberChecks` | the members fold over the three above, so no call site names a check |

…and two functions that prove nothing at all.

## The kit also owns how a suite REPORTS

`mkClaimReport` and `mkProofPrelude` are the fifth and sixth surfaces, and the odd ones out: the
four above answer *is this repo's material sound?*, and these two answer *how does a suite say what
it found?* — one for each place that answer is reached.

`mkClaimReport` owns the **eval** side. It takes a list of named `{ name; ok; }` claims, a report
title, `pkgs`, and — optionally — **execution proofs**, derivations whose *being built* is the
verdict. It renders an `ok`/`FAIL` line per claim, threads the proofs in as the report's own build
inputs, and exits non-zero if anything failed.

`mkProofPrelude "<proof name>"` owns the **shell** side, because an execution proof decides there
and nowhere else. It returns the shell a proof prepends to its builder, defining `fail <message>` to
write `<proof name>: <message>` to stderr and exit non-zero — **text** rather than a wrapper around
the derivation, because a proof's builder *is* the proof: the comparisons must stay readable at the
call site rather than become a string argument to a combinator. The name is what earns it. A proof's
output lands in a build log beside everything else Nix is doing, so a failure that does not say
which proof wrote it leaves a reader to guess.

Both are here rather than beside the contract's own internals for the same reason the four are: they
are **technique**, the material is the consumer's, and they are package-free by the same injection.
They also earn their places by the [0014](0014-producer-surface.md) bar, and by the same tell. Three
sites in this repo were running the report fold: two near-verbatim (the conformance collector and
the reference host fleet, which now report through it) and a third, the reference user fleet, which
had invented its own shell harnesses — the last of which were two `fail()`s in one file, identical
but for the label they echoed. A format with no owner is a format free to drift, and it drifts on
whichever side has no owner.

**The two kinds of claim are not interchangeable.** An eval claim is decided before anything is
built and reads as a line; a proof is decided by building. A verdict that can only be reached from
*realized* content — what actually lands in a home — has to be a proof, and calling it an eval claim
would be an approximation dressed as a verdict ([0027](0027-mode-need-not-change-home-content.md)
carries the worked case).

**An empty claim list is a hard error**, by the same rule as every other empty input here: a report
folded over nothing prints its header, touches its output and reports success. That failure is
invisible in exactly the way the whole kit exists to prevent. **An unusable proof name is refused**
for a sharper reason: the name is interpolated into a double-quoted `echo`, so one carrying a quote,
a `$`, a backtick or a backslash is not a mislabelled failure but arbitrary shell, running in a
sandbox holding the very homes the proof was given to judge.

The kit is lib-only and package-free ([0002](0002-contract-is-a-standalone-flake.md)). The caller
injects `pkgs` for a trivial witness derivation and — for the confinement check — **its own home
builder**, which is what lets the contract prove something about a home-manager module set without
importing home-manager; the prelude, being text, needs neither. Every check fails at eval with a
named message, the same posture as every other contract guard.

## A check that cannot pass vacuously, in either direction

This is the part that is got wrong by hand, and it is why the technique is worth shipping at all.
A confinement check has two failure modes that both **report green**:

- **Reject-everything.** A broken builder or a typo'd path makes every out-of-universe probe "fail
  to evaluate", and the check passes while proving nothing. Closed by a **positive control**: a
  legitimate home option must still evaluate. It is asserted **before** the confinement claim, so a
  broken harness is reported as a broken harness rather than as a pass with a strange name. This is
  the half people forget, so it is not optional here.
- **Force-nothing.** A lazily-returned home makes every probe "evaluate", so the negative claims
  fail **loudly**. An under-forcing `force` therefore breaks the check noisily rather than
  silently — the safe direction, and the reason the asymmetry is worth stating.

Both are **hooks** (`force`, `positiveControl`), never assumptions, because the contract cannot
know the consumer's home shape: the default `force` is home-manager's
`activationPackage.drvPath`, which ~every consumer has, while a hand-rolled `evalModules` home
overrides it. A home that is never forced would make the whole check vacuous, which is precisely
the failure the hook exists to let a consumer avoid.

The same refusal-to-decide governs `mkIdentityPostureCheck`: `require` has **no default**, because
[0004](0004-user-is-self-contained.md) makes the posture consumer-owned and a default would impose
one repo's posture on every repo that adopted the check.

## The defaults are only exercised outside this repo, and that is named rather than hidden

The two defaults above reference **home-manager option names**, and
[0002](0002-contract-is-a-standalone-flake.md) forbids home-manager here. So
`conformance/confinement.nix` drives this function's *logic* through a synthetic,
home-manager-free builder, and `force = home.activationPackage.drvPath` and the
`home.sessionVariables` positive control are exercised only where home-manager actually exists —
a consumer repo's own `checks`, and the reference fleets
([0022](0022-oracle-and-reference-fleets.md)).

That is a real hole in the oracle, bounded and recorded: **keep the two defaults in step with
home-manager's option names.** It is the same boundary [0022](0022-oracle-and-reference-fleets.md)
draws for anything needing a real home, arrived at from the other end.

## Consequences

- **A typical consumer ships no check file at all.** `mkMemberChecks` folds the three helpers over
  the derived members, so a user added to the directory is covered the moment it exists.
- **The three helpers stay public and separately callable.** A single-user repo has no members to
  adapt, and a repo wanting confinement alone should call for confinement alone.
- **The adapter's own traps are one level up** — an empty member set, homes naming no system, homes
  that do not cover the members. Each yields a check set that is merely *smaller*, and a missing
  check is indistinguishable from a passing one in `nix flake check` output
  ([0022](0022-oracle-and-reference-fleets.md)).

## Considered alternatives

- **Ship the verdict — the contract checks its consumers** — impossible, not merely undesirable:
  the material is on the far side of the boundary, and reaching it would mean the contract
  evaluating a consumer's Nix.
- **Bake the credential posture into `loadIdentity`** — rejected in
  [0004](0004-user-is-self-contained.md): it imposes a public repo's posture on every consumer,
  including the private single-user flakes a greeter also serves.
- **Make `force` and `positiveControl` assumptions rather than hooks** — rejected: the contract
  cannot know the consumer's home shape, and the assumption's failure mode is a check that passes
  while proving nothing.
- **Leave the technique to each consumer** — rejected on
  [0014](0014-producer-surface.md)'s tell: a rule held in prose in two repos is a rule with no
  owner, and this one is subtly wrong when hand-rolled.
- **Let `mkMemberChecks` replace the three helpers** — rejected: a fleet that genuinely bakes
  different members on different systems is outside that fold, and a single-user repo has no
  members at all.
