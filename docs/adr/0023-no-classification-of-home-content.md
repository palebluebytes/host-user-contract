# Negative result: the contract does not classify home content

**Status:** Accepted (2026-08-20). Records a **negative result** — it changes no code and adds no
surface. It exists so the question is not re-proposed without new evidence, and it is why
[0010](0010-user-declares-session-shapes.md) has a user *say* which session shapes they run in.

The question, raised naturally while looking at the user declaration:

> *is there a way to automatically tell which programs and settings belong to a graphical setup and
> which can run in just a shell?*

If the contract could derive it, a user would not have to declare anything — the modes a home
supports would fall out of its content.

**It cannot, and the route is closed rather than merely unbuilt.**

## Four mechanisms; three are structurally shut and the fourth answers a different question

### 1. There is no package metadata to read

nixpkgs' allowed metadata carries no `isGui`, `graphical`, `desktop` or `category`. Its only such
booleans are three ecosystem-specific ones. `firefox` and `ripgrep` are **structurally
indistinguishable**: identical key sets, both naming a main program, both listing the same
platforms. The only difference is free-text description.

A desktop-entry attribute is not a fallback either — it is present on some graphical packages and
absent on plenty of others, including obvious ones.

Adding such a field is a nixpkgs-wide change with tens of thousands of call sites and no owner. It
is not a mechanism this contract can reach.

### 2. Inspecting built output is IFD **by construction**

This is stronger than *"the package is not built yet"*. The mechanism is **string context**: a path
interpolating a derivation carries a reference, and any path-reading builtin must realise that
context first. Checking for a desktop file fails with IFD disabled **even when the package is
already in the store** — the manual is explicit that this holds even when the store object is
readily available. IFD is banned ([0011](0011-prebuilt-binding-mode.md)).

Discarding the string context is a trap rather than an escape hatch: it answers `false` for any
unbuilt package, making the result a function of **local store state**. The same flake would
classify a person terminal-only on a cold machine and graphical on a warm one — non-deterministic
across hosts and across time, which is precisely what the pre-built binding mode exists to prevent.

### 3. The namespace heuristic is a curated catalog, and it does not even work

home-manager carries no module classification to borrow, and directory layout is not a proxy — its
program modules mix terminal emulators and browsers with shells and search tools.

That leaves inferring from the option namespaces a home *sets*. Measured across five homes differing
by exactly one enabled program, **every signal was false for all five**: a terminal emulator, a
browser and a media player were indistinguishable from a search tool **and from an empty home**.

The reason is categorical rather than incidental. Those namespaces are opt-in **session-management**
options. They mean *"this home configures a graphical session"*, not *"this home contains graphical
software"* — and a home installing a browser while letting the desktop handle theming sets none of
them. False positives run the other way too: an empty home already pulls mime-info packages in
unconditionally.

Making it work would mean hand-classifying several hundred leaf namespaces, churning on every
home-manager bump. That is a **curated catalog** — the model this contract rejected at its
foundation ([0001](0001-host-user-contract.md)), whose losing argument is unchanged and now has a
number attached: it must be maintained forever, and it is wrong the moment a user reaches for an
option it does not know.

### 4. Evaluating twice and diffing answers a different question

Comparing two evaluations' derivation paths is sound and IFD-free, and it is genuinely informative:
a home that ignores its inputs yields an identical path, and because derivation hashing is recursive
a difference anywhere in the closure propagates to the top.

But it answers *"did anything change"*, never *"is this graphical"*. A branch differing only in a
shell alias reads as affected. This mechanism cannot classify.

## Decision

**The contract does not classify home content.** No metadata read, no output inspection, no
namespace heuristic, no committed catalog. Whether a home is graphical is something the home
**says**, not something the contract infers.

## What a user does instead

Exactly what [0010](0010-user-declares-session-shapes.md) describes: enable the modes they run in,
and point each at the home for that shape. The escape hatch the original question asked for is the
*only* mechanism, and it is also the primary one.

## What would reopen this

A standard nixpkgs metadata field distinguishing graphical packages, or a home-manager module
classification. **Both are upstream changes; neither is this contract's to make.**

Note that neither reopening changes the structural argument about mechanism 2: reading a built output
is IFD by construction, whatever else improves.
