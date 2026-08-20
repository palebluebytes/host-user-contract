# Shared conformance fixtures — the synthetic-world builders every domain file reuses, so each
# domain stays a focused list of claims rather than re-deriving the harness. Built once in
# ./default.nix and passed to each domain. No host repo, no real user, no host bindings.
{
  lib,
  contractModule,
  homeModule,
  userOptions,
  nixosSystem,
  loadIdentity,
  floorMode,
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

  # A synthetic bound ACCOUNT — pure data, exactly as a real bind writes it: an identity, the mode
  # it was bound in, and whatever the host conferred. Powers arrive only through `grant` below; the
  # session shape arrives through `mode`, and the two are separate because they answer different
  # questions. `mode` defaults to the floor, as the option does.
  mkUser =
    name:
    {
      mode ? floorMode,
    }:
    {
      contract.users.${name} = {
        inherit mode;
        identity = {
          name = "User ${name}";
          email = "${name}@example.invalid";
          username = name;
        };
      };
    };
  grant = name: features: { contract.users.${name}.granted = features; };

  # The failing assertions of an evaluated system (the matrix domain reads this).
  failing = c: builtins.filter (a: !a.assertion) c.assertions;

  # ── The HOME eval side ───────────────────────────────────────────────────────────────────────
  # The home umbrella is deliberately thin — a home is handed its identity and nothing else, since
  # the user's whole voice lives one level up in `user.nix`. So the synthetic home eval supplies
  # the three required identity fields and leaves the optional ones free, which is what gives the
  # confinement probe both a thing to FORCE (`identity.username`, always present) and a legitimate
  # option to set as its POSITIVE CONTROL (`identity.gmail`, declared with a default and defined by
  # nobody here).
  homeIdentity = {
    name = "Probe User";
    email = "probe@example.invalid";
    username = "probe";
  };
  evalHome =
    mods:
    (lib.evalModules {
      modules = [
        homeModule
        { identity = homeIdentity; }
      ]
      ++ mods;
    }).config;
  # Forcing this runs the module system's unmatched-definition check across ALL definitions, so an
  # UNDECLARED option anywhere in the module set throws here.
  homeForce = c: c.identity.username;
  homePositiveControl = {
    identity.gmail = "probe@example.invalid";
  };

  # ── The USER DECLARATION eval side ───────────────────────────────────────────────────────────
  # A declaration evaluated against the REAL schema module the contract ships, so a domain proves
  # what a user's `user.nix` can and cannot say without owning a second copy of the options.
  evalDeclaration = mods: (lib.evalModules { modules = [ userOptions ] ++ mods; }).config.contract;

  # A real atom borrowed from the reference user fleet: ada's directory (her identity.json and her
  # `user.nix`), consumed by the producer domains exactly as a real users repo's would be. This is
  # the one-way oracle→reference seam — the synthetic suite consumes realistic atoms from the
  # reference fleet, never the reverse. `referenceIdentity` has username "ada", name "Ada
  # Reference"; her declaration runs in both modes and asks for the plasma desktop.
  referenceDir = ../examples/users/users/ada;
  referenceIdentity = loadIdentity ../examples/users/users/ada/identity.json;
  referenceDeclaration = evalDeclaration [ ../examples/users/users/ada/user.nix ];
}
