# The producer surface, and one name per value

**Status:** Accepted (2026-08-20). The users-repo half of
[0011](0011-prebuilt-binding-mode.md).

A users repo holds more choices than a host does — which nixpkgs, which state version, which homes
to publish, what to call them — so the two sides will never be one call each. What the contract owns
is everything that is **not a choice**: its own composition rules, re-typed per repo and wrong
silently when mistyped.

## The surface

| function | answers |
| --- | --- |
| `mkMembers` | who is in this users repo, and what does each one say |
| `mkHomeMatrix` | which homes does each system need |
| `mkContractHome` | how is one home composed |
| `mkContractFleet` | every member × system × mode, and the outputs |
| `mkContractUsers` / `mkContractUser` | the two rungs below, for a bake that is not a cross-product |
| `mkConfinementCheck` · `mkIdentityPostureCheck` · `mkHomeEvalCheck` · `mkMemberChecks` | the proofs only a consumer can run |
| `mkClaimReport` | how a suite of named claims reports what it found |

### The bar for joining it

Each entry has **real call sites that cannot get the result any other way without re-typing a
contract rule**, and is **not a second spelling of anything kept**. The test is applied by
subtraction: functions with no caller were internalized, and the package-level kernels
(`mkContractPackage`, `mkContractPackageForHome`, `bindContractPackage`) live in `kit.internal`
where the conformance suite can prove them in isolation.

The recurring **tell** that a rule belonged here was a producer holding both the rule *and the proof
of the rule*: a hand-written per-system filter beside an `assert` catching that filter's own failure
mode, with a comment naming the mode exactly.

### `mkContractUsers` is kept although no reference producer calls it

That is precisely the caller-less condition that internalized four other functions, and it is not
applied here for one reason: **the contract is consumed at a URL.** `mkContractFleet` hard-wires the
full cross-product, so a third-party producer whose bake is not one needs the rung below — and
"move it back out of `kit.internal`" is no escape hatch for someone who does not own this repo. An
escape hatch has to be reachable by the person escaping.

## Composition is by injection, never by dependency

`mkContractHome` composes the module list — umbrella, baseline, the desktop dotfile, the mode's own
`configuration`, the inline identity module — and applies the **caller's**
`homeManagerConfiguration`. `mkContractFleet` takes a `buildHome` closure, so it never names
`mkContractHome`, never learns what a state version is, and a home built **without** the builder
still bakes.

`pkgsFor` is a *function* rather than an attrset, and that is load-bearing: `systems` is derived
from the matrix, so a consumer handing over a pre-built map must derive `systems` itself first and
the absorption never completes. With a function the producer derives `systems`, applies `pkgsFor`
**once per system**, and returns the memo — which is how a rule both producers carried as prose
(*"`import nixpkgs` is not memoized; instantiate once per system, never once per user × mode ×
system"*) becomes a value a caller holds.

## The baseline is a pinned posture, not an opinion set

`homeModules.baseline` carries the universal home hygiene every produced home starts from. Every
line is `mkDefault`, and there is deliberately **no opt-out knob**: a user's plain definition wins
per-option, while the pin still beats an upstream default. An enable flag would be a whole-module
veto over lines that are individually overridable anyway.

The line that looks like dead weight is what justifies the pin. `systemd.user.startServices =
"sd-switch"` is a **no-op** against current home-manager — and that is exactly what distinguishes a
*pin* from an *opinion*: it holds the restart-on-switch semantics against upstream default churn,
and a home whose user services silently stop restarting on switch is a drift no test catches.

Excluded on principle: mime-app defaults (user intent), any packages (the user's sovereign concern).

## One name per value

Three rules the surface follows, each settled after a trace found the same value wearing different
names at every hop:

1. **One word, one type.** `grants` is the attrset, everywhere it is an argument. `granted` is an
   option path whose value is that attrset, and only that. A word that denoted an attrset at one
   site and a sorted list at another was the defect.
2. **Derive rather than pass.** `system` is read off `pkgs`, so a caller cannot key its packages by
   a system its `pkgs` was not built for. A shape that cannot express the disagreement beats a guard
   against it.
3. **A member may be restated, never replaced.** One internal resolver answers *"which user is
   this?"*, and a field passed beside a member that disagrees with it is a named error. Two
   precedence rules for one question is what made three resolution sites necessary.

Two candidate nouns were rejected on evidence and are recorded so they are not re-proposed.
**`build`** collides with *build-time binding* — an artifact and a phase sharing a stem. **`bake`**
names the *process*, not the object: "a bake" tells a reader an operation happened, not what the
thing is. That it *reads* like domain language is what made it plausible and what made it wrong.
**"Bake" survives as a verb and only as a verb.**

## Considered alternatives

- **A thinner surface, leaving the joins to each producer** — rejected on the tell above: a rule
  held in prose in two repos is a rule with no owner.
- **A fatter one absorbing the published home names** — rejected: those names are the producer's own
  and owe the published packages nothing, which makes the rule a choice however mechanical the loop
  around it looks.
- **Extending one function with a third mode instead of adding a name** — rejected: a function with
  three modes is the accretion this surface was cleaned up to stop. One more name is cheaper to read
  than one more mode.
