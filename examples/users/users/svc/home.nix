# svc — a pure automation account.
#
# cli-only on every host that runs it, never gui, never a secret. It offers no gui desktop, so no
# host can grant it a display surface — the minimal end of the roster, present to show that a user
# which never touches a seat consumes the contract exactly like the others (one contractPackage,
# bound per host) and simply carries the smallest home.
#
# Contract-pure (ADR-0008).
{ ... }:
{
  custom.home.profiles.cli.enable = true;
}
