# Conformance domain: the cross-product proof — synthetic users (wayland / x11 / cli) × host
# archetypes (workstation / exposed agent / headless). Every user realizes on every archetype with
# no failing assertion, and the gui-session union/exposed-host behaviour holds per archetype.
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

  users = {
    alice = mkUser "alice" { session = "wayland"; };
    bob = mkUser "bob" { session = "x11"; };
    carol = mkUser "carol" { gui = false; };
  };
  userNames = [
    "alice"
    "bob"
    "carol"
  ];
  allUsers = lib.attrValues users;
  mkArchetype =
    { exposed, grantsFor }:
    base (
      [
        { custom.users = lib.mkMerge (map (u: u.custom.users) allUsers); }
        {
          custom.host.exposed = exposed;
          networking.hostName = "arch";
        }
      ]
      ++ map (n: grant n (grantsFor n)) userNames
    );
  workstationArch = mkArchetype {
    exposed = false;
    grantsFor =
      n:
      # gui users carry a gui.session (mkUser sets it only when gui); cli users don't.
      if users.${n}.custom.users.${n} ? gui then
        {
          gui.enable = true;
          workstation.enable = true;
        }
      else
        { workstation.enable = true; };
  };
  agentArch = mkArchetype {
    exposed = true;
    grantsFor = _: { workstation.enable = true; };
  };
  headlessArch = mkArchetype {
    exposed = false;
    grantsFor = _: { };
  };
  accountsRealized = sys: lib.all (n: sys.config.users.users.${n}.isNormalUser or false) userNames;
  archetypes = [
    workstationArch
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
      name = "matrix: the workstation archetype offers both sessions (alice wayland + bob x11)";
      ok =
        workstationArch.config.custom.gui.surface.wayland && workstationArch.config.custom.gui.surface.x11;
    }
    {
      name = "matrix: the headless archetype needs no display surface";
      ok = !headlessArch.config.custom.gui.surface.enabled;
    }
    {
      name = "matrix: the exposed agent grants no gui yet realizes all users";
      ok = (!agentArch.config.custom.gui.surface.enabled) && (accountsRealized agentArch);
    }
  ];
}
