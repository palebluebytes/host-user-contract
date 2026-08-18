# Grants ride the bind; modes build homes

**Status:** Accepted (2026-08-18). **Supersedes** the home-affecting half of
[ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md) — the narrowed `hostFacts.granted` —
because the thing it narrowed no longer exists; that ADR's typed-voice half stands entire. **Amends**
[ADR-0002](0002-user-confinement-manifest-greeter.md) (the degradation posture, narrowed),
[ADR-0016](0016-prebuilt-binding-mode.md) (the coupling guard, restated),
[ADR-0025](0025-turnkey-host-side-bind.md) (selection) and
[ADR-0029](0029-producer-home-builder-and-home-baseline.md)/[ADR-0030](0030-one-name-per-value-on-the-producer-surface.md)
(the producer surface). Consistent with [ADR-0031](0031-published-bake-set-unclassified-unpruned.md):
the contract still does not *infer* whether a home is graphical — this is the home **saying** it.
[ADR-0006](0006-anyhost-greeter-runtime-binding.md)'s north star is served unchanged.

## What was fused

`features.nix` carried a per-feature flag, `needsOwnHome`, answering one question: *can a host apply
this grant to a home that is already built?* Every feature answered no — except `gui`.

But look at what gui's registry entry actually declares:

- `groups = [ "input" "uinput" "plugdev" ]`, and the display-surface flag the realization reads.
  **Host-side effects**, conferrable at activation on any home that already exists.
- Home content — a desktop's dotfiles, a session config — which **cannot** be injected into a sealed
  derivation.

Those are two different facts about one name, and `needsOwnHome = true` is the flag that says *this
feature is secretly two features*. Everything built on it inherited the fusion:

| structure | what it existed for |
| --- | --- |
| `homeAxes` | the features whose grant reaches home content |
| `homes = powerset(homeAxes)` | one home per **combination** of those grants — `2ⁿ` |
| the grant-less bake (`∅`, labelled `base`) | the universal floor, since `∅ ⊆ any grant` |
| `hostFactsFor`'s narrowing | a home may only see the grants something bakes for |
| the manifest's grant-key + `assertHomePairing` | keep a home paired with the grants it was built under |

## The trace that found it

An architecture review of the producer surface found the name `homes` denoting three shapes: the plan
(`[ { grants; label; } ]`), the built material (`[ { grants; label; home; } ]`), and an index
(`{ <system>.<user>.<label> = home; }`). Crossing them failed raw and undiagnosed —
`attribute 'home' missing`, `expected a list but found a set` — and `mkContractFleet` bound two of
them under one word in a single `let`.

Every attempt to fix it by *naming* ran aground, because the defect was structural: the record
existed only to carry the grants↔home pairing, and the pairing existed only because a grant could
reach home content. Remove that and the record has nothing to hold.

## Decision

### 1. Grants ride the bind — all of them

`needsOwnHome` is deleted from the registry. Every feature becomes what `sudo` already was: a
host-side effect conferred at activation, on whatever home was built. **A grant can never change a
home.** One home serves granted and ungranted alike, for every feature without exception.

### 2. A mode is the session shape a home is built for

A new registry, `modes.nix`, following the pattern `features.nix` sets — the single source of the
vocabulary, with every projection derived so they cannot drift. Modes are **mutually exclusive**: a
home is built for exactly one. Today `cli` and `gui`; `mobile` is the shape a third would take.

Each entry carries a description, an **optional associated grant** (`gui` → the gui grant; `cli` →
none), and a **`floor`** flag. Exactly one mode is the floor; zero or two is a named error.

Modes are not a powerset. N modes yield **at most N** homes per user, not `2ⁿ`. That is the whole
economic difference, and it is why `homeAxes`, `homes`-the-powerset and the grant-less bake all
disappear rather than being renamed.

### 3. The user declares what it supports and what it wants

Both live in the user's own home, per ADR-0028:

```nix
contract.supports.gui = true;   # which modes this home can run in
contract.wants.sudo   = true;   # the offer, intersected with the host's affordances
```

`supports` has **no default**, and **at least one mode is required** — a user supporting nothing is
uninstallable, and that is a named error rather than an empty published set. The absence of a default
is deliberate: a default satisfies "at least one" without the user having said anything, which would
set a user's essential nature by inheritance. The teaching convention is that an ordinary user
declares `supports.gui = true` — ADR-0006's "gui by default" — but nothing writes it for them.

`supports` must be **mode-invariant**, guarded exactly as the offer's bake-invariance is today: a
`supports` that varied by mode would make the published set depend on which mode happened to be
evaluated first.

Supporting a mode while vetoing its associated grant (`supports.gui = true` with
`wants.gui = false`) is a bake-time error. It is issue #59's rule one layer up: a contradiction no
host can rescue.

**`.enable` is dropped across the grant vocabulary.** `wants.sudo = true`, `affordances.gui = true`,
`granted.gui = true`. The suffix existed so four namespaces shared one shape, not because a feature
ever carried a second flag — parameters have their own namespace (`contract.requests.gui.desktop`),
and ADR-0024 split coarse roles into atomic features rather than adding flags to one. A word that
never varied across five features and four namespaces is ceremony.

### 4. The host declares affordances; its modes are derived

A host declares `contract.affordances.<feature> = true` and nothing else. The modes it runs follow:

```
runs = { the floor } ∪ { m | m's associated grant is afforded }
```

A gui-affording host runs `{ cli, gui }`; a headless one runs `{ cli }`. Nobody declares `cli`.

Deriving rather than declaring makes the disagreement **unwriteable** — the same move ADR-0030 made
dropping `system` in favour of reading it off `pkgs`, and `mkHomeMatrix` made when it rendered
under-baking inexpressible rather than asserted. A second host-side namespace would be two
declarations that must agree, with nothing forcing them to.

The one case where affording and running could diverge — a headless host conferring input groups for
a plugged-in device — is contrived, because the gui grant also flips the display-surface flag, which
*is* the claim to have a display. If a real instance appears, the registry can grow an explicit
override; nothing here forecloses it.

### 5. Selection

`bindContractUser`:

1. `modes = runs ∩ supports`. Empty ⇒ hard error naming both sets.
2. A non-floor mode in that set wins. **Two** non-floor modes ⇒ hard error: a host claiming two rich
   modes must say which it means.
3. Otherwise the floor.
4. Then `grant = affordances ∩ wants`, conferred at bind time as before.

No mode name appears in the algorithm — the floor is read off the registry flag, for the same reason
`keyLabel`'s output is documented as "a cosmetic label, not a parse target".

### 6. Homes are keyed by mode, and the leaf is the home

```nix
homes.<system>.<user>.<mode> = <evaluated home>;
contractUsers.<system>.<user>.contractPackages.<mode> = package;
```

No record, no `label` field, no pairing. `homes` denotes exactly one thing. `homes` is published as a
flake output; system-first matches every sibling and the shape `nix flake check` validates for
per-system outputs.

The **per-system matrix survives as a subtraction**: each row names only the modes that system's
seats cannot run, and an omitted mode is usable. That preserves the one property of `mkHomeMatrix`
this restructuring does not invalidate — fail-open on coverage, so a registry that gains a mode bakes
it everywhere with no edit in any consumer. An enumeration would silently drop a new mode from every
system, which is the failure that design exists to foreclose.

Reading `supports` forces the module fixpoint but **not** `activationPackage`, so publication is
decided before any derivation is instantiated. Stated because otherwise it quietly becomes a double
evaluation.

### 7. What a home sees

`hostFacts.mode` is the single source, and the home umbrella **derives**
`custom.home.profiles.<mode>.enable` from it — exactly one true. Leaf modules keep gating on the
familiar `lib.mkIf profiles.gui.enable`.

`hostFacts.granted` is gone from homes entirely. No grant can affect a home, so showing a home the
grant set would be showing it something it must not use — the hazard ADR-0028's narrowing existed to
prevent, now removed at the source rather than guarded. The wiring line every grant-sensitive home
writes today (`profiles.gui.enable = hostFacts.granted.gui.enable or false`) disappears: it existed
only to translate a grant into a switch, and there is no translation left to do.

This reverses `home-profiles.nix`'s rule that the contract declares those options but never writes
them. Correct now: the mode is a fact handed **to** the home, not a choice the home makes.

**The content idiom follows.** Content that works in every mode is written **unconditionally** —
that is `git.nix`, present in the gui home by default *and* in the cli home, with no gate.
Mode-specific content is `lib.mkIf profiles.<mode>.enable`. A user supporting only `gui` gates
nothing at all; the deliberate work a cli-aware author does is declaring `supports.cli = true` and
then gating the gui-only parts.

### 8. The manifest freezes the mode

`bindContractPackage` asserts that the host runs the mode the home was built for — the direct
translation of ADR-0016's coupling guard, one field instead of a list, and the same defense-in-depth
posture: selection satisfies it by construction, and the guard covers the internal path where
`bindContractPackage` is called directly.

## Consequences

**Deleted:** `needsOwnHome` · `homeAxes` · `homes`-the-powerset · the grant-less bake and its `base`
label · `hostFactsFor` and the narrowing rule · the manifest's grant-key · `assertHomePairing` · the
`{ grants; label; home; }` record · `<u>-greeter` · `.enable` across four namespaces.

**The naming defect that prompted this is dissolved, not solved.** `homes` denotes one thing; there
is no record, no `homes[].home` stutter, no "one shape filled progressively", and `bake`-as-a-noun
has nothing left to name.

**ADR-0002's posture is narrowed.** Degradation still governs *grants*: a feature a host does not
grant stays inert, exactly as before. A **mode** mismatch is a **refusal** — a user supporting only
`gui` cannot be bound by a headless host, and that is a hard eval error rather than a silently lesser
home. This is deliberate: a home built for a graphical session, activated on a machine with no
display, is a worse answer than an error naming the mismatch.

**The north star is untouched, and the reasoning is worth recording.** ADR-0019 states the invariant
as *"any host × any user"*, protecting **self-containment** — a user roams to a seat it has never met
carrying only a flake URL, username and password, and no host may own a user artifact. A gui-only
user is still completely self-contained. And the greeter path — *the* north star — always grants gui,
because `greeterGrants` is the safe set and `gui` is the only feature in it. So every **seat** binds
every user; what can refuse is an operator deliberately naming a gui-only user in a headless host's
build-time config, where a loud error is the correct answer.

**The greeter loses its special home.** `greeterDesktop` folds into the default composition alongside
`homeModules.baseline`: it writes `~/.contract-desktop` from `contract.requests.gui.desktop` and is
inert when no desktop is requested, so composing it always costs a cli home nothing. It cannot move
host-side — the greeter reads that dotfile *before* evaluating the home's Nix, so the file must be in
the home. With grants no longer reaching homes, the separate `<u>-greeter` artifact has no remaining
reason to exist, and the greeter's `homeBuilder` binding fetches
`homes.<system>.<user>.<mode>.activationPackage` — a plain `nix build` against the nested output, no
flat name involved.

**`homeConfigurations` becomes a pure `home-manager` CLI adapter**, publishing `<user>-<mode>`.
Nothing in the contract reads it. The flat naming is forced from outside and confined to the one
consumer that imposes it: `home-manager`'s CLI wraps the fragment name in quotes before it reaches
Nix (`homeConfigurations."ada.gui"`), so no nested spelling can ever resolve, and `nh` rejects a
dotted path outright. Keeping the adapter preserves `home-manager switch --flake .#ada-gui`, which is
the loop someone authoring a `home.nix` actually uses.

**Both reference fleets move**, and `examples/users` teaches **substitution** — gui content beside
its cli counterpart — rather than the same rule spelled two ways. That gives
`custom.home.profiles.cli` its first consumer in this repo; commit `267a545` had stripped the write
precisely because nothing read it.

## Considered Options

- **Keep the powerset and express "gui-only" as a per-user omission.** Rejected: not expressible
  without new producer surface, since `∅` is always a member of a powerset and a matrix row can only
  cut bakes naming an unusable axis. More importantly it treats the symptom — the grant-less bake is
  a *consequence* of grants reaching homes, and removing the cause removes it for free.
- **Prune redundant bakes by comparing `activationPackage.drvPath`.** Rejected by
  [ADR-0031](0031-published-bake-set-unclassified-unpruned.md) on measurement, and now moot: the
  redundancy it targeted (6 of 7 reference users publishing byte-identical bakes) existed *because*
  every user was baked per grant combination whether or not any grant reached their home. Per-mode
  baking makes identical bakes unproducible.
- **Two host-side namespaces — `affordances` for grants, `runs` for modes.** Rejected: two
  declarations that must agree, with nothing forcing them to. Deriving makes the disagreement
  unwriteable.
- **A total rank over modes.** Rejected: `gui` and `mobile` are incomparable — a phone runs
  `{ cli, mobile }`, a desktop runs `{ cli, gui }`, and no host ever needs them ordered against each
  other. A floor flag plus "two non-floor modes is an error" encodes what is true without inventing
  an ordering nothing consumes.
- **Free-form mode names**, on the precedent of `gui.desktop`'s DE-agnostic free-form string
  (ADR-0013). Rejected on ADR-0028's precedent instead: freeform left `contract.requests`
  specifically so a typo is an eval error, and a typo'd mode would yield a user nothing can bind,
  discovered by a host operator.
- **Defaulting `supports` to every mode** (over-publish, let the user narrow), on `mkHomeMatrix`'s
  fail-open reasoning. Rejected because that reasoning does not apply here: with no default, omission
  is a **named error**, so the silent under-publication fail-open guards against cannot occur.
- **Making the mode imply the grant automatically.** Rejected: it re-fuses what this ADR splits. A
  host must still be able to grant gui's groups to a cli-mode user, and `wants.gui` must stay
  independently vetoable.
- **Nesting `homeConfigurations`** to match the `homes` tree. Rejected on measurement: `home-manager`
  quotes the fragment name unconditionally, so no nested layout is reachable from its CLI, and
  `nix flake check` would not report the breakage — `homeConfigurations` is a "known but unchecked
  community attribute" in Nix's own `flake.cc`.
