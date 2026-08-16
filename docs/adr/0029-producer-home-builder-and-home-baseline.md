# The contract ships the producer home builder: `mkContractHome` composes the home, the baseline is pinned hygiene

**Status:** Accepted (2026-08-16). Extends [ADR-0026](0026-consumer-producer-public-surface.md) (the
public surface grows by the front door) and the [ADR-0004](0004-extract-contract-flake.md) amendment
(the home-manager rule is about *building* homes, satisfied here by injection — the `buildHome`
precedent from the check kit, issue #35). Executes wayfinder tickets #40 (the builder shape) and #42
(who owns universal home hygiene).

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
