# vault — a headless, NON-exposed host that runs the secret-bearing user.
#
# It binds:
#   - ben, GRANTED signing (secret-bearing): safe here precisely because the host is not exposed,
#     so the exposed-host ban does not apply. The grant matches the variant ben's contractPackage
#     was baked with (ADR-0016 coupling guard), and ben's signing secret rides his own home sops.
#   - svc, GRANTED nothing: a cli-only automation account.
#
# Non-exposed and headless: no gui grants, so no display surface.
{ bindUserPkg, ... }:
{
  imports = [
    (bindUserPkg {
      name = "ben";
      grants = {
        signing.enable = true;
      };
    })
    (bindUserPkg {
      name = "svc";
      grants = { };
    })
  ];

  networking.hostName = "vault";
}
