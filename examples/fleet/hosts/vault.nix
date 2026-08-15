# vault — a headless, NON-exposed host.
#
# It affords NOTHING (default `contract.affordances = { }`) and binds:
#   - ben: a plain reference account. He rides the safe-set gui default, but vault affords no gui,
#     so the host's veto makes him cli-only here — the offer is only half of the negotiation.
#   - svc: a cli-only automation account (it opts out of gui in its own home, so it offers nothing
#     anywhere — belt and braces on a host that affords nothing anyway).
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
