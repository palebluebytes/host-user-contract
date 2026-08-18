# desk — a SEAT host (non-exposed) with the reference greeter enabled.
#
# It declares its `contract.affordances` ONCE and binds three users turnkey via `bindContractUser`
# (ADR-0025) — no per-user grants, no mode names, no identity paths. Because it affords `gui`, it
# RUNS `{ cli, gui }` (ADR-0032): the modes a host runs are DERIVED from its affordances and nobody
# declares them, so nothing here says `gui` twice. Each user gets the rich mode it publishes, and
# each user's grant is derived as `affordances ∩ offer`, where the offer is that user's own
# `contract.wants` harvested from its home (ADR-0028):
#   - ada wants gui (the safe-set default); desk affords gui ⇒ she gets it — her gui.desktop request
#     bridges in, the display surface turns on, she gets the gui input groups. This is ada-as-gui-user
#     (contrast agent, which does NOT afford gui, so the SAME ada is cli-only there).
#   - cleo asks for containers (privileged ⇒ never a default); desk affords it ⇒ the grant confers
#     `docker`/`podman` — the ONLY way cleo obtains them, since her self-declared `docker` in
#     identity.extraGroups is clamped out otherwise. `containers` is atomic (ADR-0024): container
#     access and nothing else, no wheel.
#   - admin asks for sudo (privileged) and rides the gui default; desk affords both ⇒ `wheel` plus
#     the gui input groups. The sudo grant itself still confers wheel and NOTHING else — atomic
#     grants compose rather than bundle (contrast cleo's docker). A break-glass account whose login
#     password is "password".
# desk affords all three; each user still receives only the intersection with its own offer, so no
# user is over-granted (ada gets neither docker nor wheel, etc.).
#
# It also enables the reference greeter (a seat concern): the runtime login path. The greeter's
# end-to-end provisioning is exercised by the fleet-integration VM, which consumes the same ada
# home at runtime — declarative here, runtime there, one convention, and since ADR-0032 literally
# one artifact: there is no greeter-specific home to build.
{ contract, users, ... }:
{
  imports = [
    contract.nixosModules.greeter
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "ada";
    })
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "cleo";
    })
    (contract.lib.bindContractUser {
      usersFlake = users;
      username = "admin";
    })
  ];

  contract.affordances = {
    gui = true;
    containers = true;
    sudo = true;
  };

  networking.hostName = "desk";
  custom.greeter.enable = true;
}
