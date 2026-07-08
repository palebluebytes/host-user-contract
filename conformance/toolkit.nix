# Shared conformance fixtures — the synthetic-world builders every domain file reuses, so each
# domain (./realization.nix, ./requests.nix, ./bind.nix, ./greeter.nix, ./matrix.nix) stays a
# focused list of claims rather than re-deriving the harness. Built once in ./default.nix and
# passed to each domain. No host repo, no real user, no host bindings (ADR-0004 Q5).
{
  lib,
  contractModule,
  homeModule,
  nixosSystem,
  loadIdentity,
  system,
}:
rec {
  # A minimal bootable system built from ONLY the contract umbrella + bare nixpkgs.
  base =
    mods:
    nixosSystem {
      modules = [
        contractModule
        {
          nixpkgs.hostPlatform = system;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "tmpfs";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.11";
          # Stub the platform interface (ADR-0004 review F3). The contract's own CI binds
          # no real secrets backend; a no-op keeps the suite robust if a future system-side
          # secret feature reads custom.platform.secretFile during eval.
          custom.platform = {
            secretFile = _: builtins.toFile "stub-secret" "";
            secretPath = _: builtins.toFile "stub-secret" "";
          };
          # ADR-0018: the fixture host's desktop→type map. mkUser's `session` param selects a
          # `<session>-de` desktop here, so the union derives that session type; "plasma" is the
          # example user's desktop (a wayland session, as greeter-desktop-plasma launches
          # startplasma-wayland).
          custom.gui.desktops = {
            "wayland-de" = "wayland";
            "x11-de" = "x11";
            plasma = "wayland";
          };
        }
      ]
      ++ mods;
    };
  eval = mods: (base mods).config;

  # A synthetic manifest — pure data, exactly as a real one: identity + (for gui) a chosen
  # desktop, no grants (the host grants), no system config. `session` selects which fixture
  # desktop the gui user picks (a `<session>-de` entry in the host's custom.gui.desktops map),
  # so the derived session type is `session` (ADR-0018).
  mkUser =
    name:
    {
      gui ? true,
      session ? "wayland",
    }:
    {
      custom.users.${name} = {
        identity = {
          name = "User ${name}";
          email = "${name}@example.invalid";
          username = name;
        };
      }
      // lib.optionalAttrs gui { gui.desktop = "${session}-de"; };
    };
  grant = name: features: { custom.users.${name}.granted = features; };

  # The failing assertions of an evaluated system (the exposed-host ban + matrix read these).
  failing = c: builtins.filter (a: !a.assertion) c.assertions;

  # The home eval-side: a user's home module populates contract.requests; evalModules with only
  # the home umbrella proves the namespace's shape with no home-manager.
  evalHome = mods: (lib.evalModules { modules = [ homeModule ] ++ mods; }).config;

  # The in-repo example user (ADR-0007): a contract-pure home + its identity.json, bound by the
  # tracer and the real bindUserModule. exampleIdentity has username "example", name "Example User".
  exampleHome = import ../examples/user/home.nix;
  exampleIdentity = loadIdentity ../examples/user/identity.json;
  exampleHostFacts = {
    exposed = false;
    platform = system;
    granted = { };
  };
}
