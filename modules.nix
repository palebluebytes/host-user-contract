# The contract's umbrella modules — one per eval-side (ADR-0020 Q2), split out of
# kit.nix (thermo-nuclear review). Each is closed over the registry projections + option
# fragments the kit computes, so it depends on neither `self` nor `inputs`. The host
# imports these and supplies only the `platform` binding (Q7).
{
  lib,
  realization,
  identityOptions,
  platformOptions,
  homeProfileOptions,
  grantedOptions,
  featureConfigOptions,
  exposedHostOffenders,
}:
{
  # System kit: the custom.users schema, the platform INTERFACE (host binds it), the
  # exposed-host marker + ban, and the realization + insecure aggregator. The host
  # imports this and supplies the platform binding.
  nixosModule =
    { config, ... }:
    {
      imports = [
        realization
        ./insecure-packages.nix
      ];

      options.custom.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              identity = identityOptions;
              granted = grantedOptions;
            }
            // featureConfigOptions;
          }
        );
        default = { };
        description = "Per-user identity, grants, and feature configuration.";
      };
      options.custom.platform = platformOptions;
      options.custom.host.exposed = lib.mkEnableOption "an exposed/agent-facing host that may not be granted secret-bearing features";

      config.assertions = lib.optional config.custom.host.exposed (
        let
          offending = exposedHostOffenders config;
        in
        {
          assertion = offending == [ ];
          message = "exposed host '${config.networking.hostName}' must not be granted secret-bearing feature(s): ${lib.concatStringsSep ", " offending}";
        }
      );
    };

  # Home kit: the identity + home-profile vocabulary + the platform INTERFACE (host
  # binds it) + the contract.requests namespace the user emits. The home identity value
  # is populated from the system identity by the host.
  homeModule = _: {
    options.identity = identityOptions;
    options.custom.home.profiles = homeProfileOptions;
    options.custom.platform = platformOptions;

    # contract.requests (ADR-0018/0023, issue #5): the typed, read-only namespace a user's
    # home module POPULATES to describe host-affecting parameters of the features it
    # offers (e.g. gui.session). The host harvests the GRANTED ones post-eval (bindUser);
    # the user only asks, never writes system state. Its per-feature shape IS the registry's
    # feature `config` fragments (featureConfigOptions) — the same parameters carried
    # system-side as custom.users.<u>.<feature>.* today (ADR-0019), now emitted from the
    # user's own side. Enforcement (ADR-0018 "ignore-overreach / validate-intent"):
    #   - a KNOWN request is typed, so a malformed one (wrong-typed gui.session, a
    #     misspelled param within a known feature) ERRORS — the schema is the typo-net;
    #   - an UNKNOWN feature key is ACCEPTED and ignored (the freeformType below), so a
    #     request for a feature this contract version lacks never breaks the build — the
    #     "build still happens" posture the greeter's forward-compat needs.
    options.contract.requests = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.anything;
        options = featureConfigOptions;
      };
      default = { };
      description = "Host-affecting requests this user emits; the host applies the granted ones (mkIf granted). The user populates it; the host reads it.";
    };
  };
}
