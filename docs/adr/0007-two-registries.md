# Two registries: a mode is a machine capability, a feature is a power over a person

**Status:** Accepted (2026-08-20). The spine of the current design; every surface below is a
projection of one of these two maps.

The contract had one registry, `features.nix`, and one entry in it behaved unlike the rest. `gui`
carried a per-feature flag meaning *this power cannot be applied to a home that is already built* —
and it was the only entry that carried it.

Look at what that one entry actually declared:

- `groups = [ "input" "uinput" … ]` and a display-surface flag — **host-side effects**, conferrable
  at activation on any home that already exists;
- home content — a desktop's dotfiles, a session config — which **cannot** be injected into a sealed
  derivation.

Those are two different facts wearing one name. The flag was not a property of `gui`; it was the
tell that `gui` was secretly two things.

## Decision

**Two registries, and they touch nowhere.**

### `modes.nix` — the session shape a home is built for

A **mode** is what a home is *built for*, and — asked from the other end — what a machine *can run*.
Those are the same vocabulary because they are the same question: *"was this home built for a
graphical session?"* and *"can this box run one?"* A host that cannot run a shape simply does not
offer it, which is **incapacity, not policy**.

Modes are **mutually exclusive**: a home is built for exactly one. N modes yield at most N homes per
user, not 2ⁿ, which is the whole economic difference from the powerset the old flag implied.

Each entry carries a `description` (the word a user reads when declaring it), an optional `floor`
flag, optional `groups` the session needs in order to run, an optional `display` flag, and its own
`options`. Today: `cli` (the floor) and `gui`.

### `features.nix` — a power a host confers on a person

A **feature** is a judgement about an individual, decided per bind. It has **no parameters**: it is
a bare capability, a set of groups. The one parameter the contract ever carried — `gui.desktop` —
turned out to describe a *session* rather than a capability, so it lives on the gui mode.

### The registries have no association

A mode used to name the feature a host had to afford in order to run it. That laundered a machine
capability through a per-person policy namespace, and it meant two maps had to be kept in step. The
host now declares its modes directly ([0009](0009-host-declares-modes.md)), so there is no
association left to drift.

## Exactly one floor, and no ordering

One mode carries `floor = true`: the shape every host runs, that every selection falls back to, and
that no host declares. Zero or two is a named error — a selection with no floor has no fallback and
one with two has no answer.

There is deliberately **no total rank**. `gui` and `mobile` are incomparable: a phone runs
`{ cli, mobile }`, a desktop runs `{ cli, gui }`, and no host ever needs them ordered. A floor flag
plus *"two rich modes is an error"* encodes what is true without inventing an ordering nothing
consumes.

## Consequences

- **Adding a mode is one edit.** The user's declaration schema, the host's enum, the matrix axis
  names and the key a home publishes under are all projections of this map.
- **A third mode is not a code change.** `display` and `floor` are registry flags rather than mode
  names spelled inside a derivation, precisely so that stays true.
- **Every feature left is privileged** — see [0008](0008-features-are-atomic-and-privileged.md).

## Considered alternatives

- **Keep one registry and express the distinction as a flag** — rejected: the flag *was* the defect.
  A feature that answers "no" to *can this be conferred at activation?* is two facts under one name,
  and everything downstream inherited the fusion.
- **Free-form mode names**, on the precedent of the free-form desktop name — rejected: a typo'd mode
  yields a user nothing can bind, discovered later by a host operator, where a typed enum is an error
  in the user's own repo at the moment they write it.
- **Make the mode imply an affordance automatically** — rejected: it re-fuses what this splits. A
  host must still be able to confer gui's groups on a terminal-mode user.
