# One name per value on the producer surface

**Status:** Accepted (2026-08-17). Amends [ADR-0026](0026-consumer-producer-public-surface.md) (the
public surface), [ADR-0029](0029-producer-home-builder-and-home-baseline.md) (`mkContractHome`) and
[ADR-0026](0026-consumer-producer-public-surface.md)'s roster amendment (the `member` input). It
changes **argument names and argument counts only** — no behaviour, no published data shape, no
option path. It settles three naming and shape rules that future surface must follow, including the
signature of the not-yet-built `mkContractFleet` ([ADR-0029](0029-producer-home-builder-and-home-baseline.md)'s
2026-08-17 amendment, issue #61). **Amended in place (2026-08-18)** — two corrections to this record's claims about itself: the "only one exception" sentence, and the account of `variant`'s deletion. No decision changes; see the amendment at the end. **Amended by [ADR-0032](0032-grants-ride-the-bind-modes-build-homes.md) (2026-08-18)**: the `{ grants; label; home; }` record is deleted, so `homes` denotes one shape (`homes.<system>.<user>.<mode>`) and the progressive-filling doctrine has nothing left to govern; `.enable` is dropped across the grant vocabulary.

ADR-0026 fixed *which* functions the surface carries and re-levelled them onto one concept seam. It
did not look at what those functions **call their arguments**. An architecture review focused on
consumer ergonomics found the residue: the surface was right, and a producer still had to hold four
names for one value, two spellings of one system, and three different answers to "which user is
this?".

## What the trace showed

### 1. One grant attrset, four parameter names — and one name with two types

A producer holds a grant set as `grants` (the `{ grants; label; }` rows [`mkBakeMatrix`](../../lib.nix)
hands out, and the `{ grants; home }` records [`mkContractUser`](../../lib.nix) consumes). Between
those two points the *same value* was renamed at every hop:

| hop | name it took |
| --- | --- |
| the bake matrix row, and the coin's variant record | `grants` |
| `mkContractHome` | `granted` |
| `hostFactsFor` | `granted` |
| the home's recorded key | `contractBakedGrantKey` |
| `assertBakePairing` reading it back | `grants` |

Worse, `granted` denoted **two types** at two sites: an attrset at `mkUserAccount` (writing
`custom.users.<u>.granted`) and a sorted **name list** in the manifest and the binding index. Nothing
told a reader which one a given `granted` was.

### 2. `system` was a parameter `pkgs` already answers

`mkContractUser` and `mkContractUsers` took **both** `pkgs` and `system`, and never cross-checked
them — the only place on the surface where a caller could key its published packages and its binding
index by a system its `pkgs` was not built for. Both `mkContractHome` and `bindContractUser` already
derived it (`pkgs.stdenv.hostPlatform.system`), so the contract carried two rules for one value.

### 3. "Which user is this?" was answered three times, with two contradicting rules

The dual input the roster amendment introduced — a `member`, or the pieces to build one — was
normalised at three sites with three error texts, and the two precedence rules **disagreed**:

- `mkContractUser` held a passed `name` to the member's and **refused** a mismatch, because `name`
  keys the published package and the index entry.
- `mkContractHome` let `userDir`/`identity` **silently override** the member's, documented as
  deliberate because the builder publishes nothing.

Both were defended in comments; neither was visible from a signature; and no test exercised the
override-beside-a-member case at all — the suite only drives `userDir` + `identity` *without* a
member, which is the roster-less shape.

## Decision

### One word, one type — `grants` is the attrset, `grantKey` is the list

The rule is about **types**, not about which side of a signature a name sits on:

| name | type | where it appears |
| --- | --- | --- |
| **`grants`** | the attrset `{ <feature>.enable = bool; }` | every **argument**, everywhere |
| **`grantKey`** | the sorted **name list** | every **argument and field** holding one |
| **`granted`** | the attrset, as a **NixOS/home option path** | `custom.users.<u>.granted`, `hostFacts.granted` |

`granted` survives only where it is an option path **whose value is the attrset** — so it never
denotes two types. Everywhere it previously denoted a *list*, it becomes `grantKey`:

- `mkContractHome { granted = …; }` → `{ grants = …; }`; `hostFactsFor` takes `grants` and returns
  `granted`. One function holding both is the rule in miniature: the narrowing is exactly where a
  grant attrset becomes an option a home reads.
- the binding index's `variants[].granted` → **`contractPackages[].grantKey`** (the list is
  renamed too — see the amendment below).
- the manifest module's Nix surface — the argument `writeManifest` takes and the field
  `readManifest` returns — → **`grantKey`**, and `bindContractPackage` reads `parsed.grantKey`.

An earlier draft of this ADR stated the rule as "`granted` is an option path **or a published data
field**, never a parameter". That was a rule written around its own exceptions: it unified four sites
by the negative property "not a parameter" while two of them held attrsets and two held lists, which
is the very confusion this ADR exists to remove. Recorded because the weaker rule was Accepted for
part of a day and the reasoning should not be reconstructed as if it were always this.

#### The one exception, scoped and dated

The manifest's **wire** key stays `granted` in `contract-requests.json`. A JSON key is a format
commitment, and v2 shipped with it; renaming it means a v3, a version-dispatched write, a
version-dispatched read, and regenerating every committed fixture — for a name that appears in no
hand-written file and that exactly one internal function reads. So the translation lives in
`manifest.nix`, which owns the schema: `grantKey` on both Nix faces, `granted` on the wire, spelled
once as `grantKeyWireField`. That is what a schema owner is *for* — a reader downstream never meets
the mismatched word.

This is a deliberate, bounded violation of "one word, one type", and it is the **only** one. Its
trigger is explicit: **the next time the manifest is versioned for any reason, the wire key moves
too.** Do not treat it as precedent for a second exception.

No consumer's *data* changes for the manifest; the index field is a live Nix value with no on-disk
schema, and producer and consumer share one contract revision under the canonical
`users.inputs.contract.follows = "contract"` pattern, so it moves in lockstep.

### The system is read off `pkgs`

`mkContractUser`/`mkContractUsers` drop `system`. It is derived, as the other two public functions
already derive it. A disagreement between the two becomes **unwriteable** rather than uncaught —
this ADR's preference, following [ADR-0026](0026-consumer-producer-public-surface.md)'s bake-matrix
amendment, for foreclosing a failure over asserting against it.

### One resolver, one rule: a member may be restated, never replaced

An internal `resolveMember` answers `{ name; dir; identity; }` for both the producer coin and the
home builder, under **one** rule:

> A member answers every field, and a field passed beside a member may restate it but never replace
> it.

A member handed a disagreeing `name`, `userDir` or `identity` is a named error. The roster-less
shapes are untouched: they are simply the case with no member to agree with, so composing a home
from one directory while holding an identity from elsewhere still works exactly as before — that
call passes no member.

This **tightens** `mkContractHome`: a member beside an overriding `userDir` used to win silently and
now errors. The override was documented as deliberate, but it was override-of-the-*loader* that the
suite actually drives, and that is the no-member case. An override that replaces part of an
already-resolved member is the same species of silent mispairing the [bake
pairing](0029-producer-home-builder-and-home-baseline.md) rejects one rung down, where one user's
material reaches an output under another's name.

The three fields resolve **lazily and independently**, so each caller forces only what it uses — the
coin never asks for `dir`, the builder never asks for `name` — and an unresolvable field is a named
error only where it is needed.

## Consequences

- **Breaking for producers, not for hosts.** A host repo changes nothing: `bindContractUser` and
  every option path are untouched. Landed in lockstep across the contract, conformance and both
  reference fleets, with no back-compat aliases — the contract is pre-1.0, the posture ADR-0026 set.
- **The known out-of-tree producer is `~/code/users`, and it breaks in exactly two places.** It is
  deliberately left pinned to migrate on its next contract bump (it takes none of #45/#57/#58/#60 and
  is not scheduled to converge, per
  [ADR-0029](0029-producer-home-builder-and-home-baseline.md)). Both are hard eval errors, not silent
  — neither signature takes `...`:
  - `flake.nix:225` — `mkContractUsers { … system = sys; … }`; drop the `system` line.
  - `flake.nix:167` — `hostFactsFor { inherit granted; … }`; rename to `grants`.

  Note it does **not** call `mkContractHome` (it hand-rolls its own `mkHome`), so the builder rename
  does not reach it. `hostFactsFor` is the consumer-facing rename that does — worth naming, because
  the obvious guess about which call sites move is wrong here.
- **`mkContractFleet` inherits one vocabulary.** Its signature (`roster`, `bakedVariants`,
  `pkgsFor`, `buildHome = { member, granted, pkgs }: …` as
  [ADR-0029](0029-producer-home-builder-and-home-baseline.md) sketched it) must spell that closure's
  grant argument **`grants`** when it is built. Doing these renames first is what stops the eleventh
  public name from shipping with the fourth spelling.
- **`resolveMember` is internal and stays internal.** It has no consumer — it exists so two public
  functions cannot answer one question two ways. It is not exposed to the conformance suite either;
  its rule is proven through the two public functions that use it, which is where the rule is
  observable.
- **One guard was deleted rather than moved.** `mkContractUser`'s hand-rolled name-mismatch
  `assertMsg` is gone; the conformance case that proves a disagreeing `name` fails the bake (and its
  positive control, an *agreeing* name) is unchanged and now exercises the shared rule. That is the
  test the resolver is verified through.
- **What this does not do.** `usersDir` (the roster's parent directory) and `userDir` (one user's)
  keep their one-character distinction **for now**, and not for the reason a first draft of this ADR
  gave. That draft claimed renaming them "would desync from ADR-0020's own prose"; ADR-0020's prose
  does not use those terms at all. The words appear there only inside its 2026-08-16 amendment, in
  code spans, back-referencing argument names the contract had already chosen. **ADR-0020 fixes the
  layout (`users/<u>/identity.json`), not the word** — so nothing in the ADR set stops a rename, and
  a future review is entitled to make one. The honest reasons to defer are that `usersDir` appears in
  four signatures against `userDir`'s one, and that the shared resolver above means a caller now
  rarely holds both at once.

## Amendment (2026-08-17) — the producer's nouns: the extra one is deleted, not replaced

The rules above fixed the *grant* vocabulary. A read-through of the result found two more nouns a
producer must learn, one of which also denoted two shapes. The outcome is better than a rename:
**one of them turned out to be unnecessary.**

### `variant` is deleted — the things already had names

`variant` denoted two shapes, exactly as `granted` had: `{ grants; label }` (the plan the matrix
hands out) and `{ grants; home }` (the built material the coin takes). Worse, the *published* end —
`{ grantKey; package }` in the binding index — wore the same word, though a `contractPackage` is
emphatically not a home ([CONTEXT.md](../../CONTEXT.md) keeps `contractPackage` and
`activationPackage` distinct for exactly this reason).

Naming the *pairing* was the mistake. Name the two things being paired and no third noun is needed:

```nix
# the matrix says which HOMES each system needs, each identified by the grants it is for
mkHomeMatrix { systems = { … }; }  →  { <system> = [ { grants; label } ]; }

# you build a HOME per row; the row gains `home` and nothing is re-keyed
mkContractUser { member = …; homes = [ { grants; label; home } ]; }

# the coin publishes a CONTRACTPACKAGE per home
contractUsers.<sys>.<u>.contractPackages = [ { grantKey; package } ]
```

Three nouns already in the vocabulary — **grants**, **home**, **contractPackage** — and none to
learn. The decisive evidence was that **the check kit already called them `homes`**
(`mkMemberChecks { homes; }`, and `mkHomeEvalCheck`'s own error text says "this user's baked
homes"), so the repo was carrying two names for one concept and `variant` was the outsider.

The `homes[].home` stutter is accepted: it is transparent, where a learned noun is not.

**Renamed with it:** `mkBakeMatrix` → **`mkHomeMatrix`** (it answers "which homes does this system
need?"), `bakeMatrixOver` → `homeMatrixOver`, `variantAxes` → `homeAxes`, `variantName` →
`homeLabel`, `mkVariantEvalCheck` → **`mkHomeEvalCheck`** with its check renamed `variant-eval-<u>`
→ **`home-eval-<u>`** (which now sorts beside the existing `home-confinement-<u>`), the registry
flag `needsOwnBuild` → **`needsOwnHome`**, and `assertBakePairing` → `assertHomePairing`.

**"Bake" survives as a verb and only as a verb** — "fails the bake", "the bake pairing", "baked
under". The error was ever using it as a *noun* for the object. That distinction is now written into
the glossary.

### Two candidates rejected on evidence, recorded so they are not re-proposed

- **`build`.** The obvious everyday word, and wrong here: `build-time` appears **74 times**,
  including the glossary entry **"build-time binding vs runtime binding"**
  ([ADR-0002](0002-user-confinement-manifest-greeter.md)). A `build` (an artifact) and a `build-time
  binding` (a phase) would be unrelated concepts sharing a stem — a worse instance of the defect
  being fixed.
- **`bake`.** Briefly adopted, on the argument that the domain already said it (164 uses:
  `mkBakeMatrix`, `bakeUnder`, `assertBakePairing`). Rejected because **it names the process, not the
  object** — "a bake" tells a reader an operation happened, not what the thing is. That it *reads*
  like domain language is what made it plausible and what made it wrong: familiarity is not the same
  as saying what something is.

### `roster` → `members`

The entry was already a **`member`**; the collection was a **`roster`** — two nouns for one
relationship, and the glossary carried a whole *"never call the bake matrix the roster"* entry, which
is what a pair of fighting names looks like.

- `mkContractRoster` → **`mkMembers`** (*not* `mkContractMembers`, which would sit one word from
  `mkContractUsers` — the confusable-pair defect this ADR removes)
- `mkRosterChecks` → **`mkMemberChecks`**; `userDir` → **`memberDir`** (`usersDir` keeps its name: it
  is the literal `users/` directory of [ADR-0020](0020-multi-user-repo-shape.md)'s layout, so the two
  are now different words rather than different plurals)

**Cost, recorded honestly:** `members` is plural with no singular collective, so prose that said "a
roster" now says "**the member set**". Accepted because the gain is one fewer word in the
*interface*, where it is met far more often than in prose.

### `mkContractUsers`'s `users` → `homes`, wrapper dropped

`users.<name>` was a record with exactly one key, which `mkContractUser` immediately unwrapped — a
shallow container. It is now `homes.<name> = [ … ]` directly, and stops colliding with NixOS's
`users.users`, the repo's own `users/` directory, and the function's own name.

`homes` names two shapes across the surface — `{ <user> = [ { grants; label; home } ]; }` here, and
`{ <system>.<user>.<label> = home; }` in `mkMemberChecks`. That is deliberate and is *not* the defect
this ADR fixes: both are collections of the same thing, keyed for two different questions, and each
is named for the argument its consumer takes. Noted in the reference producer at the one place both
appear.

### The older ADRs keep their words, deliberately

[ADR-0020](0020-multi-user-repo-shape.md), [ADR-0025](0025-turnkey-host-side-bind.md),
[ADR-0026](0026-consumer-producer-public-surface.md), [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)
and [ADR-0029](0029-producer-home-builder-and-home-baseline.md) are dated, accepted records and are
**not rewritten**. They say "variant" and "roster" because that is what they decided, and editing
them would make the record claim it always said otherwise. Each carries a dated pointer to this
amendment. `CONTEXT.md` is the live vocabulary and has moved.

## Amendment (2026-08-18) — two corrections to this record's claims about itself

Two things this ADR states are not true of it. Recorded rather than quietly fixed, on the principle
the rule section already applies to its own superseded draft: *"the reasoning should not be
reconstructed as if it were always this."* **No decision below changes.**

### 1. "It is the only one" is contradicted by this ADR's own amendment

The rule section says of the manifest's wire key:

> This is a deliberate, bounded violation of "one word, one type", and it is the **only** one… Do not
> treat it as precedent for a second exception.

The 2026-08-17 amendment then says `homes` names two shapes and "that is deliberate". Both cannot
stand.

The claim is narrowed here to what it can carry: the wire key is the only violation this ADR
deliberately **keeps**. It was never a surface-wide census — no such audit was performed. `homes` is
a second instance, blessed in the same document on the same day.

Worse, it was blessed with reasoning this ADR elsewhere rejects. The amendment defends `homes`
because "each is named for the argument its consumer takes". The rule section states that "the rule
is about **types**, not about which side of a signature a name sits on", and rejects an earlier draft
of itself precisely for unifying sites by role rather than by type. The amendment overturned the
document's own criterion without saying it was doing so.

Two lessons worth keeping: a completeness claim about a surface needs an audit behind it, and an
amendment that overturns its document's criterion has to say so out loud.

### 2. `variant` was not deleted cleanly — one collision of three was removed

The amendment's indictment is that `variant` denoted `{ grants; label }`, `{ grants; home }`, and the
published `{ grantKey; package }`. Its claim is that "the outcome is better than a rename: one of
them turned out to be unnecessary."

What actually happened:

| the three `variant` shapes | after |
| --- | --- |
| `{ grantKey; package }` | → `contractPackages`. **Genuinely fixed** — a contractPackage is not a home |
| `{ grants; label }` | → `homes` |
| `{ grants; home }` | → `homes` |

The two shapes that motivated the indictment both survived under the new word, redescribed as "one
shape, filled progressively". That is a reclassification, not a fix, and it is not free:
`contract.homes` is a **public output** shaped `[ { grants; label; } ]` while `mkContractUser`'s
parameter is `[ { grants; home; } ]` — same container, one field apart. Crossing them fails with
`error: attribute 'home' missing`, raw and undiagnosed.

### The third correction, deliberately not made

A third fix was considered and is **declined**: writing "one shape, filled progressively" into the
rule statement, where [`lib.nix`](../../lib.nix) cites this ADR for it and [`CONTEXT.md`](../../CONTEXT.md)
defines it, but this ADR does not contain it. Work in progress removes the shape the doctrine
describes — grants stop reaching home content, so a home no longer travels paired with a grant set —
and writing a rule for a shape being deleted would date the moment it landed.

### What stands

Every decision. The `grants`/`grantKey`/`granted` split, reading `system` off `pkgs`, and the
one-resolver rule are untouched by both corrections, and the code conforms to all three.

## Considered Options

- **Leave the published `granted` fields alone**, on the grounds that renaming them means a manifest
  v3 and a breaking data-shape change. **Rejected on the facts.** The two fields are fully
  independent — they share only the `grantKey` projection, and at bind time `bindContractUser` reads
  the index field and discards it, handing `bindContractPackage` a *reconstructed* attrset, so no
  value flows between them. The index has no on-disk schema at all, and the manifest's Nix surface is
  separable from its wire format, which is what makes the scoped exception above possible without a
  v3. The deferral also pointed at a trigger that does not exist: a sweep of all open issues, every
  ADR and the whole tree found **no** other anticipated manifest version bump, so "later" meant
  "never".
- **Rename the manifest's wire key as well, accepting a v3.** Rejected: version-dispatched write,
  version-dispatched read, regenerated fixtures and a permanent compat branch, all for a key no
  human types and one internal function reads. Deferred to the next bump with a real reason, per the
  scoped exception above.
- **Keep `granted` as the parameter and rename the option path.** Rejected: the option paths are the
  user-facing schema (`custom.users.<u>.granted` is in every host repo) and `granted` reads correctly
  there. The argument is the side with no external commitments.
- **Cross-check `pkgs` and `system` with an assert instead of dropping `system`.** Rejected on
  ADR-0026's bake-matrix reasoning: a shape that cannot express the disagreement beats a guard
  against it, and the parameter bought nothing else.
- **Keep the two member-resolution precedences and just document them together.** Rejected: two rules
  for one question is what made three sites necessary. One rule with a named error is smaller to
  state and strictly safer, and the divergence had no test and no caller.
