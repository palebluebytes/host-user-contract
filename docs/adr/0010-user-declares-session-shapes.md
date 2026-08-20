# A user declares the session shapes they run in

**Status:** Accepted (2026-08-20). The user-side half of [0007](0007-two-registries.md); the
whole user-facing surface.

```nix
# users/ada/user.nix
{
  contract.cli.enable = true;
  contract.gui = {
    enable        = true;
    configuration = ./home.nix;
    desktop       = "plasma";
  };
}
```

That is the entirety of what a user says: **which session shapes they run in, and for each one the
home to build and that shape's own parameters.**

## The schema is a projection, not a hand-written option set

`contract-user.nix` maps over the mode registry. A contract that gains a mode gains its declaration
with no edit, and a user naming a mode the contract does not have is an eval error **in the user's
own repo, at the moment they write it** — rather than a user nothing can bind, discovered later by a
host operator.

There is **no freeform**. The one freeform the contract ever had was justified by forward
compatibility — *"a request for a feature this contract version lacks never breaks the build"* — and
that rationale went stale when the host stopped evaluating a user's Nix
([0011](0011-prebuilt-binding-mode.md)). Version skew is handled at the data layer by the manifest's
explicit version, so the freeform's only remaining effect was hiding typos in the user's own repo:
`desktp = "plasma"` silently accepted, yielding a wrong desktop with no error. **The schema is the
typo-net, everywhere.**

## It is not a home-manager module

The declaration is evaluated by bare `evalModules` with no home-manager present. That is what lets
the producer read a user's modes without building anything, and lets a greeter learn them from a
plain `nix eval` over the published index. The home-manager content lives behind `configuration`,
a `deferredModule`, so reading the declaration never forces it.

## A user says nothing about their powers

The user side carries no ask. There is no `wants`, no `offer`, no negotiated intersection — which
also deletes the machinery that reconciled them.

**Which groups an account lands in is the host's decision alone.** A user-side veto would be a
second authority over the same value with nothing forcing the two to agree, and that is a defect
rather than a safeguard: a host that afforded `sudo` has decided.

The refusal a user genuinely needs is *"never give me a desktop"*, and it is already expressible
here by not enabling the mode. That is the whole of the user-side veto, and it needs no veto
mechanism: a seat running the gui mode for everybody still binds a terminal-only user to a terminal
session, because selection can only choose among the modes a user actually runs in.

## `enable` has no default, deliberately

A user that says nothing enables nothing, and the bake refuses that by name. A default satisfying
*"at least one mode"* would decide what a user **is** by inheritance, without the user having said
anything. The teaching convention is that an ordinary person declares both modes; nothing writes it
for them.

## The home is per mode, and that is why modes exist

A sway config cannot be injected into a home built for a terminal, so the graphical home and the
terminal home are different derivations. Two modes may name the **same** file — the common case,
where a home does not depend on the session — and a user with genuinely mode-specific content points
them at different ones.

The content idiom follows: content that works in every mode is written **unconditionally**; a mode's
own content lives in the module that mode names. There is no per-mode conditional anywhere, because
a module that belongs in both homes is imported by both and one that belongs in one is named by one.

## Considered alternatives

- **Keep a user-side ask (`wants`) intersected with the host's affordances** — rejected: it gave one
  value two authorities, put per-user policy in the producer's repo, and required a bake-time
  invariance guard to stop the published ask depending on which home happened to evaluate first.
- **A default of "every mode"**, on fail-open reasoning — rejected: with no default, omission is a
  **named error**, so the silent under-declaration fail-open guards against cannot occur.
- **One home for all modes, with the contract selecting content** — impossible: content cannot be
  injected into a sealed derivation, which is the fact modes exist to express.
