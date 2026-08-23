# The contract's umbrella modules — one per eval-side. Each is closed over the option fragments and
# registry projections the kit computes, so it names neither `self` nor `inputs` (ADR-0002).
{
  lib,
  realization,
  identityOptions,
  grantedOptions,
  modeNames,
  floorMode,
}:
{
  # System kit: the host's declarations, the account schema, and the realization.
  #
  # EVERYTHING THE CONTRACT PUTS ON A HOST LIVES UNDER `contract.*` — the declarations an operator
  # writes and the values a bind writes back — and so does the user's own declaration, in its
  # `user.nix`, on the other eval-side (ADR-0026).
  nixosModule =
    { ... }:
    {
      imports = [
        realization
        ./insecure-packages.nix
      ];

      # THE MACHINE CAPABILITY, and the only thing a host says about itself that is not per-user.
      # A fact about the hardware, never a judgement about a person: incapacity, not policy
      # (ADR-0007, ADR-0009).
      #
      # FAIL-CLOSED, and deliberately the opposite default to the producer's home matrix, which
      # subtracts (ADR-0009, ADR-0012). THE FLOOR IS IMPLICIT and unexcludable: `runsWith` filters
      # the registry rather than concatenating this list, so the declaration is a SET.
      options.contract.modes = lib.mkOption {
        type = lib.types.listOf (lib.types.enum modeNames);
        default = [ ];
        example = [ "gui" ];
        description = "Session shapes this machine can run, beyond the floor (`${floorMode}`), which every host runs. A capability of the box, not a policy about anybody: what a given account is allowed to DO is `affordances`, stated per bind.";
      };

      # A bound account, and the whole of it. Written by a bind; an operator never sets it.
      #
      # The `mode` is here because the account needs it: a graphical session's input groups ride
      # the mode rather than a grant (ADR-0006), so `accountPlan` cannot derive an account's groups
      # without it. It defaults to the floor, so an account assembled by hand — a fixture, a host
      # with its own binding — is a terminal account rather than an error.
      options.contract.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              identity = identityOptions;
              granted = grantedOptions;
              mode = lib.mkOption {
                type = lib.types.enum modeNames;
                default = floorMode;
                description = "The session shape this account was bound in. Written by a bind; it decides which mode groups the account needs.";
              };
            };
          }
        );
        default = { };
        description = "Per-user identity, grants and bound mode, written by a bind.";
      };

      options.contract.exposed = lib.mkEnableOption "an exposed/agent-facing host — a plain fact a host operator records; the contract enforces nothing on it";

      # The host's half of program scope (ADR-0016): after contractPackage activation a bind
      # replaces ~/.nix-profile with the INTERSECTION of this list and the user's package manifest.
      # An empty list (the default) means no package policy at all — the profile is left as
      # activated. Each name resolves to `pkgs.<name>` from the host's pin, and an unknown name is
      # silently dropped.
      options.contract.packagePolicy.allowedPrograms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Programs the host allows in user sessions. Each entry resolves to pkgs.<name> from the host's nixpkgs pin. Non-empty enables profile replacement after contractPackage activation.";
      };
    };

  # Home kit: the identity a home is handed. That is the whole of it — the user's VOICE lives one
  # level up, in `users/<u>/user.nix`, which is not a home-manager module (./contract-user.nix,
  # ADR-0010). A home HOLDS its identity — it neither loads it nor authors it — so `git.userName`
  # and friends read `config.contract.identity` instead of each home re-reading identity.json
  # (ADR-0005).
  #
  # UNDER THE PREFIX like every other surface the contract declares (ADR-0026). The reason here is
  # the collision, not the provenance: this is a home-manager module tree, and a BARE top-level
  # `identity` is the one case ADR-0026's "no prefix" alternative names — home-manager declares
  # what it declares upstream, on its own schedule, and a top-level name that arrives there MERGES
  # with the contract's rather than colliding with it.
  #
  # It stays evaluable by BARE `evalModules` with no home-manager present (ADR-0002).
  homeModule = _: {
    options.contract.identity = identityOptions;
  };

  # The HOME BASELINE: the standing, uniform-across-users home-manager hygiene every produced home
  # starts from — a PINNED POSTURE, not an opinion set, with no opt-out knob (ADR-0014).
  # `mkContractHome` composes it by default; `homeModules.baseline` exposes it for a consumer
  # building homes by hand. It lives OUTSIDE `homeModules.default` because it sets home-manager
  # options, and the default umbrella must stay evaluable by bare evalModules (ADR-0002).
  #
  # Every line is `lib.mkDefault`, which is what makes the missing knob safe: a user module's PLAIN
  # definition wins per-option (prio 100 < 1000), while the pin still beats an upstream option
  # default (prio 1000 < 1500).
  homeBaselineModule = _: {
    # Self-manage: the home-manager CLI rides the home it manages — the one line with live effect
    # today (home-manager does not enable it by default in a standalone homeManagerConfiguration).
    programs.home-manager.enable = lib.mkDefault true;
    # PIN, and the line that shows what a pin is: upstream's default is already `true` (the
    # option's apply maps "sd-switch" -> true), so this changes nothing today. It holds the
    # restart-on-switch semantics against upstream default churn (ADR-0014).
    systemd.user.startServices = lib.mkDefault "sd-switch";
  };

  # The DESKTOP dotfile, as a function of the value rather than a module that reads one. A greeter
  # launches the session before evaluating any of the home's Nix, so the choice has to travel with
  # the home as a file (`~/.contract-desktop`, read by contract-greeter-session) — which is why it
  # cannot move host-side (ADR-0021).
  #
  # It takes the desktop NAME because the value does not live in the home: the gui mode's `desktop`
  # parameter is declared in `users/<u>/user.nix`, and `mkContractHome` hands it here when it
  # composes the gui home. Empty ⇒ nothing is written, and the seat's default is used.
  homeDesktopModule =
    desktop: _:
    lib.optionalAttrs (desktop != "") {
      home.file.".contract-desktop".text = desktop;
    };
}
