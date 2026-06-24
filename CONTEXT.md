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
  `lib` (the functions), and a data surface (`features`, `featureMeta`, `featureGroups`,
  `privilegedGroups`, `safeSet`). Neither host nor user. (ADR-0015, ADR-0020)
- **host** — a machine config that imports the contract, materializes user accounts,
  **grants** features, and supplies **bindings**. Sovereign: it runs only what it grants.
- **user** — a public identity + home config + the features it *offers*; host-agnostic (it
  never names a secrets backend or a host's `self`/inputs). Target shape: a home-manager
  config repo consumed via `bindUser` (ADR-0023); today still in-repo in the fleet.
- **umbrella / kit** — the assembled shipped surface (`kit.nix`). `nixosModules.default` =
  the `custom.users` schema + `platform` interface + `custom.host.exposed` + the
  exposed-host ban + realization + the insecure-package aggregator. `nixosModules.greeter` =
  the opt-in reference runtime greeter (a seat host enables it). `homeModules.default` =
  identity + home profiles + the `platform` interface.
- **mechanism vs binding** — the contract ships generic **mechanism**; the host supplies
  only **bindings** (the `platform` secrets binding, the display/theme, *which* hosts, the
  trust-tier policy). The split keeps every fleet from re-implementing — and drifting on —
  the security-critical parts. (ADR-0024)

## Features and the registry

- **feature** — one entry in the registry: the unit of capability a host grants or denies,
  and the shared name "deny" keys on. Per-entry fields: `grant`, `groups`, `secretBearing`,
  `secretFiles`, `execPayload`, `config`. (`features.nix`)
- **registry** — `features.nix`, the **single source of truth** for the feature vocabulary.
- **projection** — any surface *derived* from the registry (`featureMeta`, `featureGroups`,
  `grantedOptions`, `featureConfigOptions`, `safeSet`, the sops recipients). Keys can't
  drift across projections because there is one set of keys. (`kit.nix`)
- **offer** — *implicit*: a user emitting a `contract.requests` entry for a feature is
  offering it. No formal `offers` field exists until the separate-repo future needs one. (ADR-0018)

## Grants and confinement

- **grant** — a host's decision to enable a feature for a user
  (`custom.users.<u>.granted.<f>.enable`). **Host-write-only**, and the *only* source of
  privilege. (ADR-0015 mechanic 2)
- **deny** — the **absence of a grant**. Not a veto, not a default-open block — a host runs
  only what it explicitly grants.
- **feature configuration** *(a feature's **parameters**)* — the **host-owned** parameters the
  realization consumes (`custom.users.<u>.<feature>.*`, e.g. `gui.session`), distinct from the
  grant (the yes/no). The **consumer** end of a producer→consumer pair with **request**:
  written only host-side — operator grant-data, or `bindUser` bridging a granted request —
  **never** by the user across the trust boundary. Host-affecting parameters **aggregate**
  across granted users. (ADR-0019, `featureConfigOptions`)
- **request** / **`contract.requests`** — the **user's** voice: the home-side namespace a
  user's home module *emits* (read-only data inside home-manager's sandbox) to ask for a
  feature's parameters. The **producer** end of the pair with **feature configuration**:
  `bindUser` harvests it post-eval and bridges only the **granted** ones into the system-side
  feature configuration the realization reads. A request *names* a host effect but never
  performs it; the user never writes system-side. (ADR-0018, ADR-0023; `homeModules.default`)
- **realization** — the host-invariant module mapping each `custom.users.<u>` to a
  `users.users` account. Powers route through *grants*, not raw identity. (`realization.nix`,
  ADR-0015 mechanic 5)
- **clamp** — the realization filtering privileged groups out of a user's self-declared
  `identity.extraGroups` (untrusted input). Privileged groups come only from a grant — a
  user can never self-escalate by listing `docker`/`wheel` in its identity.
- **gui-session union** — the realization deriving the host's display surface
  (`custom.gui.surface`) as the union of every granted gui user's `gui.session`, so a
  Wayland user and an X11 user coexist on one seat. (ADR-0019)
- **model A / B / C** — trust postures for the user surface (ADR-0015 mechanic 7): A = user
  exports arbitrary modules (in-repo migration only; "deny" cosmetic); B = flat data only
  (deny enforceable, expressiveness lost); C = restricted `evalModules` over a curated
  catalog — the old target, **superseded** by the request channel (home-manager *is* a
  restricted universe, so no catalog). (ADR-0018)

## Secrets and the platform

- **platform — interface vs binding** — the backend-neutral secret-provisioning seam
  (`platform.nix`). A feature declares a *logical* secret and reads a resolved **runtime
  path**; the host **binding** owns the backend (sops/agenix) and is the only place a
  backend is named. The contract ships the **interface**; the host supplies the **binding**.
  (ADR-0021)
- **secret-bearing** — a feature that pulls a secret onto a host (`secretBearing = true`).
  Excluded from the safe set; an exposed host may not be granted it.
- **user secret (three tiers)** — *public identity* (`authorizedKeys`, name, email,
  username — not secret); *`hashedPassword`* (a one-way hash; handling depends on repo
  visibility); *feature secrets* (the real secrets — private keys, tokens). Keep these
  distinct; "user secret" alone is ambiguous. (ADR-0015 mechanic 1)
- **recipients-from-grants** — `mkFeatureRecipients`: for each secret-bearing feature's sops
  file, the set of hosts that *grant* it — the single source of truth for `.sops.yaml`
  recipients, making recipients ≡ grants. (`lib.nix`, ADR-0015)
- **revocation = remove recipient + rotate** — un-granting a secret-bearing feature is not
  enough: a host that ever held it saw cleartext, so revocation removes the host as a sops
  recipient **and** rotates the secret. (ADR-0015 threat model)

## Hosts and trust

- **exposed host / the exposed-host ban** — a host marked `custom.host.exposed` (an
  agent/code-executing or otherwise exposed box) may not be granted *any* secret-bearing
  feature; enforced as a NixOS assertion (`exposedHostOffenders`). The hosts most likely to
  be compromised then hold no cleartext. (ADR-0015 threat model)
- **incapacity vs prohibition** — a *headless* host has no greeter because it has no display:
  **incapacity**, not a ban. **Prohibition** (the exposed-host rule) is the security verb;
  don't model "no screen" as a ban or you dilute the one word that carries security weight.
  (ADR-0018)
- **hostFacts** — the restricted, read-only, **self-scoped** projection of host state a
  user's home module may read: `{ exposed, platform, granted }`. Deliberately excludes
  `hostName` so adaptation keys on *semantic* facts, not host identity. (`mkHostFacts`,
  ADR-0018)

## The greeter and binding

- **build-time binding vs runtime binding** — two paths over one contract. Build-time =
  operator-authored fleet declaration, **default-closed**. Runtime = the **greeter**,
  **default-open over the safe set**. Opposite defaults, *one* mechanism (`bindUserModule`).
  (ADR-0018, ADR-0022)
- **bindUser** — binding a user's home module to the contract: inject `identity` (single
  loader, ADR-0025) + `hostFacts`, evaluate the home, and **bridge** the granted
  `contract.requests` into the system-side feature configuration. It ships in **two shapes**,
  both in `self.lib`:
  - **`bindUserModule`** — the **real mechanism both binding paths call** (operator grant +
    greeter): a NixOS module the host imports. The home is evaluated **once** by the host's
    home-manager and the bridge is a **config reference**
    (`config.home-manager.users.<u>.contract.requests`), so a real home-manager home
    (`programs.*`, `home.*`) binds. The host supplies home-manager; the contract only
    *references* its option paths, staying package-free (ADR-0020). **(built — issue #8)**
  - **`bindUser`** — the **headless tracer**: the package-purest proof of the same
    request→grant→bridge logic, harvesting a *contract-pure* home via bare `evalModules` (no
    home-manager, not even a stub). Returns a record (`{ system, home, requests, … }`) for
    eval testing. **(built — issue #5)**

  The greeter program that drives `bindUserModule` at runtime is issue #2. (ADR-0023, ADR-0024,
  ADR-0025)
- **portable user** — the runtime north star: the *same* identity logs into *any* contract
  seat and gets the **exact same experience** — home config **and** allowed system-side options —
  with host and user mediated only by the contract. This is *why* the greeter must **fully
  realize** both the home and the allowed system options **before** login, identically on every
  seat (ADR-0028); the safe set being contract-defined and the greeter-seat baseline being uniform
  are what make "same experience everywhere" hold. (ADR-0018, ADR-0022, ADR-0026, ADR-0028)
- **greeter** — the runtime path: a seat host's greetd flow that fetches a user flake,
  authenticates **eval-free** on `identity.json`, classifies the tier, binds with
  `grants = greeterGrants`, builds, and provisions the account. Ships as the opt-in, replaceable
  `nixosModules.greeter` (`greeter.nix`) — `nixosModules` is split `default` (every host) +
  `greeter` (a seat host enables it). The project's north star. **(built — issue #2)** (ADR-0018,
  ADR-0022, ADR-0024)
- **greeter mechanism vs program** — ADR-0024's split, what makes `nixosModules.greeter` both
  canonical and replaceable. **Mandatory mechanism** (pure `lib`/module, no package): authenticate
  **eval-free** on `identity.json` before any user Nix, bind via the contract, grant at most the
  `safeSet`. **Replaceable program** (where packages live): the greetd integration, the UI, and the
  runtime-provisioning helper. The reference module ships scripts that reference packages from the
  **host's** `pkgs`, so the contract *flake* still inputs only nixpkgs `lib` (ADR-0020) — the one
  place a package is allowed without breaking the package-free invariant.
- **contract-greeter-{bind,auth,provision}** — the reference greeter's three scripts. `auth` is
  the **canonical eval-free** step (`jq` over `identity.json` + libc-crypt password + Tier-1 SSH
  signature, running zero user Nix); `provision` is the **runtime-provisioning helper** — the
  privileged crux that is the **shell-side `realization.nix`** for one user: it fully realizes the
  account from `identity.json` + the safe-set grant (password, `authorizedKeys`, GECOS, the
  **clamped** safe groups + the greeter-seat baseline) **and** activates the built home AS the
  user, all before the session starts, outside NixOS's declarative build-time model; `bind` is the
  greetd orchestrator tying the ordering together. (`greeter.nix`; ADR-0022, ADR-0028)
- **homeBuilder** — the greeter's one **host binding** (`custom.greeter.homeBuilder`, null by
  default): the command that evaluates + builds a user's home *through the contract* under the
  [[tier1-eval-posture]] and prints the activation package. It is host-side because building a real
  home needs home-manager, which the contract does not depend on — exactly as the platform/display
  bindings are host-side. The greeter hands it the posture as `NIX_CONFIG`, so a naive `nix build`
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
  time; its real-seat form is the `nix build "$src#…activationPackage"` one-liner. (issue #2; ADR-0022)
- **greeter-secret-provisioning** — how a roaming Tier-1 user gets their **own home secrets** back at a
  greeter, which holds a **password, not a key** (issue #4, ADR-0031). It is ONE seam — "make the user's
  age identity available to home activation for the session" — so every strength is a different SOURCE
  feeding the same unlock + placement path (`contract-greeter-unlock` → `provision` writes the key to
  `~/.config/sops/age/keys.txt` before activation, so the user's sops decrypt). Sources:
  **(a) passphrase** (issue #10, BUILT): a passphrase-wrapped age key in the repo (openssl AES-256-CBC +
  PBKDF2 + a magic header; a SEPARATE unlock passphrase by default). **(b) escrow** (issue #11): the
  wrapped key lives on the user's server, fetched after a **phone** approval — the fetch is a **host-bound
  `keyFetcher` command** (the contract ships the seam, not the wire protocol, exactly like [[homeBuilder]];
  the request/poll HTTP loop is the **reference example**, #13, which composes **OpenBao** one-time
  wrapping + **ntfy** push, approval = number-match (default) / tap / passkey). **FIDO2/YubiKey** stays
  **on-demand only** (issue #12). Hard gates, any source: **Tier-1 only**, **trusted (non-[[exposed]]) seat
  only** (the seat sees the plaintext while it activates the home — ADR-0015), never Tier-2 — refused in
  `bind` and as eval assertions. Escrow **fails closed on secrets**: server unreachable ⇒ degrade to a
  secret-free session (never blocks the login; can't leak), **no in-repo passphrase fallback** (that would
  be a downgrade attack), optional `requireSecrets` to hard-fail for workloads that must not run
  secret-free. Distinct from contract secret-features (`signing`), which stay build-time via the
  [[safe-set]]. Tested without a real phone: the [[bind-loop]] VM proves passphrase end-to-end, and a stub
  release server + a keypair-controlled challenge-signer proves the escrow gate. (issues #4/#10/#11/#13; ADR-0031)
- **tier1-eval-posture** — the **contract-pinned** Nix settings a host-signed home is evaluated +
  built under (`tier1EvalConfig`, a projection beside [[safe-set]]/[[greeterGrants]]; ADR-0030):
  `accept-flake-config = false` (**the un-widenable linchpin** — the repo's own `nixConfig` is
  ignored, so it cannot relax its own eval; ADR-0027 applied to eval), `restrict-eval`, no IFD, and
  a sandboxed build. The greeter renders it (contract's own `renderNixConfig`) and exports it as
  `NIX_CONFIG` to [[homeBuilder]]; it augments the seat's `nix.conf` (experimental-features survive)
  and a host may **add** restrictions, never remove these. `restrict-eval` is coherent because the
  fetch step is `nix flake archive` (source **+ input closure**), so the restricted build needs no
  eval-time network. Exposed read-only as `custom.greeter.tier1EvalConfig` for audit. Proven in
  conformance both by eval assertions and by an **executable** proof (the rendered posture actually
  blocks a hostile `readFile`; the same eval succeeds without it). Tier 2 will pin a stricter
  posture; deferred. (ADR-0027, ADR-0030; `lib.nix`, `greeter.nix`)
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
  desktop), where greetd serializes `seat0` so logins never overlap. (ADR-0022, ADR-0024)
- **desktop choice** — which DESKTOP (GNOME, Plasma, a WM…) a greeter user logs into, chosen
  **per user** (ADR-0029). The user carries a **free-form** name in their home
  (`contract.requests.gui.desktop`) so it travels with the identity — same desktop on any seat that
  offers it (the [[portable-user]] north star); the **seat offers** desktops as a host binding
  (`custom.greeter.desktops.<name> = { type; command; }`, reusing each DE's session-entry Exec, like
  a display manager). The greeter resolves the user's name against the offered set and launches it
  via greetd-as-user (a full DE needs that seat session); an un-offered name degrades to
  `defaultDesktop`. DE-agnostic: the contract carries an opaque name, the seat maps it. The choice
  is **auto-surfaced** to `~/.contract-desktop` by `homeModules.greeterDesktop` — a SEPARATE home
  module from `homeModules.default` (it sets `home.file`, a home-manager option, so the default
  umbrella stays tracer-pure / home-manager-free; a real home imports both). Inert when no desktop
  is requested ⇒ the seat default. (ADR-0029; `features.nix`, `greeter.nix`, `modules.nix`)
- **safe set** — the features a runtime/greeter login may auto-grant: the **runtime-eligible**
  ones. `safeSet = ["gui"]` today. (`lib.nix`)
- **greeterGrants** — the **canonical runtime grant value** (`self.greeterGrants`): the safe set
  lifted into a grant attrset (`{ <feature>.enable = true; }`), i.e. **default-open over the
  safe set**. The greeter binds with it (`bindUserModule { grants = greeterGrants; }`); it is
  ADR-0024's conformance condition (3) — *a greeter grants at most the safe set* — made a
  single-sourced value, so escalation is impossible by construction, not by a deny rule.
  (`lib.nix`; ADR-0022, ADR-0024)
- **runtime-eligible** — *derived*, not declared (`runtimeEligibleFeature`): a feature is in
  the safe set iff it bears no secret, confers no privileged group, **and** carries no exec
  payload. Deriving it keeps "what a stranger may have" tied to "what confers no privilege."
- **tier (Tier 1 / Tier 2)** — the greeter's trust classification of a flake URL. Tier 1 =
  semi-trusted (own, *signed* repo; persisted home; the [[tier1-eval-posture]] guarding accidents) —
  built first. Tier 2 = untrusted (anyone; hardened eval; ephemeral home) — designed-for,
  deferred. A tier is a *parameter* over one mechanism, not a separate code path. (ADR-0022)
- **trustedSigners vs trustedKeys** — two different key sets, kept distinct (ADR-0027).
  **`trustedSigners`** (`custom.greeter.trustedSigners`, host-pinned) is the **sole Tier-1
  signing authority**: a repo is Tier 1 iff its `contract.sig` verifies against an
  *operator-pinned* key. **`trustedKeys`** (in the user's `identity.json`) is the user's SSH
  **login** keys (→ `authorizedKeys`, `realization.nix`). A repo signing with a key it lists in
  its own `identity.json` proves nothing about *host* trust — so tier classification consults the
  host set only; a repo cannot self-certify its tier. (ADR-0027; `greeter.nix`, `realization.nix`)
- **identity.json** — the contract-conventional **data** file (not Nix) carrying a user's
  public identity. The greeter authenticates against it with `jq` **before** evaluating any
  user Nix (**data before code** — eval is not a sandbox). The contract owns the schema and
  ships `loadIdentity`, a lossless loader whose schema is **projected from `identity.nix`**
  (the single identity source). (ADR-0022, ADR-0023; `identity-json.nix`)
- **inert payload vs exec payload** — a request payload the host merely *reads* (the
  `session` enum) is **inert**; one the host *executes with privilege* (a `kanata-with-cmd`
  keymap running shell) is an **exec payload** (`execPayload = true`) — a code-exec vector,
  never safe-set-eligible, build-time-only. No feature sets it yet. (ADR-0018, issue #3)

## Testing

- **conformance suite** — the contract's own tests (`conformance/`): synthetic users × the
  umbrella, no host repo. **Eval** (`default.nix`) proves grant/deny, the gui-union
  *decision*, the clamp, the exposed-host ban, the safe set, and the users × archetypes
  matrix; the **VM** (`vm.nix`, a `runNixOSTest` boot) proves the gui-union *renders* — two
  gui users with different sessions, both plasma session files live, both accounts realized.
- **coherence gate** — the thin host-side check (in the fleet) that every real host's
  trait-tuple is archetype-covered and the real manifest realizes — the fleet's tie-back to
  the contract suite. (ADR-0020)

## Terms to keep distinct

- **deny** is the *absence of a grant*, never a "veto" or a default-open block.
- **ban** is only for **prohibition** (the exposed-host rule). A headless host lacking a
  greeter is **incapacity**, not a ban.
- a feature's **grant** (the yes/no) vs its **configuration / parameters** (the knobs):
  never call configuration a "grant."
- **request** (user-emitted, home-side) and **feature configuration** (host-owned,
  system-side) are a **producer→consumer pair**, *not* interchangeable: the user writes a
  request, `bindUser` bridges granted ones into feature configuration, the realization reads
  feature configuration. Same shape, different owner and trust-side — never call a user's
  request "feature configuration," or a host-written value a "request."
- **platform** names the secret-provisioning **interface**; don't conflate the interface
  (contract) with the **binding** (host).
- **user secret** is ambiguous on its own — say *public identity*, *hashedPassword*, or
  *feature secret*.

## Load-bearing invariants

- The contract **depends only on nixpkgs `lib`** — no `self`, no `inputs`, no secrets
  backend, no package. (ADR-0020; the extraction litmus test)
- **One nixpkgs**: a user pins `inputs.nixpkgs.follows` to the host's — no second nixpkgs.
- **Privilege is build-time-only**; the runtime greeter confers only the safe set.
- **A request names a host effect but never performs it** — the host writes, only on grant.
- **Data before code** — authenticate on `identity.json` before evaluating any user Nix.
