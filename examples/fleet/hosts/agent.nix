# agent — an EXPOSED, headless host (custom.host.exposed = true).
#
# `exposed` is a plain host fact a user's home may read (via hostFacts) and adapt to; the contract
# enforces nothing on it. This host binds:
#   - ada, GRANTED nothing (cli-only): the SAME ada output that is gui on desk, here bound
#     with no gui grant — her gui.desktop request is not bridged, the surface stays off, no input
#     groups. One identity, one output, opposite session because the HOST decided (ADR-0002 silent
#     degradation).
#   - svc, GRANTED nothing: the cli-only automation account, at home on an exposed box.
{ bindUserPkg, ... }:
{
  imports = [
    (bindUserPkg {
      name = "ada";
      grants = { };
    })
    (bindUserPkg {
      name = "svc";
      grants = { };
    })
  ];

  networking.hostName = "agent";
  custom.host.exposed = true;
}
