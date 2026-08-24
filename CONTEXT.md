# CONTEXT

The domain glossary for the **host↔user contract** — the shared interface a NixOS fleet's hosts and
users agree on, so any host can enable any user. It is neither host nor user: it is the negotiated
interface between them, and it depends on nothing but nixpkgs `lib`.

This file is the vocabulary. When an issue, a hypothesis, a test name or an ADR names a domain
concept, use the term as defined here and avoid the synonyms called out under
[Terms to keep distinct](#terms-to-keep-distinct). The rationale for each decision lives in
[`docs/adr/`](docs/adr/); this is the index of *language*, not decisions.

## The north star

**Any seat host runs a greeter that takes a flake URL, a username and a password, and transparently
enables that user — with a desktop by default.** Nothing is declared in advance on either side. The
declarative bind is the build-time version of the same handshake, not the other way round: when the
two paths disagree about what a machine can run, the greeter is what the design is answerable to.

## The boundary

- **the contract** — the shared schema, the host-invariant realization and the derivation logic both
  sides agree on. Ships as `nixosModules.default` / `homeModules.default` (the umbrella), `lib` (the
  functions) and a data surface (`features`, `featureGroups`, `privilegedGroups`, `safeSet`,
  `modes`, `floorMode`, `greeterAffordances`). Neither host nor user.
- **host** — a machine config that imports the contract, binds users, and supplies **bindings**. It
  says exactly two kinds of thing: what this MACHINE can run (`contract.modes`, once for the box)
  and what each PERSON may do (`affordances`, at each bind). Sovereign on both.
- **user** — a public identity plus a **declaration** naming the session shapes it runs in and the
  home for each. Host-agnostic: it never names a host's `self`/inputs. Its own home secrets (if any)
  ride its own key, provisioned by its own home module — never through the contract.
- **users repo** — one directory per user: `users/<u>/{identity.json, user.nix}` plus whatever home
  modules the declaration points at. Lifting one user out into its own repo is a directory move.
- **umbrella / kit** — the assembled shipped surface (`kit.nix`). `nixosModules.default` = the
  `contract.modes` declaration + the `contract.users` account schema + `contract.exposed` + the
  package policy + the realization + the insecure-package aggregator. `nixosModules.greeter` = the opt-in reference runtime greeter.
  `homeModules.default` = the identity a home is handed, at `contract.identity`.
- **`contract.*`** — the one option prefix, written by BOTH parties on their own eval-side: the
  host's declarations and the values a bind writes back, and the user's own declaration in
  `user.nix`. There is no second prefix and none per party
  ([0026](docs/adr/0026-one-option-prefix-per-party.md)).
- **mechanism vs binding** — the contract ships generic **mechanism**; the host supplies only
  **bindings** (the display/desktop launch, the home builder, the trust-tier policy). The split
  keeps every fleet from re-implementing — and drifting on — the security-critical parts.

## Features and the registry

- **feature** — one entry in `features.nix`: a POWER a host confers on a PERSON, decided per bind.
  Per-entry fields: `grant`, `groups`, `privilegedGroups`. A feature has **no parameters**, and
  every feature in the registry is **privileged** — what a machine can *do* is a mode, not a
  feature, so what is left here is exactly the set that needs a deliberate per-person decision.
- **registry** — `features.nix`, the single source of truth for the feature vocabulary.
- **projection** — any surface *derived* from a registry (`featureGroups`, `grantedOptions`,
  `safeSet`; and from the mode registry, the user declaration schema and `floorMode`). Keys cannot
  drift across projections because there is one set of keys.
- **grantLib** — the grant-projection helper set computed once in the kit and *injected* into the
  realization, the greeter and the derivation logic. It single-sources the three folds every
  grant-reading site would otherwise re-derive: `grantedNames`, `grantedGroups`, and `safeDeclared`
  (the **privileged-group filter**). One owner ⇒ it cannot drift between eval sites.
- **safe set** — the features declaring no `privilegedGroups`, derived rather than listed. Today
  **empty**, so a greeter confers no feature at all: a stranger gets a *session*, not powers. The
  derivation is kept and the conformance suite asserts the emptiness as a **tripwire** — it fails
  the day a non-privileged feature is added, which is when a human should be asked whether somebody
  who just typed a URL at a login prompt ought to receive it.
- **an identity describes a person, never their powers** — `identity.json` carries who somebody is
  (name, email) and how they log in (hashedPassword, sshKey, trustedKeys). Nothing in it decides
  what an account may DO. It used to carry `extraGroups`, filtered by a deny-list of privileged
  names — so anything outside that list (`networkmanager`, say) reached the account unconditionally,
  which on the greeter path meant a stranger could grant it to themselves by editing their own file.
  It is gone: escalation is impossible because the vocabulary does not exist, which is the same
  structural argument [[confinement]] makes about the home.
- **privileged-group filter** — what is left of the old clamp. Nothing untrusted reaches it now, so
  its remaining job is keeping contract-owned data honest: a privileged group added to `modes.nix`
  would otherwise reach every account in that mode with no grant.

## Modes

- **mode** — the **session shape a home is BUILT for** (`cli`, `gui`) and, on the host side, a
  **capability of the machine**. Those are one vocabulary because they are one question asked from
  two ends: *can this box run a graphical session?* and *was this home built for one?* Exactly one
  mode per home, and no bind can change it. Declared in `modes.nix`.
- **the registries touch nowhere** — a mode used to name the feature a host afforded in order to run
  it, which laundered a machine capability through a per-user policy namespace. A host declares its
  modes directly now, so no value crosses between `modes.nix` and `features.nix`.
- **mode groups** — groups an account needs in order to RUN a session shape (a graphical session's
  input devices). They ride the **selected mode**, not a grant, because needing them is a property
  of running that session rather than a judgement about who is running it. Non-privileged by
  construction, and `accountPlan` filters them anyway — see [[privileged-group filter]].
- **floor** — the one mode every host runs and every selection falls back to (`cli`). Carried as a
  registry **flag**, not a rank: a future `mobile` is incomparable with `gui`, not below it. Exactly
  one mode carries it; zero or two is a named error.
- **mode parameters** — a mode's own knobs, declared beside it in `modes.nix` and appearing on
  `contract.<mode>` in a user's declaration. Today: `gui.desktop`. Parameters live on the thing they
  parameterise, so there is no second namespace to keep in step.
- **runs** — the modes a host runs: the floor, plus whatever `contract.modes` declares
  (`runsWith`). It **filters the registry** rather than concatenating the declaration, which makes
  the declaration a SET rather than a sequence — order and duplicates wash out, a redundantly
  written floor collapses, and there is no spelling that excludes the floor.
- **fail-closed, and deliberately the opposite default to the home matrix** — a host enumerates what
  it runs, because the risk of the unknown here is *admitting* something (a box claiming a display
  it lacks). A matrix row subtracts, because there the risk is *omitting* (a home nobody built).
- **selection** — `runs ∩ published`; a non-floor mode wins, the floor is the fallback, an empty
  intersection is a hard error naming both sides, and two non-floor modes is a hard error rather
  than an invented ordering. Both the declarative bind and the greeter select through the same
  kernel.

## The user declaration

- **declaration** — `users/<u>/user.nix`, the whole of what a user says:
  `contract.<mode> = { enable; configuration; <that mode's parameters> }`. It is **not** a
  home-manager module: it is evaluated by bare `evalModules`, which is what lets a producer — and a
  greeter, over the published index — learn a user's modes without building anything.
- **configuration** — the home-manager module a mode's declaration points at, a `deferredModule` so
  reading the declaration never forces it. Two modes may name one module (the common case) or two
  (when the content genuinely differs).
- **enabled modes** — the declaration's enabled-name projection, and the only shape anything
  downstream consumes. Nothing defaults to enabled; a user enabling none is a named error, because a
  default would set a user's essential nature without the user having said anything.
- **the user has no feature voice** — which powers an account holds is the host's decision alone. A
  user-side veto would be a second authority over one value with nothing forcing the two to agree,
  and the refusal a user actually needs — *never give me a desktop* — is already expressible by not
  enabling the gui mode.

## Grants and confinement

- **affordance** — what a host is willing to confer on **one** user, stated as an argument to
  `bindContractUser`. It rides the bind, at the site that already names the user, so per-user
  variation needs no second mechanism and there is no host-wide default to inherit. It is
  *policy about a person* — never a fact about the machine, which is `contract.modes`.
- **grant** — what that user therefore holds, conferred on the **account at activation**. On the
  declarative path the grant *is* the affordance; at a greeter the affordance is the safe set. A
  grant can never change a **home**.
- **granted** — a grant seen as an *option path* (`contract.users.<u>.granted`), never an argument.
- **deny** — the *absence* of a grant. There is no active block anywhere in the contract.
- **realization** — the host-invariant map from `contract.users.<u>` to a system account, via the
  shared **account plan**. It also derives the one neutral display fact a host's display binding
  reads.
- **account plan** — the single pure `(identity, grants, mode) → account record`. TWO group sources
  meet in one union with one owner: what the MODE needs ∪ what the GRANT confers. There is no third
  — an account's groups are always decisions somebody else made. `realization.nix` renders it into `users.users` at build time; the greeter's
  `provision` renders the same record at login, so the two adapters cannot drift.
- **display surface** — `contract.display.enabled`, derived from the `display` flag on the modes
  this MACHINE runs. It follows the box, not its users: a seat has one before anybody is bound,
  which is what a greeter needs.
- **confinement** — a user's home is a home-manager module with **no system channel**: `users.users`,
  `security.sudo`, `boot.*`, `sops.*` are *unexpressible*, not merely rejected. Privilege escalation
  is impossible because the vocabulary to ask for it does not exist.

## Secrets

The contract handles **no secrets beyond the login credential**. `identity.json` carries a public
identity and a one-way `hashedPassword`; a user's own home secrets ride the user's own key,
provisioned by the user's own home module.

- **credential posture** — how strong a repo requires its `hashedPassword` hashes to be. Consumer-
  owned and opt-in (`mkIdentityPostureCheck { require = … }`), because a private repo may
  legitimately ship `$6$` while a public one needs memory-hard `$y$`. The loader imposes none.

## Hosts and trust

- **seat** — a host with a display, which is the kind that runs a greeter.
- **exposed** — a plain host fact an operator records (`contract.exposed`); the contract enforces
  nothing on it.
- **incapacity, not a ban** — a headless host does not *refuse* a desktop, it *cannot* run one. That
  distinction is what separates `contract.modes` from `affordances`, and it is why a host that
  declares no gui mode is not "denying" anybody anything.
- **tier** — the trust classification a seat binds a walk-up repo at. `tier1` (semi-trusted: signed
  by a host-trusted key, home persisted, restricted eval) is built; `tier2` (untrusted, ephemeral)
  is designed-for and deferred, and refused by name rather than silently downgraded.
- **Tier-1 eval posture** — the canonical `NIX_CONFIG` a greeter hands the home builder:
  `accept-flake-config = false` (the un-widenable linchpin — a repo cannot self-certify its own
  eval), `restrict-eval`, no IFD, sandboxed build. A host may add restrictions, never remove them.

## The greeter and binding

- **greeter** — the reference runtime login path: prompt → archive the flake → **authenticate
  eval-free** on `identity.json` → select the mode → build that home through the host's
  `homeBuilder` binding → provision the account → launch the session. Opt-in per seat; replaceable,
  as long as a replacement honours the ordering and confers at most the safe set. What it *offers*
  is the machine's own `contract.modes`, frozen to a store file at build time — so a seat without a
  display no longer claims to run a graphical session, which a contract-level constant did.
- **data before code** — authenticate on inert data before any of the user's Nix is evaluated. Eval
  is not a sandbox.
- **homeBuilder** — the host binding invoked as `homeBuilder <src> <username> <mode>`. The **mode is
  the greeter's answer**, not the binding's: a seat never hardcodes one.
- **provision** — the runtime, shell-side equivalent of the realization: it fully realizes the
  account from `identity.json` plus the safe-set grant, so a greeter user realizes identically to a
  build-time one — modulo the `greeter-users` seat marker, which is seat infrastructure rather than
  part of the portable account.
- **binding index** — `contractUsers.<system>.<user> = { identity; modes; contractPackages }`, plain
  data. A host selects by *reading* it, never by building every home to inspect a manifest; a
  greeter reads `modes` off it with one cheap `nix eval`.
- **source** — whatever publishes that index. Usually a pinned users flake, but nothing requires a
  flake (the conformance suite hands plain attrsets), which is why the argument is not
  `usersFlake`. It is per-user with a top-level default, so one host can bind across repos.
- **the index key and the identity are ONE answer** — a host binds by the key and gets an account
  named by `identity.username`; the producer refuses to publish a user where the two disagree. The
  name a host writes therefore does SELECTION, never naming.
- **contractPackage** — what a producer publishes per home: the activation script plus a
  `contract-manifest.json` sidecar freezing `{ version, username, packages, mode }`.
- **coupling guard** — a host may activate a home only if it actually runs the mode that home was
  built for. Selection satisfies it by construction; the guard covers the internal kernel path.
- **matrix subtraction guard** — a mode this host runs and this user runs in, which this system's
  home matrix took away, is a disagreement with no home to bind. Without it, selection would quietly
  fall back to the floor and activate a terminal home on a graphical seat with no message at all.

## The producer surface

- **member** — one user in a users repo, resolved once: `{ name; dir; identity; declaration }`. It
  is what everything downstream takes, so no path is re-derived and no file is read twice.
- **member set** — `mkMembers { usersDir }`, the contract's one answer to *who is in this users repo
  and what does each one say*. A directory holding no member at all is a named error, never an empty
  set that bakes nothing while every output stays green.
- **home matrix** — `mkHomeMatrix { systems }`: which modes each system bakes. Declared as
  **subtraction** — a row names only what its seats CANNOT run — because an under-bake is silent and
  an omitted mode must therefore default to baked. A contract that gains a mode bakes it everywhere
  with no consumer edit.
- **row** vs **modes** — a **row** is what a fleet *declares* into `mkHomeMatrix`
  (`{ <mode> = bool; }`); **modes** is what it *returns* (`[ <mode> ]`). They sit either side of one
  function; a consumer never writes what the fold reads.
- **home** — one built home, identified by its mode: `homes.<system>.<user>.<mode>`. What a greeter
  builds against, and what a consumer's checks read.
- **CLI adapter** — `homeConfigurations.<user>-<mode>`, the flat shape home-manager's own CLI
  resolves, returned by the producer over the same homes. Nothing in the contract reads it: a host
  binds through the binding index and a greeter builds `homes`. The flat naming is not a fleet's
  choice — home-manager quotes the fragment before it reaches Nix, so no nested spelling resolves —
  and being *external and identical for every users repo* is precisely why it has one owner rather
  than a fold per repo.
- **default system** — which system the CLI adapter publishes on (`defaultSystem`). The one thing
  the adapter cannot derive, because a CLI fragment carries a user and a mode and has nowhere to put
  a third. A fleet baking for one system is not asked; a multi-system fleet that stays silent is
  refused when the adapter is read, never before.
- **publication** — a system's row ∩ the modes the user runs in. The fold intersects *before* it
  builds, so a home nobody could bind is never built. A system baking none of a user's modes
  publishes an empty index entry there rather than refusing: the matrix is fail-**open** on
  coverage, and the refusal belongs at the bind, where both sides can be named.
- **hostFacts** — the whole of what a home is told: `{ mode; platform; exposed }`. `granted` is
  deliberately absent — no grant can affect a home, so showing one the grant set would be showing it
  something it must not use.

## Program scope and package policy

The contract governs **system effects** (privilege, services, groups). **Program scope** — which
applications a user runs — is the user's own concern, and advisory whenever daemon access is
present.

- **package policy** — `contract.packagePolicy.allowedPrograms`: after activation, the host
  replaces `~/.nix-profile` with the intersection of that list and the user's manifest packages.
  Meaningful for a **daemon-restricted** user (no `nix-daemon` grant), for whom that profile is the
  only store they can reach.

## Testing

- **conformance suite** — the contract's own synthetic proof: adversarial worlds probing the
  decision logic (the filter DROPS, the guard FIRES), with no host repo and no home-manager.
- **reference implementations** — `examples/users` and `examples/fleet`: the positive space a
  consumer copies, and where home-manager actually lives. The synthetic suite borrows real atoms
  from them, **never the reverse**.
- **check kit** — `check-kit.nix`: the proofs a CONSUMER runs over its OWN repo
  (`mkConfinementCheck`, `mkIdentityPostureCheck`, `mkHomeEvalCheck`, and `mkMemberChecks` folding
  the three over a member set), plus `mkClaimReport` and `mkProofPrelude`, which prove nothing and
  own how a suite REPORTS what it found. A third thing beside the two above: the contract ships the
  **technique**, never the verdict, because the material — a repo's real imports, identities and
  homes — is on the far side of the boundary ([0025](docs/adr/0025-consumer-check-kit.md)).
- **seat harness** — the seat-host scaffolding the conformance suite owns (boot base, greeter
  preamble, greetd wiring) plus the fixtures a seat test varies against, so a runtime proof is a
  record of what it VARIES. Published as the `testing.mkSeatHarness` output. The THIRD surface
  beside `lib` and the check kit, and the one that hands over a MACHINE rather than a function or a
  technique — it boots a seat; the claim stays the caller's. Named at the flake surface because its
  one consumer outside the suite (the reference fleet's end-to-end greeter test) must not read the
  oracle's file layout ([0022](docs/adr/0022-oracle-and-reference-fleets.md)).
- **claim report** — a suite's own output, through `mkClaimReport`: named claims rendered
  `ok`/`FAIL`, execution proofs threaded in as build inputs, non-zero exit if anything failed. Two
  KINDS of claim — an **eval claim** (`{ name; ok; }`, a boolean already decided) and an **execution
  proof** (a derivation whose being built IS the verdict, for a claim only answerable from realized
  content).
- **proof prelude** — `mkProofPrelude "<proof name>"`, the shell side of the same ownership: the
  `fail <message>` an execution proof opens its builder with, which names the proof it speaks for.
  A report decides at eval; a proof decides in shell, and both decisions have one owner.
- **positive control** — the legitimate case a negative check must still ACCEPT. Without it a
  harness that rejects everything reads as a passing check. Asserted before the negative claim, so
  a broken harness is reported as one.
- **anti-vacuity** — a fold over nothing produces nothing and reports success, so the failure is
  invisible. Every empty-input case in this repo is a hard error, and every negative claim carries a
  positive control.

## Terms to keep distinct

- **`contract.modes`** (what the MACHINE can run — a capability) vs **`affordances`** (what a PERSON
  may do — a policy). Never call a mode an affordance, and never say a host "grants gui": it runs
  the gui mode, and the mode carries its own groups.
- **affordance** (what a host is willing to confer) vs **grant** (what an account holds) vs
  **granted** (the option path). One word, one type; do not introduce a third spelling.
- **deny** is the *absence of a grant*, never a "veto" or a default-open block.
- **ban / prohibition** is reserved for a real security *rule*. A headless host lacking a greeter is
  **incapacity**, not a ban.
- **mode** vs **grant** — a mode is what a home IS; a grant is what a host confers on an account at
  activation. A grant can never change a home; a bind can never change a mode. Never say "the gui
  grant" when you mean the gui mode, and never call the mode set a grant set.
- **mode** is one word for one value: the matrix row, the builder's argument, the published key, the
  manifest field and `hostFacts.mode`.
- **declaration** (what a user says, in `user.nix`) vs **configuration** (the home-manager module a
  mode points at). The first is read as data; the second is built.
- **desktop** vs **session type** — **desktop** (`contract.gui.desktop`) is the user's intent, an
  experience that travels with the identity, and the only thing the contract carries. **Session
  type** (`wayland`/`x11`) is not a contract concern at all: the seat's launch command owns it.
- **user secret** is ambiguous on its own — say *public identity*, *hashedPassword*, or *feature
  secret* (and note the contract handles only the first two).
- **program scope vs system effects** — do not conflate "the host decides feature grants" with "the
  host decides what programs can run."
- **member set vs home matrix** — the member set answers *who is in this users repo*; the home
  matrix answers *which modes this fleet bakes, per system*. Never let a hand-listed set of names
  stand in for either.
- **bake is a verb, and only a verb** — "fails the bake", "baked under". The object is a **home**,
  or once published a **contractPackage**.
- **`contractPackage` vs `activationPackage`** — `contractPackage` is the contract-level
  content-addressed flake output (activation + manifest sidecar); `activationPackage` is
  home-manager's own term for the derivation that activates the home. `contractPackage` wraps it.
- **the contract version** — ONE number (`version.nix`, owned by release-please). It is the repo's
  release version *and* what a manifest declares *and* what `readManifest` refuses a mismatch on.
  There is no separate "wire format" version: a counter over the manifest's field set would gate
  only those fields, while the producer↔consumer agreement is also the activation, the account plan
  and the mode groups ([0024](docs/adr/0024-versioned-releases.md)). Say **the contract version**,
  never "the manifest version" or "the release version" as if they were different things.
- **compatibility line** — a version's leftmost non-zero component (`1.9.3` → `1`; `0.3.9` → `0.3`),
  the part a BREAKING change moves. Two versions are compatible exactly when their lines match, so a
  published package keeps binding until a **major** release. Say *compatible* / *incompatible*, never
  "same version": an older release on the line is accepted, and that is the guarantee.
- **an incompatible version is a refusal, not a warning** — a manifest off this contract's line is a
  hard, named error. There is no migration path and no advisory mode: a major release moved the
  agreement, and a bind would assemble an account against realization code the home was never built
  for. `users.inputs.contract.follows = "contract"` sidesteps it — both sides become one contract.

## Load-bearing invariants

- The contract **depends only on nixpkgs `lib`** — no `self`, no `inputs`, no secrets backend, no
  package, and **no home-manager**. Every home-manager-shaped thing arrives by injection.
- **The user controls their own nixpkgs pin**: the home is baked by the producer, so there is no
  one-nixpkgs constraint.
- **Privilege is build-time-only.** A greeter confers the safe set and nothing else, and the safe
  set is derived from the registry rather than maintained. It is currently empty, so a greeter
  confers nothing at all.
- **A machine capability is not a power.** What a box can run is declared once for the box; what a
  person may do is decided at the bind that names them. Nothing has to agree between the two,
  because they answer different questions.
- **A grant rides the bind and can never change a home**; **a mode is what a home IS and no bind can
  change it.**
- **The user's declaration is typed and carries no freeform**, so a misspelled mode or parameter is
  an eval error in the user's own repo rather than a user nothing can bind.
- **A user can only see what it may vary on** — a home is handed the mode it was built for and no
  grant at all.
- **Data before code** — authenticate on `identity.json` before evaluating any user Nix.
- **A missing check reads exactly like a passing one**, so nothing is allowed to fold over nothing.
