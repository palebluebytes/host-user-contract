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
  # What svc asks a host for (ADR-0028): nothing — the explicit OPT-OUT. Every non-privileged (safe-set) feature is wanted
  # by default, so an account that must never take a seat says so — this is the one line that keeps
  # "never gui" true even on a host that affords gui.
  contract.wants.gui.enable = false;
  custom.home.profiles.cli.enable = true;
}
