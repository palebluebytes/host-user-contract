# The contract kit — a pure function of nixpkgs `lib` that ASSEMBLES the contract from
# the registry: it computes the registry's projections (the data), then wires the
# derivation logic (./lib.nix) and the umbrella modules (./modules.nix) and returns the
# public surface. It depends on NOTHING but `lib` — no `self`, no `inputs` — which is
# what lets the contract be a standalone flake (./flake.nix wraps this). The host
# supplies only the `platform` binding and the package/display bindings (ADR-0020).
{ lib }:
let
  registry = import ./features.nix { inherit lib; };

  # --- projections of the single registry (the data) ---
  featureGroups = lib.mapAttrs (_: f: f.groups) (lib.filterAttrs (_: f: f ? groups) registry);
  privilegedGroups = [
    "docker"
    "podman"
    "wheel"
    "libvirtd"
    "kvm"
    "disk"
    "qemu-libvirtd"
  ];
  grantedOptions = lib.mapAttrs (_: f: { enable = lib.mkEnableOption f.grant; }) registry;
  featureConfigOptions = lib.foldl' lib.recursiveUpdate { } (
    map (f: f.config or { }) (lib.attrValues registry)
  );
  featureMeta = lib.mapAttrs (
    _: f:
    {
      secretBearing = f.secretBearing or false;
    }
    // lib.optionalAttrs (f ? secretFiles) { inherit (f) secretFiles; }
  ) registry;

  # --- closed-over modules + option fragments ---
  realization = import ./realization.nix { inherit privilegedGroups featureGroups; };
  identityOptions = import ./identity.nix { inherit lib; };
  identityJson = import ./identity-json.nix { inherit lib identityOptions; };
  platformOptions = import ./platform.nix { inherit lib; };
  homeProfileOptions = import ./home-profiles.nix { inherit lib; };

  # --- the two substantial pieces, split out for focus ---
  contractLib = import ./lib.nix {
    inherit
      lib
      registry
      privilegedGroups
      featureMeta
      ;
  };
  modules = import ./modules.nix {
    inherit
      lib
      realization
      identityOptions
      platformOptions
      homeProfileOptions
      grantedOptions
      featureConfigOptions
      ;
    inherit (contractLib) exposedHostOffenders;
  };

  # The opt-in reference greeter (ADR-0024, issue #2): a SEPARATE nixosModule a seat host
  # enables, not part of nixosModule.default (a headless host wants the schema, not the
  # greeter). It is the one module that references real packages — supplied by the host's
  # `pkgs`, so the contract FLAKE still inputs only nixpkgs `lib` (ADR-0020). It is closed
  # over the fixed runtime grant + the identity.json filename it authenticates on.
  greeterModule = import ./greeter.nix {
    inherit lib;
    inherit (contractLib) greeterGrants;
    inherit (identityJson) identityFile;
  };
in
{
  # Public data surface — introspection API for consumers (a host grant matrix, the
  # greeter reading the safe set).
  features = registry;
  inherit
    featureMeta
    featureGroups
    privilegedGroups
    ;
  inherit (contractLib) safeSet greeterGrants;

  # The identity.json schema, exposed so a host/greeter can introspect the jq-readable
  # shape it authenticates against before any eval (ADR-0023, issue #5).
  inherit (identityJson) identityFile identitySchema;

  # Public derivation functions hosts consume (ADR-0020 Q4). The internal predicates
  # (runtimeEligibleFeature, exposedHostOffenders) stay internal to ./lib.nix.
  lib = {
    inherit (contractLib) mkFeatureRecipients mkHostFacts;
    # The identity.json loader (ADR-0023): lossless over identity.nix, used by both the
    # user's home module and host-side bindUser.
    inherit (identityJson) loadIdentity;
    # The binding mechanism (ADR-0023/0024), each partially applied over the contract's own
    # homeModule so a caller passes only { userModule, identity, grants, … }:
    #   - bindUser (issue #5): the headless tracer — harvests a contract-pure home via bare
    #     evalModules, returns { username, home, requests, system }. The logic-level proof.
    #   - bindUserModule (issue #8): the REAL mechanism both paths call — a NixOS module the
    #     host imports; the home is evaluated once by the host's home-manager and the bridge is
    #     a config reference, so real homes (programs.*, home.*) bind. The host supplies
    #     home-manager; the contract stays package-free.
    bindUser = args: contractLib.bindUser (args // { homeModule = modules.homeModule; });
    bindUserModule = args: contractLib.bindUserModule (args // { homeModule = modules.homeModule; });
  };

  # The umbrella modules (one per eval-side) + the opt-in reference greeter (ADR-0024).
  inherit (modules) nixosModule homeModule;
  inherit greeterModule;
}
