# duo-a's GUI home: the common content, plus the graphical answer to "how do I drive windows?".
{ ... }:
{
  imports = [ ./common.nix ];

  home.file.".config/sway/config".text = ''
    # The GUI leaf — present only in the home built for the gui mode, and the reason duo-a's two
    # homes are different derivations rather than one home with a switch in it.
    set $mod Mod4
    bindsym $mod+Shift+q kill
  '';
}
