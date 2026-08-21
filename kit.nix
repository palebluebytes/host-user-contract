# The contract kit — a pure function of nixpkgs `lib` that ASSEMBLES the contract from its two
# registries: it computes their projections (the data), then wires the derivation logic (./lib.nix)
# and the umbrella modules (./modules.nix) and returns the public surface. It depends on NOTHING
# but `lib` — no `self`, no `inputs`, and no home-manager — which is what lets the contract be a
# standalone flake (./flake.nix wraps this).
{ lib }:
let
  registry = import ./features.nix;
  # THE DIAGNOSTIC MODULE — the one owner of what the contract says when it refuses. Imported HERE
  # and injected into everything that refuses (./lib.nix, ./check-kit.nix) rather than imported
  # separately by each, so "one voice" is one instance rather than a convention two files keep. It
  # rides `internal` for the same reason the other kernels do: its shape rules (the `<who>: `
  # prefix, one terminator per clause, `[a, b]`) are the only part of a refusal the suite can prove
  # directly, since `tryEval` discards the message a real guard raises (issue #64).
  diag = import ./diagnostics.nix { inherit lib; };
  # The MODE registry — the second single source beside the feature one, and the backbone of the
  # user-facing surface: a user's whole declaration is a projection of it.
  modeRegistry = import ./modes.nix { inherit lib; };
  # The USER DECLARATION schema, projected off the mode registry: `contract.<mode> = { enable;
  # configuration; <the mode's own parameters> }`. It is a plain module, evaluated by bare
  # `evalModules` (no home-manager), which is what lets the producer and a greeter read a user's
  # modes without building anything.
  userOptions = import ./contract-user.nix { inherit lib modeRegistry; };

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
  # the privileged-group filter is single-sourced.
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
      # The privileged-group filter. Nothing UNTRUSTED reaches it any more — an identity cannot
      # name groups at all — so its remaining job is to keep contract-owned data honest: a
      # privileged group added to `modes.nix` would otherwise reach every account in that mode with
      # no grant. Named for what it does rather than for what used to feed it.
      withoutPrivileged = groups: lib.filter (g: !lib.elem g privilegedGroups) groups;
    };
  # The grant option fragment: ONE BOOL PER FEATURE, `{ <feature> = bool; }`. It is the shape of
  # every grant-ish value in the contract — what a host affords at a bind, and what an account was
  # granted — so the grant algebra needs no normalising shim anywhere. There is no `.enable` suffix:
  # a feature never carried a second flag, and features are ATOMIC (ADR-0008), so a word that never
  # varied was ceremony.
  grantedOptions = lib.mapAttrs (_: f: lib.mkEnableOption f.grant) registry;

  # The shared account plan (issue #30): the single pure `accountPlan (identity, grants) → account
  # record`, closed over grantLib so its clamp + grant→groups fold are single-sourced (issue #28).
  # `realization.nix` renders it into `users.users` at build time; the greeter's runtime provisioning
  # renders the same record to data (issue #31), so the two adapters cannot drift.
  inherit (import ./account-plan.nix { inherit lib grantLib modeRegistry; }) accountPlan;

  # --- closed-over modules + option fragments ---
  realization = import ./realization.nix {
    inherit accountPlan modeRegistry;
    inherit (contractLib) runsWith;
  };
  identityOptions = import ./identity.nix { inherit lib; };
  identityJson = import ./identity-json.nix { inherit lib identityOptions; };
  # The manifest module: the single owner of the `contract-manifest.json` schema — the seam
  # `mkContractPackage` writes through and `bindContractPackage` reads through.
  manifest = import ./manifest.nix { inherit lib; };

  # The check kit: the proofs a CONSUMER runs over its own repo (ADR-0025).
  checkKit = import ./check-kit.nix { inherit lib diag; };

  # --- the two substantial pieces, split out for focus ---
  contractLib = import ./lib.nix {
    inherit
      lib
      registry
      modeRegistry
      manifest
      grantLib
      userOptions
      diag
      ;
  };
  modules = import ./modules.nix {
    inherit
      lib
      realization
      identityOptions
      grantedOptions
      ;
    inherit (contractLib) modeNames floorMode;
  };

  # The opt-in reference greeter: a SEPARATE nixosModule a seat host enables, not part of
  # nixosModule.default (a headless host wants the schema, not the greeter). It is the one module
  # that references real packages — supplied by the host's `pkgs`, so the contract FLAKE still
  # inputs only nixpkgs `lib`. It is closed over what a greeter affords, the modes that makes a
  # seat run, and the identity.json filename it authenticates on.
  greeterModule = import ./greeter.nix {
    inherit lib modeRegistry;
    inherit (contractLib)
      greeterAffordances
      runsWith
      tier1EvalConfig
      renderNixConfig
      ;
    inherit (identityJson) identityFile identityFields;
  };
in
{
  # ── Public DATA surface ──────────────────────────────────────────────────────────────────────
  # Introspection for consumers: the vocabulary this contract speaks, so a host or a users repo
  # reads the names rather than re-spelling them.
  features = registry;
  inherit
    featureGroups
    privilegedGroups
    ;
  # The MODE registry, exposed exactly as `features` is and for the same reason: it is the
  # vocabulary a consumer reads — the names a per-system matrix row may take away, the keys a
  # user's declaration is written under, and (through `description`) what each mode IS. The FLOOR
  # travels beside it because it is derived, not declared: a consumer asking "what does a host that
  # affords nothing run?" must not have to re-scan the registry for the flag.
  modes = modeRegistry;
  inherit (contractLib)
    safeSet
    floorMode
    greeterAffordances
    tier1EvalConfig
    ;

  # The identity.json schema, exposed so a host/greeter can introspect the jq-readable shape it
  # authenticates against before any eval.
  inherit (identityJson) identityFile identitySchema;

  # ── Public FUNCTIONS ─────────────────────────────────────────────────────────────────────────
  # The package-level kernels (mkContractPackage/mkContractPackageForHome/bindContractPackage) stay
  # INTERNAL — see `internal` below.
  lib = {
    inherit (contractLib) renderNixConfig;

    # ── CONSUMER (a host) — the whole of it ──────────────────────────────────────────────────
    # bindContractUsers `{ source; users; all ? false }`: a host's whole user list in one call.
    # Each entry is that person's affordances, plus an optional `source` when they come from
    # somewhere other than the default. `all = true` binds everybody the source publishes.
    #
    # bindContractUser `{ source; username; affordances }` is the singular underneath — the true
    # partner of `mkContractUser`, and what a host binding one user reaches for. Both read the
    # binding index, take the modes the machine runs, select one, confer what was afforded, and
    # realize the account.
    inherit (contractLib) bindContractUser bindContractUsers;

    # ── PRODUCER (a users repo) ──────────────────────────────────────────────────────────────
    # mkMembers: the MEMBER-SET derivation over a users directory —
    # `{ <name> = { name; dir; identity; declaration; }; }`, the contract's one answer to "who is
    # in this users repo, and what does each one say" (ADR-0014).
    mkMembers = args: contractLib.mkMembers (args // { inherit (identityJson) loadIdentity; });

    # mkHomeMatrix: the per-system HOME MATRIX over `contract.modes`. The caller declares its whole
    # matrix as one fact — `{ <system> = { <mode> = bool; }; }`, a row per system it bakes, each
    # row naming only the modes that system's seats CANNOT run — and gets the subtraction plus its
    # guards. Which modes a fleet bakes stays the fleet's; the SHAPE of the declaration is the
    # contract's (ADR-0012).
    inherit (contractLib) mkHomeMatrix;

    # mkContractFleet `{ members; homeMatrix; pkgsFor; buildHome }` → the whole published surface
    # (`{ homes; packages; contractUsers; systems; pkgsBySystem; }`). The fleet-level producer, and
    # the one a multi-user repo calls: it owns the members × system × mode fold, the output merges
    # and the once-per-system `pkgs`. Package-free by injection (ADR-0014).
    mkContractFleet =
      args: contractLib.mkContractFleet (args // { inherit (identityJson) loadIdentity; });

    # The two rungs below the fleet, for a producer whose bake is not a full cross-product:
    #   - mkContractUser (singular): bake ONE user's homes into contractPackages + its
    #     `contractUsers.<sys>.<user>` index entry. The per-user partner of bindContractUser.
    #   - mkContractUsers: that mapped over a member set and merged.
    mkContractUser =
      args: contractLib.mkContractUser (args // { inherit (identityJson) loadIdentity; });
    mkContractUsers =
      args: contractLib.mkContractUsers (args // { inherit (identityJson) loadIdentity; });

    # mkContractHome: the producer HOME builder — the contract-owned composition (umbrella +
    # baseline + the desktop dotfile + the mode's own `configuration` + the identity/home.* inline
    # module + the hostFacts specialArg), applying the consumer's own
    # `homeManagerConfiguration` verbatim (ADR-0014). A caller passes only its own side:
    # `{ homeManagerConfiguration; pkgs; member (or memberDir); mode; stateVersion; … }`.
    mkContractHome =
      args:
      contractLib.mkContractHome (
        args
        // {
          inherit (identityJson) loadIdentity;
          inherit (modules)
            homeModule
            homeBaselineModule
            homeDesktopModule
            ;
        }
      );

    # The identity.json loader: lossless over identity.nix, for a consumer resolving an identity
    # outside the member set (a greeter fixture, a hand-driven build).
    inherit (identityJson) loadIdentity;

    # evalUser `{ userFile }` → a user's evaluated declaration, `{ <mode> = { enable;
    # configuration; … }; }`. The producer reads every declaration through this; it is public so a
    # consumer can answer "which modes does this user run in?" without building anything, which is
    # the same question a greeter asks over the published index.
    evalUser = { userFile }: contractLib.evalUserFile userFile;
    # …and its enabled-name projection, so a caller asking that question does not re-derive it.
    inherit (contractLib) enabledModesOf;

    # ── The CHECK KIT — the proofs only a consumer can run, over material only it has ─────────
    # ADR-0025; `check-kit.nix` carries each signature.
    #   - mkConfinementCheck: does this repo's REAL module set still have no system channel?
    #   - mkIdentityPostureCheck: does this repo's own members carry the credential posture THIS
    #     repo has chosen?
    #   - mkHomeEvalCheck: does everything this repo BAKES for one user actually evaluate, on every
    #     system it bakes for?
    #   - mkMemberChecks: all three applied across a whole member set in ONE call.
    inherit (checkKit)
      mkConfinementCheck
      mkIdentityPostureCheck
      mkHomeEvalCheck
      mkMemberChecks
      ;
  };

  # ── INTERNAL ─────────────────────────────────────────────────────────────────────────────────
  # NOT flake outputs. An entry is here when something IN THIS REPO must import it by name and a
  # public export would be wrong — usually the conformance suite proving a kernel in isolation, but
  # not only: `accountPlan` is imported at LOGIN TIME by the greeter's `contract-account-plan`
  # tool, which re-evaluates it from a pinned contract source (`greeter/account-plan-eval.nix`), so
  # this attrset is load-bearing at runtime and must not be renamed to something that says "for the
  # tests".
  internal = {
    # The DIAGNOSTIC MODULE itself. Every refusal in this repo is `diag.say`'s output, and
    # `tryEval` — which is how the suite drives all 50 refusal paths — returns `{ success = false;
    # value = false; }` and DISCARDS the message. So the shape rules are unprovable at the guards
    # and provable here: exposed so the suite unit-tests the constructor directly (issue #64). This
    # is not a consumer surface — how the contract phrases its own refusals is not a facility to
    # build on — which is exactly why it is `internal` and not `lib`.
    inherit diag;
    # The floor kernel behind `floorMode`, taking a mode registry explicitly. Internal because no
    # consumer needs it — `floorMode` is the answer — and exposed because its two failure
    # directions are only demonstrable against a synthetic registry (see lib.nix).
    inherit (contractLib) floorOf;
    # The run-set derivation: what a machine DECLARED → the modes it runs. Exposed so the suite can
    # claim things about the derivation itself rather than only through a whole bind.
    inherit (contractLib) runsWith;
    # The SELECTION kernel, taking the floor explicitly. The registry has ONE non-floor mode, so
    # "two rich modes is a hard error" is only demonstrable against a synthetic world.
    inherit (contractLib) selectModeOver;
    # The home-matrix kernel, taking the upper bound to narrow instead of closing over `modes`: the
    # suite cannot otherwise prove that a contract which GAINS a mode extends every system's bake.
    inherit (contractLib) homeMatrixOver;
    # The package-level kernels the public surface bakes and binds THROUGH.
    inherit (contractLib)
      mkContractPackage
      mkContractPackageForHome
      bindContractPackage
      ;
    # The USER DECLARATION schema module, so the suite can evaluate a synthetic declaration against
    # the real options rather than a copy of them.
    inherit userOptions;
    # The shared account plan — the entry with a RUNTIME consumer as well as a test one (see
    # above). The greeter-provision VM asserts the runtime render reproduces the BUILD-TIME account
    # for a fixture identity, proving build↔runtime parity from the ONE plan both adapters execute.
    inherit accountPlan;
    # The manifest schema owner: the producer/consumer seam, exposed so the conformance suite
    # proves the write→read round-trip and generates its fixtures through it.
    inherit (manifest)
      writeManifest
      readManifest
      manifestFileName
      contractVersion
      versionsCompatible
      ;
    # The out-of-universe probe set: the negative space `mkConfinementCheck` probes with, exposed
    # so the umbrella's own proof reads the SAME list rather than keeping a second copy of "what a
    # user must not be able to say".
    inherit (checkKit) outOfUniverseProbes;
  };

  # The umbrella modules (one per eval-side) + the opt-in reference greeter + the home baseline,
  # which is SEPARATE from the umbrella because it sets home-manager options and the umbrella must
  # stay evaluable with none present.
  inherit (modules)
    nixosModule
    homeModule
    homeBaselineModule
    ;
  inherit greeterModule;
}
