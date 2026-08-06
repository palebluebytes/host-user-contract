# vault — a headless, NON-exposed host.
#
# It affords NOTHING (default `contract.affordances = { }`) and binds:
#   - ben: a cli-only reference account (offers nothing).
#   - svc: a cli-only automation account (offers nothing).
#
# Non-exposed and headless: affords no gui, so no display surface.
{ contract, users, ... }:
{
  imports = [
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "ben";
    })
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "svc";
    })
  ];

  networking.hostName = "vault";
}
