# The contract ships the producer home builder: `mkContractHome` composes the home, the baseline is pinned hygiene

**Status:** Accepted (2026-08-16). Extends [ADR-0026](0026-consumer-producer-public-surface.md) (the
public surface grows by the front door) and the [ADR-0004](0004-extract-contract-flake.md) amendment
(the home-manager rule is about *building* homes, satisfied here by injection — the `buildHome`
precedent from the check kit, issue #35). Executes wayfinder tickets #40 (the builder shape) and #42
(who owns universal home hygiene). **Amended in place (2026-08-16)** — the builder now gives the
home the grant-key it was baked under, so the producer coin verifies the pairing instead of trusting
the caller's; see the amendment at the end. **Amended again (2026-08-17)** — the fatter producer
this ADR rejected under Considered Options is **overturned**: the contract also ships
`mkContractFleet`, the fleet-level producer that owns the residual join. See the second amendment.

The glue that turns a user's directory into a `homeManagerConfiguration` call was hand-written three
times across two repos — twice in `examples/users/flake.nix` (the roster homes and the greeter-login
mapper), once in the operator's `users` repo — and each copy spelled the same four things: the
contract umbrella, the user's `home.nix`, an inline `{ identity; home.username; home.homeDirectory;
home.stateVersion; }` module, and the `hostFacts` specialArg built through `hostFactsFor`. The
contract had already absorbed two fragments of that block (`hostFactsFor`, `variants`) for exactly
this reason: none of it is a consumer *choice* — it is the contract's own composition, re-typed per
repo, and wrong silently (a missed narrowing shows a home a grant it must not see; a missed umbrella
drops the user's typed voice).

## Decision

### 1. `contract.lib.mkContractHome` — the producer home builder

```nix
contract.lib.mkContractHome {
  homeManagerConfiguration,  # consumer injects home-manager.lib.homeManagerConfiguration VERBATIM (ADR-0004)
  pkgs,                      # per-user pkgs — consumer-side by design
  userDir,                   # users/<u>; home.nix always
  identity ? loadIdentity (userDir + "/identity.json"),  # kit-injected loader (ADR-0009)
  granted ? { },             # narrowed via hostFactsFor (ADR-0028); platform read off pkgs
  stateVersion,              # REQUIRED consumer arg — no contract default
  extraModules ? [ ],        # the seam: confinement probes, greeterDesktop, markers, repo glue
  extraSpecialArgs ? { },    # opaque passthrough (threads the ADR-0020 `inputs` convention); hostFacts contract-owned and wins
}
```

It composes `[ homeModules.default, homeModules.baseline, userDir + "/home.nix", the inline
identity/home.* module ] ++ extraModules` and applies the **caller's** builder to them.
`home.homeDirectory = "/home/${username}"` is a fixed contract rule, not a knob — the realized
account lands at the same path (the normal-user default the realization keeps, and the literal the
greeter's `provision` writes), so home and account can never disagree about where home is.

- **The injection posture.** The contract never inputs home-manager; the consumer passes
  home-manager's own entry point and the contract only composes arguments and applies the
  consumer's function. This is the [ADR-0004](0004-extract-contract-flake.md) amendment's rule
  satisfied the same way `mkConfinementCheck`'s `buildHome` satisfies it: an injected builder
  closure, so the capability stays consumer-side and no version choice is pushed onto anyone.
  `homeModule`, `homeBaselineModule`, and `loadIdentity` are injected by the kit — the same pattern
  that gives `traceUser` its `homeModule` and the producer coin its `loadIdentity` — so a caller
  passes only its own side.
- **`hostFacts` is contract-owned and wins.** The builder writes the specialArg *over*
  `extraSpecialArgs`, so a caller cannot clobber it — accidentally handing a home an un-narrowed
  grant set would silently defeat the [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)
  narrowing. Everything else in `extraSpecialArgs` passes through opaquely: the
  [ADR-0020](0020-multi-user-repo-shape.md) `inputs` convention is a producer convention the
  contract need not know exists.
- **What stays consumer-side by design.** `pkgs` (each home layers its own overlays and config;
  the platform is read off it), `stateVersion` (a consumer *fact* — the two real repos differ, so a
  contract default would be an invented value), and the two open seams. `extraModules` is what
  dissolves all three original call sites including the greeter-login mapper (same builder, a
  different grant, two extra modules) and is the seam the confinement check
  ([ADR-0026](0026-consumer-producer-public-surface.md) amendment, issue #35) appends its probes
  through — the real `homeConfigurations` and the check drive the *same* module set.

### 2. `homeModules.baseline` — universal home hygiene, included by default

Both real users duplicated a `modules/base.nix` of universal home-manager hygiene that was not user
intent. That is contract material, but it cannot live in `homeModules.default`: the default umbrella
is **tracer-pure** — evaluable by bare `evalModules` with no home-manager
([ADR-0008](0008-greeter-is-a-contract-deliverable.md)/[0013](0013-per-user-desktop-choice-host-offered.md))
— and hygiene sets home-manager options. So it ships as a separate module (the `greeterDesktop`
exposure pattern: kit attr `homeBaselineModule`, flake output `homeModules.baseline`), which
`mkContractHome` composes **by default**; a consumer building homes by hand can import it directly.
Package-free: it references home-manager option *paths*, never imports home-manager.

```nix
programs.home-manager.enable = lib.mkDefault true;      # self-manage CLI — live effect today
systemd.user.startServices = lib.mkDefault "sd-switch"; # PIN — a no-op today, see below
```

**Hygiene is a pinned posture, not an opinion set.** Every line is `lib.mkDefault`, and there is
deliberately **no opt-out knob**: a user module's plain definition (priority 100) wins per-option,
while the pin (1000) still beats an upstream option default (1500). An enable-flag would be a
whole-module veto over lines that are individually overridable anyway — a second mechanism for a
weaker property.

**The no-op findings are what justify the pin.** Auditing the duplicated `base.nix` against current
home-manager found `systemd.user.startServices = "sd-switch"` to be a **no-op**: upstream's default
is already `true`, and the option's `apply` maps `"sd-switch"` to `true`. A line that changes
nothing looks like dead weight — but that is precisely what distinguishes a *pin* from an
*opinion*: it holds the restart-on-switch semantics against upstream default churn, and a home
whose user services silently stop restarting on switch is a drift no test catches. The boundary the
audit drew:

- **In** (uniform across users *and* worth pinning): the self-manage CLI, the restart-on-switch
  semantics.
- **Out — opinion**: `xdg.mimeApps.enable = false` dies with the duplicated file. Which
  application opens a file type is user intent, per-user like any other home choice.
- **Out — user intent**: any packages. Program scope is the user's sovereign concern
  ([ADR-0017](0017-daemon-restricted-user-package-policy.md)).
- **Out — reference convention**: `homeModules.greeterDesktop`. It is only *inert* when no desktop
  is requested (it materialises a dotfile otherwise), and surfacing the desktop choice is the
  reference greeter's convention, not universal hygiene — it stays opt-in via `extraModules`.

### 3. Proven package-free

The conformance coverage (`conformance/contract-home.nix`) passes a **recording stub** as
`homeManagerConfiguration` — a function returning its own arguments — and asserts over what the
contract composed: the module list and its order, the inline identity/home.* module, the
`hostFacts` narrowing and its clobber-resistance, baseline-in/greeterDesktop-out, and the
mkDefault-priority posture in a merged eval over stub option declarations. No home-manager
anywhere ([ADR-0004](0004-extract-contract-flake.md)/[0022](0022-reference-fleets-and-the-test-split.md));
the proof that a *real* home-manager eval accepts the composition lives with the reference fleet,
which builds its `homeConfigurations` through this builder.

## Consequences

- **The public `lib` grows to ten** (recorded as an amendment in
  [ADR-0026](0026-consumer-producer-public-surface.md)). `mkContractHome` passes that ADR's test:
  three real call sites that cannot get the composition any other way without re-typing it, and it
  is not a second spelling of anything kept — the producer coin bakes *packages from* evaluated
  homes; this is the one place homes are *evaluated*.
- **A producer's `mkHome` becomes policy-only.** What remains repo-side is which `pkgs`, which
  `stateVersion`, and which extra modules — choices, not mechanics. The `examples/users` adoption
  is the teaching rewrite (wayfinder #44); the operator's `users` repo follows its own sequencing.
- **The baseline is one more thing a user need not copy.** The duplicated `base.nix` dies; a user
  who dislikes a pin overrides that option in their own `home.nix` and their plain definition wins.
- **`homeModules.default` stays tracer-pure.** The baseline lives outside it, so `traceUser` and
  the bare-`evalModules` conformance paths are untouched.

## Considered Options

- **A fatter `mkContractUsers` that also builds the homes from `userDir`.** Rejected: which
  variants to bake is the producer's call ([ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)),
  and the greeter-login mapper needs the *same* composition outside any bake (a different grant,
  extra modules) — a builder fused to the bake could not dissolve that third call site.
  **OVERTURNED (2026-08-17, issue #61) — do not read this rejection as standing.** Both grounds
  were answered by surface that shipped afterwards; the fleet producer layers *over* this ADR's
  builder rather than fusing with it. See the second amendment at the end.
- **Injecting the whole `home-manager.lib`, or a bespoke builder closure.** Rejected: the contract
  needs exactly one capability — build a home from modules + specialArgs — and
  `homeManagerConfiguration` verbatim is that capability's own name. A wider surface invites the
  contract to grow home-manager knowledge; a bespoke closure shape is one more thing to document
  and get wrong.
- **A contract default for `stateVersion`.** Rejected: it is a consumer fact (the real repos
  differ), and a defaulted stateVersion silently migrates a home the day the default moves.
- **An `enable` knob on the baseline.** Rejected: mkDefault already makes every line individually
  overridable; a whole-module veto is a second, coarser mechanism for a weaker property.
- **`xdg.mimeApps.enable = false` in the baseline.** Rejected as opinion — see the boundary above.
- **Composing `homeModules.greeterDesktop` by default.** Rejected: reference-implementation
  convention, and not inert (it writes a dotfile whenever a desktop is requested). Opt-in via
  `extraModules`, as the greeter-login mapper does.
- **Folding the baseline into `homeModules.default`.** Impossible without breaking tracer purity:
  the default umbrella declares no `home.*`/`programs.*` options and must keep evaluating under
  bare `evalModules`.

## Amendment (2026-08-16) — a home carries the grant set it was baked with (issue #56)

The contract owns both ends of a bake — `mkContractHome` evaluates one home *under* a grant set,
and the producer coin bakes an already-evaluated home *with* one — but it did not own the **join**
between them. A producer builds each variant's home keyed by its label, then re-pairs
`{ grants; home }` by that label when it hands the list to `mkContractUser`.

That pairing was **trusted, never checked**. A variant's `granted` — in the manifest and in the
binding index — came from the grant attrset passed *alongside* the home, never from what the home
was actually built with, and every downstream guard reads that same passed value: the
[ADR-0016](0016-prebuilt-binding-mode.md) coupling guard asserts `manifest.granted ⊆ host grant`,
and `bindContractUser` selects the maximal variant by the index's `granted`. So a mispairing
shipped a `base` home published under a `gui` grant-key, the host granted gui, bound what it
believed was the gui variant, and activated a home built without it — silent, and *structurally*
undetectable by the checks that exist, because every one of them was reading the label rather than
the home.

So the grant set **travels with the home**, and the producer cross-checks it:

- **`mkContractHome` attaches `contractBakedGrantKey`** — the grant-key it was baked under (the
  sorted enabled feature names) — to the value it returns.
- **`mkContractPackageForHome` and `mkContractUser` verify it.** The adapter guards the *manifest*
  (it is where a home and a grant set join into a published artifact); `mkContractUser` guards the
  whole variant *record*, so the index's grant-key and the published package's **name** force the
  check too. A mispairing is a hard eval error naming the user, the baked key, and the passed key.
- **The marker is compared as a key, not as an attrset**, through the same `grantKey` projection
  the variant label and the index's `granted` read — so "the same grant set" cannot mean two things
  across them. The key recorded is the one **as passed** to the builder, before the
  [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md) narrowing: the narrowing is the
  contract's own deterministic downstream step, and the rule a producer holds is the simple one —
  *hand the bake the same grant attrset you handed the builder*.
- **A home built without the builder still bakes.** Not every producer uses `mkContractHome` (a
  hand-rolled or future nix-darwin home bakes through the generic kernel), so an absent marker
  **skips** the check rather than firing it. The builder stays a convenience, not a requirement.

**Why the returned value rather than a home option.** The alternative — a contract-owned read-only
option the home carries, read off `config` — was rejected on two counts. `homeModules.default` must
stay evaluable by bare `evalModules` with no home-manager
([ADR-0004](0004-extract-contract-flake.md)/[0008](0008-greeter-is-a-contract-deliverable.md)), and
a nullable option would be needed anyway to tell "not set" from "baked with nothing". More
importantly, `contract.*` in a home is the **user's** voice
([ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)): a producer-written key there is a
second spelling of a fact the home already reads as `hostFacts.granted`, in the one namespace the
home itself can write. On the returned value it is unspoofable from inside the home, invisible to
the home's eval, and degrades to "absent" exactly when it should.

Conformance covers both directions: `conformance/contract-home.nix` proves the builder attaches the
key (and *only* that — the builder's arguments are untouched, so the home never sees it), while
`conformance/contract-package.nix` and `conformance/turnkey-bind.nix` prove the matching case bakes
unchanged, the mispaired case is a hard error by every route out of the bake, and an unmarked home
still bakes.

## Amendment (2026-08-17) — the fatter producer is overturned: `mkContractFleet` owns the residual join (issue #61)

The **A fatter `mkContractUsers`** option above is rejected no longer. Its two grounds were both
answered by surface that shipped *after* this ADR was accepted, and the shape that answers them is
not the shape it rejected: the fleet producer layers **over** `mkContractHome` rather than fusing
with it.

### The residue, measured

Measured at `2b6254f`, with the four blockers landed (#56 the bake pairing, #57 the roster, #58 the
bake matrix, #60 the roster check adapter) — the decision is made on the *remainder*, never on the
file as it stood when the candidate was first raised. `examples/users/flake.nix` is 577 lines, of
which 314 are comments and 125 more are shell inside two teaching checks; the join itself is **99
code lines**. Of those, 37 are mechanics re-typed character-for-character in a second, independently
evolved producer (`~/code/users`): the per-variant home loop, the roster × system × variant fold,
the grants↔home re-pairing into `mkContractUsers`, the two output merges, and the `systems`/`pkgs`
derivation. Absorbing them costs ~9 lines back at the new call site — **a net ~28 of 99, about 27%.**

### Decision: `contract.lib.mkContractFleet`

```nix
contract.lib.mkContractFleet {
  roster;                                     # from mkContractRoster (#57)
  bakedVariants;                              # from mkBakeMatrix (#58) — the consumer's fleet fact
  pkgsFor = sys: …;                           # a FUNCTION, not an attrset — see below
  buildHome = { member, granted, pkgs }: …;   # injected closure (ADR-0004)
}
# → { homes; packages; contractUsers; systems; pkgsBySystem; }
```

- **The home arrives by injected closure, not by the contract calling its own builder.** `buildHome`
  is the consumer's, so the fleet producer never names `mkContractHome`, `stateVersion`,
  `extraModules` or `extraSpecialArgs` — which is what preserves the first amendment's guarantee
  that *a home built without the builder still bakes*, lets a producer thread its own
  `extraSpecialArgs` (the [ADR-0020](0020-multi-user-repo-shape.md) `inputs` convention) without the
  contract learning what `inputs` is, and keeps the whole thing package-free by the same injection
  posture as `mkConfinementCheck`'s `buildHome`. Taking `mkContractHome`'s own arguments instead
  would re-fuse builder to bake — the exact thing the overturned ground feared, and the thing this
  shape avoids.
- **`pkgsFor` is a function because an attrset creates an ordering problem.** `systems` is derived
  from `bakedVariants`, so a consumer handing over a pre-built `pkgsBySystem` must derive `systems`
  first and the absorption never completes. With a function, the producer derives `systems`, folds
  `pkgs` per system **once**, and returns both. That fold is the point: both producers carry
  near-identical prose warning that `import nixpkgs` is not memoized across applications and must be
  instantiated once per *system*, never once per user × variant × system. A performance trap
  re-typed twice is contract material.
- **Every roster member bakes every variant in its system's row — hard-wired.** This is the call
  `mkRosterChecks` already made (#60), whose coverage rule is "every member bakes on every system in
  `homes`" with the odd fleet dropping to the per-user helpers. Same structure here: a producer
  wanting a partial roster bake drops to `mkContractUsers`.
- **`packages` and `contractUsers` come out nested by system**, so `inherit (fleet) packages
  contractUsers;` *is* the flake outputs. `homes` is `<system>.<user>.<label>` — the shape
  `mkRosterChecks` and the example's teaching checks already consume, so nothing downstream moves.
  All five returned attributes are conformance-covered: a returned value nobody pins is a rule
  nobody holds.

**What stays the consumer's.** `pkgsFor`, where the roster lives, the bake matrix, the `mkHome`
partial application (`homeManagerConfiguration` verbatim, `stateVersion`), the greeter-login block,
the `homeConfigurations` published-name rule, and the checks. The published names in particular are
*not* absorbed: both producers say in prose that those names are their own and owe the published
packages nothing, which makes the rule a choice however mechanical it looks.

### The two grounds, answered

1. **"Which variants to bake is the producer's call" — stale, not wrong.** It was true when
   written. `mkBakeMatrix` (#58) has since made the matrix a value the consumer *states* and hands
   over; `mkContractFleet` takes it as a parameter exactly as `mkContractUsers` already takes
   `users`. The contract still opines on the declaration's *shape* and never on the fact.
2. **"The greeter-login mapper needs the same composition outside any bake" — answered by
   non-fusion, with the coverage gap conceded.** `mkContractHome` stays public and separate; the
   greeter-login mapper keeps calling it directly with its own grant and its two extra modules,
   untouched. The ground assumed a fatter producer would *replace* the builder, and this one does
   not. **Conceded:** `mkContractFleet` therefore serves 2 of the 3 home-building call sites in this
   repo, and the greeter mapper is exempt **by design** rather than served. It is not "the one way a
   producer builds homes", and no future proposal should claim it became one.

### Consequences, including what this costs

- **The public `lib` grows to eleven, and `mkContractUsers` stays in it** (recorded as an amendment
  in [ADR-0026](0026-consumer-producer-public-surface.md)). Both reference producers stop calling
  it, which is precisely the caller-less condition ADR-0026 used to internalize four functions —
  and it is kept anyway, for one reason: the contract is consumed at a **URL**. Under
  internalization, any third-party producer whose bake is not a full cross-product is locked out
  entirely, and ADR-0026's "one-line move back from `kit.internal`" is no escape hatch for someone
  who does not own this repo. Since the cross-product is hard-wired above, `mkContractUsers` **is**
  the escape hatch, and an escape hatch has to be reachable. The arity reads honestly:
  `mkContractUser` (one user) / `mkContractUsers` (a roster you enumerate) / `mkContractFleet` (a
  roster you *derive*, across systems).
- **A third `buildHome` spelling, accepted deliberately.** The kit already has two —
  `mkConfinementCheck` takes `extraModules: home`, `mkRosterChecks` takes `member: extraModules:
  home` curried. This one takes an **attrset**, `{ member, granted, pkgs }`, because three
  positional arguments in a fixed order is the worse failure mode: silently transposing `granted`
  and `pkgs` is a type error nowhere. The inconsistency is named here rather than hidden.
- **The symmetry framing is retired.** The candidate was raised on an asymmetry — a host binds with
  one call while the producer spends hundreds of lines. That framing does not survive the
  measurement and must not be reused: two thirds of the example's length is teaching prose, and
  ~60 code lines *remain* after this lands. A producer genuinely holds more choices than a consumer
  does, so the two sides will never be one call each. A future architecture review that observes the
  remaining asymmetry has observed a fact about producers, not a defect.
- **This ADR's own unfulfilled consequence lands.** "A producer's `mkHome` becomes policy-only" was
  recorded above and did not fully arrive; after `mkContractFleet` what remains repo-side really is
  policy — which `pkgs`, which `stateVersion`, which matrix, which names, which greeter convention.
- **The case rests on verbosity alone, and that is the weaker half.** The *safety* half of this
  candidate — a mispaired `{ grants; home }` shipping a base home under a `gui` grant-key — was
  already spent by the first amendment (#56), which made it a hard eval error. What is left is 37
  mechanical lines, and the honest bar they clear is ADR-0026's: real call sites that cannot get the
  result without re-typing it, and not a second spelling of anything kept.
- **The second call site is evidence, not a commitment.** The 37 identical lines were *observed* in
  `~/code/users`, which has taken none of #45/#57/#58/#60 and is **not scheduled to converge** on
  this dialect. So the duplication is real and measured, while the "two adopting producers" claim is
  not made. This is the weakest link in the rationale and is left visible on purpose: one operator's
  two repos is thin ground for growing a published surface, and a future review is entitled to weigh
  it again on that basis.

### Considered and rejected within this amendment

- **Absorbing the `homeConfigurations` published-name rule** (13 more lines). Rejected: the names
  are the producer's own and owe the published packages nothing — a choice, however mechanical the
  loop around it looks.
- **Absorbing the greeter/unbaked homes.** Rejected: one call site, not two — `~/code/users` has no
  greeter block at all — and it would fuse the builder to the bake for the sake of the one home that
  is never baked.
- **Absorbing the check-kit fold** (`fleet.checks`). Rejected: `mkRosterChecks` shipped for exactly
  this six commits earlier, and re-wrapping it is the "second spelling of something kept" that
  [ADR-0026](0026-consumer-producer-public-surface.md)'s test forbids.
- **A `members` filter on the roster.** Rejected: speculative generality with zero call sites, and
  it contradicts the mapper's premise that adding a user needs no edit at the root.
- **Extending `mkContractUsers` in place with a roster+matrix mode.** Genuinely close — it already
  carries dual `roster`/`usersDir` modes, so a third costs nothing on the surface budget. Rejected
  anyway: a function with three modes is the accretion ADR-0026 was written to stop. One more name
  is cheaper to read than one more mode.
- **Demoting `mkContractUsers` to `kit.internal`** to hold the surface at ten. Rejected on the
  published-URL argument above.
- **Re-rejecting the candidate outright.** The defensible form of this was: #56 already took the
  half that mattered, and ~28 net lines is not worth an eleventh public name. It is recorded here as
  a real option rather than a straw one — the deciding argument against it is consistency with the
  bar the reopening was judged by, which 37 mechanical, twice-typed lines clear.
