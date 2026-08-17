# The consumer/producer public surface: `bindContractUser` / `mkContractUser` / `traceUser`

**Status:** Accepted (2026-08-06). Amends [ADR-0007](0007-user-flake-shape.md) (the binding shapes), [ADR-0008](0008-greeter-is-a-contract-deliverable.md) (the greeter mechanism), [ADR-0016](0016-prebuilt-binding-mode.md) (the pre-built primitives), and [ADR-0025](0025-turnkey-host-side-bind.md) (the turnkey bind). It renames and re-levels the `lib` surface, and **retires** the inline-eval binding path and the unilateral direct-grant posture from the public surface. **Amended in place (2026-08-16)** — the producer data surface swaps `homeAffecting` for `variants` and gains `lib.hostFactsFor`; see the amendment at the end.

> **Terminology note (2026-08-17, [ADR-0030](0030-one-name-per-value-on-the-producer-surface.md)):** this record says **variant and roster**; the code and `CONTEXT.md` now say **home and member set**. The decision below is unchanged — only the vocabulary moved. This ADR is left as written.


The `lib` surface had grown by accretion — a function per issue, each named for the trait that distinguished it *when it was added* rather than for which one a consumer should reach for. By ADR-0025 there were eight public functions across two spellings of "bind" and three of "make," and the two a normal consumer actually wants (`bindUserFromFlake`, `mkUserBindings`) had the longest, least-guessable names, while the plainest name — `bindUser` — was taken by a test-only tracer. The reference host fleet had to locally re-alias `bindUserFromFlake` to `bindUserTurnkey` just to read. A naming review turned into a surface review, because several of the eight had no consumer at all.

## What the trace showed

- **`bindUserModule`** (the inline-eval bind, [ADR-0008](0008-greeter-is-a-contract-deliverable.md)/issue #8) had **zero** callers. `examples/fleet` binds entirely pre-built; the greeter builds the user's own `homeConfigurations.<u>.activationPackage` (never `bindUserModule`); only the conformance suite invoked it. Its stated value — "hard-enforcement," the host evaluating the home live so a denied feature cannot be present — is undercut by the contract's own *program scope* doctrine ([ADR-0017](0017-daemon-restricted-user-package-policy.md)): package restriction was never host-enforceable with daemon access, which is *why* the pre-built mode is "the coherent choice." System effects (grants, groups, privilege) are controlled equally by the pre-built path.
- **`bindContractPackage { grants }`** ([ADR-0016](0016-prebuilt-binding-mode.md)) is the only place a host could write a grant **unilaterally** (grant a feature the user never offered). No reference host does; `examples/fleet` is 100% negotiated (`affordances ∩ offer`, ADR-0025).
- **`mkContractPackage`** / **`mkContractPackageForHome`** are baked *through* by the roster producer; no reference producer calls them directly. Once `bindContractPackage` stops being a public consumer, a bare `contractPackage` they emit has no public consumer either.
- **`mkHostFacts`** projects `{exposed,platform,granted}` from a NixOS host `config` — a config that only exists where a host evaluates a home **inline**. With inline-eval retired, nothing in the pre-built world holds that config (the producer bakes hostFacts by hand; the host binds a pre-built home). Only conformance called it.

## Decision

Fix the public surface at **six** functions, organised on one concept seam — *the public surface speaks in **contract users**; the package-level kernels speak in **contract packages** and stay internal* — and retire the paths that had no consumer.

### The produce/consume coin

| Role | Name | Was |
| --- | --- | --- |
| Produce one user | **`mkContractUser`** | *(new — extracted)* |
| Produce a roster | **`mkContractUsers`** | `mkUserBindings` |
| Consume one user | **`bindContractUser`** | `bindUserFromFlake` |

`mkContractUser` is the **singular** producer — the true per-user twin of `bindContractUser` (*make one contract-user ⇄ bind one*). It bakes one user's variants into the named packages and its `contractUsers.<sys>.<user>` index entry, emitting the ready-to-`inherit … packages contractUsers` flake-output shape, so a single-user repo needs no roster. `mkContractUsers` is now nothing but `mkContractUser` mapped over a roster and merged — the multi-user convenience ([ADR-0020](0020-multi-user-repo-shape.md)). Plural producer ⇄ singular consumer is the honest arity: the producer bakes the whole roster in one call; a host binds one account at a time. Both names mirror the `contractUsers` output, whose `contract` prefix is *forced* — the users flake is itself named `users`, so a bare output would read `users.users.<sys>`.

### `traceUser` — the inspector outside the coin

The ex-`bindUser` tracer becomes **`traceUser`**: the home-manager-free dry-run that harvests a contract-pure home via bare `evalModules` and returns `{ username; home; requests; system }`. It answers "given these grants, what does my home request, and does it bridge?" without a build — the conformance kernel and the public tool a home author inspects with. It deliberately sits *outside* the coin (it takes raw pieces, never the index), so it keeps a plain name, not `traceContractUser`.

### Retired from the public surface

- **Inline-eval bind (`bindUserModule`): deleted.** The build-time path is pre-built only; the greeter builds the user's own home output. [ADR-0008](0008-greeter-is-a-contract-deliverable.md)'s greeter mechanism condition (2) is reworded from "bind via `bindUserModule`" to "build the user's own home output through the contract umbrella."
- **Unilateral direct-grant: retired.** The public grant model is **negotiation-only** — `grant = affordances ∩ offer` via `bindContractUser`. `bindContractPackage` (which takes `grants` verbatim) becomes an **internal kernel**; there is no public path to grant a feature a user did not offer.
- **`bindContractPackage`, `mkContractPackage`, `mkContractPackageForHome`, `mkHostFacts`: internalized.** Not flake outputs. Exposed to the in-repo conformance suite via `kit.internal` so they are still proven in isolation. *(Amendment: `mkHostFacts` was subsequently **deleted** as caller-less — the producer hand-builds the `{exposed,platform,granted}` literal inline, so the config-projector re-derived nothing; re-add it from git history if a host-side-eval caller returns.)*

The resulting public `lib`: `mkContractUser` · `mkContractUsers` · `bindContractUser` · `traceUser` · `loadIdentity` · `renderNixConfig`.

*(Amendment, issue #35 — the **check kit**: `mkConfinementCheck` and `mkIdentityPostureCheck` join the public `lib`, taking it to eight. They pass this ADR's own test — the one it applied to the eight it found: each has a real consumer that cannot get the proof any other way. `mkConfinementCheck` proves a **consumer's own module set** has no system channel (this repo's suite can only prove the umbrella), and `mkIdentityPostureCheck` asserts the **consumer-owned**, conditional ADR-0019 credential posture that `loadIdentity` must not impose. Neither is a second spelling of anything kept, and neither is a bind or a bake: they are the proofs only the consumer can run, which is why they are functions the contract hands over rather than checks it runs. This is surface growth by the front door — the cost being paid deliberately for two ~20-line boilerplates every consumer repo re-types, one of which (the positive control) is silently wrong when forgotten.)*

## Consequences

- **The north star is untouched.** The runtime greeter (any user logs in without being enabled in nix config) consumes only kept surface — `identityFile`, `greeterGrants`, `safeSet`, `renderNixConfig`, `nixosModules.greeter`, and the user's own `homeConfigurations.<u>`. It never called any renamed or removed function. `bindContractUser` is correctly framed as the *build-time* path (operator-managed and privileged accounts the safe-set greeter cannot grant), the opposite posture to the greeter — no longer mis-named as "the" way onto a machine.
- **Solo producers regain ergonomics.** A single-user repo calls `mkContractUser` once rather than faking a one-entry roster — the cost ADR-0025's roster-only producer would otherwise have imposed once the primitives went internal.
- **Loss:** a host can no longer grant a user a feature the user did not offer, nor evaluate a home host-side inline through a contract helper. Both had no reference consumer; both are recoverable by re-exposing the internal kernel if a real need returns (see below).
- Breaking rename of every public consumer/producer call site; landed in lockstep across the contract, conformance, and both reference fleets (no back-compat aliases — the contract is pre-1.0).

## Considered Options

- **Keep all eight, just rename.** Rejected: four had no consumer; carrying them is exactly the accretion this cleans up.
- **`mkUsers` (drop "Contract").** Rejected: collides with `users.users` (the realization's own output) and desyncs from the forced-prefix `contractUsers` output.
- **`mkUser` singular only, arity-matched to `bindUser`.** Rejected: the roster producer is intrinsically plural (that is what makes it turnkey); a singular-only form re-introduces the per-user loop ADR-0025 removed. Shipping *both* the singular partner and the roster convenience is what keeps the arity honest.

## If a retired path should return

Re-exposing is a one-line move from `kit.internal` to `kit.lib`, plus an ADR amendment: `bindContractPackage` for a fleet that genuinely wants unilateral grants, `mkHostFacts` for a host that runs its users' homes through its own home-manager, or a fresh inline bind if hard-enforcement ever becomes enforceable. Nothing here forecloses them; it only stops advertising a surface no one uses.

## Amendment (2026-08-16) — ship the producer's derivations, not the datum they derive from

The data surface exported `homeAffecting`: the feature names whose grant can reach home content. A trace of its consumers — the reference fleet in `examples/users` and the operator's own users repo — found it used for exactly two things, in both, written out by hand in both:

```nix
granted = lib.filterAttrs (f: _: lib.elem f contract.homeAffecting) grants;   # the hostFacts narrowing
variantGrants = map … (lib.foldl' … [ [ ] ] contract.homeAffecting);          # the baked variant set
```

Neither is a consumer *choice*. Both are the contract's own rules, re-derived per repo from a datum, and both fail **silently** when wrong: a mis-written narrowing shows a home a grant it must not see, and a variant set that has fallen behind the registry under-bakes — `bindContractUser` binds the maximal variant that *does* exist and the home simply lacks the new feature's content, which no coupling guard reports. One consumer had resorted to hardcoding its variant set behind an `assert` on `homeAffecting`, which is the tell: the datum was public, the rule was not.

So the surface now carries the **derived forms** and drops the datum:

- **`variants`** — `[{ label; grants; }]`, one entry per combination of the axes. A producer maps over it. `label` travels with `grants`, so the two cannot be paired up wrongly, and the label rule stops being mirrored per repo against the private `variantName`.
- **`lib.hostFactsFor`** — `{ granted, platform, exposed ? false } → hostFacts`, narrowing `granted` to the axes. Deliberately not `mkHostFacts` returning under a new name: that one projected from a NixOS host `config` and is retired above; this one has no host in sight and belongs to the producer.
- **`homeAffecting` leaves the surface.** Its projection survives as `kit.internal.variantAxes`, exposed only so the conformance suite can prove the taxonomy in isolation.

This passes the test this ADR applied to the eight functions it found: each addition has real consumers that cannot get the result any other way, and neither is a second spelling of anything kept. It is also a net *simplification* of every consumer — two hand-written derivations and an assert deleted from each — which is the opposite of the accretion this ADR was written to stop.

**The registry flag is renamed with it: `homeAffecting` → `needsOwnBuild`.** The old name asserted a vague relationship in a system where everything relates to the home, and said nothing about the cost. The new one states the mechanical test — can this grant be applied to a home that is already built? — and its complement is the registry's existing prose: a feature without it *rides the bind*. Saying yes doubles every user's variant count on every architecture, and the name should make an author feel that before they type it.

## Amendment (2026-08-16) — the producer home builder joins the `lib`

**`mkContractHome`** ([ADR-0029](0029-producer-home-builder-and-home-baseline.md), issue #40) takes the public `lib` to ten. It passes this ADR's test the same way the prior amendments did: three real call sites (the reference roster homes, its greeter-login mapper, the operator's users repo) hand-wrote the identical composition — umbrella + `home.nix` + the inline identity/`home.*` module + the `hostFactsFor` specialArg — and none can get it any other way without re-typing the contract's own rules, one of which (the `hostFacts` narrowing) fails silently when wrong. It is not a second spelling of anything kept: the producer coin bakes *packages from* already-evaluated homes; this is the one place homes are *evaluated*, with home-manager injected per call (`homeManagerConfiguration` verbatim — the check kit's `buildHome` posture), so the package-free invariant holds. It also carries the new `homeModules.baseline` into every composed home by default — the `greeterDesktop`-pattern sibling output, outside the tracer-pure `default`.

## Amendment (2026-08-16) — the roster derivation joins the `lib`

**`mkContractRoster`** (issue #57) takes the public `lib` to eleven: `{ usersDir } → { <name> = { name; dir; identity; }; }`, the one answer to *who is in this users repo, and what is each identity*.

It passes this ADR's test on the same evidence the earlier amendments did. The [ADR-0020](0020-multi-user-repo-shape.md) layout rule (`users/<u>/{identity.json,home.nix}`) was spelled in **four** independent places — the producer's own `readDir` filter, the producer's identity map, `mkContractUser`'s index resolution, and `mkContractHome`'s `identity` default — so each `identity.json` was resolved two or three times per evaluation, by three owners, and a change to the layout had to find all four. [ADR-0009](0009-binduser-single-identity-loader.md) made the contract the single identity *loader*; the resolution *site* had since scattered, which is the same drift this ADR was written to stop. It is not a second spelling of anything kept: `loadIdentity` reads **one** file into the identity shape and imposes no layout; this reads the **directory** and says who the members are.

The coin and the builder now take a **member** (`mkContractUser { member; … }`, `mkContractHome { member; … }`) rather than re-deriving a path from a name, so on the roster path each identity file is read exactly once per evaluation. The layout rule itself is now literally single-sourced: the three joins that name a path (`<usersDir>/<name>`, `<userDir>/identity.json`, `<userDir>/home.nix`) are one helper each in `lib.nix`, and the roster derivation, the coin's roster-less fallback and the builder's all read through them — so the roster-less shapes below stay possible without re-transcribing the layout.

Three things it deliberately does **not** do:

- **It does not become the users repo's index.** Liftability ([ADR-0020](0020-multi-user-repo-shape.md)) is the standing constraint: it reads `users/<u>/` and adds no file, no manifest and no knowledge at the users-repo root, so lifting a user into its own repo stays a literal directory move.
- **It does not become mandatory.** One user is not a roster: `mkContractUser` keeps taking `name` + `usersDir`, and `mkContractHome` a bare `userDir`, so a single-user repo bakes without constructing one. The member is the *preferred* input, not the only one.
- **It does not opine on the bake matrix.** `mkContractUsers` takes the roster *and* a `users` attrset of `{ variants }`: who the members are is the roster's answer, which of them bake and with which variants stays the consumer's fleet fact (the posture decision #43 fixed for the per-system variant filter). Only the incoherent direction is an error — a `users` key the roster does not hold is a hand-listed name that has drifted from the directory.

What it *does* refuse is the vacuous case: a `usersDir` yielding no member at all is a named error, not `{ }`. Everything downstream maps over the roster, so an empty one would bake, publish and check nothing while every flake output stayed green — the same trap `mkIdentityPostureCheck`'s empty-roster error and `mkConfinementCheck`'s positive control close.

## Amendment (2026-08-17) — the bake matrix's shape joins the `lib`

**`mkBakeMatrix`** (issue #58) joins the public `lib`: `{ systems = { <system> = { <axis> = bool; }; }; } → { <system> = [ variant ]; }`, the per-system narrowing of `variants` plus the guards around it.

It looks, at first, like the one thing this surface has repeatedly declined to take. Decision #43 fixed the posture that *which* variants a fleet bakes per system is the **consumer's fleet fact**, and the amendment above says outright that `mkContractUsers` "does not opine on the bake matrix". That posture is undisturbed. What moved is not the fact but the **shape of the declaration**, and the two are separable in exactly the way this ADR's test asks about:

- The **fact** is a fleet's topology — "this tier is a headless arm builder, its seats cannot use `gui`". No other repo can know it, and the contract still does not.
- The **shape** is contract mechanism. The contract knows the axes, knows the upper bound, and — decisively — knows that *binding degrades quietly*: `bindContractUser` selects the maximal baked variant whose grant-key is covered, so a set that has fallen behind the registry hands a host a home that simply lacks the new feature's content, and no coupling guard, manifest field or check reports it. The failure mode is the contract's, so the shape that forecloses it is too.

The evidence is the same species the earlier amendments turned on, and sharper. The reference fleet hand-wrote the per-system filter **and** hand-wrote an `assert` catching its own filter's failure mode — with a comment naming that mode exactly. That is the tell: a producer holding a rule *and* the proof of the rule is holding the contract's work. It is not a second spelling of anything kept: `variants` answers "what could a host grant" (the upper bound); this answers "and which of it does *this* system bake", which nothing else says.

### The direction of default is the whole design

A row names only the axes a system's seats **cannot** use, and an axis it **omits is usable**. Both of the obvious alternatives fail the same way:

- a list of **labels** (`[ "base" ]`) names combinations, so a new axis doubles the labels and every existing list silently omits half of them;
- a list of what a system **can** use (`[ "gui" ]`) — the shape a reader schooled on `meta.platforms`, `nix.settings.allowed-users` or this repo's own `packagePolicy.allowedPrograms` will reach for first — silently drops each new axis from **every** system.

Those inclusion lists are right where the enumerated thing is owned by the declarer and the risk of the unknown is **admitting** something. Here the enumerated thing is owned by the *contract* and the risk of the unknown is **omitting** it. Fail-closed is right for privilege; fail-open is right for **coverage** — under-baking is silent and costs a user their home content, while over-baking wastes build time and nothing else. This is [ADR-0002](0002-user-confinement-manifest-greeter.md)'s "one mechanism, opposite defaults" applied a second time, on the axis [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md) already applied it on when it defaulted `contract.wants` to the safe set so "*a future non-privileged feature inherits it with no new special case*". Here a future **axis** inherits its bake with no new special case, in every consumer repo, unedited.

### What is guarded, and what is now unexpressible

Keying the matrix by system — one input, not a system list plus a rule — makes three under-bakes impossible to *write* rather than caught by an assert: a rule that names a system the fleet does not bake, a system left unclassified, and a claim of unrestrictedness that contradicts the rule. An unrestricted system is simply a row that takes nothing away, so there is no second statement for a first one to disagree with.

An earlier draft of this work did carry that second statement — a separate `unrestricted` claim joined against the rule, in the posture [ADR-0029](0029-producer-home-builder-and-home-baseline.md)'s bake pairing established one rung down. The analogy does not survive scrutiny: the bake pairing joins two statements made in **different places by different mechanisms** (a home records its grant-key during its own eval; a producer passes one in a flake output), whereas those two sat three lines apart in one call, written by the same hand in the same edit. A join between adjacent lines buys a guard against editing one of them — real, but far weaker than making the disagreement unwriteable. Where a design can foreclose a failure instead of asserting against it, this ADR prefers foreclosure.

Four guards remain, for what the shape cannot say: a setting that is not a variant axis — checked on the **key** whatever the boolean says, since `sudo = true` reads as though someone had considered whether the bake fans out on `sudo` and it does not — a non-boolean setting, a malformed row, and an emptied bake. Each error names the offending **axes and systems**, not a count.

### The testing seam stays internal

Proving that a contract which *gains* an axis extends every system's bake needs a two-axis upper bound, and the registry has one axis. Rather than put a bound-override on the public signature — a parameter documented as being for the suite's benefit, which no producer would ever pass — the kernel `bakeMatrixOver { systems, upperBound }` lives in `kit.internal` and the public `mkBakeMatrix` is it closed over `variants`. That is the posture `variantAxes` is already exposed under, and it keeps the consumer-facing surface at exactly one argument.

`mkVariantEvalCheck` is unchanged and still deliberately shape-agnostic: "whatever we bake, evaluates" is its fact, and its anti-vacuous assert is now a second net under an emptied bake that `mkBakeMatrix` refuses at the source.

### Divergence from issue #58

Two of the issue's acceptance criteria — "*A system with no exclusions is asserted to bake the contract's full variant set*" and "*Conformance covers the full-set assert firing*" — ask for an **assert** that this shape makes unnecessary. The property they name holds, structurally and unconditionally; there is no firing to cover because there is no way to write the violation. Recorded here rather than quietly satisfied, because "we deleted the assert you asked for" deserves to be legible.

## Amendment (2026-08-17) — the check kit gains a roster adapter

**`mkRosterChecks`** (issue #60) takes the public `lib` to fourteen: `{ roster; homes; buildHome; require; pkgs } → { home-confinement-<u>; variant-eval-<u>; identity-posture }` — the [check kit](../../check-kit.nix)'s three helpers applied across a whole roster in one call.

This is the amendment that most looks like a violation of the ADR's own test, and it should be read as one until the distinction holds: every function it calls is kept and public, and a fold over kept functions is very nearly the definition of "a second spelling of something we already have". Two things save it, and both are checkable.

The first is *why the helpers are roster-generic in the first place*. Decision #43 and issue #49 shaped them that way for one reason: a hand-listed set always misses the entry someone forgot to add, so the offender is precisely the user nobody wrote a check for. Leaving the fold at the call site reinstates that hazard **one level up** — the check set is now the hand-written thing, and a member missing from it fails in the most invisible way a check can, by not existing. A missing check and a passing check are indistinguishable in `nix flake check` output.

The second is the same tell the bake-matrix amendment turned on. The reference fleet hand-wrote two `mapAttrs'` folds over the roster, spelled each check's name **twice** (once as the `checks.<system>` attribute, once as the `name` its failure message reports, free to disagree), threaded a closure per user into each — and carried, per fold, a comment arguing why the fold had to be roster-generic. A producer holding the rule *and* the argument for the rule is holding the contract's work.

### What it does not take

- **It does not pick a posture.** `require` has no default here either. ADR-0019 makes the credential posture consumer-owned, and an adapter that defaulted would impose one repo's posture on every repo that adopted the adapter without thinking about it — a worse version of the policy `loadIdentity` refuses to carry.
- **It does not decide which proofs a repo runs.** The three helpers stay public and separately callable, and are documented as the primary surface: one user is not a roster, and a repo wanting confinement alone should call for confinement alone. This is a fold over them, written in the same public arguments those calls take.
- **It does not opine on the bake matrix.** It reads `homes` exactly as handed; *which* variants a fleet bakes for which system remains the fleet's fact (decision #43, and the amendment above).
- **It is not a flake output the contract writes.** It cannot be: every input is the consumer's — its `pkgs`, its builder, its homes, its posture. It is a function handed over, like everything else on this surface.

### `homes` is data, not a hook

`mkVariantEvalCheck` takes a `homesFor` closure plus a `systems` list, which is right for one user in isolation. The adapter instead takes the consumer's per-system homes **as it already holds them** (`{ <system>.<user>.<label> = home; }`), and that choice buys two things a closure could not. The systems checked are the key set of the material itself, so "which systems this fleet bakes" is read off the homes rather than handed a second time and trusted to agree. And the roster can be checked **against** the homes before any check is built: a member with no bake on some system is a named error naming the pair, where a closure could only have thrown a raw `attribute missing` from inside a helper, or — worse, had the adapter mapped over the homes instead of the roster — quietly checked one member fewer.

That is the shape of everything the adapter adds: it introduces no `tryEval` and no filtering, so each helper's guards survive it untouched, and the new guards are the vacuity traps that exist **at the fold** and nowhere else — a roster with no members, homes naming no system, and homes that do not cover the roster — each of which would otherwise yield a check set that is merely *smaller*. Two shape guards sit under those diagnoses, so a roster or a row handed as something other than an attrset is told what it is rather than reported as empty.

The coverage guard is the one demand the adapter makes that the helpers do not, and it is worth naming as such: **every member bakes on every system in `homes`**. That is not an opinion about the [bake matrix](../../CONTEXT.md) — it says nothing about which *variants* a system bakes — but it is the shape `mkBakeMatrix` already implies, whose rows are per **system**, not per user. It is also what makes "who is unchecked" answerable at all: without it there is no set to compare the roster against. A fleet that genuinely bakes different members on different systems is outside this fold, and calls the three helpers per user — one more reason they stay public, and the error message says so.

The `force` and `positiveControl` hooks are forwarded rather than fixed, defaulting to the same home-manager attrpaths the helpers default to. That keeps a hand-rolled home checkable through the adapter — and it is what lets the contract's own suite drive the adapter at all, since the contract has no home-manager (ADR-0004) and must point both hooks at the umbrella's own declared options.

## Amendment (2026-08-17) — the fleet-level producer joins the `lib`, and `mkContractUsers` stays

**`mkContractFleet`** (issue #62, executing [ADR-0029](0029-producer-home-builder-and-home-baseline.md)'s second amendment) takes the public `lib` to fifteen: `{ members; homeMatrix; pkgsFor; buildHome } → { homes; packages; contractUsers; systems; pkgsBySystem; }` — every member's every home, on every system, plus the two published attributes already nested the way a flake output is.

*(Two counts are in circulation and both are right about different sets: this ADR has been counting the whole `lib`, which the check kit took to fourteen and this takes to fifteen; ADR-0029's amendments count the produce/consume functions alone, which this takes from ten to eleven.)*

It is the third and last rung of one arity, and the three read honestly together: **`mkContractUser`** bakes one user, **`mkContractUsers`** bakes a member set you *enumerate*, **`mkContractFleet`** bakes one you *derive* — across systems. The reasoning, the conceded costs, and the options rejected inside it all live in ADR-0029's second amendment; what belongs here is only what this ADR is the register of: what joined the surface, what it cost, and what was kept.

### Against this ADR's own test

- **Real call sites that cannot get it any other way without re-typing it.** What it absorbs is the residual *join* — the per-home eval loop, the members × system × home fold, the grants↔home re-pairing, the two output merges, and the `systems`/`pkgs` derivation. Measured after the four blockers landed, that was 37 lines of `examples/users/flake.nix`, present character-for-character in a second, independently evolved producer. The adoption removed 25 code lines (37 total) and moved nothing downstream: all 21 published packages, the whole binding index, and all 21 `homeConfigurations` names are byte-identical across it.
- **Not a second spelling of anything kept.** `mkContractUsers` bakes homes it is handed; this builds them and hands them over. The one function it *contains* is that one, called once per system — the same relationship `mkContractUsers` already has to `mkContractUser`.
- **Every input is the consumer's,** so it cannot be a flake output the contract writes: its members, its matrix, its nixpkgs, its builder.

### `mkContractUsers` is kept although both reference producers stopped calling it

This is the caller-less condition that internalized four functions in the original decision, and it is **not** applied here. One reason, and it is about distribution rather than about taste: the contract is consumed at a **URL**. `mkContractFleet` hard-wires the full cross-product — every member bakes every home in its system's row — so a third-party producer whose bake is *not* a cross-product needs the rung below, and this ADR's "one-line move back from `kit.internal`" is no escape hatch for someone who does not own this repo. An escape hatch has to be reachable by the person escaping.

The demotion was considered and rejected on exactly that ground, as was extending `mkContractUsers` in place with a members-plus-matrix mode: a function with three modes is the accretion this ADR was written to stop, and one more name is cheaper to read than one more mode.

### What it does not take

- **It does not build a home.** `buildHome` is an injected closure, `{ member, grants, pkgs } → home`, so the producer never names `mkContractHome`, `stateVersion`, `extraModules` or `extraSpecialArgs`, and never imports home-manager (ADR-0004, the same posture `mkConfinementCheck`'s `buildHome` takes). That is also what keeps ADR-0029's first-amendment guarantee alive one rung up: a home built *without* the builder still bakes, because the fold cannot tell.
- **It does not opine on the bake matrix, or on who is a member.** Both arrive as values — `mkHomeMatrix`'s and `mkMembers`'. What it adds is the cross-product between them, which is the same call `mkMemberChecks` already made.
- **It does not name a published home.** The `homeConfigurations` naming rule stays the producer's: those names owe the published packages nothing, which makes the rule a choice however mechanical the loop around it looks.
- **It does not serve every home.** A greeter-login mapper builds a home that is never baked, and keeps calling `mkContractHome` directly. Exempt by design, conceded on the record in ADR-0029, and not something a future proposal may quietly reclassify.
- **It does not fold the check kit.** `mkMemberChecks` shipped for that, and re-wrapping it is the second spelling this ADR's test forbids.

### `pkgsFor` is a function, and that is the load-bearing argument for the name

An attrset would not work: `systems` is derived from the matrix, so a consumer handing over a pre-built `pkgsBySystem` must derive `systems` itself first and the absorption never completes. With a function the producer derives `systems`, applies `pkgsFor` **once per system**, and returns the memo — which is how a rule both producers carried as *prose* ("`import nixpkgs` is not memoized across applications; instantiate once per system, never once per user × home × system") becomes a value a caller holds. The conformance suite pins it as identity rather than as resemblance: the `pkgs` each home receives *is* the memo entry, and a second application of the same `pkgsFor` is *not* — the negative control without which the claim could pass by coincidence.
