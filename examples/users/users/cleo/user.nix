# cleo — the privileged-group reference user.
#
# cleo is in `docker` on exactly the hosts that afford her `containers`, and nowhere else. There is
# no second route to try: an identity names no groups at all, so a privileged group can only ever
# arrive as a grant somebody decided to make. She is also a gui user (gnome), to vary the desktop
# from ada's plasma across the fleet.
{
  contract.cli.enable = true;
  contract.gui = {
    enable = true;
    desktop = "gnome";
  };
}
