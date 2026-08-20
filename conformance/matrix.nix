# Conformance domain: the cross-product proof — synthetic users (two gui / one cli) × host
# archetypes (seat / exposed agent / headless). Every user realizes on every archetype with no
# failing assertion, and the display-surface behaviour holds per archetype.
#
# The archetypes differ along BOTH host dimensions, which is what this domain is for: a seat
# declares a machine capability (`contract.modes`) AND confers a power (`containers`), and the two
# are visibly independent — the headless archetype confers the same power with no display, and the
# exposed one is a plain fact on top of either.
{
  lib,
  toolkit,
}:
let
  inherit (toolkit)
    base
    mkUser
    grant
    failing
    ;

  # Two users bound in the gui MODE and one in the floor. Which session an account was bound in is
  # a property of the account (a bind writes it); which sessions the MACHINE can run is the
  # archetype's own declaration. Both have to line up for a graphical login, and this domain
  # varies them independently.
  guiUsers = [
    "alice"
    "bob"
  ];
  userNames = guiUsers ++ [ "carol" ];
  mkArchetype =
    {
      exposed,
      modes,
      grantsFor,
    }:
    base (
      [
        {
          contract.users = lib.mkMerge (
            map (
              n: (mkUser n { mode = if lib.elem n guiUsers then "gui" else "cli"; }).contract.users
            ) userNames
          );
          contract.modes = modes;
          contract.exposed = exposed;
          networking.hostName = "arch";
        }
      ]
      ++ map (n: grant n (grantsFor n)) userNames
    );
  # The SEAT archetype: a machine with a display whose users also hold a privileged power. It
  # confers `containers` to everybody to prove realization holds under a privileged grant, and
  # declares gui to prove the display surface follows the MACHINE.
  seatArch = mkArchetype {
    exposed = false;
    modes = [ "gui" ];
    grantsFor = _: { containers = true; };
  };
  # The exposed agent: the same privileged grant, no display. The pair is the point — one power,
  # two machines, and only one of them has a surface.
  agentArch = mkArchetype {
    exposed = true;
    modes = [ ];
    grantsFor = _: { containers = true; };
  };
  headlessArch = mkArchetype {
    exposed = false;
    modes = [ ];
    grantsFor = _: { };
  };
  accountsRealized = sys: lib.all (n: sys.config.users.users.${n}.isNormalUser or false) userNames;
  archetypes = [
    seatArch
    agentArch
    headlessArch
  ];
in
{
  assertions = [
    {
      name = "matrix: every user realizes on every archetype, no failing assertion";
      ok = lib.all (sys: (accountsRealized sys) && (failing sys.config == [ ])) archetypes;
    }
    {
      # The display surface follows the MACHINE's declaration. Session-agnostic: which session type
      # a desktop runs is the seat's concern and is not asserted here.
      name = "matrix: the seat archetype needs a display surface (it declares the gui mode)";
      ok = seatArch.config.contract.display.enabled;
    }
    {
      name = "matrix: the headless archetype needs no display surface";
      ok = !headlessArch.config.contract.display.enabled;
    }
    {
      # THE INDEPENDENCE, in one claim: the agent confers the SAME privileged power as the seat and
      # still has no display, because a power is about a person and a display is about a box.
      name = "matrix: the exposed agent confers the seat's power yet declares no mode ⇒ no surface";
      ok =
        (!agentArch.config.contract.display.enabled)
        && (accountsRealized agentArch)
        && agentArch.config.contract.users.alice.granted.containers;
    }
    {
      # …and its converse: the seat's gui-mode users get the session's input groups without any
      # affordance naming a display, while its cli user on the same machine does not.
      name = "matrix: mode groups reach the gui-mode accounts and no other, on one machine";
      ok =
        lib.elem "uinput" seatArch.config.users.users.alice.extraGroups
        && !(lib.elem "uinput" seatArch.config.users.users.carol.extraGroups);
    }
  ];
}
