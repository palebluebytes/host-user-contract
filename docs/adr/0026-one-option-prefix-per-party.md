# Both parties declare under `contract.*`, each on its own eval-side

**Status:** Accepted (2026-08-23). Refines [0001](0001-host-user-contract.md)'s boundary into a
single option namespace.

Everything the contract puts on a host lives under `contract.*` — both the declarations an operator
writes and the values the contract writes back:

```nix
contract.modes = [ "gui" ];                 # written by the operator
contract.packagePolicy.allowedPrograms = […];
contract.exposed = true;
contract.users.<u> = { identity; granted; mode; };   # written by a bind
contract.display.enabled                             # derived, readOnly
```

The user's own declaration lives under the **same word**, in its `user.nix`, on the other
eval-side:

```nix
contract.cli.enable = true;
contract.gui = { enable = true; configuration = ./home.nix; desktop = "plasma"; };
```

And a **produced home** — the user again, on a third eval — holds the identity the contract handed
it under the same word:

```nix
contract.identity.name                       # injected by the contract, readOnly
```

## The decision

**One prefix, both parties.** Each declares its half of the contract under `contract.*`, on its own
side of the boundary. There is no second prefix and no per-party prefix.

**Every surface the contract declares on, not two.** The two eval-sides above are an enumeration of
the surfaces that existed when this was first written, never a boundary of the rule: the subject is
*the contract's own option surface, wherever it appears*, and a produced home is something the
contract puts on a host as surely as a bound account is. Counting eval-sides is not how the scope is
decided — counting **parties** is, and there are still two.

`custom.*` was what the host side used first, and it was rejected because it **is not a fact about
anything**. It says only "not upstream NixOS" — true of every option any local module ever
declares. `contract.users.<u>.granted` tells a reader where the value came from and which agreement
put it there; `custom.users.<u>.granted` tells them only that somebody local wrote it.

The symmetry is the point rather than a coincidence. Two repos that never name each other
([0001](0001-host-user-contract.md)) still write the same word at the top of their declarations,
which is the boundary showing up in the option tree.

## The consequence that makes it load-bearing

**The host's display output is `contract.display.enabled`, not `contract.gui.*`.**

With one prefix shared by both parties, a host-side `contract.gui.*` would sit in a reader's head
directly on top of the user's gui-mode declaration — two different subjects (a **machine's** shared
display surface, and a **person's** session shape) under one path. The neutral name is therefore
*forced* by the shared prefix; it was not chosen for elegance.

That is a second, independent reason for the same name.
[0021](0021-display-server-agnostic.md) requires the flag to be neutral about the display
*server*; this record requires it to be neutral about the *mode*. Both land on
`contract.display.enabled`.

## The surface that had to be brought in: a home's identity

A produced home is handed the identity the greeter authenticated
([0005](0005-identity-is-inert-data.md)), and it held that value at a **bare** `identity` — a
surface that predates this record and was outside it.

The reason it moved is the third rejected alternative below, not the provenance argument above. **A
bare option at the top level of a home-manager module tree is the collision case**, and it is the
one namespace where the collision is live: home-manager declares whatever it declares, upstream, on
its own schedule, and a top-level `identity` that arrives there merges with the contract's rather
than colliding with it. Provenance is the second, independent reason — a bare `identity` in a home
answers "where did this come from?" with nothing, and looks like any home-manager option.

That is the same shape as `contract.display.enabled` above: two reasons, arrived at separately,
landing on one name.

**What this does *not* reopen.** [0005](0005-identity-is-inert-data.md) rejects identity as a
declared option *authored by the user*, because the greeter reads one file before evaluating
anything and a declared option's value is whatever the whole tree merges to. A home's
`contract.identity` is the other direction: **injected by the contract, post-auth, and `readOnly`**,
so there is no author to merge with. The home *holds* its identity — it neither loads it nor authors
it.

**What it costs.** The home umbrella declared no `contract` namespace at all, and a home trying to
speak outward — `contract.gui.enable = true;` — was an eval error because the *prefix* was absent.
It is now an eval error because that *leaf* is undeclared: the same refusal, a weaker reading of it.
The claim was therefore moved out of prose and into a check that **enumerates** the home umbrella's
declared surface and asserts it is exactly `contract.identity`. A claim about absence is the kind a
later option violates silently ([0006](0006-identity-describes-a-person.md): a check passes
everything it does not name); an enumeration names the whole surface, so the day a second option is
added to a home the suite fails rather than a comment going stale.

## Consequences

- **"Where did this value come from?" is answerable from the option path alone**, which is the
  property `custom.*` could not offer.
- **The user's half of the namespace grows with the mode registry** and needs no naming decision
  per mode: `contract.<mode>` is a projection of `modes.nix`
  ([0007](0007-two-registries.md), [0010](0010-user-declares-session-shapes.md)).
- **A host-side option that would shadow a user-side one is a naming bug**, catchable by reading
  the two declarations side by side — which only works because they share a prefix.

## Considered alternatives

- **`custom.*`** — rejected above: it names the absence of an upstream owner rather than the
  presence of an agreement.
- **A prefix per eval-side** (say `contract.*` host-side, `user.*` user-side) — rejected: it hides
  that the two are halves of one agreement, makes the symmetry unwritable, and adds a second
  vocabulary to keep in step for no gain. The eval-side is already unambiguous from *which file*
  the option is written in.
- **No prefix, options at the top level** — rejected: it collides with NixOS and home-manager
  option names, and it makes the provenance question above unanswerable. This is the alternative
  with a worked case rather than a hypothetical one: a home's identity *was* declared this way, and
  the section above is what it took to bring it back in.
