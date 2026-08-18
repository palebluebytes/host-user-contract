# The user's voice is typed and lives in the home: `contract.wants`, a narrowed `hostFacts.granted`, no freeform

**Status:** Accepted (2026-08-15). Extends [ADR-0025](0025-turnkey-host-side-bind.md) (the offer is half of the negotiated grant) and [ADR-0026](0026-consumer-producer-public-surface.md) (the producer/consumer coin). **Supersedes the ignore-overreach half of [ADR-0002](0002-user-confinement-manifest-greeter.md)** — the "an unknown request key is *ignored*" posture and the freeform that implemented it — and **amends [ADR-0025](0025-turnkey-host-side-bind.md)'s** "the contract owns no `home` flag; the producer's baked variant set is the taxonomy". **Half superseded by [ADR-0032](0032-grants-ride-the-bind-modes-build-homes.md) (2026-08-18)**: the typed-voice half stands entire, but the narrowed `hostFacts.granted` is gone — grants no longer reach home content at all, so there is nothing left to narrow; a home now sees only the MODE it was built for.

> **Terminology note (2026-08-17, [ADR-0030](0030-one-name-per-value-on-the-producer-surface.md)):** this record says **variant**; the code and `CONTEXT.md` now say **home**. The decision below is unchanged — only the vocabulary moved. This ADR is left as written.


A user's voice was split across two repos. Its home emitted `contract.requests` (the *parameters* of a feature), but its `offer` (*which* features it asks for — the half the grant is actually derived from, `affordances ∩ offer`) was declared in the **producer's** `flake.nix`, outside the home entirely. A user could not be read as one thing, and the roster carried per-user policy that belonged to the user.

Three edits close that, and they are one decision: **a user declares what it wants in its own home, typed, and can only see what it may vary on.**

## Decision

### 1. `contract.wants` — the user's feature selection, in the home

A new typed option in the home umbrella ([`modules.nix`](../../modules.nix)'s `homeModule`): a submodule over `grantedOptions` with **no freeform**, defaulting to the **safe set**.

```nix
# a user's home.nix
contract.wants = { sudo.enable = true; containers.enable = true; };  # gui rides the safe-set default
```

- **The shape mirrors `grantedOptions` exactly** — it is *derived* from it, so the two cannot drift. The grant algebra is written against `.enable` (`grantedNames`, `grantLib`), so bare booleans would need a normalising shim at exactly the seam this removes. One shape spans `wants` / `affordances` / `granted` / `offer`.
- **It defaults to `safeSet`, not to a hardcoded `gui`.** The safe set is the runtime-eligible (no-privileged-group) features, `{gui}` today. So *non-privileged features are wanted by default; privileged ones must be asked for* — [ADR-0002](0002-user-confinement-manifest-greeter.md)'s "one mechanism, opposite defaults" read from the user's side, and a future non-privileged feature inherits it with no new special case. The default is per-**feature**, not a whole-submodule default (which any definition would replace), so asking for `sudo` does not silently drop the desktop. A user wanting no desktop writes `contract.wants.gui.enable = false`.
- **`mkContractUser` harvests it**, publishing `contract.wants` off the evaluated home as the binding index's `offer`; the `offer` **argument is gone**. Consumers are untouched: `bindContractUser` still reads `offer` off the index, now harvested rather than passed.
- **Offers must be variant-invariant.** The grant is *derived from* the offer, so a want that depends on `hostFacts.granted` is circular — the harvest would differ per variant and the published offer would be whichever variant happened to be first. `mkContractUser` compares the harvest across a user's variants and fails the **bake** with a named error.

### 2. `hostFacts.granted` is narrowed to home-affecting features

The registry gains a per-feature `homeAffecting` flag, and the contract exposes the derived name list as a **public data surface** beside `safeSet`/`featureGroups`. Today only `gui` carries it: `sudo`/`containers`/`virtualization`/`nix-daemon` are pure privileged-group grants that never touch home content.

It is **declared, not derived from the group lists**. "Does this grant reach home content?" is a property of the feature, not a corollary of which groups it confers: a privileged feature could one day ship home content, and a group-conferring one need not. Deriving it from today's coincidence (`gui` is the only feature with both non-privileged groups and request params) would be a false invariant.

One surface serves two producer jobs, so neither is re-implemented per repo:

- the producer **narrows `hostFacts.granted`** with it — a home reading `granted.sudo` then structurally gets `false` forever, so it is *impossible* for a home to become grant-sensitive on a feature nothing bakes for; and
- the producer derives **`variants = powerset(homeAffecting)`** from it, rather than each repo re-asserting the rule in prose. ([ADR-0025](0025-turnkey-host-side-bind.md) left home-affecting-ness per-repo and the baked set as the taxonomy; that made every producer's variant comment a human claim that goes stale the day someone adds a `granted` read. The producer still chooses to bake fewer — the reference roster's homes read no grant at all, so a single `base` variant serves them — but the *upper bound* is now the contract's data.)

The producer hand-builds the `hostFacts` literal (there is no host `config` at bake time — [ADR-0027](0027-runtime-provision-evaluates-the-shared-rule.md) retired `mkHostFacts` for exactly that reason), so a data surface is the only place this rule can live once and be read by everyone.

### 3. `contract.requests` loses its `freeformType`

There was exactly one freeform in the contract, and its documented rationale was greeter forward-compat — "a request for a feature this contract version lacks never breaks the build."

**That rationale is stale.** It was written for the inline-eval bind path, where the *host* evaluated a roaming user's home against the *host's* contract. [ADR-0026](0026-consumer-producer-public-surface.md) deleted that path; the bind is pre-built only. Version skew is now handled at the **data layer**: `bridgeRequests` folds over the **host's** granted feature names and picks from the manifest, so an unknown key is ignored *by construction* — no type involved — and [`manifest.nix`](../../manifest.nix) carries an explicit `version`.

So the freeform's only remaining effect was hiding typos in the user's own repo, evaluated against the user's own pinned contract: `contract.requests.gui.desktp = "plasma"` was silently accepted and yielded the seat default — a wrong desktop with no error. [ADR-0002](0002-user-confinement-manifest-greeter.md)'s enforcement pair becomes **validate-intent only**: a malformed known request, a misspelled param, and an unknown feature key all error. The schema is the typo-net, everywhere.

**`traceUser` stays tolerant.** It still co-evaluates the host's umbrella with a roaming user's home module, so it is the one place cross-revision skew is real. It gains a `permissive` eval mode that re-declares the two voice namespaces with a freeform type (option declarations merge, and submodule types merge by unioning their modules, so every *known* key keeps its type) and reports what it did not recognise as **data** — `unknown = { requests; wants; }`. An inspector exists to answer "what does this home ask for?"; dying on that question turns a diagnosis into a dead end. Tolerance is confined to the inspector; the bind path is fully typed.

## Consequences

- **A user is readable as one thing.** Identity, home, requests, and now the offer live in `users/<u>/`; the roster carries only what the producer decides (which variants to bake). This is what unblocks the `users` repo's flake-mapper refactor — it can derive variants and harvest offers instead of hand-maintaining both.
- **Breaking for producers.** The `offer` argument to `mkContractUser`/`mkContractUsers` is gone; every roster entry moves its offer into the user's `home.nix` (or drops it, where the safe-set default already says it). Migrated in lockstep across the conformance fixtures and both reference fleets — no back-compat shim, the contract is pre-1.0.
- **The default is a policy change, not just a spelling.** A user that declared no offer now offers the safe set. In the reference roster `ada`/`ben` ride the default, `cleo`/`admin` ask for their privileged features explicitly, and `svc` — an account that must never get a desktop, on any host — opts out with `gui.enable = false`. An account that must not be gui-capable now says so, rather than being gui-incapable by omission. That opt-out is the **user side of the veto**: the host's affordance is not the only way a feature can fail to be granted, and `svc` is the roster's worked example of a user refusing what a host would happily afford.
- **A typo in a user's own repo is loud.** Homes pinned to an older contract that carried a stray key stop evaluating — which is the point, but it is a real migration cost for a repo that had one.
- **The clamp and the veto are untouched.** `wants` is still only an *ask*: the host's affordance remains the absolute veto, the grant is still `affordances ∩ offer`, and a user still cannot grant itself anything. Moving the ask into the home changes who *writes* it, never who *decides*.

## Considered Options

- **Keep `offer` in the roster, add `wants` as a second spelling.** Rejected: two places to declare one thing is the split this closes, and they would drift.
- **Bare booleans for `wants` (`contract.wants.sudo = true`).** Rejected: the grant algebra reads `.enable`, so this needs a normalising shim at the harvest — a seam this decision exists to remove.
- **Default `wants` to `{}` (nothing) or to a hardcoded `gui`.** Rejected. `{}` makes every user restate the desktop and gives the safe set no meaning on the user's side; a hardcoded `gui` is the same value with none of the reason, and a second non-privileged feature would need a new special case.
- **Derive `homeAffecting` from the registry's group/config fields.** Rejected: it happens to select `gui` today, but it encodes "confers a non-privileged group" as "reaches home content", which is not the same property.
- **Keep the freeform and lint for typos.** Rejected: a post-hoc lint over a merged evaluation is exactly the approximate backstop [ADR-0002](0002-user-confinement-manifest-greeter.md) already rejected as a boundary. The type is the check.
- **Make `traceUser` strict too, and let callers `tryEval`.** Rejected: `tryEval` yields a boolean, not the skew report a diagnosis needs — "which features does this home want that I don't know?" is the answer the inspector exists to produce.
