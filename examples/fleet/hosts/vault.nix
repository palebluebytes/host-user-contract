# vault — a headless, NON-exposed host.
#
# It binds:
#   - ben, GRANTED nothing: a cli-only reference account.
#   - svc, GRANTED nothing: a cli-only automation account.
#
# Non-exposed and headless: no gui grants, so no display surface.
{ bindUserPkg, ... }:
{
  imports = [
    (bindUserPkg {
      name = "ben";
      grants = { };
    })
    (bindUserPkg {
      name = "svc";
      grants = { };
    })
  ];

  networking.hostName = "vault";
}
