# Conformance domain: the cross-product proof — synthetic users (two gui / one cli) × host
# archetypes (workstation / exposed agent / headless). Every user realizes on every archetype with
# no failing assertion, and the session-agnostic gui-surface/exposed-host behaviour holds per archetype.
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
    alice = mkUser "alice" { desktop = "plasma"; };
    bob = mkUser "bob" { desktop = "gnome"; };
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
  # The "workstation" archetype is a host ROLE (a seat with privileged, gui-capable users), not the
  # retired feature of the same name: it grants the `containers` capability to every user to prove
  # realization holds under a privileged grant, and gui to the gui users.
  workstationArch = mkArchetype {
    exposed = false;
    grantsFor =
      n:
      # gui users carry a gui.desktop (mkUser sets it only when gui); cli users don't.
      if users.${n}.custom.users.${n} ? gui then
        {
          gui.enable = true;
          containers.enable = true;
        }
      else
        { containers.enable = true; };
  };
  agentArch = mkArchetype {
    exposed = true;
    grantsFor = _: { containers.enable = true; };
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
      # Session-agnostic (ADR-0021): granting gui to the two gui users ⇒ the archetype needs a
      # display surface. Which session type each desktop runs is the seat's concern, not asserted here.
      name = "matrix: the workstation archetype needs a display surface (its gui users are granted)";
      ok = workstationArch.config.custom.gui.surface.enabled;
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
