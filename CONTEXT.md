# CONTEXT

The domain glossary for the **host↔user contract** — the shared interface a NixOS fleet's
hosts and users agree on, so any host can enable any user (and deny features a user
introduces) on rebuild. It is neither host nor user: it is the negotiated interface between
them, and it depends on nothing but nixpkgs `lib`.

This file is the vocabulary. When an issue, a hypothesis, a test name, or an ADR names a
domain concept, use the term as defined here and avoid the synonyms called out under
[Terms to keep distinct](#terms-to-keep-distinct). The full rationale for each decision
lives in [`docs/adr/`](docs/adr/); this is the index of *language*, not decisions.

Entries marked **(designed; not yet built)** name a decided-but-unimplemented concept —
the term is stable, the code is pending (see the cited issue).

## The boundary

- **the contract** — the shared schema + host-invariant realization + derivation logic both
  sides agree on. Ships as `nixosModules.default` / `homeModules.default` (the umbrella),
  `lib` (the functions), and a data surface (`features`, `featureGroups`,
  `privilegedGroups`, `safeSet`, [[homeAffecting]]). Neither host nor user. (ADR-0001, ADR-0004)
- **host** — a machine config that imports the contract, materializes user accounts,
  **grants** features, and supplies **bindings**. Sovereign: it runs only what it grants.
- **user** — a public identity + home config + the features it *offers*; host-agnostic (it
  never names a host's `self`/inputs). Its own home secrets (if any) ride its own key,
  provisioned by its own home module — never through the contract. Target shape: a
  home-manager config repo consumed via `bindContractUser` (ADR-0007/0025); today still in-repo in the consuming host repo.
- **umbrella / kit** — the assembled shipped surface (`kit.nix`). `nixosModules.default` =
  the `custom.users` schema + `custom.host.exposed` + [[affordance]]s + realization + the
  insecure-package aggregator. `nixosModules.greeter` = the opt-in reference runtime greeter (a seat
  host enables it). `homeModules.default` = identity + home profiles + the user's voice
  ([[wants]] + [[request]]).
- **mechanism vs binding** — the contract ships generic **mechanism**; the host supplies
  only **bindings** (the display/theme, *which* hosts, the trust-tier policy). The split
  keeps every fleet from re-implementing — and drifting on — the security-critical parts. (ADR-0008)

## Features and the registry

- **feature** — one entry in the registry: the unit of capability a host grants or denies,
  and the shared name "deny" keys on. Per-entry fields: `grant`, `groups`,
  `privilegedGroups`, `config`. (`features.nix`)
- **registry** — `features.nix`, the **single source of truth** for the feature vocabulary.
- **projection** — any surface *derived* from the registry (`featureGroups`,
  `grantedOptions`, `wantedOptions`, `featureConfigOptions`, `safeSet`, [[homeAffecting]]). Keys
  can't drift across projections because there is one set of keys. (`kit.nix`)
- **grantLib** — the grant-projection **helper set** computed once in the kit and *injected* into
  the realization and greeter modules and the derivation logic (`lib.nix`), the same way the
  [[projection]] data (`featureGroups`/`privilegedGroups`) is. It single-sources the three folds
  each grant-reading site would otherwise re-derive: `grantedNames` (the enabled feature names in a
  grant), `grantedGroups` (the grant→groups fold), and `safeDeclared` (the privileged-group
  [[clamp]]). One owner ⇒ the security-critical clamp cannot drift between eval sites. (`kit.nix`)
- **offer** — the **user's** voice on *which* features it asks for (distinct from [[request]],
  the parameters of a feature). *Implicit* for a home emitting a `contract.requests` entry until
  ADR-0025 formalised it per-user in the `users` flake; since ADR-0028 it is **declared in the
  user's own home** as [[wants]] and **harvested** into the [[binding index]] by
  [[mkContractUser]] — the producer passes no `offer`. A grant is derived as host [[affordance]] ∩
  offer; the home-affecting subset of the offer is what the producer bakes as [[variant]]s.
  (ADR-0002, ADR-0025, ADR-0028)
- **homeAffecting** — the contract's public name list of features whose grant may reach HOME
  content, so a home may legitimately fan out on them (`{gui}` today; the per-feature
  `homeAffecting` registry flag, **declared**, not derived from the group lists). It is the upper
  bound on what a home may even see: a producer NARROWS [[hostFacts]]`.granted` with it (so a home
  reading a bind-riding grant like `sudo` structurally gets `false` forever) and
  `powerset(homeAffecting)` bounds its baked set (the per-system subset it actually bakes is the
  consumer's fleet fact — see [[variant]]). One surface, so no producer re-implements the rule in prose.
  (ADR-0028; `lib.nix`)

## Grants and confinement

- **grant** — the decision to enable a feature for a user
  (`custom.users.<u>.granted.<f>.enable`); the realization's **only** source of privilege. On the
  public surface it arrives **one** way: **derived** as `affordances ∩ offer` by the turnkey
  `bindContractUser` (ADR-0025). The grant is thus a two-sided **negotiation** — host [[affordance]]
  ∧ user [[offer]], *both necessary* — never a unilateral host write (the direct-grant primitive
  `bindContractPackage { grants }` is now an internal kernel, not a consumer path; ADR-0026). It
  remains the sole privilege source the realization reads. (ADR-0001 mechanic 2, ADR-0025, ADR-0026)
- **affordance** / **`contract.affordances`** — the **host's** voice (system-side), shaped
  `{ <feature>.enable = bool; }`: the features this host is willing to grant to users who
  [[offer]] them, declared **once** per host. The symmetric counterpart of [[request]]
  (`contract.requests`, the user's voice) and a generalisation of the greeter's safe set (the
  safe set *is* the greeter's affordance). A **necessary** condition for a derived grant — the
  host's absolute veto: a feature it does not afford is never granted, whatever a user offers.
  (ADR-0025; consumed by `bindContractUser`)
- **wants** / **`contract.wants`** — the **user's** voice on *which* features (home-side), the
  symmetric counterpart of the host's [[affordance]] and the typed form of the [[offer]]: a
  submodule over `grantedOptions` (same `{ <feature>.enable = bool; }` shape, **no freeform**)
  declared in the user's own `home.nix`. [[mkContractUser]] **harvests** it off the evaluated home
  and publishes it as the index's `offer`. It defaults to the **[[safe set]]** — non-privileged
  features are wanted by default, privileged ones must be asked for — per FEATURE, so asking for
  one keeps the rest; a user wanting no desktop writes `contract.wants.gui.enable = false`. It must
  be **variant-invariant**: a want that reads [[hostFacts]]`.granted` is circular (the grant is
  derived *from* the offer) and fails the bake with a named error. (ADR-0028; `homeModules.default`)
- **deny** — the **absence of a grant**. Not a veto, not a default-open block — a host runs
  only what it grants (derived within its [[affordance]]s).
- **feature configuration** *(a feature's **parameters**)* — the **host-owned** parameters the
  realization consumes (`custom.users.<u>.<feature>.*`, e.g. `gui.desktop`), distinct from the
  grant (the yes/no). The **consumer** end of a producer→consumer pair with **request**:
  written only host-side — operator grant-data, or the pre-built bind bridging a granted request —
  **never** by the user across the trust boundary. Host-affecting parameters **aggregate**
  across granted users. (ADR-0003, `featureConfigOptions`)
- **request** / **`contract.requests`** — the **user's** voice on a feature's *parameters*
  (distinct from [[wants]], which features): the home-side namespace a
  user's home module *emits* (read-only data inside home-manager's sandbox) to ask for a
  feature's parameters. **Fully typed** since ADR-0028 — the freeform that accepted (and ignored)
  unknown keys is gone, so a misspelled feature key or param is an eval error, not a silent
  seat-default. The **producer** end of the pair with **feature configuration**:
  the pre-built bind reads it from the baked manifest (and `traceUser` harvests it in a dry-run) and
  bridges only the **granted** ones into the system-side feature configuration the realization
  reads. A request *names* a host effect but never performs it; the user never writes system-side.
  (ADR-0002, ADR-0007; `homeModules.default`)
- **realization** — the host-invariant module mapping each `custom.users.<u>` to a
  `users.users` account. Powers route through *grants*, not raw identity. Since issue #30 it owns
  no identity→account field logic itself: it is the **build-time adapter** over the [[accountPlan]],
  mapping that neutral record into the `users.users` module shape (the `isNormalUser` framing, the
  `openssh.authorizedKeys.keys` nesting). (`realization.nix`, ADR-0001 mechanic 5)
- **accountPlan** — the pure `accountPlan (identity, grants) → account record`: the **single
  description** of how an identity and its grants become a system account — `description`/GECOS,
  `hashedPassword`, `authorizedKeys` (the primary `sshKey`, dropped when empty, then `trustedKeys`),
  and `extraGroups` (the [[clamp]]ed self-declared groups ∪ the granted groups). Closed over
  [[grantLib]] so its clamp + grant→groups fold are single-sourced. It is the plan **both** adapters
  render — and, since ADR-0027, the **one rule** both *execute*, not two spellings kept in step: the
  [[realization]] maps it into `users.users` at build time; the greeter's runtime `provision`
  **evaluates the same `accountPlan`** at login via the [[contract-account-plan]] tool (which
  re-imports this function from the pinned contract source) and renders the result. It is a neutral
  record (the four account fields, not a NixOS-module shape), so both the build-time mapping and the
  runtime rendering read it plainly. (`account-plan.nix`) **(built — issues #30, #31; ADR-0027)**
- **contract-account-plan** — the greeter-scoped **evaluator** that makes [[accountPlan]] the ONE
  owner of the account rule (ADR-0027). Given `identity.json` + a grant set it pins the contract
  source + a nixpkgs `lib` in-store, re-imports `kit.internal.accountPlan`, and prints the neutral
  record as JSON — contract-owned code over *already-authenticated* data, run **after** the eval-free
  auth gate (it evaluates no user Nix). `provision` execs it and renders the record, so the four-field
  fold is expressed **once** (in Nix) rather than reproduced in jq. Identity defaulting single-sources
  too: the raw JSON is resolved through the real `identity.nix` submodule. Internal (it needs a
  package, which the pure kit lacks), assembled in the greeter beside auth/provision/session.
  (`greeter/account-plan-eval.nix`) **(built — ADR-0027)**
- **clamp** — the account plan applying [[grantLib]]'s filter of privileged groups out of a
  user's self-declared `identity.extraGroups` (untrusted input). Privileged groups come only from a grant, so a
  user can never self-escalate by listing `docker`/`wheel` in its identity — and, under the
  negotiated grant (ADR-0025), never **beyond the host's [[affordance]]s**: the offer completes
  a grant only for features the host affords, and the untrusted/greeter path affords only the
  safe set (no privileged feature), so a stranger's offer can never reach privilege. The clamp
  remains defense-in-depth: any privileged group not backed by the derived grant is dropped.
  The clamp is [[grantLib]]'s `safeDeclared` fold inside [[accountPlan]], and since ADR-0027 it is
  **one definition executed on both sides**, not one set with two rule spellings: the build-time
  [[realization]] and the greeter's runtime `provision` both run the *same* `accountPlan` — `provision`
  by evaluating it via [[contract-account-plan]] — so a login shell no longer re-expresses the fold in
  jq. The clamp's own guarantee (a hostile `docker`/`wheel` in `identity.json` is dropped) is proven
  **without a boot** in `conformance/account-plan.nix`, driving `accountPlan` directly; the
  greeter-provision VM then proves the runtime renderer *surfaces* that clamped record onto a real
  account (a greeter user is never built into the system, so `realization.nix` never runs for it).
  (issue #31; ADR-0027)
- **gui-session union** *(REMOVED, ADR-0021)* — the realization used to derive the host's display
  surface's session types (`custom.gui.surface.{wayland,x11}`) as the union of every granted gui
  user's session type. **Removed:** the contract is now **display-server-agnostic** — it exposes only
  `custom.gui.surface.enabled` (some gui user granted) and carries the desktop *name*; wayland-vs-x11
  is wholly the seat's concern (its display binding / launch command). (ADR-0003 + ADR-0018 → ADR-0021)
- **`mkConfinementCheck`** — the **consumer-side** confinement proof the contract ships
  (`check-kit.nix`): `{ buildHome; pkgs; force ? …; positiveControl ? … }` → a check derivation.
  The suite's own `conformance/confinement.nix` proves the **umbrella** has no system channel; this
  proves a consumer's **real module set** does not, by merging one out-of-universe probe at a time
  into the consumer's OWN home builder. Includes the **positive control** — a legitimate home
  option must still evaluate — without which a builder that rejects everything reads as confined.
  **(built — issue #35)** (ADR-0002, ADR-0004)
- **model A / B / C** — trust postures for the user surface (ADR-0001 mechanic 7): A = user
  exports arbitrary modules (in-repo migration only; "deny" cosmetic); B = flat data only
  (deny enforceable, expressiveness lost); C = restricted `evalModules` over a curated
  catalog — the old target, **superseded** by the request channel (home-manager *is* a
  restricted universe, so no catalog). (ADR-0002)

## Secrets

- **the contract handles no secrets beyond the login credential** — the only secret it
  touches is the **hashedPassword** (the greeter authenticates on it; the realization installs
  it). It carries no secret-bearing features, re-keys nothing, and is never a recipient of a
  user's secret. (ADR-0023, supersedes ADR-0005 + ADR-0015)
- **user secret (three tiers)** — *public identity* (`authorizedKeys`, name, email,
  username — not secret); *`hashedPassword`* (a one-way hash; handling depends on repo
  visibility); *feature secrets* (the real secrets — private keys, tokens). The contract
  handles the first two; **feature secrets are the user's own home concern** — they ride the
  user's own key, provisioned by the user's own home module, and never pass through the
  contract. Keep the tiers distinct; "user secret" alone is ambiguous. (ADR-0001 mechanic 1, ADR-0023)

## Hosts and trust

- **exposed host** — a host marked `custom.host.exposed` (an agent/code-executing or otherwise
  exposed box). A **plain host fact** a user's home may read via [[hostFacts]] and adapt to; the
  contract enforces nothing on it. (The former exposed-host *ban* on secret-bearing features is
  retired — the contract carries none. ADR-0023.)
- **incapacity vs prohibition** — a *headless* host has no greeter because it has no display:
  **incapacity**, not a ban. Keep "ban"/"prohibition" reserved for a real security *rule* so
  the word keeps its weight; don't model "no screen" as a ban. (ADR-0002)
- **hostFacts** — the restricted, read-only, **self-scoped** projection of host state a
  user's home module may read: `{ exposed, platform, granted }`. Deliberately excludes
  `hostName` so adaptation keys on *semantic* facts, not host identity. `granted` is **narrowed to
  [[homeAffecting]]** (ADR-0028) — a home may only see the grants something bakes for, so it cannot
  become grant-sensitive on a bind-riding feature. The value is supplied by
  whoever builds the home (the producer bakes it per variant, hand-built inline — there is no host
  `config` at bake time). The `mkHostFacts` config-projector was **deleted** as caller-less (the
  pre-built path never evaluates a home host-side, ADR-0026); the no-`hostName` confinement is now a
  **convention** the producer keeps, unenforced until `hostFacts` is a typed option rather than a
  bare `specialArg`. (ADR-0002, ADR-0026)

## The greeter and binding

- **build-time binding vs runtime binding** — two paths over one contract, **opposite defaults**.
  Build-time = operator-authored fleet declaration, **default-closed**, via `bindContractUser`
  (pre-built). Runtime = the **greeter**, **default-open over the safe set**, building the user's
  own home output. Neither evaluates the home host-side inline: the build-time path binds a
  pre-built `contractPackage`, the greeter builds `homeConfigurations.<u>` (ADR-0026 retired the
  inline-eval mechanism). (ADR-0002, ADR-0006, ADR-0026)
- **`bindContractUser`** — the **sole public consumer bind** (ADR-0025/0026): a host declares its
  `contract.affordances` once and binds one indexed user with `{ usersFlake; username }`. Reads the
  user's [[binding index]] entry, derives `grant = affordances ∩ offer` (always **negotiated** —
  there is no unilateral direct-grant path on the public surface), selects the maximal covering
  [[variant]], and delegates to the internal [[bindContractPackage]] kernel. The consumer twin of
  the producer's [[mkContractUser]] (bind one contract-user ⇄ make one). **(built — issue #25)**
- **`traceUser`** — the home-manager-free **dry-run inspector**, and the one request→grant→bridge
  tool **outside** the contractUser produce/consume coin. Given a *contract-pure* home module +
  identity + grants it harvests via bare `evalModules` (no home-manager, not even a stub — ADR-0004)
  and returns a record `{ username; home; requests; wants; unknown; system }`: what does my home
  want and request under these grants, and does it bridge? Its `permissive` mode is the **one
  tolerant reader** of the otherwise fully-typed user voice: feature keys from a newer contract land
  in `unknown = { requests; wants; }` as data instead of throwing, because traceUser is the only
  place a roaming home meets a possibly-older umbrella and an inspector that dies on that question
  is a dead end (ADR-0028). It is the conformance suite's logic-level proof and the public tool a
  home author dry-runs against — **not a deployment path** (real binds are pre-built). A real home
  that sets `programs.*`/`home.*` throws here by design; it binds through the pre-built path instead.
  **(built — issue #5)** (ADR-0007, ADR-0026)
- **portable user** — the runtime north star: the *same* identity logs into *any* contract
  seat and gets the **exact same experience** — home config **and** allowed system-side options —
  with host and user mediated only by the contract. This is *why* the greeter must **fully
  realize** both the home and the allowed system options **before** login, identically on every
  seat (ADR-0012); the safe set being contract-defined and the greeter-seat baseline being uniform
  are what make "same experience everywhere" hold. (ADR-0002, ADR-0006, ADR-0010, ADR-0012)
- **greeter** — the runtime path: a seat host's greetd flow that fetches a user flake,
  authenticates **eval-free** on `identity.json`, classifies the tier, binds with
  `grants = greeterGrants`, builds, and provisions the account. Ships as the opt-in, replaceable
  `nixosModules.greeter` (`greeter.nix`) — `nixosModules` is split `default` (every host) +
  `greeter` (a seat host enables it). The project's north star. **(built — issue #2)** (ADR-0002,
  ADR-0006, ADR-0008)
- **greeter mechanism vs program** — ADR-0008's split, what makes `nixosModules.greeter` both
  canonical and replaceable. **Mandatory mechanism** (pure `lib`/module, no package): authenticate
  **eval-free** on `identity.json` before any user Nix, bind via the contract, grant at most the
  `safeSet`. **Replaceable program** (where packages live): the greetd integration, the UI, and the
  runtime-provisioning helper. The reference module ships scripts that reference packages from the
  **host's** `pkgs`, so the contract *flake* still inputs only nixpkgs `lib` (ADR-0004) — the one
  place a package is allowed without breaking the package-free invariant.
- **contract-greeter-{bind,auth,provision}** — the reference greeter's three scripts. `auth` is
  the **canonical eval-free** step (`jq` over `identity.json` + libc-crypt password + Tier-1 SSH
  signature, running zero user Nix, with the identity field names it reads projected from
  `identity.nix`); `provision` is the **runtime-provisioning helper** — the privileged crux that is
  the **runtime adapter over [[accountPlan]]** (the twin of [[realization]]'s build-time adapter). Since
  ADR-0027 it is a **pure renderer**: it *evaluates* the shared `accountPlan` via [[contract-account-plan]]
  (owning none of the combining rule) and realizes the returned record (password, `authorizedKeys`,
  GECOS, the **clamped** safe groups + the greeter-seat baseline) **and** activates the built home AS
  the user, all before the session starts, outside NixOS's declarative build-time model; `bind` is the
  greetd orchestrator tying the ordering together.
  (`greeter.nix`; ADR-0006, ADR-0012)
- **homeBuilder** — the greeter's one **host binding** (`custom.greeter.homeBuilder`, null by
  default): the command that evaluates + builds a user's home *through the contract* under the
  [[tier1-eval-posture]] and prints the activation package. It is host-side because building a real
  home needs home-manager, which the contract does not depend on — exactly as the display
  binding is host-side. The greeter hands it the posture as `NIX_CONFIG`, so a naive `nix build`
  binding inherits the floor for free. Everything else in the greeter is package-free at the flake level.
  The whole orchestrator is exercised end-to-end by the [[bind-loop]] VM.
- **bind-loop** — the FULL real runtime path the greeter performs at a login (`greeter-bind-loop` check,
  `conformance/bind-loop-vm.nix`): drive the actual `contract-greeter-bind` ORCHESTRATOR on a booted
  seat — flake URL + username + password on stdin → `nix flake archive` (real fetch) → eval-free Tier-1
  signature auth → [[homeBuilder]] → [[contract-greeter-bind|provision]] → session launch — the one
  truly-runtime step `greeter-provision-vm`/`greeter-provision` stop short of (they drive provision/session with a
  pre-built home). The fixture user flake is minimal (its `activationPackage` is a raw derivation that
  is just an `$out/activate`, all `provision` needs) so the test isolates the LOOP, not a home-manager
  build (that is the example user flake's package builds). One concession, documented in-file: a
  *nested test VM* cannot realize a fresh sandboxed `nix build`, so the reference homeBuilder there
  resolves to a home built at test-build time; its real-seat form is the
  `nix build "$src#…activationPackage"` one-liner. (issue #2; ADR-0006)
- **greeter session is secret-free** — the greeter authenticates on a **password, not a key**
  (ADR-0006) and activates the user's home with no secret step: it never unlocks or places a
  user key. Recovering a roaming user's own home secrets at a foreign seat is out of scope for
  the contract — a user who needs it provisions their key by their own means. (Greeter secret
  provisioning, ADR-0015, was removed by ADR-0023.)
- **tier1-eval-posture** — the **contract-pinned** Nix settings a host-signed home is evaluated +
  built under (`tier1EvalConfig`, a projection beside [[safe-set]]/[[greeterGrants]]; ADR-0014):
  `accept-flake-config = false` (**the un-widenable linchpin** — the repo's own `nixConfig` is
  ignored, so it cannot relax its own eval; ADR-0011 applied to eval), `restrict-eval`, no IFD, and
  a sandboxed build. The greeter renders it (contract's own `renderNixConfig`) and exports it as
  `NIX_CONFIG` to [[homeBuilder]]; it augments the seat's `nix.conf` (experimental-features survive)
  and a host may **add** restrictions, never remove these. `restrict-eval` is coherent because the
  fetch step is `nix flake archive` (source **+ input closure**), so the restricted build needs no
  eval-time network. Exposed read-only as `custom.greeter.tier1EvalConfig` for audit. Proven in
  conformance both by eval assertions and by an **executable** proof (the rendered posture actually
  blocks a hostile `readFile`; the same eval succeeds without it). Tier 2 will pin a stricter
  posture; deferred. (ADR-0011, ADR-0014; `lib.nix`, `greeter.nix`)
- **greeter-seat baseline** — the **standing, build-time** system-side effects a greeter seat
  pre-realizes once, so a runtime login needs **no per-login rebuild**. Because every greeter login
  gets *exactly* `greeterGrants` and the safe set is statically known, the grant's system effects
  are uniform across all greeter users — so the seat declares them as a property of "this host runs
  a greeter" (the safe-set group memberships as a `greeter-users` group; both session stacks
  installed; the session/display backend bound), and `provision` just **enrolls** the new account
  into it. Applying grant effects per-login via `nixos-rebuild` is privilege-safe (the safe set
  bounds it) but rejected: it mutates the *global* generation (shared blast radius), and the
  runtime user isn't in the operator's flake so the next operator switch deletes it (drift). The
  invariant that keeps this rebuild-free: safe-set membership requires the effect be **uniformly
  pre-realizable** as a seat capability — anything needing per-login system mutation is build-time
  only, like privilege. Scoped to **single-seat personal machines** (laptop / single-monitor
  desktop), where greetd serializes `seat0` so logins never overlap. Its home-side sibling is the
  [[home baseline]] — same species (a standing, uniform-across-users posture), the opposite
  negotiability (the host owns the seat; the user owns the home). (ADR-0006, ADR-0008)
- **desktop choice** — which DESKTOP (GNOME, Plasma, a WM…) a greeter user logs into, chosen
  **per user** (ADR-0013). The user carries a **free-form** name in their home
  (`contract.requests.gui.desktop`) so it travels with the identity — same desktop on any seat that
  offers it (the [[portable-user]] north star); the **seat offers** desktops as a host binding
  (`custom.greeter.desktops.<name> = { command; }`, reusing each DE's session-entry Exec, like
  a display manager). The greeter resolves the user's name against the offered set and launches it
  via greetd-as-user (a full DE needs that seat session); an un-offered name degrades to
  `defaultDesktop`. DE-agnostic: the contract carries an opaque name, the seat maps it. The choice
  is **auto-surfaced** to `~/.contract-desktop` by `homeModules.greeterDesktop` — a SEPARATE home
  module from `homeModules.default` (it sets `home.file`, a home-manager option, so the default
  umbrella stays tracer-pure / home-manager-free; a real home imports both). Inert when no desktop
  is requested ⇒ the seat default. (ADR-0013; `features.nix`, `greeter.nix`, `modules.nix`)
- **safe set** — the features a runtime/greeter login may auto-grant: the **runtime-eligible**
  ones. `safeSet = ["gui"]` today. (`lib.nix`)
- **greeterGrants** — the **canonical runtime grant value** (`self.greeterGrants`): the safe set
  lifted into a grant attrset (`{ <feature>.enable = true; }`), i.e. **default-open over the
  safe set**. The greeter provisions with it (`contract-greeter-provision` realizes at most the
  safe set); it is ADR-0008's conformance condition (3) — *a greeter grants at most the safe set* —
  made a single-sourced value, so escalation is impossible by construction, not by a deny rule.
  (`lib.nix`; ADR-0006, ADR-0008)
- **runtime-eligible** — *derived*, not declared (`runtimeEligibleFeature`): a feature is in
  the safe set iff it confers no privileged group. Deriving it keeps
  "what a stranger may have" tied to "what confers no privilege." The exec-payload clause
  (features where the host executes user-supplied code) is deferred — no feature uses it yet;
  it re-enters the derivation when a concrete feature requires it. (ADR-0002, ADR-0016)
- **tier (Tier 1 / Tier 2)** — the greeter's trust classification of a flake URL. Tier 1 =
  semi-trusted (own, *signed* repo; persisted home; the [[tier1-eval-posture]] guarding accidents) —
  built first. Tier 2 = untrusted (anyone; hardened eval; ephemeral home) — designed-for,
  deferred. A tier is a *parameter* over one mechanism, not a separate code path. (ADR-0006)
- **trustedSigners vs trustedKeys** — two different key sets, kept distinct (ADR-0011).
  **`trustedSigners`** (`custom.greeter.trustedSigners`, host-pinned) is the **sole Tier-1
  signing authority**: a repo is Tier 1 iff its `contract.sig` verifies against an
  *operator-pinned* key. **`trustedKeys`** (in the user's `identity.json`) is the user's SSH
  **login** keys (→ `authorizedKeys`, `realization.nix`). A repo signing with a key it lists in
  its own `identity.json` proves nothing about *host* trust — so tier classification consults the
  host set only; a repo cannot self-certify its tier. (ADR-0011; `greeter.nix`, `realization.nix`)
- **identity.json** — the contract-conventional **data** file (not Nix) carrying a user's
  public identity. The greeter authenticates against it with `jq` **before** evaluating any
  user Nix (**data before code** — eval is not a sandbox). The contract owns the schema and
  ships `loadIdentity`, a lossless loader whose schema is **projected from `identity.nix`**
  (the single identity source). It validates the **schema** and nothing else — no hash policy; see
  [[credential posture]]. (ADR-0006, ADR-0007; `identity-json.nix`)
- **credential posture** — *which hash algorithm* a repo's `identity.json` files must carry:
  `libc` (any libc-`crypt` hash, `$6$` included) for a **private** repo, `yescrypt` (`$y$`) for a
  **public/shared** one. **Conditional and consumer-owned**, never a contract invariant — so
  [[identity.json]]'s `loadIdentity` imposes none. Asserted by the **opt-in**
  `mkIdentityPostureCheck { identities; require; pkgs }` (`check-kit.nix`), which a repo calls over
  its own — derived, never hardcoded — roster with the posture *it* chose; `require` has no default,
  an unknown posture name is a loud error, and an empty roster is a hard error rather than a vacuous
  pass. **(built — issue #35)** (ADR-0019)
- **inert payload vs exec payload** — a request payload the host merely *reads* (the
  `session` enum) is **inert**; one the host *executes with privilege* (a `kanata-with-cmd`
  keymap running shell) is an **exec payload** — a code-exec vector, never safe-set-eligible,
  build-time-only. The registry flag (`execPayload`) and its exclusion from `runtimeEligibleFeature`
  are **deferred** (ADR-0016): no feature carries an exec payload yet, and the mechanism will
  be introduced alongside the first feature that does. (ADR-0002, issue #3)

- **contractPackage** — the user flake's `packages.${system}.contractPackage` output: a
  content-addressed store path the host pins as a flake input and activates at switch time.
  Contains the home activation script and a `contract-requests.json` sidecar
  (`{ version, username, requests, packages }`). The host reads `contract-requests.json` at
  eval time (no IFD — it is pre-built and pinned) and bridges granted feature requests; at switch
  time it runs the activation then replaces `~/.nix-profile` with a host-built package profile. The
  **one binding mode** (ADR-0026 retired the inline-eval alternative). **(built — issue #16)**
  (ADR-0016; amends ADR-0007)
- **manifest module** *(internal)* — the single owner of the `contract-requests.json` schema: the
  seam between the producer [[mkContractPackage]] and the consumer [[bindContractPackage]]. It owns
  the manifest **version**, its **field set** (`version`, `username`, `requests`, `packages`,
  `granted`), the seam **filename**, and the **v1→v2 compat read** (v2 added the `granted`
  coupling-guard field; a v1 manifest predates it and reads back as `[ ]`). `writeManifest`
  serializes a manifest to a store path at eval time (`builtins.toFile`, no IFD); `readManifest`
  parses a pinned/realized store path back into the canonical field set. The producer writes
  *through* `writeManifest` and the consumer reads *through* `readManifest`, so neither re-encodes
  the shape. Exposed via `kit.internal` so the conformance suite proves the write→read round-trip and
  generates its `reference-contract-package{,-gui}` fixtures through it. **(built — issue #27)**
  (ADR-0016)
- **`mkContractPackage`** *(internal kernel)* — the derivation logic that produces a
  `contractPackage` from an already-evaluated home config:
  `mkContractPackage { pkgs; activationPackage; requests; packages; username }`. Projects
  `config.contract.requests` and the top-level package manifest into the [[manifest module]]'s
  `writeManifest` (`builtins.toFile` at eval time, no IFD) and wraps activate + manifest into a
  single derivation. **Not a flake output** — the public producer surface is
  [[mkContractUser]]/[[mkContractUsers]], which bake through it (ADR-0026). **(built — issue #14)**
  (ADR-0016)
- **`mkContractPackageForHome`** *(internal kernel)* — the home-manager producer adapter:
  `mkContractPackageForHome { home; grants ? { }; pkgs }`. Reads `mkContractPackage`'s four
  primitives off an already-evaluated home (`home.activationPackage`,
  `home.config.contract.requests`, `home.config.home.{packages,username}`) and forwards them. It
  does **not** import home-manager (only *reads* attributes), so the package-free invariant
  (ADR-0004) holds. It is where a home and a grant set join into a published artifact, so it is
  also where the [[bake pairing]] is verified. **Not a flake output** — [[mkContractUser]] bakes
  each variant through it (ADR-0026). **(built — issues #23, #56)** (ADR-0016)
- **`bindContractPackage`** *(internal kernel)* — the package-level host bind:
  `bindContractPackage { contractPackage; identity; grants }`. Returns a NixOS module that reads
  `contract-requests.json` at eval time via the [[manifest module]]'s `readManifest`, bridges
  granted requests via the `mkUserAccount`/
  `bridgeRequests` kernel, and registers a `system.activationScripts` entry that runs
  `contractPackage/activate` at switch time. When `custom.host.packagePolicy.allowedPrograms` is
  non-empty it also builds and links a host-built package profile. **Not a flake output** — the
  public consumer [[bindContractUser]] selects a variant and delegates here; the grant model is
  negotiation-only, so its unilateral `grants` argument is never a consumer entry (ADR-0026).
  **(built — issue #16)** (ADR-0016)
- **variant** — a **baked home identified by the grant set it was baked with**. `mkContractPackage`
  freezes `activationPackage`, so a grant that *changes the baked home* (a **home-affecting**
  grant — one the user's `home.nix` fans out on, e.g. `gui` → emacs/ai) must be its own variant,
  while a grant conferring only host-side effects (a privileged group) rides the bind and needs
  no bake. Which grants a home *may* branch on is contract data since ADR-0028 ([[homeAffecting]],
  the upper bound `hostFacts.granted` is narrowed to, so `powerset(homeAffecting)` bounds the
  baked set); whether *that* repo's home actually branches stays the producer's
  call, so a repo whose homes read no grant still bakes a single `base`. `powerset(homeAffecting)`
  is the upper bound on what a host could grant, **not** a per-system baking obligation: *which*
  variants a fleet bakes per system — its **bake matrix**, `{ <system> = { <label> = home; }; }` —
  is the **consumer's fleet fact**, set by its mapper's per-system filter (e.g. gui homes only
  where a seat exists — decision #43). The contract keeps answering "what could a host grant"; the
  roster-generic `mkVariantEvalCheck` proves whatever IS baked evaluates, without opining on that
  matrix. A
  variant's name (`<user>-contractPackage-<key>`, key = sorted home-affecting grant names, empty
  ⇒ `base`) is a cosmetic label, not a parse target. **(built — issue #25)** (ADR-0025)
- **binding index** — the pure-data selector a `users` flake exposes, `contractUsers.<sys>.<user>
  = { identity; offer; variants = [{ granted; package }] }`. Plain data (no IFD), so a host
  selects a [[variant]] without building any of them. Identity is resolved once from the ADR-0020
  path; the `offer` is harvested from the home's [[wants]] (ADR-0028); each variant's `granted` is
  the [[grant-key]], and cannot disagree with the home's own recorded key (the [[bake pairing]]
  guard rides the whole variant record). **(built — issues #25, #56)** (ADR-0025)
- **`mkContractUser`** — the **singular public producer** and the twin of the consumer's
  [[bindContractUser]] (make one contract-user ⇄ bind one): `{ name; variants; pkgs; system;
  usersDir }` — no `offer`, it is harvested from each variant's home and must be
  variant-invariant (ADR-0028). Bakes ONE user's [[variant]]s into the named packages and its
  `contractUsers.<sys>.<user>` [[binding index]] entry — the ready-to-`inherit … packages
  contractUsers` flake-output shape, so a single-user repo needs no roster. It verifies the
  [[bake pairing]] on the whole variant record, so neither the index's [[grant-key]] nor the
  published package's name can reach a flake output mispaired. **(built — ADR-0026; issue #56)**
- **`mkContractUsers`** — the **roster public producer**: [[mkContractUser]] mapped over a whole
  `users` flake and merged, so a multi-user repo (ADR-0020) bakes its entire roster in **one** call.
  The turnkey producer for the multi-user shape exactly as [[bindContractUser]] is the turnkey
  consumer. **(built — issue #25; singularised ADR-0026)** (ADR-0025)
- **`mkContractHome`** — the **producer home builder** (ADR-0029, issue #40): the contract-owned
  composition every producer's `mkHome` glue previously hand-wrote — the home umbrella +
  [[home baseline]] + the user's `home.nix` + the inline identity/`home.*` module + the narrowed
  [[hostFacts]] specialArg (via `hostFactsFor`). Package-free by **injection**: the consumer passes
  `home-manager.lib.homeManagerConfiguration` **verbatim** (ADR-0004; the check kit's `buildHome`
  posture) and the contract only composes arguments and applies the consumer's function. `hostFacts`
  is contract-owned and WINS over `extraSpecialArgs` (a caller cannot hand a home an un-narrowed
  grant set); `pkgs` and `stateVersion` stay consumer facts by design; `extraModules` is the open
  seam (confinement probes, `greeterDesktop`, markers, repo glue) that lets one builder serve the
  roster homes, the greeter-login mapper, and the confinement check over the SAME module set.
  `home.homeDirectory = "/home/<username>"` is a fixed contract rule, matching the realized
  account. Its result CARRIES the [[grant-key]] it was baked under, which is what makes the
  [[bake pairing]] checkable. **(built — issues #45, #56)** (ADR-0029)
- **home baseline** — the contract-shipped **universal home hygiene** (`homeModules.baseline`, kit
  attr `homeBaselineModule`): the standing, uniform-across-users home-manager posture every
  produced home starts from — the self-manage CLI, plus `systemd.user.startServices = "sd-switch"`
  **pinned** (a no-op today — upstream's default already maps there — kept to pin restart-on-switch
  semantics against upstream churn). **Hygiene is a pinned posture, not an opinion set**: every line
  is `lib.mkDefault` and there is no opt-out knob — a user module's plain definition wins
  per-option, while a pin still beats an upstream option default. Composed by default by
  [[mkContractHome]]; lives OUTSIDE `homeModules.default` (it sets home-manager options; the
  default umbrella stays tracer-pure). The same species as the [[greeter-seat baseline]] — a
  standing, uniform-across-users posture, as against per-user intent — with opposite negotiability:
  the seat baseline is non-negotiable (the host owns the seat), the home baseline overridable
  per-option (the user owns the home). Deliberately NOT in it: `xdg.mimeApps` (opinion), packages
  (user intent), `greeterDesktop` (reference convention; opt-in via `extraModules`). (ADR-0029;
  `modules.nix`)
- **`bindContractUser`** — the **sole public consumer bind**: `{ usersFlake; username }`, **no
  `grants`**. Reads `contract.affordances` and the user's [[binding index]], derives
  `grant = affordances ∩ offer` (always negotiated), selects the **maximal baked [[variant]] whose
  grant-key ⊆ grant** (no unique maximum ⇒ hard error), and delegates to the internal
  [[bindContractPackage]] kernel with the derived grant and index-supplied identity. The host holds
  **zero** users-repo internals (no variant names, no identity paths). Consumer twin of
  [[mkContractUser]]. **(built — issue #25; renamed ADR-0026)** (ADR-0025)
- **coupling guard** — `bindContractPackage`'s assertion `manifest.granted ⊆ grantedNamesOf grants`:
  a [[variant]] may bind only if its baked grants are all granted. Required by ADR-0016 but never
  enforced until ADR-0025; maximal-subset selection in [[bindContractUser]] satisfies it by
  construction, so the check is defense-in-depth for the internal kernel. **(built — issue #25)**
  (ADR-0016, ADR-0025)
- **grant-key** — the sorted **enabled feature names** of a grant set: the canonical,
  order-independent identity of a [[variant]]. One projection (`grantKey`) behind the variant
  *label* (`base` when empty, else the names joined), the [[binding index]]'s `granted`, and the
  [[bake pairing]] guard — so "the same grant set" cannot mean two things across them.
  **(built — issue #56)** (ADR-0025, ADR-0029 amendment; `lib.nix`)
- **bake pairing** — the **join** the contract owns between its two ends of a bake:
  [[mkContractHome]] evaluates a home *under* a grant set, the producer coin bakes it *with* one,
  and a producer re-pairs `{ grants; home }` by label in between. The home **carries the
  [[grant-key]] it was baked under** (`contractBakedGrantKey`, attached to the builder's returned
  value — *not* a home option: `homeModules.default` stays tracer-pure, and `contract.*` in a home
  is the user's voice, so a producer-written key there would be a spoofable second spelling of
  `hostFacts.granted`), and [[mkContractPackageForHome]] and [[mkContractUser]] cross-check it. A
  mispairing — a `base` home published under a `gui` key — is a hard bake error naming the user,
  the baked key and the passed key, where before it was *structurally* undetectable: the manifest's
  `granted`, the index's `granted`, and so the [[coupling guard]] and maximal-variant selection all
  read the grant passed *alongside* the home, never the home. A home built without the builder
  carries no key, so the check is **skipped, not fired** — the builder is a convenience, not a
  requirement. **(built — issue #56)** (ADR-0029 amendment)

## Program scope and package policy

- **program scope** — what software a user runs in their home session. Always *advisory*
  when the user has Nix daemon access: any user with access to the daemon socket can run
  `nix shell nixpkgs#<anything>` against any nixpkgs revision, regardless of what their home
  config declares. Package policy at the home-manager or contract layer is therefore soft
  governance — it describes what a user chose to include in their reproducible home, not a
  security boundary. Hard program restriction requires removing daemon access at the OS level
  (see *daemon-restricted user*). This is why the pre-built binding mode is the coherent
  choice: since packages were never enforceable from the host side anyway, the user should
  bring exactly the versions they have tested against. The contract governs *system effects*
  (privilege, services, groups); program scope is the user's sovereign concern.
- **nix-daemon feature** — the registry entry (`features.nix`) that grants a user membership
  in the `nix-users` group and thereby access to the Nix daemon
  (`nix.settings.allowed-users = ["@nix-users"]`). `nix-users` is in `privilegedGroups`, so
  it is excluded from the safe set and the greeter never auto-grants it — daemon access is
  always a deliberate build-time operator decision. Denied on hosts requiring program
  restriction; granted on personal machines. **(built — issue #15)** (ADR-0017)
- **daemon-restricted user** — a user for whom the `nix-daemon` feature is denied. Cannot add
  new store paths. The host builds a **package profile** from the *inclusion list* and installs
  it as the user's `~/.nix-profile` at activation time, replacing what the activation package
  set. Unapproved programs are absent from the profile; approved programs are at the host's
  version (most recent in its nixpkgs). A non-compliant home always deploys — missing programs
  are simply absent from the session (their home-manager configs may be present but are inert
  without the binary). **(built — issue #17)** (ADR-0017)
- **package policy / inclusion list** — `custom.host.packagePolicy.allowedPrograms`: the set
  of program names the host will build into a daemon-restricted user's package profile. Each
  entry resolves to `pkgs.${name}` from the host's nixpkgs pin — one canonical version per
  program, the most recent the host carries. Programs off the list are not in the profile. The
  effective profile is the intersection of the inclusion list and the user's package manifest
  (what the user declared in their home config). An empty list (the default) means no policy —
  `~/.nix-profile` is left as-is after activation. **(built — issue #17)** (ADR-0017)

## Testing

- **conformance suite** — the contract's own tests (`conformance/`): synthetic users × the
  umbrella, no host repo. **Eval** (`default.nix`) proves grant/deny, the gui-union
  *decision*, the clamp, the safe set, the users × archetypes matrix, the [[accountPlan]] **rule**
  itself (`account-plan.nix`: the clamp, the empty-`sshKey` drop, and key ordering, driven directly
  with no boot — ADR-0027), the typed user voice ([[wants]]' safe-set default and shape, the
  eval error a misspelled request key now is, and `traceUser`'s permissive skew report — ADR-0028),
  the `traceUser` dry-run kernel, `mkContractPackage` content,
  `mkContractPackageForHome`'s home-attribute projection (same content-addressed store path as the
  direct call), `mkContractUser`/`mkContractUsers` parity, and `bindContractPackage` reproducing the
  `traceUser` kernel's account + gui surface from a pre-built manifest. **VM
  tests** (each a `runNixOSTest` boot): `vm.nix` (gui-union renders), `greeter-vm.nix`
  (provisioning crux — now proving the runtime **renderer** surfaces the `accountPlan` record the
  same plan evaluates, ADR-0027), `nix-daemon-vm.nix` (grant/deny/clamp for daemon access),
  `prebuilt-bind-vm.nix` (account + activation via `bindContractPackage`),
  `daemon-restricted-vm.nix` (hello on PATH, curl absent, daemon refused).
- **check kit** — the checks the contract SHIPS rather than runs (`check-kit.nix`, issues #35, #49):
  [[mkConfinementCheck]], the [[credential posture]] check, and `mkVariantEvalCheck` (every baked
  [[variant]] × every baked system evaluates — roster-generic, applied per user by the consumer's
  mapper; deliberately no `tryEval`, and shape-agnostic about *which* variants a fleet bakes, the
  consumer's fact — decision #43). Each proves something only a **consumer** can prove — over its
  own real module set, over its own roster, over its own bake matrix — so the contract hands
  over the technique, not the verdict. Their own logic is proven in the suite
  (`conformance/confinement.nix`, `conformance/identity-posture.nix`,
  `conformance/variant-eval.nix`): each accepting case, each rejecting case, and that a helper
  FAILS when its positive control is broken, when its home is never forced, when a posture is
  asked for that an identity does not carry, and when a bake matrix is emptied or under-forced.
- **coherence gate** — the thin host-side check (in the consuming repo) that every real host's
  trait-tuple is archetype-covered and the real manifest realizes — the consuming repo's tie-back to
  the contract suite. (ADR-0004)

## Terms to keep distinct

- **deny** is the *absence of a grant*, never a "veto" or a default-open block.
- **ban / prohibition** is reserved for a real security *rule*. A headless host lacking a
  greeter is **incapacity**, not a ban. (The contract has no active ban today — the
  exposed-host ban was retired with the secret-bearing features it guarded, ADR-0023 — but
  keep the word disciplined for when one returns.)
- a feature's **grant** (the yes/no) vs its **configuration / parameters** (the knobs):
  never call configuration a "grant."
- **wants** (which features a user asks for) vs **requests** (the parameters of a feature) —
  both are the user's voice, home-side, but only [[wants]] feeds the negotiation. Say "wants" (or
  its published form, the [[offer]]) when you mean the feature selection; never call a request an
  offer. Neither is a **grant**: both are asks the host may refuse.
- **request** (user-emitted, home-side) and **feature configuration** (host-owned,
  system-side) are a **producer→consumer pair**, *not* interchangeable: the user writes a
  request, the pre-built bind bridges granted ones into feature configuration, the realization reads
  feature configuration. Same shape, different owner and trust-side — never call a user's
  request "feature configuration," or a host-written value a "request."
- **desktop** vs **session type** — **desktop** (`gui.desktop`) is the user's intent, an
  experience that travels with the identity, and the **only** thing the contract carries.
  **Session type** (`wayland`/`x11`) is **not a contract concern at all** — the seat's display
  binding / launch command owns it. The contract names no session type anywhere (ADR-0021).
- **user secret** is ambiguous on its own — say *public identity*, *hashedPassword*, or
  *feature secret* (and note the contract handles only the first two; feature secrets are the
  user's own home concern).
- **program scope vs system effects** — the contract governs system effects (privilege,
  services, groups); program scope (what applications a user runs) is the user's
  sovereign concern and always advisory when daemon access is present. Do not conflate
  "host controls feature grants" with "host controls what programs can run."
- **`contractPackage` vs `activationPackage`** — `contractPackage` is the contract-level
  content-addressed flake output (activation + `contract-requests.json` sidecar);
  `activationPackage` is home-manager's internal term for the derivation that activates the
  home. `contractPackage` wraps `activationPackage`.

## Load-bearing invariants

- The contract **depends only on nixpkgs `lib`** — no `self`, no `inputs`, no secrets
  backend, no package. (ADR-0004; the extraction litmus test)
- **The user controls their own nixpkgs pin** in the pre-built binding mode — the home is baked by
  the producer and packages are user-built, so there is no one-nixpkgs constraint; see *program
  scope*. (ADR-0007, ADR-0016, ADR-0026)
- **Privilege is build-time-only**; the runtime greeter confers only the safe set.
- **The grant is negotiated** — the only public path to a grant is `affordances ∩ offer`
  (`bindContractUser`); no consumer writes a grant unilaterally. (ADR-0026)
- **The user's voice is typed and lives in the home** — both halves ([[wants]] and [[request]])
  are declared in the user's own home and carry no freeform, so a typo is an eval error; the
  producer passes neither. The one tolerant reader is the `traceUser` inspector. (ADR-0028)
- **A user can only see what it may vary on** — `hostFacts.granted` is narrowed to
  [[homeAffecting]], and an offer that varies across variants fails the bake. (ADR-0028)
- **A request names a host effect but never performs it** — the host writes, only on grant.
- **Data before code** — authenticate on `identity.json` before evaluating any user Nix.
