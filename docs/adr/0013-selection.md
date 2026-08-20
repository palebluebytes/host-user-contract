# Selection: `runs ∩ published`, the richest mode wins, the floor is the fallback

**Status:** Accepted (2026-08-20). The rule that joins [0009](0009-host-declares-modes.md) to
[0010](0010-user-declares-session-shapes.md); executed identically on both binding paths.

A bind holds two facts: the modes this **machine** runs, and the modes this **user** published. The
rule that turns them into one answer is the whole of the negotiation, and it is small:

1. **`modes = runs ∩ published`.** Empty ⇒ hard error naming both sets.
2. **A non-floor mode in that set wins.** **Two** non-floor modes ⇒ hard error.
3. **Otherwise the floor.**

No mode name appears in the algorithm. The floor is read off the registry flag, so a third mode
changes nothing here.

## Both refusals are refusals, deliberately

A mode mismatch is a **hard error**, not a lesser home. A home built for a graphical session,
activated on a machine with no display, is a worse answer than an error naming the mismatch. This is
the one place the contract refuses rather than degrades: an unafforded *power* stays inert and the
build succeeds, because the host has simply declined something. An unrunnable *mode* is a
contradiction nobody can rescue.

The two-rich-modes error exists because the registry carries no ordering
([0007](0007-two-registries.md)). A host claiming two incomparable rich modes must say which it
means; inventing a tie-break would silently pick one and be wrong on some future pair.

## Selection reads one value, and a guard reads the other

Step 1 intersects with what the user **published** — the binding index's key set, which is the
user's declaration **already narrowed by the producer's per-system matrix**
([0012](0012-homes-are-keyed-by-mode.md)). That is deliberate: publication has one owner, and
re-declaring the user's modes beside it as a second input to the same decision is the
"two declarations that must agree" this design removes everywhere else.

What that leaves uncovered is a mode the host **runs** and the user **declares**, which *this
system's matrix row subtracted*. It is absent from the publication, so selection cannot see it,
falls back to the floor, and activates a terminal home on a graphical seat — with no message. That
is the silently lesser home the paragraph above refuses, arrived at from the other direction.

So the index carries the user's declared modes as well, read by **one guard and not by the
algorithm**: a mode in `runs ∩ declared` that is not published for this system is a hard error
**naming the matrix as the cause**, checked before selection so the empty-intersection refusal
cannot fire first and name the wrong thing.

The two refusals are different and have different owners:

| refusal | means |
| --- | --- |
| selection's | the user runs nothing this host runs |
| the guard's | the producer built nothing here for a mode both sides wanted |

## One implementation, executed on both paths

The rule is `selectModeOver`, and the greeter does not re-spell it — it **executes** it
([0020](0020-runtime-evaluates-the-kernels.md)). A previous login-time reimplementation in `jq` had
already drifted: the Nix kernel refused two rich modes by name while the `jq` took whichever sorted
first and logged a stranger into it.

## Consequences

- **The same user lands on different homes on different machines**, deciding nothing per host. That
  is the portable-user north star, and it falls out of the rule rather than being arranged.
- **A greeter selects by the same code a declarative bind does**, so the two paths cannot come to
  different answers about one machine.
- **What the host affords is applied after selection** and is independent of it: a terminal-mode
  user can be afforded `sudo`, and a gui-mode user afforded nothing.

## Considered alternatives

- **Fall back to the floor on an empty intersection** — rejected: it is the silently-lesser-home
  failure, and the user has said they cannot run what this machine offers.
- **Order the modes and take the maximum** — rejected: `gui` and `mobile` are incomparable, and any
  total rank is an invention nothing consumes.
- **Re-declare the user's modes beside the publication as selection's input** — rejected: two
  declarations of one thing. It survives as a *guard*, which reports a disagreement rather than
  resolving one.
