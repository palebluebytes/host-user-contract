# Negative result: the contract does not require a mode to change home content

**Status:** Accepted (2026-08-23). Records a **negative result** — it adds no surface and removes
none. It exists so the question is not re-proposed without new evidence. The mode-side counterpart
to [0023](0023-no-classification-of-home-content.md), decided against
[0007](0007-two-registries.md) and scoped by [0022](0022-oracle-and-reference-fleets.md) and
[0025](0025-consumer-check-kit.md).

The question, raised from a consumer repo rather than from this one:

> *a user who declares two modes gets two homes built. Should the check kit ship a proof that the
> two are genuinely different — different realized dotfiles or a different package profile — rather
> than the same content under two names?*

It is an attractive proposal. Per-mode building is the mechanism [0012](0012-homes-are-keyed-by-mode.md)
exists for, a converged pair looks like a mechanism paid for and not used, and a fleet can lose its
only worked example of it to one careless refactor with every other check still green.

**The answer is no, and for three separate reasons — any one of which is sufficient.**

## 1. It is not a property of a roster

A mode is a **capability of the machine** ([0007](0007-two-registries.md)), not a description of
home content. `modes.nix` attaches two things to `gui` that a home never sees:

- `groups` — the input devices a graphical session drives, which land on the **account**;
- `display` — the shared display surface, which the realization turns on for the **seat**.

So a user whose `gui` and `cli` homes are byte-identical still receives something real from the
`gui` mode: a different account and a host that binds a display. That user is **conforming**, and a
kit check asserting "your two modes must differ" would fail their build and tell them to invent a
difference. A contract does not get to require that.

This is what separates the claim from the three the kit does ship
([0025](0025-consumer-check-kit.md)): *no system channel*, *the posture this repo chose*, and
*every published home evaluates* are true of every consumer or explicitly chosen by one. *Your
modes differ* is true of neither.

## 2. The cost the proposal prices is not the cost that exists

Two modes naming one module, with no `desktop` set, produce **one derivation, built twice** — the
`mode` a home is built for reaches it only through that mode's own `configuration`, the `desktop`
dotfile, and a `hostFacts` specialArg that is inert unless a module reads it. `admin` in
`examples/users` is the live case. The store deduplicates; what a converged pair actually costs is
an extra **evaluation**, not an extra closure per user.

## 3. The property cannot be stated without the contract satisfying it on the user's behalf

`mkContractHome` composes `~/.contract-desktop` out of the mode's `desktop` parameter
([0021](0021-display-server-agnostic.md)). So **any** user who names a desktop has two homes that
differ, having substituted nothing — `ada`, `cleo` and `duo-b` are all in that state today. A check
that counts realized difference naively passes on a string **the contract wrote**, which is exactly
the emptiness it was written to reject — "the same content with a different `mode` frozen into the
manifest" — relocated one file over.

Neither cheap eval-time approximation escapes this. `drvPath` is unsound in both directions (equal
for `admin`, unequal for a user who only named a desktop), and comparing two `configuration` values
compares merged `deferredModule`s whose wrapper records the option path each came through, so every
pair differs — including two references to one file.

## Decision

**The contract requires nothing here, and the kit ships nothing for it.** Convergent modes are a
conforming arrangement, stated in `modes.nix` beside the mode-versus-grant distinction it follows
from.

Keeping a **worked example** of per-mode substitution is a different obligation with a different
owner: it belongs to the **reference fleets** ([0022](0022-oracle-and-reference-fleets.md)), which
exist to demonstrate the mechanisms this repo documents. `examples/users` carries it as the
`mode-substitution-is-load-bearing` execution proof, reported through that fleet's claim report
([0025](0025-consumer-check-kit.md)), which:

- **classifies** every (user, non-floor mode) pair rather than requiring anything of one — a
  convergent pair is reported and passes;
- **subtracts `.contract-desktop`** before judging content, because the contract will not count its
  own output as a user's evidence;
- fails only when **no** pair in the whole fleet diverges, which is the demonstration obligation
  stated as a proof;
- reaches that verdict in the **build**, since realized content is the only place it is answerable,
  and asserts at eval only that there is a pair to compare at all.

`admin` is pinned in its own `user.nix` as the convergent counterpart to `duo-a`, so both halves of
the rule are visible in the fixture set rather than only the half that diverges.

## Consequences

- **A consumer whose modes converge is conforming.** Nothing in the contract, the kit or the
  diagnostics says otherwise, and a consumer that wants the property anyway states it in its own
  repo as its own choice.
- **`mkMemberChecks` keeps exactly three helpers.** Nothing folds in, and the members adapter is
  unchanged.
- **The subtraction rule generalises.** Wherever content divergence is judged, contract-composed
  content is set aside first. `.contract-desktop` is the only such file today, and the contract
  owns it — this is not the classification [0023](0023-no-classification-of-home-content.md) rules
  out, because the contract is only declining to count what it wrote itself.

## Considered alternatives

- **Ship `mkModeSubstitutionCheck`, universal — every member declaring ≥2 modes must diverge** —
  rejected on §1: it fails correct fleets. It is also the *stronger* reading, so if the weaker one
  is wrong this is worse.
- **Ship it existentially — at least one member diverges** — rejected twice over: a second
  converging member is silently excluded and never checked, and an existential claim over somebody
  else's roster is a demonstration obligation wearing a check's clothes. Demonstration obligations
  belong to reference fleets, not to consumers.
- **Ship the declaration-only half — two modes must name different `configuration` modules** —
  rejected: satisfied by two copies of one file, so it proves that somebody named two paths and
  nothing else. The half that proves anything needs realized homes and home-manager's own output
  paths, which `conformance/` cannot exercise at all
  ([0002](0002-contract-is-a-standalone-flake.md)) — a check whose only load-bearing half is
  untestable here is not a contract deliverable.
- **Count `.contract-desktop` as evidence of substitution** — rejected on §3.
- **Say nothing and leave the question open** — rejected: it has now been proposed twice from
  consumer repos, which is what [0023](0023-no-classification-of-home-content.md) exists to stop.
