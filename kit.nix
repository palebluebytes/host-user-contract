# The contract kit — a pure function of nixpkgs `lib` that ASSEMBLES the contract from
# the registry: it computes the registry's projections (the data), then wires the
# derivation logic (./lib.nix) and the umbrella modules (./modules.nix) and returns the
# public surface. It depends on NOTHING but `lib` — no `self`, no `inputs` — which is
# what lets the contract be a standalone flake (./flake.nix wraps this). The host
# supplies only the `platform` binding and the package/display bindings (ADR-0004).
{ lib }:
let
  registry = import ./features.nix { inherit lib; };
  # The MODE registry (ADR-0032) — the second single source beside the feature one. It takes no
  # arguments: a mode entry is a description, an optional grant NAME and a flag, so unlike a
  # feature it declares no options of its own and has nothing to build them with.
  modeRegistry = import ./modes.nix;

  # --- projections of the single registry (the data) ---
  # Groups that are privilege-protected before any feature has been written to grant them.
  # Each entry here is a "todo": move it into a feature's `privilegedGroups` when the
  # feature is added rather than listing it here.
  reservedPrivilegedGroups = [ "kvm" ]; # no feature grants kvm yet
  privilegedGroups = lib.unique (
    lib.concatMap (f: f.privilegedGroups or [ ]) (lib.attrValues registry) ++ reservedPrivilegedGroups
  );
  featureGroups = lib.mapAttrs (_: f: (f.groups or [ ]) ++ (f.privilegedGroups or [ ])) (
    lib.filterAttrs (_: f: f ? groups || f ? privilegedGroups) registry
  );

  # The grant-projection helper set (issue #28, deepening candidate 04): the single owner of the
  # three folds every grant-reading site would otherwise re-derive — the granted-feature-names
  # projection, the grant→groups fold, and the privileged-group clamp. Computed once here (over the
  # featureGroups/privilegedGroups projections above) and injected into the realization and greeter
  # modules and the derivation logic (./lib.nix) exactly as featureGroups/privilegedGroups are, so
  # the security-critical clamp is single-sourced ahead of the account-plan work. No behaviour change.
  grantLib =
    let
      # Granted-feature-names projection: the enabled feature names in a grant attrset
      # `{ <feature> = bool; }` (the registry's grantedOptions shape).
      grantedNames = grants: lib.filter (f: grants.${f} or false) (lib.attrNames grants);
    in
    {
      inherit grantedNames;
      # grant→groups fold: the privileged + input groups the enabled features of a grant confer.
      # Takes a grant (the same shape grantedNames does), so both folds compose over one input.
      grantedGroups = grants: lib.concatMap (f: featureGroups.${f} or [ ]) (grantedNames grants);
      # Privileged-group clamp: self-declared groups with privileged ones filtered out (untrusted
      # input — a user can never escalate by listing a privileged group in its own identity).
      safeDeclared = declared: lib.filter (g: !lib.elem g privilegedGroups) declared;
    };
  # The grant option fragment: ONE BOOL PER FEATURE, `{ <feature> = bool; }`. The `.enable` suffix
  # it used to carry is gone (ADR-0032 §3) — it existed so four namespaces
  # (wants/affordances/granted/offer) shared one shape, not because a feature ever carried a second
  # flag. Parameters have their own namespace (`contract.requests.gui.desktop`), and ADR-0024 split
  # coarse roles into ATOMIC features rather than adding flags to one, so a word that never varied
  # across five features and four namespaces was ceremony. The four namespaces still share one
  # shape; the shape is simply a bool.
  grantedOptions = lib.mapAttrs (_: f: lib.mkEnableOption f.grant) registry;
  # The `contract.wants` option fragment (ADR-0028): the USER's voice, home-side — which features
  # this user asks a host for. DERIVED from grantedOptions so the two shapes can never drift (one
  # shape spans wants/affordances/granted/offer), with one change: each SAFE-SET feature defaults
  # to WANTED. Non-privileged features are wanted by default; privileged ones must be asked for —
  # ADR-0002's "one mechanism, opposite defaults" read from the user's side, and a future
  # non-privileged feature inherits it with no new special case.
  # The default is per-FEATURE, not a whole-submodule default: a home asking for `sudo` must not
  # thereby discard the safe-set default (a submodule default is replaced by any definition).
  # The description is re-worded rather than inherited: `grant`'s text names a HOST GRANT, and a
  # want is only ever an ASK (CONTEXT.md keeps the two words distinct).
  wantedOptions = lib.mapAttrs (
    name: opt:
    opt
    // {
      default = lib.elem name contractLib.safeSet;
      description = "Whether this user asks a host for the ${name} feature. An ask, never a grant: it is enabled only where the host also affords it (grant = affordances ∩ offer).";
    }
  ) grantedOptions;
  # The `contract.supports` option fragment (ADR-0032 §3): the user's OTHER voice — which MODES
  # this home can run in. One bool per mode, projected off the mode registry exactly as
  # grantedOptions is off the feature one, so a registry that gains a mode gains the option with no
  # edit here.
  #
  # NO DEFAULT SATISFIES THE RULE. Each mode defaults to `false` — the module system needs a value
  # to merge, and an undefined option would surface as a raw Nix error rather than one of the
  # contract's own — but nothing defaults to TRUE, so "supports at least one mode" is never
  # satisfied by inheritance. A user that says nothing supports nothing, and the bake refuses it by
  # name (`harvestVoice` in lib.nix). That is deliberate: a default that satisfied the rule would
  # set a user's essential nature without the user having said anything, and ADR-0006's "gui by
  # default" is a TEACHING convention (`supports.gui = true` in an ordinary home), not a value
  # written for anyone.
  supportsOptions = lib.mapAttrs (
    _: m: lib.mkEnableOption "${m.description} — whether this user's home can run in it"
  ) modeRegistry;
  featureConfigOptions = lib.foldl' lib.recursiveUpdate { } (
    map (f: f.config or { }) (lib.attrValues registry)
  );

  # The shared account plan (issue #30): the single pure `accountPlan (identity, grants) → account
  # record`, closed over grantLib so its clamp + grant→groups fold are single-sourced (issue #28).
  # `realization.nix` renders it into `users.users` at build time; the greeter's runtime provisioning
  # renders the same record to data (issue #31), so the two adapters cannot drift.
  inherit (import ./account-plan.nix { inherit lib grantLib; }) accountPlan;

  # --- closed-over modules + option fragments ---
  realization = import ./realization.nix { inherit accountPlan; };
  identityOptions = import ./identity.nix { inherit lib; };
  identityJson = import ./identity-json.nix { inherit lib identityOptions; };
  homeProfileOptions = import ./home-profiles.nix { inherit lib; };

  # The manifest module (ADR-0016, issue #27): the single owner of the `contract-requests.json`
  # schema — the seam `mkContractPackage` writes through and `bindContractPackage` reads through.
  manifest = import ./manifest.nix { inherit lib; };

  # The check kit (issues #35, #49): the proofs a CONSUMER runs over its own repo — its real
  # module set stays confined, its own members carry the credential posture it has chosen, and
  # everything it bakes evaluates. Lib-only and package-free like everything else here (each check
  # takes the caller's `pkgs`, and the confinement one takes the caller's home BUILDER, so the
  # contract never needs home-manager).
  checkKit = import ./check-kit.nix { inherit lib; };

  # --- the two substantial pieces, split out for focus ---
  contractLib = import ./lib.nix {
    inherit
      lib
      registry
      modeRegistry
      manifest
      grantLib
      featureConfigOptions
      ;
  };
  modules = import ./modules.nix {
    inherit
      lib
      realization
      identityOptions
      homeProfileOptions
      grantedOptions
      wantedOptions
      supportsOptions
      featureConfigOptions
      ;
  };

  # The opt-in reference greeter (ADR-0008, issue #2): a SEPARATE nixosModule a seat host
  # enables, not part of nixosModule.default (a headless host wants the schema, not the
  # greeter). It is the one module that references real packages — supplied by the host's
  # `pkgs`, so the contract FLAKE still inputs only nixpkgs `lib` (ADR-0004). It is closed
  # over the fixed runtime grant + the identity.json filename it authenticates on.
  greeterModule = import ./greeter.nix {
    inherit lib grantLib;
    inherit (contractLib)
      greeterGrants
      tier1EvalConfig
      renderNixConfig
      ;
    inherit (identityJson) identityFile identityFields;
  };
in
{
  # Public data surface — introspection API for consumers (a host grant matrix, the
  # greeter reading the safe set).
  features = registry;
  inherit
    featureGroups
    privilegedGroups
    ;
  # The MODE registry (ADR-0032), exposed exactly as `features` is and for the same reason: it is
  # the vocabulary a consumer reads — the names a per-system matrix row may take away, the names a
  # user's `contract.supports` declares over, and (through `description`) what each mode IS. The
  # FLOOR travels beside it because it is derived, not declared: a consumer asking "what does a
  # host that affords nothing run?" must not have to re-scan the registry for the flag.
  modes = modeRegistry;
  inherit (contractLib)
    safeSet
    floorMode
    greeterGrants
    tier1EvalConfig
    ;

  # The identity.json schema, exposed so a host/greeter can introspect the jq-readable
  # shape it authenticates against before any eval (ADR-0007, issue #5).
  inherit (identityJson) identityFile identitySchema;

  # Public derivation functions consumers use (ADR-0004 Q4, surface fixed by ADR-0026). The
  # package-level kernels (mkContractPackage/mkContractPackageForHome/bindContractPackage) stay
  # INTERNAL — see `internal` below. (`runtimeEligibleFeature` is not exposed anywhere: it is
  # private to lib.nix, where `safeSet` is its only reader. This comment used to claim it lived in
  # `internal`, which it never did.)
  lib = {
    inherit (contractLib) renderNixConfig;
    # mkHomeMatrix (issue #58, reshaped by ADR-0032): the per-system HOME MATRIX over `contract.modes`.
    # The caller declares its whole matrix as one fact — `{ <system> = { <mode> = bool; }; }`, a row
    # per system it bakes, each row naming only the modes that system's seats CANNOT run — and gets
    # the subtraction plus its guards. Which modes a fleet bakes stays the fleet's (decision #43);
    # the shape of the declaration is the contract's, because an under-bake is silent and an omitted
    # mode must therefore default to BAKED. See lib.nix.
    inherit (contractLib) mkHomeMatrix;
    # The identity.json loader (ADR-0007): lossless over identity.nix, used by a user's home
    # module and by the producer coin below.
    inherit (identityJson) loadIdentity;
    # traceUser (ADR-0007/0026/0028): the home-manager-free dry-run inspector, partially applied over
    # the contract's own homeModule so a caller passes only { userModule, identity, grants, … }.
    # Harvests a contract-pure home via bare evalModules → { username, home, requests, wants,
    # unknown, system }. Its `permissive` mode reports feature keys from a NEWER contract as data
    # (`unknown`) instead of throwing — the one tolerant reader of the otherwise fully-typed user
    # voice. Sits OUTSIDE the produce/consume coin (it inspects a home, it never touches the index).
    traceUser = args: contractLib.traceUser (args // { homeModule = modules.homeModule; });
    # mkMembers (ADR-0020, issue #57): the MEMBER-SET derivation over a users directory —
    # `{ <name> = { name; dir; identity; }; }`, the contract's one answer to "who is in this users
    # repo". The layout rule and the identity resolution live here rather than in each producer's own
    # `readDir` + identity map, and its MEMBERS are what the coin and the home builder take, so no
    # identity path is re-derived downstream. `loadIdentity` is injected here exactly as it is for
    # the producer coin.
    mkMembers = args: contractLib.mkMembers (args // { inherit (identityJson) loadIdentity; });
    # The turnkey producer/consumer COIN over the contractUsers binding index (ADR-0025/0026):
    #   - mkContractUser (producer, singular): bake ONE user's bakes into contractPackages +
    #     its `contractUsers.<sys>.<user>` index entry. The per-user partner of bindContractUser.
    #   - mkContractUsers (producer, members): mkContractUser mapped over a whole users flake — one
    #     call bakes the multi-user repo (ADR-0020). loadIdentity is injected here (as homeModule
    #     is for traceUser) so the users flake needn't wire the loader.
    #   - bindContractUser (consumer): a host declares `contract.affordances` once and binds a user
    #     with `{ usersFlake; username }`; the grant is DERIVED as `affordances ∩ offer` (always
    #     negotiated, ADR-0026) and the maximal covering bake selected — no per-user grants, no
    #     users-repo internals.
    mkContractUser =
      args: contractLib.mkContractUser (args // { inherit (identityJson) loadIdentity; });
    mkContractUsers =
      args: contractLib.mkContractUsers (args // { inherit (identityJson) loadIdentity; });
    # mkContractFleet (ADR-0029's second amendment, issue #62): the FLEET-level producer, one rung
    # above `mkContractUsers` — `{ members; homeMatrix; pkgsFor; buildHome }` in, and the whole
    # published surface out (`{ homes; packages; contractUsers; systems; pkgsBySystem; }`). It owns
    # the residual join a multi-user, multi-system producer was left holding: the home eval loop,
    # the members × system × home fold, the grants↔home pairing, the output merges, and the
    # once-per-system `pkgs`. Package-free by the same injection posture as everything else here —
    # `buildHome` is the consumer's closure, so this never names `mkContractHome` and a home built
    # WITHOUT the builder still bakes through it. `loadIdentity` is injected as it is for the coin.
    # The arity reads honestly: `mkContractUser` (one user) / `mkContractUsers` (a member set you
    # enumerate) / `mkContractFleet` (one you DERIVE, across systems).
    mkContractFleet =
      args: contractLib.mkContractFleet (args // { inherit (identityJson) loadIdentity; });
    inherit (contractLib) bindContractUser;
    # mkContractHome (ADR-0029, issue #40): the producer HOME builder — the contract-owned mkHome
    # composition (umbrella + baseline + the user's home.nix + the identity/home.* inline module +
    # the narrowed hostFacts specialArg). Package-free by INJECTION: the consumer passes
    # `home-manager.lib.homeManagerConfiguration` verbatim (ADR-0004, the buildHome trick). The
    # umbrella, the baseline hygiene module, and the identity loader are injected here (exactly as
    # homeModule is for traceUser and loadIdentity for the producer coin), so a caller passes only
    # its own side: { homeManagerConfiguration; pkgs; member (or memberDir); grants; stateVersion; … }.
    # `grants` is the same word the producer coin and the home matrix use for a grant attrset, so one
    # value keeps one name from the matrix through the builder to the pairing guard.
    mkContractHome =
      args:
      contractLib.mkContractHome (
        args
        // {
          inherit (identityJson) loadIdentity;
          inherit (modules) homeModule homeBaselineModule;
        }
      );
    # The CHECK KIT (issues #35, #49) — the proofs only a consumer can run, over material only it
    # has. They join the ADR-0026 surface deliberately (it is fixed at what a consumer needs, not
    # frozen), because each is otherwise ~20 lines of `tryEval`/`hasPrefix` boilerplate re-typed
    # per repo and easy to get subtly, silently wrong:
    #   - mkConfinementCheck: does this repo's REAL module set still have no system channel?
    #     (`conformance/confinement.nix` can only prove the umbrella; a consumer's own imports are
    #     where a channel gets smuggled back in.) Takes the consumer's home BUILDER, so the
    #     contract proves a home-manager module set without depending on home-manager (ADR-0004).
    #   - mkIdentityPostureCheck: does this repo's own members carry the credential posture THIS
    #     repo has chosen? Opt-in and parameterized (`require`) because ADR-0019 makes the posture
    #     conditional and consumer-owned — which is also why `loadIdentity` imposes no hash policy.
    #   - mkHomeEvalCheck: does everything this repo BAKES for one user actually evaluate, on
    #     every system it bakes for? The members-generic cross-arch eval check a consumer's mapper
    #     applies per user (decision #43) — which bakes a fleet bakes per system stays the
    #     mapper's own fact.
    # …and the MEMBER-SET ADAPTER over the three (issue #60): `mkMemberChecks` applies all of them
    # across a whole members in ONE call, with the check names single-sourced, so a consumer folds
    # the kit over its members instead of hand-writing the fold that the helpers being
    # members-generic was supposed to spare it. The three stay public and separately callable — a
    # single-user repo has no members to adapt, and a repo wanting one proof calls for one proof.
    inherit (checkKit)
      mkConfinementCheck
      mkIdentityPostureCheck
      mkHomeEvalCheck
      mkMemberChecks
      ;
  };

  # INTERNAL derivation logic (ADR-0016/0026): NOT flake outputs, exposed here only so the in-repo
  # conformance suite can prove them in isolation.
  #   - the package-level kernels the public `bindContractUser`/`mkContractUser` bind and bake
  #     THROUGH — a consumer never calls them directly (the grant model is negotiation-only; a bare
  #     contractPackage has no public consumer).
  internal = {
    # NOT flake outputs, and not a consumer surface — but reachable BY NAME from inside this repo,
    # which is the whole membership rule: an entry is here when something in-repo must import it and
    # a public export would be wrong.
    #
    # "Something in-repo" is usually the conformance suite proving a kernel in isolation. It is NOT
    # only the suite: `accountPlan` is imported at LOGIN TIME by the greeter's
    # `contract-account-plan` tool, which re-evaluates it from a pinned contract source
    # (`greeter/account-plan-eval.nix`) — so this attrset is load-bearing at runtime, not just under
    # test, and must not be renamed to something that says "for the tests".
    #
    # Re-exposing an entry publicly stays a one-line move to `lib` above, plus an ADR amendment
    # (ADR-0026's posture).
    #
    # The floor kernel behind `floorMode` (ADR-0032), taking a mode registry explicitly. Internal
    # because no consumer needs it: `floorMode` is the answer. Exposed here because the contract's
    # own registry has exactly one floor by construction, so the guard's two failure directions —
    # no floor, and two — are only demonstrable against a synthetic registry.
    inherit (contractLib) floorOf;
    # The host-side mode DERIVATION (ADR-0032 §4): afforded feature names → the modes a host runs.
    # `bindContractUser` is its only caller, so a consumer never needs it; exposed here so the
    # suite can state "a gui-affording host runs { cli, gui }; a headless one runs { cli }" as a
    # claim about the derivation itself rather than only through a whole bind.
    inherit (contractLib) runsFor;
    # The home-matrix kernel behind the public `mkHomeMatrix` (issue #58), taking the upper bound to
    # narrow instead of closing over `modes`. Internal for the same reason `floorOf` is: no
    # consumer needs it, and the suite cannot otherwise prove that a contract which GAINS a mode
    # extends every system's bake — the registry has two modes, so the third is synthetic.
    inherit (contractLib) homeMatrixOver;
    inherit (contractLib)
      mkContractPackage
      mkContractPackageForHome
      bindContractPackage
      ;
    # The shared account plan (issues #30/#31, ADR-0027) — the one entry here with a RUNTIME
    # consumer as well as a test one. `greeter/account-plan-eval.nix` pins the contract source and
    # evaluates `kit.internal.accountPlan` at every greeter login, so `provision` renders the record
    # rather than re-spelling the fold in jq; the greeter-provision VM then asserts the runtime
    # render reproduces the BUILD-TIME account for a fixture identity, proving build↔runtime parity
    # from the ONE plan both adapters execute (ADR-0012, ADR-0027).
    inherit accountPlan;
    # The manifest schema owner (issue #27): the producer/consumer seam, exposed so the
    # conformance suite proves the write→read round-trip and generates its fixtures through it.
    inherit (manifest)
      writeManifest
      readManifest
      manifestFileName
      ;
    # The out-of-universe probe set (issue #35): the negative space `mkConfinementCheck` probes
    # with, exposed so the umbrella's own proof (`conformance/confinement.nix`) reads the SAME list
    # rather than keeping a second copy of "what a user must not be able to say".
    inherit (checkKit) outOfUniverseProbes;
  };

  # The umbrella modules (one per eval-side) + the opt-in reference greeter (ADR-0008) + the two
  # home-manager-aware helpers, each SEPARATE from the tracer-pure homeModule because they set
  # home-manager options: the desktop-choice surface (ADR-0013) and the home baseline hygiene
  # `mkContractHome` composes by default (issue #42, ADR-0029).
  inherit (modules)
    nixosModule
    homeModule
    homeGreeterDesktopModule
    homeBaselineModule
    ;
  inherit greeterModule;
}
