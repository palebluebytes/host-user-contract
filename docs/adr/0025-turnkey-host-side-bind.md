# Turnkey host-side bind: `affordances ∩ offer`, variant selection from the baked set

**Status:** Accepted (2026-08-05). Extends [ADR-0016](0016-prebuilt-binding-mode.md) (the pre-built binding mode), [ADR-0020](0020-multi-user-repo-shape.md) (the multi-user `users` repo), and [ADR-0007](0007-user-flake-shape.md) (the user-flake shape). **Amends [ADR-0016](0016-prebuilt-binding-mode.md)**: its grant/variant coupling guard, documented but never enforced, is implemented here as a subset check. **Amends [ADR-0021](0021-contract-display-server-agnostic.md)**: the XDG portal/desktop path-linking a gui seat needs folds into the contract's gui realization (display-server-agnostic, so it stays inside 0021's boundary). Reframes [ADR-0001](0001-host-user-contract.md)'s grant model for the turnkey path (see *The grant becomes a negotiation*). **Amended by [ADR-0026](0026-consumer-producer-public-surface.md)**: `mkUserBindings`→`mkContractUsers` (plus the extracted singular partner `mkContractUser`) and `bindUserFromFlake`→`bindContractUser`; `bindContractPackage`/`mkContractPackage`/`mkContractPackageForHome` become internal kernels, making the negotiated `affordances ∩ offer` the *only* public grant path. **Amended by [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md)**: the `offer` is **harvested** from the home's typed `contract.wants` (the `offer` argument is gone), and home-affecting-ness — left per-repo here, with "the producer's baked variant set is the taxonomy" — becomes contract data (`homeAffecting`), bounding the baked set at `powerset(homeAffecting)` and narrowing `hostFacts.granted` to it.

> **Terminology note (2026-08-17, [ADR-0030](0030-one-name-per-value-on-the-producer-surface.md)):** this record says **variant**; the code and `CONTEXT.md` now say **home**. The decision below is unchanged — only the vocabulary moved. This ADR is left as written.


The contract shipped the low-level pre-built primitive — `bindContractPackage { contractPackage; identity; grants }` ([ADR-0016](0016-prebuilt-binding-mode.md)) — and, on the producer side, `mkContractPackageForHome` ([ADR-0020](0020-multi-user-repo-shape.md), issue #23). But every host that consumes an [ADR-0020](0020-multi-user-repo-shape.md) `users` flake hand-rolls the *same* wrapper around the primitive, and that wrapper hardcodes the users repo's internal conventions into the consumer two ways:

1. **Variant selection** — `inputs.users.packages.${sys}.<user>-contractPackage-<variant>`: the consumer must know the variant-naming scheme and pick the right output.
2. **Identity path** — `loadIdentity "${inputs.users}/users/<user>/identity.json"`: the consumer must know the [ADR-0020](0020-multi-user-repo-shape.md) on-disk layout.

If the users repo renames a variant or reshapes its layout, every consumer silently breaks. This is the symmetric consumer-side twin of issue #23: a turnkey adapter every consumer reinvents. It also left a deeper question unanswered — *how should a host express what it grants each of many users without hand-writing a per-user grant matrix?*

## The two things that had to be untangled first

**A variant is a baked home, identified by the grant set it was baked with.** `mkContractPackage` freezes a home's `activationPackage` at bake time; a grant applied at bind time can no longer change what packages the home contains. So a grant that *changes the baked home* (a gui grant a user's `home.nix` fans out on — emacs, ai) **must** be baked into a distinct variant, while a grant that only confers host-side effects (a privileged group — `sudo`, `containers`) needs no distinct bake and can vary freely at bind time. The first kind is **home-affecting**; the second is not.

**Home-affecting-ness is per-repo, not a global contract fact.** Whether `gui` is home-affecting depends on whether *that repo's* `home.nix` branches on it. The reference fleet (`examples/users`) had trivial homes that did not branch, so it baked **one** grant-less package per user (`<user>-contractPackage`) and applied every grant at bind time. A real fleet whose homes fan out on gui bakes a `gui` variant. *(Amended in place 2026-08-16, issue #55 — both halves of that reference-fleet aside are now false: [ADR-0028](0028-user-voice-is-typed-and-lives-in-the-home.md) made the baked set contract data, so the fleet bakes `base` + `gui` per user per system, and `duo-a` branches on the grant for real — its `gui` bake differs from its `base` one in realized home content, pinned by the fleet's `home-affecting-grant-is-load-bearing` check. What survives is the sentence's point: whether a given repo's homes branch stays that repo's own affair.)* Same feature, home-affecting in one repo and not the other. Therefore the contract cannot own a `home = true` flag in its registry — the ground truth is simply *which variants the producer chose to bake*. That baked set **is** the taxonomy; there is nothing separate to declare.

## Decision

Add a turnkey **host-side bind** to the contract, and the **producer helper** the `users` flake uses to feed it. The host owns only its affordances and genuine host policy; the users flake owns its variants and each user's offer; the contract owns the mechanics that marry them.

### The grant becomes a negotiation: `grant = affordances ∩ offer`

Split the two voices that [ADR-0001](0001-host-user-contract.md) fused into a single host-written grant:

- **`contract.affordances`** — the **host's** voice (system-side), a new contract-module option shaped `{ <feature>.enable = bool; }`. The set of features this host is willing to grant to users who ask for them. Declared **once** per host. It is the symmetric counterpart of `contract.requests` (the user's home-side voice) and generalises the greeter's "default-open over the safe set" — the safe set is simply the greeter's affordance.
- **offer** — the **user's** voice, formalised per-user in the `users` flake (the "formal `offers` field" [ADR-0002](0002-user-confinement-manifest-greeter.md)/CONTEXT anticipated "until the separate-repo future needs one" — this is that future). The home-affecting subset of a user's offer is what the producer bakes as variants.
- **grant** = `affordances ∩ offer`, computed per user at bind time. The realization still consumes `custom.users.<u>.granted` and privilege still flows **only** from a grant — but in the turnkey path that grant is *derived*, a two-sided agreement, rather than enumerated by the host per user.

This preserves the spine of the threat model and stays truer to "the contract is the negotiated interface between them — neither host nor user":

- **The host keeps an absolute veto.** A feature the host does not afford is never granted to anyone, whatever they offer. Affordance is a *necessary* condition.
- **A user cannot escalate beyond the host's affordances.** Within them, the offer — authored in the operator-owned, co-trusted `users` monorepo ([ADR-0020](0020-multi-user-repo-shape.md): one repo = one trust domain) — completes the grant.
- **The untrusted/greeter path is unaffected.** It affords only the safe set, which excludes every privileged feature by construction, so a stranger's offer can never intersect into privilege — exactly today's guarantee.
- **The clamp stays as defense-in-depth.** Any privileged group not backed by the derived grant is still dropped from `identity.extraGroups`.

The direct path (`bindContractPackage { grants }`, a host writing `custom.users.<u>.granted` verbatim) is retained unchanged for inline/hard-enforcement deployments. `affordances ∩ offer` is the turnkey *derivation* of the grant, not a replacement for the ability to write it.

### Variant selection: maximal baked subset

`bindUserFromFlake` selects the **maximal baked variant whose grant-key is a subset of the derived grant**. `sudo`/`containers` don't multiply variants; they ride the bind. No unique maximum (two incomparable baked variants both ⊆ the grant, the combo never baked) is a **hard error** listing the available variants — never a silent fallback.

### The coupling guard, finally enforced

[ADR-0016](0016-prebuilt-binding-mode.md) required "the grant baked into the home MUST match the grant the host passes", and `mkContractPackage` bakes `manifest.granted` for it — but nothing ever read it. `bindContractPackage` now asserts **`manifest.granted ⊆ grantedNamesOf grants`**: you may only bind a variant whose baked grants you actually granted (so you can never activate a variant baked with a secret-bearing/home-affecting grant you are not conferring). Maximal-subset selection satisfies the assert by construction; the check is defense-in-depth for direct callers.

### The two new surfaces

- **`mkUserBindings`** (producer, contract `lib`) — the `users` flake calls it once. It maps over each user's declared variants and emits **both** the named packages (`<user>-contractPackage-<name>`, name = the home-affecting grant-key serialised canonically — sorted feature names, empty ⇒ `base`; cosmetic, a label only) **and** a pure `contractUsers.<sys>.<user>` **binding index** — `{ identity; offer; variants = [{ granted; package }] }` — with identity resolved once from the [ADR-0020](0020-multi-user-repo-shape.md) path. The index is plain data (`builtins.toFile`-free, no IFD): selection reads it without building any variant.
- **`bindUserFromFlake`** (consumer, contract `lib`) — `{ usersFlake; username }`, **no `grants` argument**. Returns a NixOS module that infers `system` from the host `pkgs`, reads `config.contract.affordances` and the user's binding index, computes `grant = affordances ∩ offer`, runs maximal-subset selection, and delegates to `bindContractPackage` with the derived grant and the index-supplied identity. The host holds **zero** users-repo internals.

### XDG fold

The residual gui host-glue a seat hand-writes — `environment.pathsToLink = [ "/share/xdg-desktop-portal" "/share/applications" ]` — moves into the contract's gui realization, set when the gui surface is enabled. It names no display server or DE, so it is a display-server-agnostic gui host-effect and stays inside [ADR-0021](0021-contract-display-server-agnostic.md)'s boundary. `shell` remains host/account policy (it is not in `identity.json`).

## Consequences

- **A host declares its affordances once and imports users with a single function.** `contract.affordances = { … }` then `bindUserFromFlake { usersFlake; username }` per user — no per-user grant matrix, no variant names, no identity paths. Per-user differentiation lives where it belongs: the affordances (host policy) and each user's offer (the trusted users flake).
- **The baked home is a function of the granted feature *set* only — never request *values*.** `gui.desktop = "sway"` vs `"gnome"` does not fork a variant (the home is desktop-agnostic, [ADR-0013](0013-per-user-desktop-choice-host-offered.md)/[ADR-0021](0021-contract-display-server-agnostic.md)); only grant *enablement* of home-affecting features does. Homes branch only on features the producer chose to bake; privilege grants never rebake a home.
- **The latent [ADR-0016](0016-prebuilt-binding-mode.md) guard is now real** — `manifest.granted` stops being dead metadata and becomes an enforced subset check.
- **The grant model gains a second, negotiated derivation.** `custom.users.<u>.granted` remains the realization's sole privilege input; the turnkey path derives it as `affordances ∩ offer`. The CONTEXT `grant`/`clamp` entries are updated to state privilege as host-affordance ∧ user-offer, both necessary, with the host's veto and the safe-set guarantee intact.
- **Selection needs no manifest introspection.** The binding index is pure data, so picking a variant never builds every variant (the [ADR-0016](0016-prebuilt-binding-mode.md) "can't read baked manifests cheaply" trap is sidestepped by construction).
- **Downstream adoption.** `examples/users` adopts `mkUserBindings`; a reference host binds via `bindUserFromFlake`. The external `~/code/nixos` fleet drops its `bindInkpotmonkey*` stopgaps when it next updates its `contract` pin.

## Considered Options

- **Contract-owned variant-naming convention with a registry `home` flag** — rejected: home-affecting-ness is per-repo (a `gui.home = true` flag would be a lie in the reference fleet, whose gui is bind-time), and it would force the contract to absorb a per-repo home-fanout taxonomy it deliberately does not own ([ADR-0021](0021-contract-display-server-agnostic.md)).
- **Full-grant-set variant identity** — rejected: `gui+sudo`, `gui+containers`, … would each be distinct variants, exploding the baked set combinatorially. Home-affecting-subset identity keeps the count sane and matches why the guard exists.
- **Name-parse selection** (enumerate `packages` attrs, parse the suffix back into a grant set) — rejected: makes the serialised name load-bearing for correctness; the binding index is the honest data structure and demotes the name to a label.
- **Host passes an explicit per-user `grants`** (the issue's own framing) — rejected as the *default*: it makes the host hand-write a grant matrix per user, the opposite of the north star. Retained only as the direct `bindContractPackage` path for hard-enforcement.
- **`affordances ∩ offer` for the safe set only; privileged grants stay explicit per-user** — considered and rejected in favour of the uniform negotiation: under [ADR-0020](0020-multi-user-repo-shape.md)'s trust model plus the safe-set guarantee, the uniform rule is safe, and it delivers the one-function golden path for privileged features too. (Reversible — see below.)

## If the negotiation should narrow again

Reversible by a new ADR: restrict `affordances ∩ offer` to the safe set and require explicit per-user grants for privileged features, or drop affordances entirely and return to host-written `grants`. Nothing here is load-bearing beyond `contract.affordances`, the binding index shape, and the two helper functions; `bindContractPackage` and the direct grant path are unchanged underneath.
