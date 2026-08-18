# agent — an EXPOSED, headless host (custom.host.exposed = true).
#
# `exposed` is a plain host fact a user's home may read (via hostFacts) and adapt to; the contract
# enforces nothing on it. It affords NOTHING (the default `contract.affordances = { }`), so it runs
# the floor alone and grants nothing — the host's absolute veto in its simplest form, on both
# dimensions at once. It binds:
#   - ada: the SAME ada that is gui on desk. She wants gui, but agent affords none, so
#     `affordances ∩ offer = { }` — her gui.desktop request is not bridged, the surface stays off,
#     no input groups; and since agent runs only `cli`, selection binds her CLI home rather than her
#     gui one. One identity, one flake, opposite session because the HOST did not afford it
#     (ADR-0002 silent degradation for the grant, ADR-0032 mode selection for the home).
#   - svc: the user-side veto, at home on an exposed box; it offers no desktop anyway
#     (its home opts out of the safe-set gui default).
{ contract, users, ... }:
{
  imports = [
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "ada";
    })
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "svc";
    })
  ];

  networking.hostName = "agent";
  custom.host.exposed = true;
}
