# duo-a's MODE-INDEPENDENT home content — everything that is the same whichever session it runs in.
#
# This is the idiom and the common case: a shell alias file, a git config, an editor rc — none of
# them care what session they are in, so none of them is written twice. Both of duo-a's modes
# import this module; only the parts that genuinely differ live in `cli.nix` and `gui.nix`.
{ ... }:
{
  # The shared setup, opted into per user — one module, one overlay, both from `../../shared/`.
  imports = [ ../../shared/module.nix ];

  # A home may declare its OWN overlays even though the producer passes `pkgs` explicitly — this
  # list MERGES with the producer's rather than replacing it. Why that holds, and why this overlay
  # needs no `inputs` specialArg, is spelled out once in `shared/overlay.nix`.
  nixpkgs.overlays = [ (import ../../shared/overlay.nix) ];

  home.file.".config/duo/common.conf".text = ''
    # duo-a's mode-independent settings — present in the cli home and the gui home alike.
    editor = nvim
  '';
}
