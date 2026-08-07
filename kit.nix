# The contract kit — a pure function of nixpkgs `lib` that ASSEMBLES the contract from
# the registry: it computes the registry's projections (the data), then wires the
# derivation logic (./lib.nix) and the umbrella modules (./modules.nix) and returns the
# public surface. It depends on NOTHING but `lib` — no `self`, no `inputs` — which is
# what lets the contract be a standalone flake (./flake.nix wraps this). The host
# supplies only the `platform` binding and the package/display bindings (ADR-0004).
{ lib }:
let
  registry = import ./features.nix { inherit lib; };

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
      # `{ <feature>.enable = bool; }` (the registry's grantedOptions shape).
      grantedNames = grants: lib.filter (f: grants.${f}.enable or false) (lib.attrNames grants);
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
  grantedOptions = lib.mapAttrs (_: f: { enable = lib.mkEnableOption f.grant; }) registry;
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

  # --- the two substantial pieces, split out for focus ---
  contractLib = import ./lib.nix {
    inherit
      lib
      registry
      manifest
      grantLib
      ;
  };
  modules = import ./modules.nix {
    inherit
      lib
      realization
      identityOptions
      homeProfileOptions
      grantedOptions
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
  inherit (contractLib) safeSet greeterGrants tier1EvalConfig;

  # The identity.json schema, exposed so a host/greeter can introspect the jq-readable
  # shape it authenticates against before any eval (ADR-0007, issue #5).
  inherit (identityJson) identityFile identitySchema;

  # Public derivation functions consumers use (ADR-0004 Q4, surface fixed by ADR-0026). The
  # package-level kernels (mkContractPackage/mkContractPackageForHome/bindContractPackage) and the
  # predicate (runtimeEligibleFeature) stay INTERNAL — see `internal` below.
  lib = {
    inherit (contractLib) renderNixConfig;
    # The identity.json loader (ADR-0007): lossless over identity.nix, used by a user's home
    # module and by the producer coin below.
    inherit (identityJson) loadIdentity;
    # traceUser (ADR-0007/0026): the home-manager-free dry-run inspector, partially applied over
    # the contract's own homeModule so a caller passes only { userModule, identity, grants, … }.
    # Harvests a contract-pure home via bare evalModules → { username, home, requests, system }.
    # Sits OUTSIDE the produce/consume coin (it inspects a home, it never touches the index).
    traceUser = args: contractLib.traceUser (args // { homeModule = modules.homeModule; });
    # The turnkey producer/consumer COIN over the contractUsers binding index (ADR-0025/0026):
    #   - mkContractUser (producer, singular): bake ONE user's variants into contractPackages +
    #     its `contractUsers.<sys>.<user>` index entry. The per-user partner of bindContractUser.
    #   - mkContractUsers (producer, roster): mkContractUser mapped over a whole users flake — one
    #     call bakes the multi-user repo (ADR-0020). loadIdentity is injected here (as homeModule
    #     is for traceUser) so the users flake needn't wire the loader.
    #   - bindContractUser (consumer): a host declares `contract.affordances` once and binds a user
    #     with `{ usersFlake; username }`; the grant is DERIVED as `affordances ∩ offer` (always
    #     negotiated, ADR-0026) and the maximal covering variant selected — no per-user grants, no
    #     users-repo internals.
    mkContractUser =
      args: contractLib.mkContractUser (args // { inherit (identityJson) loadIdentity; });
    mkContractUsers =
      args: contractLib.mkContractUsers (args // { inherit (identityJson) loadIdentity; });
    inherit (contractLib) bindContractUser;
  };

  # INTERNAL derivation logic (ADR-0016/0026): NOT flake outputs, exposed here only so the in-repo
  # conformance suite can prove them in isolation.
  #   - the package-level kernels the public `bindContractUser`/`mkContractUser` bind and bake
  #     THROUGH — a consumer never calls them directly (the grant model is negotiation-only; a bare
  #     contractPackage has no public consumer).
  internal = {
    inherit (contractLib)
      mkContractPackage
      mkContractPackageForHome
      bindContractPackage
      ;
    # The shared account plan (issue #30/#31), exposed so the greeter-provision VM can render the
    # BUILD-TIME account for a fixture identity and assert the runtime `provision` reproduces it —
    # proving build↔runtime realization parity from the ONE plan both adapters render (ADR-0012).
    inherit accountPlan;
    # The manifest schema owner (issue #27): the producer/consumer seam, exposed so the
    # conformance suite proves the write→read round-trip and generates its fixtures through it.
    inherit (manifest)
      writeManifest
      readManifest
      manifestFileName
      ;
  };

  # The umbrella modules (one per eval-side) + the opt-in reference greeter (ADR-0008) + the
  # home-manager-aware desktop-choice helper (ADR-0013, separate from the tracer-pure homeModule).
  inherit (modules) nixosModule homeModule homeGreeterDesktopModule;
  inherit greeterModule;
}
