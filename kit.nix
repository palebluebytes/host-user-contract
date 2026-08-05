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
  grantedOptions = lib.mapAttrs (_: f: { enable = lib.mkEnableOption f.grant; }) registry;
  featureConfigOptions = lib.foldl' lib.recursiveUpdate { } (
    map (f: f.config or { }) (lib.attrValues registry)
  );

  # --- closed-over modules + option fragments ---
  realization = import ./realization.nix { inherit privilegedGroups featureGroups; };
  identityOptions = import ./identity.nix { inherit lib; };
  identityJson = import ./identity-json.nix { inherit lib identityOptions; };
  homeProfileOptions = import ./home-profiles.nix { inherit lib; };

  # --- the two substantial pieces, split out for focus ---
  contractLib = import ./lib.nix {
    inherit
      lib
      registry
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
    inherit lib privilegedGroups featureGroups;
    inherit (contractLib)
      greeterGrants
      safeSet
      tier1EvalConfig
      renderNixConfig
      ;
    inherit (identityJson) identityFile;
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

  # Public derivation functions hosts consume (ADR-0004 Q4). The internal predicate
  # (runtimeEligibleFeature) stays internal to ./lib.nix.
  lib = {
    inherit (contractLib) mkHostFacts renderNixConfig;
    # The identity.json loader (ADR-0007): lossless over identity.nix, used by both the
    # user's home module and host-side bindUser.
    inherit (identityJson) loadIdentity;
    # The binding mechanism (ADR-0007/0008), each partially applied over the contract's own
    # homeModule so a caller passes only { userModule, identity, grants, … }:
    #   - bindUser (issue #5): the headless tracer — harvests a contract-pure home via bare
    #     evalModules, returns { username, home, requests, system }. The logic-level proof.
    #   - bindUserModule (issue #8): the REAL mechanism both paths call — a NixOS module the
    #     host imports; the home is evaluated once by the host's home-manager and the bridge is
    #     a config reference, so real homes (programs.*, home.*) bind. The host supplies
    #     home-manager; the contract stays package-free.
    bindUser = args: contractLib.bindUser (args // { homeModule = modules.homeModule; });
    bindUserModule = args: contractLib.bindUserModule (args // { homeModule = modules.homeModule; });
    # Pre-built binding mode (ADR-0016):
    #   - mkContractPackage (issue #14): assembles the contractPackage derivation a user CI
    #     produces — activate + contract-requests.json — from an already-evaluated home.
    #   - mkContractPackageForHome (issue #23): the optional home-manager producer adapter — a
    #     turnkey wrapper that reads mkContractPackage's four primitives off an already-evaluated
    #     home, so a producer calls { home; grants; pkgs; }. No home-manager import (ADR-0004).
    #   - bindContractPackage (issue #16): the host-side binding for the pre-built path; reads
    #     contract-requests.json from a pinned store path and registers the activation step.
    inherit (contractLib) mkContractPackage mkContractPackageForHome bindContractPackage;
    # Turnkey binding (ADR-0025, issue #25), the twin of the pre-built primitives above:
    #   - mkUserBindings (producer): the users flake calls it once to emit the named per-variant
    #     packages AND the pure `contractUsers.<sys>.<user>` binding index. loadIdentity is
    #     injected here (like homeModule for bindUser) so the users flake needn't wire the loader.
    #   - bindUserFromFlake (consumer): a host declares `contract.affordances` once and imports a
    #     user with `{ usersFlake; username }`; the grant is derived as `affordances ∩ offer` and
    #     the maximal covering variant is selected — no per-user grants, no users-repo internals.
    mkUserBindings =
      args: contractLib.mkUserBindings (args // { inherit (identityJson) loadIdentity; });
    inherit (contractLib) bindUserFromFlake;
  };

  # The umbrella modules (one per eval-side) + the opt-in reference greeter (ADR-0008) + the
  # home-manager-aware desktop-choice helper (ADR-0013, separate from the tracer-pure homeModule).
  inherit (modules) nixosModule homeModule homeGreeterDesktopModule;
  inherit greeterModule;
}
