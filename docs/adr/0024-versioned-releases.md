# The contract has one version; compatibility is by major release

**Status:** Accepted (2026-08-21). It records a commitment to *consumers* — that this repo publishes
a changelogged, tagged surface — and settles what a version means here: there is exactly **one**, it
is what release-please computes from commit types, and it is also what a manifest declares and what
a bind refuses a mismatch on.

## The problem a release version solves here

A flake consumer already gets byte-exact reproducibility from `flake.lock`. The lock pins a revision
hash whether or not a tag ever exists, so a semver tag buys **nothing mechanically**. What it buys
is legible intent, and the repo had no way to express it: `nix flake update` either kept working or
did not, and the only account of why was `git log`.

That gap is not hypothetical. [0014](0014-producer-surface.md) and [0015](0015-consumer-surface.md)
landed as a breaking rewrite of the producer and consumer surfaces, and every consumer pinned to
`main` — including this project's own reference fleets — took the break with no announcement
attached.

So the deliverable is the **CHANGELOG**, and the tag is a cheap by-product of producing one.

## The decision

Conventional Commits on `main` drive [release-please](https://github.com/googleapis/release-please),
which keeps a standing release PR carrying the computed bump and the generated changelog, and cuts
the tag and GitHub Release when that PR merges. Configuration is `release-please-config.json` +
`.release-please-manifest.json` at the root; the job is
[`.github/workflows/release-please.yml`](../../.github/workflows/release-please.yml). The version
itself lives in [`version.nix`](../../version.nix) — one annotated line release-please rewrites.

### The version's compatibility digit means "breaking", and nothing else

`bump-minor-pre-major` is on, so pre-1.0 a breaking change bumps the **minor** — the minor stands in
for the major until 1.0. `bump-patch-for-minor-pre-major` is **also** on, so an ordinary `feat:`
bumps the **patch**.

The second knob was rejected at first, on the grounds that rendering every feature as a patch
understates it. That reasoning was wrong once the version became load-bearing: the compatibility
digit has to mean *breaking* and nothing else, or a feature that breaks nothing would invalidate
every published package. **The version answers "can I still use this?"; the CHANGELOG answers "what
changed?"** Those are different questions and the changelog is the one that lists features.

So, concretely — pre-1.0: `fix:`/`feat:` → patch, `feat!:` → minor. From 1.0: `fix:` → patch,
`feat:` → minor, `feat!:` → major.

### One version, and why it also gates the manifest

The contract has **one** version: `version.nix`. A manifest declares it, and a bind refuses a
manifest that is not compatible with it. There is deliberately no second, narrower "wire format"
counter over the manifest's field set.

A field-set counter was built first and then removed, because it **gates the wrong thing**. The
producer↔consumer agreement is not four JSON fields — it is also what `activate` expects, what
`accountPlan` computes, which groups a mode confers, and how the realization reads an account. A
counter over the manifest's shape sees none of that, so a host several releases ahead of the producer
that baked a home passes the check while running realization code the home was never built against.

### Compatibility is by major version, so releases do not invalidate published packages

A manifest is accepted when it shares this contract's **compatibility line** — semver's caret rule,
the leftmost non-zero component:

| producer | consumer | line | |
| --- | --- | --- | --- |
| `1.2.0` | `1.9.3` | `1` | accepted |
| `1.9.3` | `2.0.0` | `1` vs `2` | refused |
| `0.3.1` | `0.3.9` | `0.3` | accepted |
| `0.3.9` | `0.4.0` | `0.3` vs `0.4` | refused |

**A package built by an older contract keeps working until a major release.** A fix, a feature or a
docs typo moves the patch and invalidates nothing — which is what makes it acceptable that *every*
conventional commit eventually cuts a release (`strategies/base.ts` skips only when there are no
conventional commits at all, and `hidden: true` suppresses a changelog section, not the bump).

An exact-match gate was implemented before this and rejected: it made every release, including a
docs typo, refuse every already-published package. It is only defensible if you never intend to keep
compatibility, and this contract does — up to a major release.

**The discipline this requires** is the flip side of the guarantee: **changing the manifest's field
set is a breaking change and must be committed as one** (`feat!:` or a `BREAKING CHANGE:` footer).
That is what moves the compatibility line and refuses the packages the change would otherwise
mis-read. Add a field quietly under `fix:` and old packages will be accepted by a reader that
expects it. `manifest.nix` says so at the point of the decision, and AGENTS.md says so where commits
are written.

The strictness is also nearly free in the topology this contract recommends: a host writes
`users.inputs.contract.follows = "contract"`, which overrides the users repo's own contract pin, so
the manifest is written and read by the *same* contract evaluation. `examples/fleet` does exactly
this.

### Release-please keeps the fixtures in step, and the check fails loudly if it does not

`conformance/contract-package.nix` byte-compares the two committed fixture manifests against
`writeManifest`'s output, to attest the fixtures are generated rather than hand-typed. Those
manifests must also carry the *live* version, or `readManifest` would refuse them and every bind
test would fail. So the version inside them has to move on every release.

`extra-files` therefore names three files, not one: `version.nix` via the generic updater, and both
fixture manifests via the `json` updater at `$.version`. All three move in the same release PR. The
fixtures stay byte-identical because release-please's `jsonStringify` detects the compact
formatting's empty indent and `JSON.parse`→`stringify` preserves Nix's sorted key order — verified
against the real updater's logic before adopting it.

If release-please ever fails to update one of them, the byte-equality assertion fails on `main`. That
is a loud, self-correcting failure — a red build and one regeneration command — rather than a silent
drift, which is why the attestation is worth keeping in this shape.

### There is no `stateVersion`, and that is a decision

NixOS and home-manager carry a version this repo does not: `system.stateVersion` /
`home.stateVersion`, which marks the generation of *stateful defaults* a deployment was created
under. It is set once at install and never moves on its own — genuinely a third thing, neither a
release number nor a compatibility gate.

The contract does not have one because it owns no stateful data.
[0023](0023-no-classification-of-home-content.md) already refuses to look inside a home, and
`mkContractHome` takes `stateVersion` and passes it straight to home-manager, which owns that
concept. Recorded because a NixOS-native reader will look for it, and "delegated" is an answer where
"absent" would look like an oversight.

### The README still pins `main`

Tags exist and can be pinned, but the recommended pin stays `main` + `flake.lock`. Under `0.x` with
breaking-as-minor, pinning a tag obliges a consumer to hand-bump on every feature as well as every
break, and this contract's known consumers are the same author's fleets. Revisit at 1.0.

## What was rejected

**Keeping the annotated line inside `flake.nix`.** Tried first, and it works right up until anything
other than the flake needs the value. `manifest.nix` does, and it cannot get there: a flake's outputs
are not an importable expression, and threading a second parameter through `kit.nix` is barred
because the greeter re-imports `kit.nix` at runtime with only `lib` in hand
([0020](0020-runtime-evaluates-the-kernels.md)) — a second parameter would break a seat at login. So
the version lives in a plain `version.nix` that both `flake.nix` and `manifest.nix` import. (`nixfmt`
was checked against the annotation: it round-trips unchanged, so the formatter and the bot do not
fight.) There is no `version.txt` — under manifest mode the source of truth is
`.release-please-manifest.json`.

**An exact-version gate.** Implemented before the compatibility rule, on the premise that this
contract owes nobody backward compatibility. It does — up to a major release — and an exact match
turns every routine release, a docs typo included, into a refusal of every published package. The
compatibility line keeps the broad gate while making the promise a consumer can actually plan
around.

**A separate manifest "wire format" version.** Built first, then removed. It looked right — a small
integer, moved by hand when the field set moves, unaffected by release churn — and it survives in
git history. It fails because it is *narrower than the agreement it guards*: it can only detect
changes to the fields it counts, so it silently permits exactly the mismatch that matters most, a
host and a producer on different contract revisions whose manifests happen to have the same shape.
Two versions also cost two explanations everywhere — in this record, in `CONTEXT.md`, in
`manifest.nix`'s header — and the amount of prose needed to keep them apart was itself the argument
against them.

**An advisory release-drift warning** (after home-manager's `home.enableNixpkgsReleaseCheck`), built
alongside the two-version design and removed with it. Once the release version *is* the gate, a
warning about release drift can only fire where the assert has already passed — which is nowhere.

**Stamping the version into `diagnostics.nix`.** That module owns what the contract says when it
*refuses* ([its whole point](../../diagnostics.nix) is that a refusal reads the same way every
time), and `check-kit.nix` asserts against those strings. A version in an error message would be
noise in the one place the reader has already lost, and churn in the assertions.

**Versioning `examples/users` and `examples/fleet` separately.** They are separate flakes, so the
tooling could. But [0022](0022-oracle-and-reference-fleets.md) frames them as oracles for the
contract, not independently consumable products, and giving them version numbers would imply a
consumer contract they do not offer. One version, root only.

**Running the CI matrix on the release PR.** The PR is opened with the default `GITHUB_TOKEN`, which
by design does not trigger other workflows, and a personal access token would be needed to change
that. It is not worth one: the matrix boots NixOS VMs and needs KVM, the release PR edits only
`CHANGELOG.md`, the `flake.nix` version line and the manifest JSON — files no check reads — and the
commits underneath already went green on `main`.

**Calendar versioning (`26.11`), to match the ecosystem.** nixpkgs (`.version`) and home-manager
(`release.json`) both do it, and home-manager has *no git tags at all* — consumers pin the
`release-25.11` **branch**. Tempting for idiom, but calendar versions say nothing about breakage,
which is this record's entire purpose. That scheme works for nixpkgs because it comes with a fixed
six-month cadence, release branches and staffed backports; adopting the notation without the
machinery would copy the one part that does not function alone. Release branches are out for the
same reason: `release-0.x` means nothing unless somebody backports into it.

**Starting at `1.0.0`.** Defensible on maturity grounds — 23 prior records and a conformance oracle
is not a `0.x` posture — but the producer and consumer surfaces are still moving, and claiming
stability the repo is not yet holding itself to is the worse error.
