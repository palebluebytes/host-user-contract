# agent — an EXPOSED, headless host (custom.host.exposed = true).
#
# Exposure is the security-critical case: an exposed host may NEVER be granted a secret-bearing
# feature (the exposed-host ban, ADR-0001 threat model). So this host binds only users it can grant
# safely, and deliberately does NOT run ben (whose signing grant would trip the ban):
#   - ada, GRANTED nothing (cli-only): the SAME ada output that is gui on workstation, here bound
#     with no gui grant — her gui.desktop request is not bridged, the surface stays off, no input
#     groups. One identity, one output, opposite session because the HOST decided (ADR-0002 silent
#     degradation).
#   - svc, GRANTED nothing: the cli-only automation account, at home on an exposed box.
#
# Because it grants no secret-bearing feature, the exposed-host ban raises no failure — the positive
# demonstration that exposure and correct granting coexist.
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
