# desk — a SEAT host (non-exposed) with the reference greeter enabled.
#
# It says two different kinds of thing, and the split is the point.
#
# WHAT THIS MACHINE IS: `contract.modes = [ "gui" ]`. It has a display, so it runs the graphical
# session shape. That is a fact about the hardware, stated once, and it is true for everybody —
# nobody is being *given* anything by it. The floor (`cli`) is implicit; every host runs it.
#
# WHAT EACH PERSON MAY DO: their entry in `bindContractUsers`. These are decisions about people, so
# each sits beside the person it is about:
#   - ada is afforded NOTHING. She still logs into a full desktop, because a graphical session is
#     what this machine runs and the gui MODE carries its own input groups. This is the shape an
#     ordinary user's entry takes — a name, and an empty set.
#   - cleo is afforded `containers` ⇒ `docker`/`podman`, which is the ONLY way anybody obtains
#     them: an identity names no groups, so there is no other route to try. Atomic: container
#     access and nothing else, no wheel.
#   - admin is afforded `sudo` ⇒ `wheel`, and nothing more. Atomic grants compose rather than
#     bundle. A break-glass account whose login password is "password".
#
# Each name appears ONCE, as the key of its own settings. It is not the account's name — that comes
# from the user's own identity.json, and the producer refuses to publish a user whose key and
# identity disagree. It is a SELECTION: this users repo holds seven people and this machine wants
# three of them. `all = true` is for a host that wants the lot.
#
# The greeter needs no entry for anybody. It confers the safe set — which is empty, so no feature at
# all — and runs the modes this machine declared, so a stranger with a flake URL gets a desktop and
# can never get wheel.
{ contract, users, ... }:
{
  contract.modes = [ "gui" ];
  contract.greeter.enable = true;

  imports = [
    contract.nixosModules.greeter

    (contract.lib.bindContractUsers {
      source = users;
      users = {
        ada = { };
        cleo.containers = true;
        admin.sudo = true;
      };
    })
  ];

  networking.hostName = "desk";
}
