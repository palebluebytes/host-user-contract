# Shared conformance fixtures — the synthetic-world builders every domain file reuses, so each
# domain stays a focused list of claims rather than re-deriving the harness. Built once in
# ./default.nix and passed to each domain. No host repo, no real user, no host bindings.
{
  lib,
  contractModule,
  homeModule,
  userOptions,
  nixosSystem,
  resolveIdentity,
  # The contract's own member-set derivation, so the reference fleet's member set is BORROWED
  # through the shipped function rather than re-derived by a second read of the same directory.
  mkMembers,
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
        # RESOLVED, because neither identity surface carries defaults any more (modules.nix): a
        # partial record leaves the optional fields with no value at all, and `accountPlan` reads
        # `sshKey` and `trustedKeys` off every account. This is what a consumer assembling an
        # account by hand does too — the same function, exposed for exactly this.
        identity = resolveIdentity {
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
  # the ONE required identity field and leaves every optional one UNDEFINED — deliberately NOT
  # `resolveIdentity`d, unlike `mkUser` above, which is what gives the confinement probes both a
  # thing to FORCE (`contract.identity.username`, always present) and a field nobody has defined to
  # use as a POSITIVE CONTROL (`contract.identity.sshKey`). A resolved record would define every
  # field, and the positive control would then be a SECOND definition of a readOnly option —
  # failing for the opposite of the reason it is testing.
  homeIdentity = {
    username = "probe";
  };
  evalHome =
    mods:
    (lib.evalModules {
      modules = [
        homeModule
        { contract.identity = homeIdentity; }
      ]
      ++ mods;
    }).config;
  # Forcing this runs the module system's unmatched-definition check across ALL definitions, so an
  # UNDECLARED option anywhere in the module set throws here.
  homeForce = c: c.contract.identity.username;
  homePositiveControl = {
    contract.identity.sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIProbePositiveControl";
  };

  # The home umbrella's DECLARED SURFACE, as sorted option paths — `evalHome` returns that eval's
  # `config`, this returns its `options`, walked to the leaves.
  #
  # It exists so a domain can state what a home may say by ENUMERATION rather than by probing one
  # path at a time. Probes are claims about absence, and absence is what a newly-added option
  # violates silently; a list of every declared path fails the day the surface changes, whatever
  # changed (ADR-0026).
  homeOptionPaths =
    let
      walk =
        prefix: opts:
        lib.concatLists (
          lib.mapAttrsToList (
            n: v:
            if n == "_module" then
              [ ]
            else if lib.isOption v then
              [ (lib.concatStringsSep "." (prefix ++ [ n ])) ]
            else
              walk (prefix ++ [ n ]) v
          ) opts
        );
    in
    lib.sort (a: b: a < b) (walk [ ] (lib.evalModules { modules = [ homeModule ]; }).options);

  # ── The USER DECLARATION eval side ───────────────────────────────────────────────────────────
  # A declaration evaluated against the REAL schema module the contract ships, so a domain proves
  # what a user's `user.nix` can and cannot say without owning a second copy of the options.
  evalDeclaration = mods: (lib.evalModules { modules = [ userOptions ] ++ mods; }).config.contract;

  # ── THE ONE-WAY ORACLE→REFERENCE SEAM (ADR-0022) ─────────────────────────────────────────────
  # The synthetic suite may borrow realistic atoms FROM the reference fleets; the reference fleets
  # never defer to the oracle. THIS BLOCK IS THE WHOLE OF THAT SEAM — the only place under
  # `conformance/` that knows where `examples/` is, or which of the people in it the suite borrows.
  # (Reference names still appear elsewhere as SYNTHETIC fixture data — a refusal's expected
  # message, a diagnostic's subject — but nothing there reads the reference fleet.)
  #
  # Two things follow, and both are the point of naming the atoms here rather than reaching past
  # them. Renaming a reference user, or restructuring the users repo, is an edit to THIS FILE and
  # nowhere else, so the reference fleet stays free to change shape. And the fleet can read one
  # screen to see exactly which of its atoms the oracle leans on — a debt that was otherwise
  # invisible from the side that would pay it.
  #
  # A borrowing domain asks by ROLE, never by person: it wants "the user who runs cli alone", not
  # "ben". Every atom below carries the one line a caller needs so it never has to open
  # `examples/` to know what it got.

  # The reference users repo's users directory: the `users/<u>/{identity.json,user.nix}` layout a
  # real consumer ships, seven people deep. What a producer domain points a `usersDir` at.
  referenceUsersDir = ../examples/users/users;

  # The member set over it, derived through the contract's OWN `mkMembers` — ONE read of that
  # directory for the whole suite. A domain borrowing "the reference fleet's members" and a domain
  # borrowing one person's identity therefore read the same records, and no second scan can drift
  # from this one.
  referenceMembers = mkMembers { usersDir = referenceUsersDir; };

  # THE ROLE TABLE — the only place a reference person's name appears. Each entry is that user's
  # `mkMembers` record, `{ name; dir; identity; declaration; }`, so a domain reads the directory,
  # the identity or the declaration off one value instead of re-resolving a path.
  referenceUsers = {
    # ada — the PORTABLE user, and the default borrow. Runs BOTH modes and asks for the `plasma`
    # desktop; her `identity.json` is the fleet's one FULL FORM (every schema field spelled out,
    # name "Ada Reference"), and her credential is `$y$` yescrypt, because `examples/users` is a
    # public repo and ADR-0004 assigns a public repo that posture. Her cleartext is
    # `referenceSecret` below.
    portable = referenceMembers.ada;
    # ben — runs `cli` ALONE, in a one-line declaration. The atom for "a mode this user does not
    # run in": the only reference user for whom a `gui` home is a producer mistake rather than a
    # home.
    cliOnly = referenceMembers.ben;
    # duo-a — half the shared-setup pair, and the fleet's one user whose modes SUBSTITUTE content:
    # `gui` and `cli` name two DIFFERENT modules (`referenceHomeModules` below), and the `gui` mode
    # asks for the `sway` desktop. The atom that makes per-mode composition observable at all.
    twoModule = referenceMembers.duo-a;
    # duo-b — the other half of that pair, and the CONTROL for it: both modes name ONE module, so
    # its two homes compose the same configuration.
    oneModule = referenceMembers.duo-b;
  };

  # The home MODULES those two declarations name — what the home-composition domain compares a
  # composed slot against. Spelled here, beside the users they belong to, so which file the pair
  # keeps its home in stays the reference fleet's business rather than the oracle's.
  #
  # The two SHAPES are the fact: the two-module user names one module PER MODE, the one-module user
  # names a single module for both. An `oneModule.<mode>` keyed like its neighbour would spell that
  # difference away.
  referenceHomeModules = {
    twoModule = {
      cli = referenceUsers.twoModule.dir + "/cli.nix";
      gui = referenceUsers.twoModule.dir + "/gui.nix";
    };
    oneModule = referenceUsers.oneModule.dir + "/home.nix";
  };

  # The cleartext behind every reference credential (`examples/users/flake.nix` says so out loud —
  # they are teaching fixtures). Borrowed exactly as the paths are: the greeter's auth-flow proof
  # has to type a real password at a real `identity.json`, so the secret is an atom of the
  # reference fleet like any other.
  referenceSecret = "correct-horse-battery-staple";
}
