# Conformance domain: the user's home-side VOICE — `contract.wants` (WHICH features this user asks
# for, ADR-0028) and `contract.requests` (their PARAMETERS, ADR-0002/0007) — plus the desktop-choice
# home helper (ADR-0013) that surfaces a request to ~/.contract-desktop. All home-side, proven with
# bare evalModules — no home-manager (ADR-0004).
{
  lib,
  toolkit,
  homeModule,
  homeGreeterDesktopModule,
  safeSet,
}:
let
  inherit (toolkit) evalHome;

  guiRequest = evalHome [ { contract.requests.gui.desktop = "plasma"; } ];
  # An unknown FEATURE key must now FAIL (ADR-0028 removed the freeformType): a request key the
  # contract does not know is a typo in the user's own repo, not forward-compat.
  unknownRequest = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.requests.bogusFeature.whatever = 42; } ]).contract.requests
      true
  );
  # A misspelled PARAM inside a known feature (gui.desktp) must fail too — the freeform accepted it
  # at any depth, silently yielding the seat default (a wrong desktop with no error).
  misspelledParam = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.requests.gui.desktp = "plasma"; } ]).contract.requests true
  );
  # A malformed KNOWN request must fail to evaluate (the typo-net, ADR-0002). gui.desktop is
  # free-form but still typed `str`, so a wrong-typed value (an int, not a str) errors.
  malformedRequest = builtins.tryEval (
    (evalHome [ { contract.requests.gui.desktop = 42; } ]).contract.requests.gui.desktop
  );

  # --- contract.wants: the user's feature selection, typed, in the home (ADR-0028) ---
  # The enabled feature names of a want/grant set — the same `.enable` fold the grant algebra uses
  # (grantLib.grantedNames), spelled here so the domain asserts against the SHAPE it claims.
  wantedNames = w: lib.attrNames (lib.filterAttrs (_: f: f.enable) w);
  defaultWants = (evalHome [ ]).contract.wants;
  privilegedWant = evalHome [ { contract.wants.sudo.enable = true; } ];
  optedOut = evalHome [ { contract.wants.gui.enable = false; } ];
  # No freeform here either: a want for a feature this contract has no registry entry for errors.
  unknownWant = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.wants.bogusFeature.enable = true; } ]).contract.wants true
  );
  # The shape MIRRORS grantedOptions (`{ <feature>.enable = bool; }`), so a bare boolean is a type
  # error rather than a silently-accepted second shape.
  bareBoolWant = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.wants.gui = true; } ]).contract.wants true
  );

  # The desktop helper sets `home.file`, a home-manager option the tracer-pure umbrella does not
  # declare, so — exactly as bind.nix's hmStub stands in for `home-manager.users` — a tiny stub
  # declares `home.file` so the helper's logic is provable with no home-manager.
  homeFileStub =
    { lib, ... }:
    {
      options.home.file = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule { options.text = lib.mkOption { type = lib.types.str; }; }
        );
      };
    };
  surfaceDesktop =
    mods:
    (lib.evalModules {
      modules = [
        homeModule
        homeFileStub
        homeGreeterDesktopModule
      ]
      ++ mods;
    }).config;
  desktopChosen = surfaceDesktop [ { contract.requests.gui.desktop = "plasma"; } ];
  desktopUnset = surfaceDesktop [ ];
in
{
  assertions = [
    {
      name = "requests: a known request (gui.desktop) is readable on the home eval";
      ok = guiRequest.contract.requests.gui.desktop == "plasma";
    }
    {
      name = "requests: an unknown feature key is an eval error (no freeform — ADR-0028)";
      ok = !unknownRequest.success;
    }
    {
      name = "requests: a misspelled param in a known feature (gui.desktp) is an eval error";
      ok = !misspelledParam.success;
    }
    {
      name = "requests: a malformed known request (wrong-typed gui.desktop) errors";
      ok = !malformedRequest.success;
    }

    # --- contract.wants (ADR-0028): the user's feature selection lives in the home ---
    {
      # Non-privileged features are wanted by default; privileged ones must be asked for. The
      # default IS the safe set — not a hardcoded gui — so a future non-privileged feature
      # inherits the posture with no new special case.
      name = "wants: the default is exactly the safe set";
      ok = wantedNames defaultWants == safeSet;
    }
    {
      name = "wants: the shape mirrors grantedOptions (<feature>.enable), a bare boolean errors";
      ok =
        lib.isBool defaultWants.gui.enable && lib.isBool defaultWants.sudo.enable && !bareBoolWant.success;
    }
    {
      # Asking for a privileged feature must not discard the safe-set default (the default is
      # per-feature, not a whole-submodule default a single definition would replace).
      name = "wants: asking for a privileged feature keeps the safe-set default (gui still wanted)";
      ok = privilegedWant.contract.wants.sudo.enable && privilegedWant.contract.wants.gui.enable;
    }
    {
      name = "wants: a user wanting no desktop opts out explicitly (gui.enable = false)";
      ok = wantedNames optedOut.contract.wants == [ ];
    }
    {
      name = "wants: an unknown feature key is an eval error (no freeform)";
      ok = !unknownWant.success;
    }
    {
      # ADR-0013 helper: a requested desktop is auto-surfaced to ~/.contract-desktop verbatim, so the
      # greeter's launcher (which runs before the home Nix) reads the user's choice with no manual step.
      name = "desktop helper: contract.requests.gui.desktop materialises ~/.contract-desktop";
      ok = desktopChosen.home.file.".contract-desktop".text == "plasma";
    }
    {
      # No desktop requested ⇒ no dotfile, so the greeter degrades to the seat default (ADR-0013).
      name = "desktop helper: no desktop request leaves ~/.contract-desktop absent (seat default)";
      ok = !(desktopUnset.home.file ? ".contract-desktop");
    }
  ];
}
