# vault — a headless, NON-exposed host.
#
# It affords NOTHING (default `contract.affordances = { }`) and binds:
#   - ben: a cli-only reference account (offers nothing).
#   - svc: a cli-only automation account (offers nothing).
#
# Non-exposed and headless: affords no gui, so no display surface.
{ bindUserTurnkey, ... }:
{
  imports = [
    (bindUserTurnkey "ben")
    (bindUserTurnkey "svc")
  ];

  networking.hostName = "vault";
}
