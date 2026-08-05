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
  `privilegedGroups`, `safeSet`). Neither host nor user. (ADR-0001, ADR-0004)
- **host** — a machine config that imports the contract, materializes user accounts,
  **grants** features, and supplies **bindings**. Sovereign: it runs only what it grants.
- **user** — a public identity + home config + the features it *offers*; host-agnostic (it
  never names a host's `self`/inputs). Its own home secrets (if any) ride its own key,
  provisioned by its own home module — never through the contract. Target shape: a
  home-manager config repo consumed via `bindUser` (ADR-0007); today still in-repo in the consuming host repo.
- **umbrella / kit** — the assembled shipped surface (`kit.nix`). `nixosModules.default` =
  the `custom.users` schema + `custom.host.exposed` + realization + the insecure-package
  aggregator. `nixosModules.greeter` = the opt-in reference runtime greeter (a seat host
  enables it). `homeModules.default` = identity + home profiles.
- **mechanism vs binding** — the contract ships generic **mechanism**; the host supplies
  only **bindings** (the display/theme, *which* hosts, the trust-tier policy). The split
  keeps every fleet from re-implementing — and drifting on — the security-critical parts. (ADR-0008)

## Features and the registry

- **feature** — one entry in the registry: the unit of capability a host grants or denies,
  and the shared name "deny" keys on. Per-entry fields: `grant`, `groups`,
  `privilegedGroups`, `config`. (`features.nix`)
- **registry** — `features.nix`, the **single source of truth** for the feature vocabulary.
- **projection** — any surface *derived* from the registry (`featureGroups`,
  `grantedOptions`, `featureConfigOptions`, `safeSet`). Keys can't drift across projections
  because there is one set of keys. (`kit.nix`)
- **offer** — the **user's** voice on *which* features it asks for (distinct from [[request]],
  the parameters of a feature). *Implicit* for a home emitting a `contract.requests` entry;
  **formalised** per-user by the `users` flake in the turnkey path — the "formal `offers` field
  until the separate-repo future needs one" that future being now (ADR-0020/0025). A grant is
  derived as host [[affordance]] ∩ offer; the home-affecting subset of the offer is what the
  producer bakes as [[variant]]s. (ADR-0002, ADR-0025)

## Grants and confinement

- **grant** — the decision to enable a feature for a user
  (`custom.users.<u>.granted.<f>.enable`); the realization's **only** source of privilege. Two
  ways to arrive at it: written **directly** by the host (the inline/hard-enforcement path,
  `bindContractPackage { grants }`), or **derived** as `affordances ∩ offer` in the turnkey
  pre-built path (`bindUserFromFlake`, ADR-0025). Derived, the grant is a two-sided
  **negotiation** — host [[affordance]] ∧ user [[offer]], *both necessary* — not a unilateral
  host write. Either way it remains the sole privilege source the realization reads. (ADR-0001
  mechanic 2, ADR-0025)
- **affordance** / **`contract.affordances`** — the **host's** voice (system-side), shaped
  `{ <feature>.enable = bool; }`: the features this host is willing to grant to users who
  [[offer]] them, declared **once** per host. The symmetric counterpart of [[request]]
  (`contract.requests`, the user's voice) and a generalisation of the greeter's safe set (the
  safe set *is* the greeter's affordance). A **necessary** condition for a derived grant — the
  host's absolute veto: a feature it does not afford is never granted, whatever a user offers.
  (ADR-0025; consumed by `bindUserFromFlake`)
- **deny** — the **absence of a grant**. Not a veto, not a default-open block — a host runs
  only what it grants (written directly, or derived within its [[affordance]]s).
- **feature configuration** *(a feature's **parameters**)* — the **host-owned** parameters the
  realization consumes (`custom.users.<u>.<feature>.*`, e.g. `gui.desktop`), distinct from the
  grant (the yes/no). The **consumer** end of a producer→consumer pair with **request**:
  written only host-side — operator grant-data, or `bindUser` bridging a granted request —
  **never** by the user across the trust boundary. Host-affecting parameters **aggregate**
  across granted users. (ADR-0003, `featureConfigOptions`)
- **request** / **`contract.requests`** — the **user's** voice: the home-side namespace a
  user's home module *emits* (read-only data inside home-manager's sandbox) to ask for a
  feature's parameters. The **producer** end of the pair with **feature configuration**:
  `bindUser` harvests it post-eval and bridges only the **granted** ones into the system-side
  feature configuration the realization reads. A request *names* a host effect but never
  performs it; the user never writes system-side. (ADR-0002, ADR-0007; `homeModules.default`)
- **realization** — the host-invariant module mapping each `custom.users.<u>` to a
  `users.users` account. Powers route through *grants*, not raw identity. (`realization.nix`,
  ADR-0001 mechanic 5)
- **clamp** — the realization filtering privileged groups out of a user's self-declared
  `identity.extraGroups` (untrusted input). Privileged groups come only from a grant, so a
  user can never self-escalate by listing `docker`/`wheel` in its identity — and, under the
  negotiated grant (ADR-0025), never **beyond the host's [[affordance]]s**: the offer completes
  a grant only for features the host affords, and the untrusted/greeter path affords only the
  safe set (no privileged feature), so a stranger's offer can never reach privilege. The clamp
  remains defense-in-depth: any privileged group not backed by the derived grant is dropped.
- **gui-session union** *(REMOVED, ADR-0021)* — the realization used to derive the host's display
  surface's session types (`custom.gui.surface.{wayland,x11}`) as the union of every granted gui
  user's session type. **Removed:** the contract is now **display-server-agnostic** — it exposes only
  `custom.gui.surface.enabled` (some gui user granted) and carries the desktop *name*; wayland-vs-x11
  is wholly the seat's concern (its display binding / launch command). (ADR-0003 + ADR-0018 → ADR-0021)
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
  `hostName` so adaptation keys on *semantic* facts, not host identity. (`mkHostFacts`,
  ADR-0002)

## The greeter and binding

- **build-time binding vs runtime binding** — two paths over one contract. Build-time =
  operator-authored fleet declaration, **default-closed**. Runtime = the **greeter**,
  **default-open over the safe set**. Opposite defaults, *one* mechanism (`bindUserModule`).
  (ADR-0002, ADR-0006)
- **bindUser** — binding a user's home module to the contract: inject `identity` (single
  loader, ADR-0009) + `hostFacts`, evaluate the home, and **bridge** the granted
  `contract.requests` into the system-side feature configuration. It ships in **two shapes**,
  both in `self.lib`:
  - **`bindUserModule`** — the **real mechanism both binding paths call** (operator grant +
    greeter): a NixOS module the host imports. The home is evaluated **once** by the host's
    home-manager and the bridge is a **config reference**
    (`config.home-manager.users.<u>.contract.requests`), so a real home-manager home
    (`programs.*`, `home.*`) binds. The host supplies home-manager; the contract only
    *references* its option paths, staying package-free (ADR-0004). **(built — issue #8)**
  - **`bindUser`** — the **headless tracer**: the package-purest proof of the same
    request→grant→bridge logic, harvesting a *contract-pure* home via bare `evalModules` (no
    home-manager, not even a stub). Returns a record (`{ system, home, requests, … }`) for
    eval testing. **(built — issue #5)**

  The greeter program that drives `bindUserModule` at runtime is issue #2. (ADR-0007, ADR-0008,
  ADR-0009)
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
  signature, running zero user Nix); `provision` is the **runtime-provisioning helper** — the
  privileged crux that is the **shell-side `realization.nix`** for one user: it fully realizes the
  account from `identity.json` + the safe-set grant (password, `authorizedKeys`, GECOS, the
  **clamped** safe groups + the greeter-seat baseline) **and** activates the built home AS the
  user, all before the session starts, outside NixOS's declarative build-time model; `bind` is the
  greetd orchestrator tying the ordering together. (`greeter.nix`; ADR-0006, ADR-0012)
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
  truly-runtime step `greeter-vm`/`greeter-provision` stop short of (they drive provision/session with a
  pre-built home). The fixture user flake is minimal (its `activationPackage` is a raw derivation that
  is just an `$out/activate`, all `provision` needs) so the test isolates the LOOP, not a home-manager
  build (that is `home-build`). One concession, documented in-file: a *nested test VM* cannot realize a
  fresh sandboxed `nix build`, so the reference homeBuilder there resolves to a home built at test-build
  time; its real-seat form is the `nix build "$src#…activationPackage"` one-liner. (issue #2; ADR-0006)
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
  desktop), where greetd serializes `seat0` so logins never overlap. (ADR-0006, ADR-0008)
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
  safe set**. The greeter binds with it (`bindUserModule { grants = greeterGrants; }`); it is
  ADR-0008's conformance condition (3) — *a greeter grants at most the safe set* — made a
  single-sourced value, so escalation is impossible by construction, not by a deny rule.
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
  (the single identity source). (ADR-0006, ADR-0007; `identity-json.nix`)
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
  eval time (no IFD — it is pre-built and pinned) and bridges granted feature requests exactly
  as today; at switch time it runs the activation then replaces `~/.nix-profile` with a
  host-built package profile. Replaces `bindUserModule`'s inline home evaluation for the
  **pre-built binding mode**; `bindUserModule` is retained for **inline-eval
  (hard-enforcement)** deployments. **(built — issue #16)** (ADR-0016; amends ADR-0007)
- **`mkContractPackage`** — the contract `lib` function that produces a `contractPackage` from
  an already-evaluated home config:
  `mkContractPackage { pkgs; activationPackage; requests; packages; username }`. Serializes
  `config.contract.requests` and the top-level package manifest into `contract-requests.json`
  (via `builtins.toFile` at eval time, no IFD) and wraps both into a single derivation. The
  home is evaluated once by the user's flake; the contract supplies only the wrapper.
  **(built — issue #14)** (ADR-0016)
- **`mkContractPackageForHome`** — the optional **home-manager producer adapter**:
  `mkContractPackageForHome { home; grants ? { }; pkgs }`. Reads `mkContractPackage`'s four
  primitives off an already-evaluated home (`home.activationPackage`,
  `home.config.contract.requests`, `home.config.home.{packages,username}`) and forwards them,
  so a home-manager producer passes one `home` instead of hand-rolling the disassembly — turnkey
  on the **producer** side exactly as `bindContractPackage` is on the **consumer** side. It does
  **not** import home-manager (it only *reads* attributes, like `bindUserModule` references
  `config.home-manager.users.<u>`), so the package-free invariant (ADR-0004) holds; the generic
  `mkContractPackage` stays builder-agnostic. `pkgs` is a parameter so one call emits multi-arch
  variants. **(built — issue #23)** (ADR-0016)
- **`bindContractPackage`** — the host-side binding for the pre-built path:
  `bindContractPackage { contractPackage; identity; grants }`. Returns a NixOS module that
  reads `contract-requests.json` at eval time, bridges granted requests via the same
  `mkUserAccount`/`bridgeRequests` kernel as `bindUserModule`, and registers a
  `system.activationScripts` entry that runs `contractPackage/activate` at switch time. When
  `custom.host.packagePolicy.allowedPrograms` is non-empty it also builds and links a
  host-built package profile. **(built — issue #16)** (ADR-0016)
- **variant** — a **baked home identified by the grant set it was baked with**. `mkContractPackage`
  freezes `activationPackage`, so a grant that *changes the baked home* (a **home-affecting**
  grant — one the user's `home.nix` fans out on, e.g. `gui` → emacs/ai) must be its own variant,
  while a grant conferring only host-side effects (a privileged group) rides the bind and needs
  no bake. Home-affecting-ness is **per-repo** (whether *that* repo's home branches on the grant),
  so the contract owns no `home` flag: the producer's **baked variant set is the taxonomy**. A
  variant's name (`<user>-contractPackage-<key>`, key = sorted home-affecting grant names, empty
  ⇒ `base`) is a cosmetic label, not a parse target. **(built — issue #25)** (ADR-0025)
- **binding index** — the pure-data selector a `users` flake exposes, `contractUsers.<sys>.<user>
  = { identity; offer; variants = [{ granted; package }] }`. Plain data (no IFD), so a host
  selects a [[variant]] without building any of them. Identity is resolved once from the ADR-0020
  path. **(built — issue #25)** (ADR-0025)
- **`mkUserBindings`** — the **producer** helper (contract `lib`) the `users` flake calls once:
  maps over each user's declared [[offer]]/variants and emits **both** the named packages **and**
  the [[binding index]]. The turnkey producer surface for the multi-user repo (ADR-0020), as
  `mkContractPackageForHome` is for a single home. **(built — issue #25)** (ADR-0025)
- **`bindUserFromFlake`** — the **turnkey host-side bind**: `{ usersFlake; username }`, **no
  `grants`**. Reads `contract.affordances` and the user's [[binding index]], derives
  `grant = affordances ∩ offer`, selects the **maximal baked [[variant]] whose grant-key ⊆ grant**
  (no unique maximum ⇒ hard error), and delegates to `bindContractPackage` with the derived grant
  and index-supplied identity. The host holds **zero** users-repo internals (no variant names, no
  identity paths). Wraps the primitive on the consumer side as `mkUserBindings` does on the
  producer side. **(built — issue #25)** (ADR-0025)
- **coupling guard** — `bindContractPackage`'s assertion `manifest.granted ⊆ grantedNamesOf grants`:
  you may only bind a [[variant]] whose baked grants you actually grant. Required by ADR-0016 but
  never enforced until ADR-0025; maximal-subset selection satisfies it by construction, so the
  check is defense-in-depth for direct callers. **(built — issue #25)** (ADR-0016, ADR-0025)

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
  *decision*, the clamp, the safe set, the users × archetypes matrix,
  `mkContractPackage` content, `mkContractPackageForHome`'s home-attribute projection (same
  content-addressed store path as the direct call), and `bindContractPackage` parity with
  `bindUserModule`. **VM
  tests** (each a `runNixOSTest` boot): `vm.nix` (gui-union renders), `greeter-vm.nix`
  (provisioning crux), `nix-daemon-vm.nix` (grant/deny/clamp for daemon access),
  `prebuilt-bind-vm.nix` (account + activation via `bindContractPackage`),
  `daemon-restricted-vm.nix` (hello on PATH, curl absent, daemon refused).
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
- **request** (user-emitted, home-side) and **feature configuration** (host-owned,
  system-side) are a **producer→consumer pair**, *not* interchangeable: the user writes a
  request, `bindUser` bridges granted ones into feature configuration, the realization reads
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
- **One nixpkgs (inline-eval mode)**: a user pins `inputs.nixpkgs.follows` to the host's —
  no second nixpkgs. Relaxed in the pre-built binding mode: the user controls their own
  nixpkgs pin and packages are user-built; see *program scope*. (ADR-0007, ADR-0016)
- **Privilege is build-time-only**; the runtime greeter confers only the safe set.
- **A request names a host effect but never performs it** — the host writes, only on grant.
- **Data before code** — authenticate on `identity.json` before evaluating any user Nix.
