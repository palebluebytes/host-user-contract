# vault — a headless, NON-exposed host.
#
# It affords NOTHING (default `contract.affordances = { }`), so it RUNS the floor alone —
# `{ cli }` (ADR-0032), derived, with no mode declared anywhere. It binds:
#   - ben: a plain reference account. He rides the safe-set gui default, but vault affords no gui,
#     so the host's veto makes him cli-only here — the offer is only half of the negotiation. He
#     supports `cli`, so this host has a mode of his to bind; a user supporting only `gui` would be
#     REFUSED here rather than silently given a lesser home.
#   - svc: the user-side veto (it opts out of gui in its own home, so it offers no desktop
#     anywhere — belt and braces on a host that affords none anyway).
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
