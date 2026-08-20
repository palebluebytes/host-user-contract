# duo-a's CLI home: the common content, plus the terminal answer to "how do I drive windows?".
{ ... }:
{
  imports = [ ./common.nix ];

  home.file.".config/tmux/tmux.conf".text = ''
    # The CLI leaf — the counterpart of the sway config in ./gui.nix, answering the same concern
    # (window management) the way a terminal session can answer it.
    set -g prefix C-a
    bind | split-window -h
  '';
}
