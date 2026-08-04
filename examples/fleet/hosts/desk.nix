# desk — a SEAT host (non-exposed) with the reference greeter enabled. (Named `desk`, not
# `workstation`, so it never collides with the `workstation` FEATURE it grants below.)
#
# It DECLARATIVELY binds two users by their contractPackage outputs:
#   - ada, GRANTED gui: her gui.desktop request bridges into the account, the display surface
#     turns on, and she gets the gui input groups. This is ada-as-gui-user (contrast agent, where
#     the SAME ada output is bound cli-only).
#   - cleo, GRANTED workstation: the privileged-group grant confers `docker` — the ONLY way cleo
#     obtains it, since her self-declared `docker` in identity.extraGroups is clamped out otherwise.
#
# It also enables the reference greeter (a seat concern): the runtime login path. The greeter's
# end-to-end provisioning is exercised by the fleet-integration VM, which consumes the same ada
# output at runtime — declarative here, runtime there, one convention.
{ contract, bindUserPkg, ... }:
{
  imports = [
    contract.nixosModules.greeter
    (bindUserPkg {
      name = "ada";
      grants = {
        gui.enable = true;
      };
    })
    (bindUserPkg {
      name = "cleo";
      grants = {
        workstation.enable = true;
      };
    })
    # admin, GRANTED sudo: the MINIMAL privileged grant — `wheel` and nothing more. Contrast cleo
    # above, whose `workstation` grant also confers docker/podman. A break-glass account whose
    # login password is the well-known "password".
    (bindUserPkg {
      name = "admin";
      grants = {
        sudo.enable = true;
      };
    })
  ];

  networking.hostName = "desk";
  custom.greeter.enable = true;
}
