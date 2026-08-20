# Conformance domain: the USER DECLARATION — the whole of what a user says, and the whole of the
# user-facing surface.
#
#   contract.<mode> = { enable; configuration; <that mode's own parameters> };
#
# Everything here is proven against the REAL schema module the contract ships
# (`../contract-user.nix`, reached through `kit.internal.userOptions`), evaluated by bare
# `evalModules` with no home-manager — which is the same evaluation the producer makes to learn a
# user's modes, and the same one a greeter's `nix eval` makes over the published index.
#
# The claims fall into three groups:
#   SHAPE      what a declaration is, and what it defaults to.
#   TYPING     what it cannot say. The schema is a projection of the mode registry and carries no
#              freeform, so a misspelled mode or parameter is an error in the USER's own repo, at
#              the moment they write it — never a user nothing can bind, discovered later by a host
#              operator.
#   LOCATION   a parameter lives on the thing it parameterises. `desktop` is a property of the
#              graphical session, so it exists on `contract.gui` and nowhere else.
#   DEAD DATA  the one mistake a fully-typed schema cannot catch by itself: a mode configured but
#              never enabled. Every value in it is individually well-formed; only the pair is
#              wrong. That guard lives where the declaration is READ (`declarationOf`), so it is
#              driven here through `mkMembers`, with the fixture's own control.
{
  lib,
  toolkit,
  modes,
  enabledModesOf,
  mkMembers,
  mkContractHome,
}:
let
  inherit (toolkit) evalDeclaration referenceDeclaration;

  # Nothing said at all.
  silent = evalDeclaration [ ];
  bothModes = evalDeclaration [
    {
      contract.cli.enable = true;
      contract.gui = {
        enable = true;
        desktop = "plasma";
      };
    }
  ];
  guiOnly = evalDeclaration [ { contract.gui.enable = true; } ];

  # A declaration is only observed through its evaluated value, so an error is observed by trying
  # to force one. `deepSeq` reaches the module system's unmatched-definition check.
  refuses = mods: !(builtins.tryEval (builtins.deepSeq (evalDeclaration mods) true)).success;
in
{
  assertions = [
    # ── SHAPE ────────────────────────────────────────────────────────────────────────────────
    {
      # One key per mode, always present — the schema is a projection of the mode registry, so the
      # declaration's vocabulary and the contract's cannot drift.
      name = "declaration: it has exactly one key per MODE the contract names";
      ok = lib.attrNames silent == lib.attrNames modes;
    }
    {
      # NOTHING defaults to enabled. A default would set a user's essential nature without the user
      # having said anything, and would silently satisfy the at-least-one-mode rule.
      name = "declaration: no mode is enabled by default — a user that says nothing runs nowhere";
      ok = enabledModesOf silent == [ ];
    }
    {
      # …and the enabled-name projection is what everything downstream reads.
      name = "declaration: enabling modes shows up as the enabled-mode projection";
      ok =
        enabledModesOf bothModes == [
          "cli"
          "gui"
        ]
        && enabledModesOf guiOnly == [ "gui" ];
    }
    {
      # A mode with no home content is a real shape (a service account, a break-glass admin): it
      # still yields an account and the contract's own home baseline.
      name = "declaration: `configuration` defaults to the empty module";
      ok = silent.cli.configuration != null && guiOnly.gui.configuration != null;
    }
    {
      # Reading a declaration must never force the home behind it — that is what lets the producer
      # and a greeter learn a user's modes for the price of an eval. `configuration` is a
      # deferredModule, so a declaration pointing at a path that does not exist still reads back.
      name = "declaration: reading the modes never forces the home behind `configuration`";
      ok =
        enabledModesOf (evalDeclaration [
          {
            contract.cli = {
              enable = true;
              configuration = /this/path/does/not/exist.nix;
            };
          }
        ]) == [ "cli" ];
    }

    # ── TYPING ───────────────────────────────────────────────────────────────────────────────
    {
      # A misspelled MODE is an error, not a silently-ignored key. There is no freeform: a user
      # nothing can bind is worse than a user that fails to evaluate in its own repo.
      name = "declaration: a mode the contract does not name is an eval error";
      ok = refuses [ { contract.desktop.enable = true; } ];
    }
    {
      name = "declaration: a misspelled field within a known mode is an eval error";
      ok = refuses [ { contract.gui.enabel = true; } ];
    }
    {
      name = "declaration: a wrong-typed mode parameter is an eval error";
      ok = refuses [ { contract.gui.desktop = 42; } ];
    }
    {
      name = "declaration: a wrong-typed `enable` is an eval error";
      ok = refuses [ { contract.cli.enable = "yes"; } ];
    }

    # ── LOCATION ─────────────────────────────────────────────────────────────────────────────
    {
      # `desktop` belongs to the graphical session, so it is declared on the gui MODE. A terminal
      # has no desktop to choose, and writing one there is a mistake the schema catches rather than
      # a value nothing reads.
      name = "declaration: `desktop` exists on the gui mode";
      ok = bothModes.gui.desktop == "plasma";
    }
    {
      name = "declaration: `desktop` does NOT exist on the cli mode — a terminal has none to choose";
      ok = refuses [
        {
          contract.cli.enable = true;
          contract.cli.desktop = "plasma";
        }
      ];
    }
    {
      # No choice ⇒ the seat's own default. The empty string is what makes the desktop dotfile
      # inert for a user who does not care, so a gui home costs nothing to a seat with one desktop.
      name = "declaration: a gui user that names no desktop defaults to the empty (seat-default) name";
      ok = guiOnly.gui.desktop == "";
    }

    # ── DEAD DATA ────────────────────────────────────────────────────────────────────────────
    {
      # A mode carrying a home and a desktop that no host can ever be given, because nothing will
      # build it. The likeliest reading is a forgotten `enable`, and the schema alone cannot say so
      # — every definition in the file is well-typed.
      name = "declaration: a mode configured but never enabled is a hard error, not silent dead data";
      ok =
        !(builtins.tryEval (builtins.deepSeq (mkMembers { usersDir = ./fixtures/declarations; }) true))
        .success;
    }
    {
      # THE CONTROL, and the fixture exists for it: the byte-identical settings with the one
      # missing line restored compose a home. Without this, "the guard fires" could hold for a
      # reason that has nothing to do with the missing `enable`.
      name = "declaration: the same settings WITH `enable` compose a home (the control)";
      ok =
        (mkContractHome {
          homeManagerConfiguration = args: args;
          pkgs.stdenv.hostPlatform.system = "riscv64-linux";
          memberDir = ./fixtures/declarations/live;
          mode = "gui";
          stateVersion = "25.11";
        }) ? modules;
    }

    # ── THE REFERENCE ATOM ───────────────────────────────────────────────────────────────────
    {
      # The real `users/ada/user.nix` from the reference fleet, read by this suite exactly as the
      # producer reads it. If the reference user's own file ever stops saying what her header
      # claims, this domain notices.
      name = "declaration: the reference user runs in both modes and asks for plasma";
      ok =
        enabledModesOf referenceDeclaration == [
          "cli"
          "gui"
        ]
        && referenceDeclaration.gui.desktop == "plasma";
    }
  ];
}
