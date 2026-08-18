# The published bake set is the matrix: unclassified and unpruned

**Status:** Accepted (2026-08-18). Records a **negative result** — it changes no code and adds no
surface. It answers [issue #63](https://github.com/palebluebytes/host-user-contract/issues/63) and
the design question behind it, and exists so that neither half is re-proposed without new evidence.
Confirms [ADR-0002](0002-user-confinement-manifest-greeter.md)'s rejection of the curated-catalog
model (*model C*) by re-testing it empirically against a concrete re-proposal; relies on
[ADR-0016](0016-prebuilt-binding-mode.md)'s IFD ban; concerns the published bake set of
[ADR-0025](0025-turnkey-host-side-bind.md)/[ADR-0026](0026-consumer-producer-public-surface.md) and
the home matrix of [ADR-0029](0029-producer-home-builder-and-home-baseline.md)/[ADR-0030](0030-one-name-per-value-on-the-producer-surface.md).

## The question

Raised while renaming the producer surface:

> *is there a way to automatically tell which programs/settings belong to a gui setup and which can
> run in just a shell? (with an escape hatch for more advanced users)*

Today a producer hand-wires the branch — `custom.home.profiles.gui.enable =
hostFacts.granted.gui.enable or false` — and every member bakes every home in its system's row of
the home matrix, whether or not those homes differ.

The ask contains **two** questions, and they have different answers:

1. **Classify** — can the contract *derive* which of a home's content is graphical? **No**, and the
   route is closed rather than merely unbuilt.
2. **Prune** — can the contract detect that two baked homes are *the same* and publish one? **Yes**,
   and it is not worth doing.

## Classification is closed

Four mechanisms exist. Three are structurally shut; the fourth answers a different question.

| # | mechanism | verdict |
| --- | --- | --- |
| 1 | package `meta` marks a package graphical | no such field exists in nixpkgs |
| 2 | inspect built outputs for `.desktop` files | IFD, banned by [ADR-0016](0016-prebuilt-binding-mode.md) |
| 3 | heuristic over home-manager namespaces | *model C*, already rejected by [ADR-0002](0002-user-confinement-manifest-greeter.md) — and measured to give **zero** discrimination |
| 4 | evaluate twice and diff | works, but answers *whether* two homes differ, never *what* about one is graphical |

### 1. There is no `meta` field to read

The allowed-`meta` list (`pkgs/stdenv/generic/check-meta.nix`) carries no `isGui`, `graphical`,
`desktop` or `category`. Its only `is*` booleans are three ecosystem-specific ones (`isFcitxEngine`,
`isIbusEngine`, `isGutenprint`). `firefox` and `ripgrep` are **structurally indistinguishable**:
identical key sets, both carrying `mainProgram`, both listing linux platforms. The only difference is
free-text `description`.

`passthru.desktopItem` is not a fallback. `firefox ? desktopItem` is true, but `chromium ?
desktopItem` and `kitty ? desktopItem` are both **false** — it appears in 128 files against ~21,440
`pkgs/by-name` packages.

Adding such a field is a nixpkgs-wide change with ~21,000 call sites and no owner. It is not a
mechanism this contract can reach.

### 2. `.desktop` detection is IFD *by construction*, not by store state

This is stronger than "it would be IFD because the package is not built yet". The mechanism is
**string context**: `"${pkgs.foo}/..."` carries a derivation reference, and any path-reading builtin
must realise that context first. `builtins.pathExists "${pkgs.ripgrep}/share/applications"` fails
with IFD disabled **even though ripgrep is already realised in the store** — the Nix manual is
explicit that this holds "even when the required store object is readily available".

`unsafeDiscardStringContext` is a trap rather than an escape hatch: it returns `false` for any
unbuilt package, which makes the answer a function of **local store state**. The same flake would
classify a user CLI-only on a cold machine and graphical on a warm one — non-deterministic across
hosts and across time, which is precisely what the pre-built binding mode exists to prevent.

The only IFD-free route is a table committed to the source tree. Reading `nix-index-database` at
eval is *also* IFD, since a fetched database is a fixed-output derivation. A committed table is
mechanism 3.

### 3. The namespace heuristic is model C, and it does not even work

Home-manager carries no module classification to borrow: it reuses nixpkgs' module `meta`, which
declares exactly three keys (`maintainers`, `doc`, `buildDocsInSandbox`). Directory layout is not a
proxy either — `modules/programs/` mixes `kitty`/`chromium`/`mpv` with `bash`/`git`/`ripgrep`, and
grepping for any graphical marker across it hits **3 of 445 files**. Every obvious graphical program
scores zero: kitty, alacritty, chromium, mpv, obs-studio, wezterm, foot.

That leaves inferring from the *option namespaces a home sets* (`wayland.*`, `xsession.*`, `gtk.*`,
`qt.*`, `xdg.mimeApps.*`). Measured across five homes differing by exactly one enabled program, all
five signals are **false for all five homes**:

| home | `gtk` | `qt` | `xsession` | `wayland.windowManager` | `xdg.mimeApps` |
| --- | --- | --- | --- | --- | --- |
| empty baseline | false | false | false | false | false |
| `programs.kitty` | false | false | false | false | false |
| `programs.chromium` | false | false | false | false | false |
| `programs.mpv` | false | false | false | false | false |
| `programs.ripgrep` | false | false | false | false | false |

Kitty, Chromium and mpv are indistinguishable from ripgrep **and from an empty home**. The reason is
categorical rather than incidental: those namespaces are opt-in **session-management** options. They
mean "this home configures a graphical session", not "this home contains graphical software" — and a
home installing Firefox and mpv while letting the desktop environment handle theming sets none of
them. False positives exist in the other direction too: an empty home already pulls
`shared-mime-info` and `dummy-xdg-mime-dirs` into `home.packages` unconditionally.

Making it work would mean hand-classifying **592 leaf namespaces** (414 `programs.*` + 178
`services.*`), churning on every home-manager bump. That is a curated catalog — *model C* — which
[ADR-0002](0002-user-confinement-manifest-greeter.md) already considered and rejected in favour of
the request channel. Its losing argument is unchanged and now has a number attached: the catalog must
be maintained forever, and it is wrong the moment a user reaches for an option it does not know.
**Re-proposing the heuristic means reopening ADR-0002**, and the measurement above says it would not
even buy the thing ADR-0002 traded away.

### 4. Double-eval answers a different question

Two evaluations of one home under different `hostFacts` produce two `drvPath`s, and comparing them is
IFD-free (`drvPath` instantiates a `.drv` but never realises it). It is sound in both directions:
a home that ignores `hostFacts` yields a byte-identical `drvPath`, and because derivation hashing is
recursive over `inputDrvs`, a difference anywhere in the closure propagates to the top.

But it answers *"did anything change"*, never *"is this graphical"*. A gui branch that differs only
in a shell alias reads as gui-affected. This mechanism cannot classify; it can only **prune**.

## Pruning is feasible, and not worth doing

Mechanism 4 gives a real capability: `mkContractUser` could compare a home's
`activationPackage.drvPath` against the weaker homes it covers, at eval time with no IFD and no
build, and skip publishing one that is identical to a home already covered. Selection stays safe —
`bindContractUser` picks the maximal covered bake and `base` ⊆ any grant, so a gui-granting host
binding a pruned user gets `base`, with identical content.

It is rejected on cost, and the decisive argument is structural rather than numerical.

### You cannot know a bake is redundant without evaluating it

The predicate *is* `activationPackage.drvPath` equality, which forces both homes. So the expensive
half — the second full home evaluation — is paid **whether or not** the result is published. Pruning
cannot recover it. What pruning saves is only what remains after that: the wrapper `runCommand` and
its store path.

Measured on the reference fleet (appendix below), that residue is **~81 KiB and ~4 seconds**, against
an evaluation cost of ~14 s that no pruning design can avoid. The optimisation targets the 8% and
collects the 0.013%.

### A redundant pair differs by five bytes

The premise "byte-identical" is not true of the published artifact, and cannot be made true. A
contractPackage's manifest freezes the grant-key the home was baked under
([ADR-0016](0016-prebuilt-binding-mode.md)'s coupling guard), so two bakes of one home always differ:

```
-  "granted": [],
+  "granted": [ "gui" ],
```

That is the entire difference — for every redundant user, `inputs.drvs` is byte-identical and both
wrappers quote the same `home-manager-generation` output. The equivalence pruning would exploit is
therefore a claim about the **home**, not about the artifact, and it holds only while the manifest's
grant-key stays read-only-by-the-coupling-guard. That is true today
([`bindContractPackage`](../../lib.nix) asserts `bakedKey ⊆ granted` and nothing else consumes it),
but it is an invariant nothing pins — pruning would make correctness depend on it silently.

The contract already asserts the *opposite* of pruning's premise where it matters:
`conformance/contract-package.nix` pins "a non-empty grant changes the artifact (forwarding is
real)".

### What pruning would cost

| what breaks | where |
| --- | --- |
| `checks = packages // …` — building every package builds every home, which is what retired the per-user `home-build-*` checks | `examples/users/flake.nix`; the argument is cited in three conformance files |
| exact name-set equality on the published fleet | `conformance/contract-fleet.nix` |
| exact grant-key list equality on the binding index | `conformance/contract-fleet.nix` |
| one of the **two routes** that force the bake guards (`assertHomePairing`, `assertNoVetoedRequests`) — a pruned defective bake loses its package-name route | [`lib.nix`](../../lib.nix), probed throughout `conformance/turnkey-bind.nix` |
| the manifest stops recording which grant a home was baked for — behaviour is unchanged, provenance degrades | the bound package's manifest |

And the escape hatch the proposal requires — a per-member or per-build opt-out, so a producer can
keep publishing a name a host pins — has **no instance in this repo**: every host binds through
`bindContractUser` and selects by grant-key, nothing in CI names a package, and `CONTEXT.md` already
states that the published label is "a cosmetic label, not a parse target". The hatch would be new
public surface built for a hypothetical.

Silent under-publication is also the exact failure mode `mkHomeMatrix`
([ADR-0029](0029-producer-home-builder-and-home-baseline.md)) exists to foreclose: `bindContractUser`
binds the maximal bake that *does* exist, so a smaller published set costs a home its content with
nothing objecting. Pruning would introduce, deliberately and as a feature, the shape the matrix
guards were written to reject.

## Decision

1. **The contract does not classify home content.** No `meta` read, no output inspection, no
   namespace heuristic, no committed catalog. Whether a home is graphical is something the home
   **says**, not something the contract infers.
2. **The published bake set is the home matrix, unpruned.** `mkContractUser` publishes one
   contractPackage per bake in its system's row, whether or not two bakes coincide. Coincidence is
   normal and correct — most users legitimately do not branch on any grant.
3. **No redundancy diagnostic either.** A warning that fires on the healthy majority trains people to
   ignore warnings, and it is the same machinery as pruning minus the payoff.

## What a producer does instead

The escape hatch the original question asked for already exists, and it is the *only* mechanism:
a home reads `hostFacts.granted.<feature>.enable` and gates its own content on it. `examples/users`
carries the live reference — `duo-a` wires `custom.home.profiles.gui.enable` off
`hostFacts.granted.gui.enable` and gates a sway config on it, which is what makes its two bakes
differ in content. The `home-affecting-grant-is-load-bearing` check exists to keep that fixture
honest.

This is [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)'s posture applied to content:
the user's voice is typed and lives in the home. Classification would move that judgement into the
contract, where it has no information to make it with.

## What would reopen this

- **Classification:** a standard nixpkgs `meta` field distinguishing graphical packages, or a
  home-manager module classification. Both are upstream changes; neither is this contract's to make.
- **Pruning:** a fleet where the residue is no longer negligible. The residue scales with the number
  of *published wrappers*, not homes — so it takes a contract with several home axes (a large
  powerset per user) before ~14 KiB per redundant bake amounts to anything. If a second `needsOwnHome`
  feature ever lands, re-measure before assuming this verdict still holds.

Note that neither reopening changes the *structural* argument: pruning always pays the evaluation it
prunes. Only the size of what it recovers can change.

## Appendix — measurements (2026-08-18)

Classification measured against nixpkgs `753cc8a3` (26.11) and home-manager `165228b0`, every eval
run with `--offline --max-jobs 0 --option allow-import-from-derivation false`, so a build or IFD
would have hard-failed rather than silently succeeded. Pruning measured against `examples/users` on
x86_64-linux, Nix 2.34.8, fully offline. **These numbers are dated and pinned; the arguments above do
not depend on them.**

**Which homes actually coincide** — `activationPackage.drvPath`, base vs gui:

| user | base ≡ gui |
| --- | --- |
| ada, admin, ben, cleo, **duo-b**, svc | identical |
| duo-a | differs |

**6 of 7, not the 5 the issue estimated.** `duo-b` is redundant too: its only graphical line is
`contract.requests.gui.desktop = "cosmic"`, which is a *request* — manifest data that rides the bind
— rather than home content. Only `duo-a` branches on `hostFacts`.

**What the redundancy costs:**

| quantity | value |
| --- | --- |
| store paths saved by pruning 6 of 14 packages | 6 paths, 81,304 bytes (**0.013%** of the published closure) |
| build time saved | ~4 s total (~0.7 s per wrapper `runCommand`, sandbox setup dominating) |
| `nix flake check examples/users`, x86_64 row | ~180 s, essentially all evaluation |
| share attributable to the 6 redundant bakes | ~14 s (**~8%**) — **unrecoverable**, since the predicate forces the evaluation |
| per-package closure delta (`nix store diff-closures`, ada base vs gui) | empty — nothing added, removed or resized |

The `activate` file inside each package is hardlinked across outputs, so it is counted once on disk.
