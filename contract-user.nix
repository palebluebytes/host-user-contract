# The USER DECLARATION schema — the whole of what a user says, and the entire user-facing surface
# of this contract. It is a PROJECTION of the mode registry (`modes.nix`): one submodule per mode,
# so a contract that gains a mode gains its declaration with no edit here, and a user naming a mode
# the contract does not have is an eval error in the user's own repo rather than a user nothing can
# bind.
#
# A user declaration is `users/<name>/user.nix`, and it says exactly one kind of thing:
#
#   contract.gui = {
#     enable        = true;
#     configuration = ./home.nix;
#     desktop       = "plasma";
#   };
#   contract.cli = {
#     enable        = true;
#     configuration = ./home.nix;
#   };
#
# WHICH SESSION SHAPES THIS USER RUNS IN, and for each one the home to build and that shape's own
# parameters. Nothing else — in particular a user does NOT say which FEATURES it wants, and the
# veto it actually needs ("never give me a desktop") is expressible here by not enabling the gui
# mode (ADR-0010).
#
# IT IS NOT A HOME-MANAGER MODULE. Evaluated by bare `evalModules` with no home-manager present
# (ADR-0002), which is what lets the producer read a user's published modes without building
# anything and lets a greeter learn them from a plain `nix eval`. The home-manager content lives
# behind `configuration`, a deferredModule, so it is never forced by that read.
{ lib, modeRegistry }:
{
  options.contract = lib.mapAttrs (
    _: m:
    lib.mkOption {
      type = lib.types.submodule {
        options = {
          # Whether this user runs in this session shape. There is NO default, deliberately: a
          # user's essential nature is not set by inheritance, and a default that satisfied
          # "at least one mode" would decide what a user IS without the user having said anything.
          # The `false` is only so the module system has a value to merge; a user that says nothing
          # enables nothing, and the bake refuses that by name.
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this user runs in ${m.description}. At least one mode is required; nothing defaults to true.";
          };

          # THE HOME for this mode — an ordinary home-manager module (a path, an attrset, or a
          # function), composed by the producer with the contract's own umbrella and baseline.
          #
          # It is PER MODE because that is the whole reason modes exist: a sway config cannot be
          # injected into a home built for a terminal, so the graphical home and the terminal home
          # are different derivations. Two modes may name the SAME file — the common case, where a
          # user's home does not depend on the session — and a user with genuinely mode-specific
          # content points them at different ones (or at a shared module plus a leaf).
          #
          # A `deferredModule`, so reading this declaration to learn which modes a user runs never
          # forces the home: the producer and the greeter both read the mode set long before
          # anything is built. It defaults to the empty module — a user with no home content at all
          # still gets an account and the contract's baseline, which is a real shape (a service
          # account, a break-glass admin).
          configuration = lib.mkOption {
            type = lib.types.deferredModule;
            default = { };
            description = "The home-manager module built for this mode. Two modes may name the same module; a mode with no configuration still yields an account and the contract's home baseline.";
          };
        }
        # The mode's own PARAMETERS, declared in `modes.nix` beside the mode itself (gui's
        # `desktop`). They sit HERE, on the mode, rather than in a parallel namespace keyed by
        # feature: a parameter belongs to the thing it parameterises, and one namespace cannot
        # drift from the other if there is only one.
        // (m.options or { });
      };
      default = { };
      description = "This user's declaration for ${m.description}: whether it runs there, the home to build, and that session's own parameters.";
    }
  ) modeRegistry;
}
