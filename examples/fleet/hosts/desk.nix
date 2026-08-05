# desk — a SEAT host (non-exposed) with the reference greeter enabled.
#
# It declares its `contract.affordances` ONCE and binds three users turnkey via `bindUserFromFlake`
# (ADR-0025) — no per-user grants, no variant names, no identity paths. Each user's grant is
# derived as `affordances ∩ offer`:
#   - ada OFFERS gui; desk affords gui ⇒ she gets it — her gui.desktop request bridges in, the
#     display surface turns on, she gets the gui input groups. This is ada-as-gui-user (contrast
#     agent, which does NOT afford gui, so the SAME ada is cli-only there).
#   - cleo OFFERS containers; desk affords it ⇒ the grant confers `docker`/`podman` — the ONLY way
#     cleo obtains them, since her self-declared `docker` in identity.extraGroups is clamped out
#     otherwise. `containers` is atomic (ADR-0024): container access and nothing else, no wheel.
#   - admin OFFERS sudo; desk affords it ⇒ `wheel` and nothing more (contrast cleo — atomic grants
#     compose, the host affords both). A break-glass account whose login password is "password".
# desk affords all three; each user still receives only the intersection with its own offer, so no
# user is over-granted (ada gets neither docker nor wheel, etc.).
#
# It also enables the reference greeter (a seat concern): the runtime login path. The greeter's
# end-to-end provisioning is exercised by the fleet-integration VM, which consumes the same ada
# output at runtime — declarative here, runtime there, one convention.
{ contract, bindUserTurnkey, ... }:
{
  imports = [
    contract.nixosModules.greeter
    (bindUserTurnkey "ada")
    (bindUserTurnkey "cleo")
    (bindUserTurnkey "admin")
  ];

  contract.affordances = {
    gui.enable = true;
    containers.enable = true;
    sudo.enable = true;
  };

  networking.hostName = "desk";
  custom.greeter.enable = true;
}
