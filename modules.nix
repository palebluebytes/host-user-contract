# The contract's umbrella modules — one per eval-side (ADR-0004 Q2), split out of
# kit.nix (thermo-nuclear review). Each is closed over the registry projections + option
# fragments the kit computes, so it depends on neither `self` nor `inputs`. The host
# imports these and supplies only the `platform` binding (Q7).
{
  lib,
  realization,
  identityOptions,
  homeProfileOptions,
  grantedOptions,
  featureConfigOptions,
}:
{
  # System kit: the custom.users schema, the exposed-host marker, and the realization +
  # insecure aggregator. The host imports this.
  nixosModule =
    { ... }:
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
      # contract.affordances (ADR-0025, issue #25): the HOST's voice — the features this host is
      # willing to grant to users who offer them, declared ONCE per host. Same `{ <feature>.enable
      # = bool; }` shape as a grant set (grantedOptions). It is the symmetric counterpart of the
      # user's `contract.requests` and a generalisation of the greeter's safe set (the safe set is
      # simply the greeter's affordance). Consumed by `bindContractUser` — the sole public consumer
      # bind (ADR-0026) — which derives each user's grant as `affordances ∩ offer`: a NECESSARY
      # condition, the host's absolute veto — a feature not afforded is never granted, whatever a
      # user offers. There is no unilateral direct-grant path: the public grant model is always
      # negotiated.
      options.contract.affordances = lib.mkOption {
        type = lib.types.submodule { options = grantedOptions; };
        default = { };
        description = "Features this host affords to users who offer them (ADR-0025); bindContractUser derives each grant as affordances ∩ offer. Same shape as a grant set; the host's absolute veto.";
      };
      options.custom.host.exposed = lib.mkEnableOption "an exposed/agent-facing host — a plain fact a user's home may read (via hostFacts) and adapt to; the contract enforces nothing on it";
      # Package policy inclusion list (ADR-0017, issue #17): after contractPackage activation,
      # bindContractPackage replaces ~/.nix-profile with a host-built profile containing the
      # INTERSECTION of this list and the user's package manifest. Programs the user declared
      # but the host did not allow are absent; programs not in this list are never imposed. An
      # empty list (the default) means no package policy — ~/.nix-profile is left as-is after
      # activation. Each name resolves to `pkgs.<name>` from the host's nixpkgs pin; unknown
      # names are silently dropped (graceful degradation). Effective for users bound via the
      # pre-built path (bindContractUser and its bindContractPackage kernel), where a daemon-
      # restricted user's ~/.nix-profile is rebuilt from this list.
      options.custom.host.packagePolicy.allowedPrograms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Programs the host allows in user sessions (ADR-0017). Each entry resolves to pkgs.<name> from the host's nixpkgs pin. Non-empty enables profile replacement after contractPackage activation.";
      };
    };

  # Home kit: the identity + home-profile vocabulary + the contract.requests namespace the
  # user emits. The home identity value is populated from the system identity by the host.
  homeModule = _: {
    options.identity = identityOptions;
    options.custom.home.profiles = homeProfileOptions;

    # contract.requests (ADR-0002/0007, issue #5): the typed, read-only namespace a user's
    # home module POPULATES to describe host-affecting parameters of the features it
    # offers (e.g. gui.desktop). The host bridges the GRANTED ones from the pre-built manifest
    # (bindContractPackage) or a dry-run harvest (traceUser); the user only asks, never writes
    # system state. Its per-feature shape IS the registry's
    # feature `config` fragments (featureConfigOptions) — the same parameters carried
    # system-side as custom.users.<u>.<feature>.* today (ADR-0003), now emitted from the
    # user's own side. Enforcement (ADR-0002 "ignore-overreach / validate-intent"):
    #   - a KNOWN request is typed, so a malformed one (wrong-typed gui.desktop, a
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

  # Home helper (ADR-0013): auto-surface the user's DESKTOP CHOICE so the greeter's session
  # launcher can read it. The greeter runs the session BEFORE evaluating the home's Nix, so it
  # reads the choice from a dotfile (`~/.contract-desktop`, see contract-greeter-session); this
  # materialises that file from the home's `contract.requests.gui.desktop`, so the portable-user
  # choice travels with the home and needs NO manual step. It is SEPARATE from `homeModule` (which
  # is pure schema the headless tracer evaluates with NO home-manager): this sets `home.file`, a
  # home-manager option, so a real home imports it ALONGSIDE the umbrella inside home-manager. Inert
  # when no desktop is requested ⇒ the greeter falls back to the seat default. Package-free: it only
  # references the `home.file` option path (home-manager declares it), never imports home-manager.
  homeGreeterDesktopModule =
    { config, ... }:
    # gui.desktop is a declared request option (always present, defaulting to ""), so read it
    # directly — no fallback. The empty default is the "no choice ⇒ seat default" case below.
    lib.mkIf (config.contract.requests.gui.desktop != "") {
      home.file.".contract-desktop".text = config.contract.requests.gui.desktop;
    };
}
