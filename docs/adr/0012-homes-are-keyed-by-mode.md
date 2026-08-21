# Homes are keyed by mode, and the manifest freezes it

**Status:** Accepted (2026-08-20). The published shape of
[0011](0011-prebuilt-binding-mode.md), keyed by [0007](0007-two-registries.md)'s mode registry.

Because a power can never change a home ([0007](0007-two-registries.md)), the only thing a home
varies on is the **session shape it was built for**:

```nix
homes.<system>.<user>.<mode>                              = <evaluated home>;
contractUsers.<system>.<user>.contractPackages.<mode>     = <package>;
```

One key, one shape, no record and no pairing. N modes yield at most **N** homes per user.

This replaced a powerset over the features whose grant could reach home content — one home per
*combination*, plus a grant-less floor bake, plus a rule narrowing what a home was allowed to see,
plus a marker travelling with each home so the producer could verify it had been paired with the
right grant set. Every one of those structures existed to carry a pairing, and the pairing existed
only because a power could reach home content. Remove the cause and they disappear rather than
being renamed.

## The per-system matrix survives as a subtraction

A fleet still says which modes each system bakes, and the shape of that statement is the contract's
even though the fact is the fleet's:

```nix
mkHomeMatrix { systems = { x86_64-linux = { }; aarch64-linux = { gui = false; }; }; }
```

**A row names only the modes that system's seats cannot run; an omitted mode is baked.** The
direction of the default is the whole design, and both obvious alternatives fail the same way:

- a list of what a system **can** run silently drops each new mode from **every** system;
- a list of labels names combinations, so a new axis doubles them.

Inclusion lists are right when the enumerated thing is owned by the declarer and the risk of the
unknown is *admitting* something. Here the enumerated thing is owned by the **contract** and the
risk is *omitting* it. **Fail-closed is right for privilege; fail-open is right for coverage** —
under-baking is silent and costs a user their home content, while over-baking wastes build time and
nothing else.

Keying the matrix by system also makes three under-bakes **unwriteable** rather than asserted
against: a rule naming a system the fleet does not bake, a system left unclassified, and a claim of
unrestrictedness contradicting the rule. An unrestricted system is a row that takes nothing away, so
there is no second statement for a first to disagree with.

## The manifest freezes the mode

`contract-manifest.json`:

```json
{ "version": "0.0.0", "username": "ada", "packages": [ … ], "mode": "gui" }
```

The `version` is **the contract's own release version**, not a counter over this field set — see
[0024](0024-versioned-releases.md), which records why a separate "wire format" number was built and
then removed.

The mode is precisely the thing a bind **cannot** change, and therefore precisely the thing worth
asserting about: activating a graphical home on a machine with no display is a mismatch worth
refusing by name. `bindContractPackage` asserts the host runs the mode the home was built for.
Selection satisfies that by construction; the guard covers the internal path where the kernel is
called directly.

**There is no backward-compatibility read.** A manifest is written and read through one module, so
an incompatible version is a named refusal rather than a shape guessed at from whichever fields
happen to be present.

## Consequences

- **Publication is decided before any derivation is instantiated.** Reading a user's declaration
  forces the module fixpoint but not the activation package — stated explicitly, because otherwise
  it quietly becomes a double evaluation.
- **Identical bakes are unproducible.** Two homes of one user differ in the mode they were built
  for, so the redundancy that once made most users publish byte-identical artifacts cannot arise.
- **`homeConfigurations` is a pure `home-manager` CLI adapter**, publishing `<user>-<mode>`. Nothing
  in the contract reads it. The flat naming is forced from outside: `home-manager`'s CLI quotes the
  fragment name before it reaches Nix, so no nested spelling resolves. Keeping the adapter preserves
  `home-manager switch --flake .#ada-gui`, which is the loop a home author actually uses.

## Considered alternatives

- **Keep the powerset and express "gui-only" as a per-user omission** — rejected: not expressible
  without new producer surface, since the empty set is always a member of a powerset. More
  importantly it treats the symptom.
- **Prune homes that turn out identical** by comparing derivation paths — rejected on structure
  before measurement: the predicate *is* the comparison, so the expensive half — the second full
  evaluation — is paid whether or not the result is published. Pruning always pays the evaluation it
  prunes. And it is moot now: per-mode baking makes identical homes unproducible.
- **Nest `homeConfigurations` to match the `homes` tree** — rejected on measurement: no nested
  layout is reachable from home-manager's CLI, and `nix flake check` would not report the breakage.
