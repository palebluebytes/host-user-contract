{
  description = "Reference USER FLEET (ADR-0020) — the operator's own accounts grouped in one repo, each consumed via the contract's per-user contractPackage output (ADR-0016). Standalone inputs exist only for this repo's own CI; when a host binds a user it supplies the canonical contract + pkgs. This is the positive-space reference the synthetic conformance suite borrows real atoms from — never the reverse (see docs/adr/0022).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # A real user repo uses `github:palebluebytes/host-user-contract`; the in-repo example
    # points at the contract two levels up. nixpkgs follows so there is ONE nixpkgs.
    contract.url = "path:../..";
    contract.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      contract,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The reference roster. Each user is a SELF-CONTAINED subdir (identity.json + home.nix) —
      # no shared home modules, no platform binding, no overlays: a user is host-agnostic and
      # never names a secrets backend (CONTEXT.md), and the self-contained-user invariant means
      # nothing reaches sideways between users. What distinguishes the users is not their homes
      # (deliberately thin, contract-pure) but what the FLEET grants each of them per host.
      #
      # Two per-user knobs here:
      #   - `bakedGrants`: the grants the contractPackage is BUILT with. No grant is secret-bearing
      #     (the contract handles no secrets) and these reference homes don't FAN OUT on any grant
      #     (they are trivial, contract-pure), so nothing is home-affecting and every user bakes a
      #     single grant-less `base` variant. That is exactly what lets one `ada-contractPackage-base`
      #     be gui on one seat and cli-only on another — the grant rides the bind, never the bake.
      #   - `offer` (ADR-0025): the features this user ASKS a host for. In the turnkey path a host
      #     declares its `contract.affordances` once and binds each user with `bindUserFromFlake`;
      #     the grant is derived as `affordances ∩ offer`. So ada OFFERS gui and RECEIVES it only on
      #     a host that affords gui — the portable-user gui↔cli divergence, now a two-sided
      #     negotiation rather than a hand-written per-host grant.
      roster = {
        # ada — the multi-machine user (the contract's portable-user north star): ONE identity,
        # ONE home, OFFERS gui — she gets a gui session on a seat that affords gui and cli-only on a
        # headless host that does not. Whether she gets gui is a per-host AFFORDANCE ∩ her offer,
        # never a user trait.
        ada = {
          bakedGrants = { };
          offer = {
            gui.enable = true;
          };
        };
        # ben — a second cli reference user (a plain, contract-pure home): distinct identity, offers
        # nothing. Useful as a co-resident on the same host as a privileged account.
        ben = {
          bakedGrants = { };
          offer = { };
        };
        # cleo — the privileged-group user: declares `docker` in identity.extraGroups and OFFERS
        # `containers`; she receives docker ONLY on a host that affords containers (the clamp +
        # negotiation, positive direction). containers is non-secret, so nothing is baked.
        cleo = {
          bakedGrants = { };
          offer = {
            containers.enable = true;
          };
        };
        # svc — a pure automation account: cli-only on every host that runs it, never gui. Offers
        # nothing. The minimal home; nothing secret.
        svc = {
          bakedGrants = { };
          offer = { };
        };
        # admin — a break-glass administrative account: OFFERS `sudo`, so on a host that affords sudo
        # it gets `wheel` and nothing more (the minimal privileged grant, ADR-0020). Its login
        # password is the well-known "password" (ADR-0019: the credential travels with the user).
        # sudo is privileged but non-secret, so nothing is baked.
        admin = {
          bakedGrants = { };
          offer = {
            sudo.enable = true;
          };
        };
      };

      identityOf = name: contract.lib.loadIdentity ./users/${name}/identity.json;

      # The home the contract umbrella + this user's contract-pure module + identity render,
      # parameterized by the host's grant (hostFacts.granted) and any extra modules. The home.*
      # fields + home.packages are the home-manager glue a BOUND path gets from the host — kept
      # HERE (not in the user's home.nix) so home.nix stays contract-pure and evaluates headlessly
      # against the bare contract umbrella when the conformance tracer harvests its requests
      # (ADR-0008). home.packages is present so the contractPackage's `packages` manifest is
      # non-empty and the package-policy intersection stays exercisable end-to-end.
      mkHome =
        {
          name,
          granted ? { },
          extra ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            contract.homeModules.default
            ./users/${name}/home.nix
            {
              identity = identityOf name;
              home.username = name;
              home.homeDirectory = "/home/${name}";
              home.stateVersion = "25.11";
              home.packages = [ pkgs.hello ];
            }
          ]
          ++ extra;
          extraSpecialArgs = {
            hostFacts = {
              exposed = false;
              platform = system;
              inherit granted;
            };
          };
        };

      # The greeter-login variant of a home: granted the safe set the runtime path auto-grants
      # (greeterGrants), importing the desktop-choice helper (ADR-0013) so the home's
      # contract.requests.gui.desktop surfaces to ~/.contract-desktop, and carrying a marker
      # dotfile the fleet's integration VM observes to prove a REAL home-manager home activated.
      mkGreeterHome =
        name:
        mkHome {
          inherit name;
          granted = contract.greeterGrants;
          extra = [
            contract.homeModules.greeterDesktop
            {
              home.file.".contract-home-active".text = "greeter-activated for ${(identityOf name).name}";
            }
          ];
        };

    in
    {
      # Standalone homes (`nix build .#homeConfigurations.<u>.activationPackage`): each user's
      # contract-pure home + identity.json build against the contract on their own, granted the
      # user's baked grants so a real home reacts to its own secret grant where it has one.
      homeConfigurations =
        (lib.mapAttrs (
          name: u:
          mkHome {
            inherit name;
            granted = u.bakedGrants;
            extra = u.homeModules or [ ];
          }
        ) roster)
        // (lib.mapAttrs' (name: _: lib.nameValuePair "${name}-greeter" (mkGreeterHome name)) roster);

      # The turnkey PRODUCER surface (ADR-0025, issue #25): `mkUserBindings` maps the whole roster
      # ONCE into BOTH the per-user pre-built binding artifacts AND the pure `contractUsers` binding
      # index a host selects a variant from. It replaces the hand-rolled `mkContractPackageForHome`
      # loop the fleet used to write (issue #23) — the producer twin of the host's `bindUserFromFlake`.
      #
      # Each user declares its `offer` and its `variants` (here a single grant-less `base` variant,
      # since these reference homes don't fan out on any grant). mkUserBindings bakes each variant
      # via mkContractPackageForHome (still package-free — it only READS the already-evaluated home),
      # names it `<user>-contractPackage-<variantName>` (empty grant-key ⇒ `base`), resolves each
      # identity once from `users/<u>/identity.json`, and emits the index `contractUsers.<sys>.<u> =
      # { identity; offer; variants = [{ granted; package }] }` as plain data (no IFD) so a host
      # picks a variant without building any of them.
      inherit
        (contract.lib.mkUserBindings {
          inherit pkgs system;
          usersDir = ./users;
          users = lib.mapAttrs (name: u: {
            inherit (u) offer;
            variants = [
              {
                grants = u.bakedGrants;
                home = self.homeConfigurations.${name};
              }
            ];
          }) roster;
        })
        packages
        contractUsers
        ;

      # The REAL home build step, per user (the model a real user repo follows when it CIs its own
      # homes). The contract's OWN suite cannot cover this — it needs home-manager, which the
      # contract does not depend on (ADR-0004) — so it lives HERE, in the fleet that legitimately
      # has home-manager. The greeter-path end-to-end lives in examples/fleet (it needs a booted
      # host), pointed at these same outputs.
      checks.${system} = lib.mapAttrs' (
        name: _: lib.nameValuePair "home-build-${name}" self.homeConfigurations.${name}.activationPackage
      ) roster;
    };
}
