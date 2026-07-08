# Conformance domain: the contract.requests namespace (ADR-0002/0007) a user's home emits, and the
# desktop-choice home helper (ADR-0013) that surfaces it to ~/.contract-desktop. Both are home-side,
# proven with bare evalModules — no home-manager (ADR-0004).
{
  lib,
  toolkit,
  homeModule,
  homeGreeterDesktopModule,
}:
let
  inherit (toolkit) evalHome;

  guiRequest = evalHome [ { contract.requests.gui.desktop = "plasma"; } ];
  # An unknown FEATURE key is accepted (freeformType) and ignored — build still happens.
  unknownRequest = evalHome [ { contract.requests.bogusFeature.whatever = 42; } ];
  # A malformed KNOWN request must fail to evaluate (the typo-net, ADR-0002). gui.desktop is
  # free-form but still typed `str`, so a wrong-typed value (an int, not a str) errors.
  malformedRequest = builtins.tryEval (
    (evalHome [ { contract.requests.gui.desktop = 42; } ]).contract.requests.gui.desktop
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
      name = "requests: an unknown feature key is accepted and ignored (build still happens)";
      ok = unknownRequest.contract.requests.bogusFeature.whatever == 42;
    }
    {
      name = "requests: a malformed known request (wrong-typed gui.desktop) errors";
      ok = !malformedRequest.success;
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
