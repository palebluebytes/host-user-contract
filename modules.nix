# The contract's umbrella modules — one per eval-side. Each is closed over the option fragments and
# registry projections the kit computes, so it depends on neither `self` nor `inputs`, which is
# what lets the contract be a standalone flake.
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
  # writes and the values the contract writes back. There is no second prefix: `custom.*` said only
  # "not upstream NixOS", which is not a fact about anything, whereas `contract.users.<u>.granted`
  # tells a reader exactly where the value came from.
  #
  # The user's own declaration also lives under `contract.*`, in its `user.nix`. That symmetry is
  # deliberate — each party declares its half of the contract under the same word, on its own
  # eval-side — and it is why the host's display output is `contract.display.enabled` rather than
  # `contract.gui.*`, which would shadow the user's gui-mode declaration in a reader's head.
  nixosModule =
    { ... }:
    {
      imports = [
        realization
        ./insecure-packages.nix
      ];

      # THE MACHINE CAPABILITY, and the only thing a host says about itself that is not per-user.
      #
      # Which session shapes can this box run? A display is a fact about the hardware, not a
      # judgement about a person — a headless server does not *decline* to give Ada a desktop, it
      # *cannot* run one. That is incapacity, and it used to be laundered through the per-user
      # feature namespace as an `affordance`, where it behaved unlike every other entry: the one
      # feature in the safe set, the one associated with a mode, the one that meant a fact rather
      # than a policy.
      #
      # FAIL-CLOSED, and deliberately the opposite default to the producer's home matrix. A row of
      # that matrix names only what a system CANNOT build, because an under-bake is silent and
      # costs a user their session. Here the risk runs the other way: a host that said nothing and
      # was assumed to run everything would claim a display it may not have, and every machine in
      # a fleet would silently acquire each new mode as the contract grew. So a host enumerates
      # what it runs.
      #
      # THE FLOOR IS IMPLICIT. Every host runs it, so writing it changes nothing — `runsWith`
      # filters the registry rather than concatenating this list, which makes the declaration a
      # SET rather than a sequence: `[ "gui" ]`, `[ "gui" "cli" ]` and `[ "cli" "gui" ]` are one
      # declaration, order never reaches a diagnostic, and there is no spelling that excludes the
      # floor. A host that could refuse the floor would break "any host can enable any user".
      options.contract.modes = lib.mkOption {
        type = lib.types.listOf (lib.types.enum modeNames);
        default = [ ];
        example = [ "gui" ];
        description = "Session shapes this machine can run, beyond the floor (`${floorMode}`), which every host runs. A capability of the box, not a policy about anybody: what a given account is allowed to DO is `affordances`, stated per bind.";
      };

      # A bound account, and the whole of it: WHO the user is, WHICH features this host conferred,
      # and WHICH session shape it was bound in. Written by a bind; an operator never sets it.
      #
      # The `mode` is here because the account needs it: a graphical session's input groups ride
      # the mode rather than a grant, and `accountPlan` unions all three group sources in one
      # place. It defaults to the floor so an account assembled by hand — a fixture, a host with
      # its own binding — is a terminal account rather than an error.
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

      # Package policy inclusion list: after contractPackage activation, a bind replaces
      # ~/.nix-profile with a host-built profile containing the INTERSECTION of this list and the
      # user's package manifest. Programs the user declared but the host did not allow are absent;
      # programs not in this list are never imposed. An empty list (the default) means no package
      # policy — ~/.nix-profile is left as-is after activation. Each name resolves to `pkgs.<name>`
      # from the host's nixpkgs pin; unknown names are silently dropped. It matters most for a
      # daemon-restricted user, whose ~/.nix-profile is otherwise the only store they can reach.
      options.contract.packagePolicy.allowedPrograms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Programs the host allows in user sessions. Each entry resolves to pkgs.<name> from the host's nixpkgs pin. Non-empty enables profile replacement after contractPackage activation.";
      };
    };

  # Home kit: the identity a home is handed. That is the whole of it.
  #
  # The user's VOICE is not here — it lives one level up, in `users/<u>/user.nix`, which is not a
  # home-manager module (see ./contract-user.nix). A home is what a mode's declaration POINTS AT,
  # so by the time this module is in scope every question about which modes exist and what they
  # are parameterised by has been answered, and there is nothing left for a home to declare
  # outward. What a home still needs is who it belongs to, so `git.userName` and friends can read
  # it rather than each home re-loading identity.json.
  #
  # It stays evaluable by BARE `evalModules` with no home-manager present, which is what keeps the
  # contract free of a home-manager dependency.
  homeModule = _: {
    options.identity = identityOptions;
  };

  # The HOME BASELINE: the standing, uniform-across-users home-manager hygiene every produced home
  # starts from. `mkContractHome` composes it by default, and it is also exposed as
  # `homeModules.baseline` for a consumer building homes by hand. It lives OUTSIDE
  # `homeModules.default` because it sets home-manager options: the default umbrella must stay
  # evaluable by bare evalModules with no home-manager.
  #
  # HYGIENE IS A PINNED POSTURE, NOT AN OPINION SET: every line is `lib.mkDefault`, so there is no
  # opt-out knob — a user module's PLAIN definition wins per-option (prio 100 < 1000), while the
  # pin still beats an upstream option default (prio 1000 < 1500). What earns a line here is
  # "uniform across users AND worth pinning against upstream churn"; user intent stays out.
  homeBaselineModule = _: {
    # Self-manage: the home-manager CLI rides the home it manages — the one line with live effect
    # today (home-manager does not enable it by default in a standalone homeManagerConfiguration).
    programs.home-manager.enable = lib.mkDefault true;
    # PIN: upstream's default is already `true` (the option's apply maps "sd-switch" -> true), so
    # this line changes nothing TODAY. It is kept to pin the restart-on-switch semantics against
    # upstream default churn: a home whose services silently stop restarting on switch is a drift
    # no test catches.
    systemd.user.startServices = lib.mkDefault "sd-switch";
  };

  # The DESKTOP dotfile, as a function of the value rather than a module that reads one.
  #
  # A greeter runs the session BEFORE evaluating any of the home's Nix, so it reads the user's
  # desktop choice from a file in the home (`~/.contract-desktop`, see contract-greeter-session).
  # This materialises that file, so the portable-user choice travels with the home and needs no
  # manual step — which is also why it cannot move host-side.
  #
  # It takes the desktop NAME because the value does not live in the home: the gui mode's
  # `desktop` parameter is declared in `users/<u>/user.nix`, and `mkContractHome` hands it here
  # when it composes the gui home. Empty ⇒ nothing is written, and the seat's default is used.
  homeDesktopModule =
    desktop: _:
    lib.optionalAttrs (desktop != "") {
      home.file.".contract-desktop".text = desktop;
    };
}
