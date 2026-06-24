# Conformance domain: the contract.requests namespace (ADR-0018/0023) a user's home emits, and the
# desktop-choice home helper (ADR-0029) that surfaces it to ~/.contract-desktop. Both are home-side,
# proven with bare evalModules — no home-manager (ADR-0020).
{
  lib,
  toolkit,
  homeModule,
  homeGreeterDesktopModule,
}:
let
  inherit (toolkit) evalHome;

  guiRequest = evalHome [ { contract.requests.gui.session = "x11"; } ];
  # An unknown FEATURE key is accepted (freeformType) and ignored — build still happens.
  unknownRequest = evalHome [ { contract.requests.bogusFeature.whatever = 42; } ];
  # A malformed KNOWN request (bad enum) must fail to evaluate (the typo-net).
  malformedRequest = builtins.tryEval (
    (evalHome [ { contract.requests.gui.session = "macos"; } ]).contract.requests.gui.session
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
      name = "requests: a known request (gui.session) is readable on the home eval";
      ok = guiRequest.contract.requests.gui.session == "x11";
    }
    {
      name = "requests: an unknown feature key is accepted and ignored (build still happens)";
      ok = unknownRequest.contract.requests.bogusFeature.whatever == 42;
    }
    {
      name = "requests: a malformed known request (bad gui.session enum) errors";
      ok = !malformedRequest.success;
    }
    {
      # ADR-0029 helper: a requested desktop is auto-surfaced to ~/.contract-desktop verbatim, so the
      # greeter's launcher (which runs before the home Nix) reads the user's choice with no manual step.
      name = "desktop helper: contract.requests.gui.desktop materialises ~/.contract-desktop";
      ok = desktopChosen.home.file.".contract-desktop".text == "plasma";
    }
    {
      # No desktop requested ⇒ no dotfile, so the greeter degrades to the seat default (ADR-0029).
      name = "desktop helper: no desktop request leaves ~/.contract-desktop absent (seat default)";
      ok = !(desktopUnset.home.file ? ".contract-desktop");
    }
  ];
}
