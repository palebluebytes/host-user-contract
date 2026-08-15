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
      # ONE per-user knob remains here:
      #   - `bakedGrants`: the grants the contractPackage is BUILT with. No grant is secret-bearing
      #     (the contract handles no secrets). The contract's HOME-AFFECTING set — the upper bound
      #     on what a home may even see, `contract.homeAffecting` — is `{gui}`, so a repo whose homes
      #     fan out bakes `powerset(homeAffecting)` = a base + a gui variant. These reference homes
      #     are trivial and contract-pure: not one of them reads `hostFacts.granted`, so none fans
      #     out and every user bakes a single grant-less `base` variant. That is exactly what lets
      #     one `ada-contractPackage-base` be gui on one seat and cli-only on another — the grant
      #     rides the bind, never the bake.
      #
      # The `offer` (ADR-0025) — the features a user ASKS a host for — is NO LONGER declared here.
      # Since ADR-0028 each user declares `contract.wants` in its OWN home and `mkContractUsers`
      # HARVESTS it into the binding index, so a user's voice is not split between its home and this
      # flake. The negotiation is unchanged: a host declares `contract.affordances` once and each
      # grant is derived as `affordances ∩ offer`, so ada is gui on a seat that affords gui and
      # cli-only on a headless host. What each user asks for now reads out of `users/<u>/home.nix`:
      #   - ada, ben: no `wants` line — the safe-set default (gui) is their whole offer;
      #   - cleo: `containers`, admin: `sudo` — privileged, so asked for explicitly;
      #   - svc: `gui.enable = false` — the explicit opt-out that keeps an automation account
      #     cli-only even where a seat affords gui.
      roster = {
        # ada — the multi-machine user (the contract's portable-user north star): ONE identity,
        # ONE home, wants gui (the default) — she gets a gui session on a seat that affords gui and
        # cli-only on a headless host that does not. Whether she gets gui is a per-host AFFORDANCE ∩
        # her offer, never a user trait.
        ada.bakedGrants = { };
        # ben — a second cli reference user (a plain, contract-pure home): distinct identity, asks
        # for nothing privileged. Useful as a co-resident on the same host as a privileged account.
        ben.bakedGrants = { };
        # cleo — the privileged-group user: declares `docker` in identity.extraGroups and wants
        # `containers`; she receives docker ONLY on a host that affords containers (the clamp +
        # negotiation, positive direction). containers is non-secret, so nothing is baked.
        cleo.bakedGrants = { };
        # svc — a pure automation account: cli-only on every host that runs it, never gui (it opts
        # out of the safe-set default). The minimal home; nothing secret.
        svc.bakedGrants = { };
        # admin — a break-glass administrative account: wants `sudo`, so on a host that affords sudo
        # it gets `wheel` and nothing more (the minimal privileged grant, ADR-0020). Its login
        # password is the well-known "password" (ADR-0019: the credential travels with the user).
        # sudo is privileged but non-secret, so nothing is baked.
        admin.bakedGrants = { };
      };

      # The self-scoped hostFacts a bake supplies to a home (ADR-0002). There is no host `config`
      # at bake time (ADR-0026/0027), so the producer builds the literal — and NARROWS `granted`
      # with the contract's `homeAffecting` surface (ADR-0028): a home may only see the grants
      # something bakes for, so a home reading `granted.sudo` structurally gets false forever and
      # cannot become grant-sensitive on a feature that rides the bind. The rule is the contract's
      # data, not a comment kept in step by hand.
      hostFactsFor = grants: {
        exposed = false;
        platform = system;
        granted = lib.filterAttrs (f: _: lib.elem f contract.homeAffecting) grants;
      };
    in
    {
      # Standalone homes (`nix build .#homeConfigurations.<u>.activationPackage`): each user's
      # contract-pure home + its identity.json, built directly with home-manager's own canonical
      # `homeManagerConfiguration` (the golden path a real user repo follows) against the contract
      # umbrella. The home.* fields + home.packages are the home-manager glue a BOUND path gets from
      # the host — kept HERE, not in the user's home.nix, so home.nix stays contract-pure and
      # evaluates headlessly against the bare umbrella when the conformance tracer harvests requests
      # (ADR-0008). Identity is loaded once via the canonical `contract.lib.loadIdentity` and injected
      # (ADR-0009); hostFacts is the self-scoped host projection the producer supplies inline (there
      # is no host `config` at bake time — ADR-0026), built by `hostFactsFor` below.
      homeConfigurations =
        lib.mapAttrs (
          name: u:
          let
            identity = contract.lib.loadIdentity ./users/${name}/identity.json;
          in
          home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              contract.homeModules.default
              ./users/${name}/home.nix
              {
                inherit identity;
                home.username = name;
                home.homeDirectory = "/home/${name}";
                home.stateVersion = "25.11";
                home.packages = [ pkgs.hello ];
              }
            ]
            ++ (u.homeModules or [ ]);
            extraSpecialArgs.hostFacts = hostFactsFor u.bakedGrants;
          }
        ) roster
        # The greeter-login variant (<u>-greeter): the SAME home granted the safe set (greeterGrants),
        # importing the desktop-choice helper (ADR-0013) so contract.requests.gui.desktop surfaces to
        # ~/.contract-desktop, plus a marker dotfile the fleet's integration VM observes.
        // lib.mapAttrs' (
          name: _:
          let
            identity = contract.lib.loadIdentity ./users/${name}/identity.json;
          in
          lib.nameValuePair "${name}-greeter" (
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                contract.homeModules.default
                contract.homeModules.greeterDesktop
                ./users/${name}/home.nix
                {
                  inherit identity;
                  home.username = name;
                  home.homeDirectory = "/home/${name}";
                  home.stateVersion = "25.11";
                  home.packages = [ pkgs.hello ];
                  home.file.".contract-home-active".text = "greeter-activated for ${identity.name}";
                }
              ];
              extraSpecialArgs.hostFacts = hostFactsFor contract.greeterGrants;
            }
          )
        ) roster;

      # The turnkey PRODUCER surface (ADR-0025, issue #25): `mkContractUsers` maps the whole roster
      # ONCE into BOTH the per-user pre-built binding artifacts AND the pure `contractUsers` binding
      # index a host selects a variant from. It is `mkContractUser` (the singular per-user producer,
      # the twin of the host's `bindContractUser`) mapped over the roster and merged — one call bakes
      # the multi-user repo (ADR-0020).
      #
      # Each user declares only its `variants` (here a single grant-less `base` variant, since these
      # reference homes don't fan out on any grant); its OFFER is harvested from each variant's home
      # (`contract.wants`, ADR-0028) rather than passed. mkContractUsers bakes each variant
      # via the internal package kernels (only READING the already-evaluated home, so package-free),
      # names it `<user>-contractPackage-<variantName>` (empty grant-key ⇒ `base`), resolves each
      # identity once from `users/<u>/identity.json`, and emits the index `contractUsers.<sys>.<u> =
      # { identity; offer; variants = [{ granted; package }] }` as plain data (no IFD) so a host
      # picks a variant without building any of them.
      inherit
        (contract.lib.mkContractUsers {
          inherit pkgs system;
          usersDir = ./users;
          users = lib.mapAttrs (name: u: {
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
