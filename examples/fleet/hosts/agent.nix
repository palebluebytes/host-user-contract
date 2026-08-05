# agent — an EXPOSED, headless host (custom.host.exposed = true).
#
# `exposed` is a plain host fact a user's home may read (via hostFacts) and adapt to; the contract
# enforces nothing on it. It affords NOTHING (the default `contract.affordances = { }`), so every
# user is bound cli-only whatever it offers — the host's absolute veto in its simplest form. It
# binds:
#   - ada: the SAME ada that is gui on desk. She OFFERS gui, but agent affords none, so
#     `affordances ∩ offer = { }` — her gui.desktop request is not bridged, the surface stays off,
#     no input groups. One identity, one flake, opposite session because the HOST did not afford it
#     (ADR-0002 silent degradation, now expressed as the affordance veto).
#   - svc: the cli-only automation account, at home on an exposed box; offers nothing anyway.
{ bindUserTurnkey, ... }:
{
  imports = [
    (bindUserTurnkey "ada")
    (bindUserTurnkey "svc")
  ];

  networking.hostName = "agent";
  custom.host.exposed = true;
}
