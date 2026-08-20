# duo-b's home — the same module in both of its modes, because nothing in it depends on the session.
{ ... }:
{
  imports = [ ../../shared/module.nix ];

  nixpkgs.overlays = [ (import ../../shared/overlay.nix) ];
}
