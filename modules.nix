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
  wantedOptions,
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

  # Home kit: the identity + home-profile vocabulary + the user's two-part VOICE — which features
  # it wants (contract.wants) and their parameters (contract.requests). The home identity value is
  # populated from the system identity by the host.
  homeModule = _: {
    options.identity = identityOptions;
    options.custom.home.profiles = homeProfileOptions;

    # contract.wants (ADR-0028, issue #34): the user's ASK, declared in its own home — WHICH
    # features this user wants of a host, the counterpart of the host's `contract.affordances`
    # (and the source of the `offer`, which is this set once harvested and published).
    # `mkContractUser` HARVESTS it off the evaluated home and publishes it as the binding index's
    # `offer`, so the user's voice lives in ONE place (the home) rather than split between the home
    # and the producer's flake. `bindContractUser` then derives the grant as `affordances ∩ offer`.
    #
    # Same `{ <feature>.enable = bool; }` shape as a grant set (wantedOptions is DERIVED from
    # grantedOptions) — one shape across wants/affordances/granted/offer, so the grant algebra
    # needs no normalising shim. NO freeformType: a want for a feature the contract does not
    # declare is a typo in the user's own repo, and typos must not silently become "offers nothing".
    # It defaults to the SAFE SET (the runtime-eligible, non-privileged features): a privileged
    # feature is only ever offered deliberately, and a user wanting no desktop writes
    # `contract.wants.gui.enable = false`.
    #
    # It must be VARIANT-INVARIANT: `contract.wants` may not depend on `hostFacts.granted`, because
    # the grant is derived FROM the offer — mkContractUser fails the bake if the harvest differs
    # across a user's baked variants.
    options.contract.wants = lib.mkOption {
      type = lib.types.submodule { options = wantedOptions; };
      default = { };
      description = "Features this user asks a host for (ADR-0028); mkContractUser harvests it as the binding index's offer and bindContractUser derives the grant as affordances ∩ offer. Same shape as a grant set; defaults to the safe set.";
    };

    # contract.requests (ADR-0002/0007, issue #5): the typed, read-only namespace a user's
    # home module POPULATES to describe host-affecting parameters of the features it
    # wants (e.g. gui.desktop). The host bridges the GRANTED ones from the pre-built manifest
    # (bindContractPackage) or a dry-run harvest (traceUser); the user only asks, never writes
    # system state. Its per-feature shape IS the registry's
    # feature `config` fragments (featureConfigOptions) — the same parameters carried
    # system-side as custom.users.<u>.<feature>.* today (ADR-0003), now emitted from the
    # user's own side. Enforcement (ADR-0002's "validate-intent", with its ignore-overreach half
    # superseded by ADR-0028): the namespace is FULLY typed — a malformed known request
    # (wrong-typed gui.desktop), a misspelled param within a known feature, and an unknown feature
    # key all ERROR. The freeformType that once accepted unknown keys for greeter forward-compat is
    # gone: version skew is handled at the DATA layer (bridgeRequests folds over the HOST's granted
    # names, so an unknown key is ignored by construction, and the manifest carries a version), so
    # the freeform's only remaining effect was hiding typos in the user's own repo. Cross-revision
    # tolerance lives where skew is real — `traceUser`'s permissive inspector mode.
    options.contract.requests = lib.mkOption {
      type = lib.types.submodule { options = featureConfigOptions; };
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
