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
        }
      ]
      ++ mods;
    };
  eval = mods: (base mods).config;

  # A synthetic manifest — pure data, exactly as a real one: identity + (for gui) a chosen
  # desktop NAME, no grants (the host grants), no system config. `desktop` is a free-form name
  # the user requests; the contract does not map it to a session type — that is the seat's
  # concern (ADR-0021). It defaults to "plasma" (the example user's desktop).
  mkUser =
    name:
    {
      gui ? true,
      desktop ? "plasma",
    }:
    {
      custom.users.${name} = {
        identity = {
          name = "User ${name}";
          email = "${name}@example.invalid";
          username = name;
        };
      }
      // lib.optionalAttrs gui { gui.desktop = desktop; };
    };
  grant = name: features: { custom.users.${name}.granted = features; };

  # The failing assertions of an evaluated system (the exposed-host ban + matrix read these).
  failing = c: builtins.filter (a: !a.assertion) c.assertions;

  # The home eval-side: a user's home module populates contract.requests; evalModules with only
  # the home umbrella proves the namespace's shape with no home-manager.
  evalHome = mods: (lib.evalModules { modules = [ homeModule ] ++ mods; }).config;

  # A real atom borrowed from the reference user fleet (ADR-0020, docs/adr/0022): ada's contract-pure
  # home + her identity.json, inspected by traceUser and baked via the pre-built path. This is the one-way
  # oracle→reference seam — the synthetic suite consumes realistic atoms from the reference fleet,
  # never the reverse. referenceIdentity has username "ada", name "Ada Reference".
  referenceHome = import ../examples/users/users/ada/home.nix;
  referenceIdentity = loadIdentity ../examples/users/users/ada/identity.json;
  referenceHostFacts = {
    exposed = false;
    platform = system;
    granted = { };
  };
}
