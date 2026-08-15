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

      # The reference roster. Each user is its own subdir (identity.json + home.nix), and each is
      # host-agnostic: no platform binding, and no user ever names a secrets backend (CONTEXT.md).
      #
      # What IS invariant is the self-contained USER: a user's identity and its login credential
      # travel with the user (ADR-0019/0023) — no host owns them, and no user's secrets are ever
      # readable by another (ADR-0020's per-user secret isolation).
      #
      # This fleet lives in a PUBLIC repo, so it follows the posture ADR-0019 assigns a public repo:
      # every identity.json ships a `$y$` YESCRYPT hash, not `$6$` sha512crypt. The reference fleet
      # is what consumers copy, so it models the rule rather than merely citing it — and the
      # `identity-posture` check below enforces it, so a member added with a weaker hash fails the
      # build. (The cleartexts are published on purpose — "correct-horse-battery-staple", and
      # "password" for admin — because these are teaching fixtures; the posture is modelled for the
      # shape a real repo must copy, not because these particular hashes guard anything.)
      #
      # What is a CHOICE is whether users
      # share CODE. Since ADR-0020's 2026-08-15 amendment (issue #36) sharing home modules and
      # overlays is permitted, not required, so this roster deliberately shows BOTH arrangements:
      #   - ada, ben, cleo, svc, admin — the self-contained five. They share no module and no
      #     overlay, because there is nothing universal to factor across them (ADR-0022): what a
      #     home DOES with the contract's signal is application policy that varies per user. It also
      #     keeps each a clean standalone teaching artifact, and keeps ada evaluable headlessly —
      #     the conformance tracer borrows her home.nix with no home-manager at all.
      #   - duo-a, duo-b — the shared-setup pair. They import ONE `shared/module.nix` and ONE
      #     `shared/overlay.nix`, the mechanism an operator uses to enforce a common setup across
      #     their own accounts: the module is keyed on `config.identity.username`, so the same code
      #     yields per-user data and no user's identity is baked into it. The
      #     `shared-code-per-user-data` check below proves exactly that.
      # Neither arrangement reaches sideways between users' DATA; they differ only in whether the
      # CODE is written once or per user.
      #
      # What otherwise distinguishes the users is not their homes (the five are deliberately thin
      # and contract-pure) but what the FLEET grants each of them per host.
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
      #   - ada, ben, duo-a, duo-b: no `wants` line — the safe-set default (gui) is their whole offer;
      #   - cleo: `containers`, admin: `sudo` — privileged, so asked for explicitly;
      #   - svc: `gui.enable = false` — the explicit opt-out, the USER-side veto that keeps an
      #     account desktop-free even where a seat affords gui.
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
        # svc — the USER-side veto: it signs in like anyone else, but opts out of the safe-set gui
        # default, so no host can grant it a desktop however much it affords one. ada shows the host
        # half of `affordances ∩ offer`; svc is the only user showing the user half. The minimal
        # home; nothing secret.
        svc.bakedGrants = { };
        # admin — a break-glass administrative account: wants `sudo`, so on a host that affords sudo
        # it gets `wheel` and nothing more (the minimal privileged grant, ADR-0020). Its login
        # password is the well-known "password" (ADR-0019: the credential travels with the user).
        # sudo is privileged but non-secret, so nothing is baked.
        admin.bakedGrants = { };
        # duo-a / duo-b — the SHARED-SETUP pair (ADR-0020 as amended by issue #36). Two ordinary
        # roster members whose homes import the same `shared/module.nix` and the same
        # `shared/overlay.nix`. They ask for nothing privileged, so like ada and ben their offer is
        # the safe-set default; they exist to demonstrate the sharing MECHANISM, not to factor the
        # other five. Their homes are the roster's only non-contract-pure ones (the shared module
        # sets home-manager options), which is why the pair is new rather than grafted onto ada.
        duo-a.bakedGrants = { };
        duo-b.bakedGrants = { };
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

      # This repo's OWN home builder, named rather than inlined so the real `homeConfigurations`
      # and the contract's confinement check drive the SAME module set (issue #35). A check that
      # ran over a module set assembled separately would prove nothing about what actually ships.
      # `extraModules` is the seam the check needs: it appends one probe module at a time and asks
      # whether the home still evaluates.
      mkHome =
        {
          name,
          bakedGrants ? { },
          extraModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            contract.homeModules.default
            ./users/${name}/home.nix
            {
              identity = contract.lib.loadIdentity ./users/${name}/identity.json;
              home.username = name;
              home.homeDirectory = "/home/${name}";
              home.stateVersion = "25.11";
              home.packages = [ pkgs.hello ];
            }
          ]
          ++ extraModules;
          extraSpecialArgs.hostFacts = hostFactsFor bakedGrants;
        };
    in
    {
      # Standalone homes (`nix build .#homeConfigurations.<u>.activationPackage`): each user's home +
      # its identity.json, built directly with home-manager's own canonical
      # `homeManagerConfiguration` (the golden path a real user repo follows) against the contract
      # umbrella. The home.* fields + home.packages are the home-manager glue a BOUND path gets from
      # the host — kept HERE, not in the five self-contained users' home.nix, so those stay
      # contract-pure and evaluate headlessly against the bare umbrella when the conformance tracer
      # harvests requests (ADR-0008). The duo pair is the deliberate exception: its shared module sets
      # home-manager options of its own, so it needs home-manager and is never borrowed headlessly.
      # Identity is loaded once via the canonical `contract.lib.loadIdentity` and injected
      # (ADR-0009); hostFacts is the self-scoped host projection the producer supplies inline (there
      # is no host `config` at bake time — ADR-0026), built by `hostFactsFor` below.
      homeConfigurations =
        lib.mapAttrs (
          name: u:
          mkHome {
            inherit name;
            inherit (u) bakedGrants;
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
      checks.${system} =
        lib.mapAttrs' (
          name: _: lib.nameValuePair "home-build-${name}" self.homeConfigurations.${name}.activationPackage
        ) roster
        // {
          # The CONSUMER half of the confinement promise (issue #35). `conformance/confinement.nix`
          # proves the contract UMBRELLA declares no system channel; that is the contract's own
          # promise, and it says nothing about whether THIS repo's imports smuggled one back in.
          # `mkConfinementCheck` closes that half by probing the real `mkHome` above.
          #
          # Run over duo-a deliberately: it is the ONLY home with non-trivial imports (the shared
          # module and the shared overlay), which is exactly the hazard the check exists for. ada
          # imports nothing, so a check over her would merely re-prove the umbrella in a costlier
          # way. This call site is also what exercises the helper's two DEFAULTS — the
          # `activationPackage.drvPath` force and the `home.sessionVariables` positive control —
          # which the contract's own suite structurally cannot reach (it has no home-manager).
          home-confinement = contract.lib.mkConfinementCheck {
            inherit pkgs;
            buildHome =
              extraModules:
              mkHome {
                name = "duo-a";
                inherit extraModules;
              };
          };

          # The ADR-0020 claim the duo pair exists to prove: SHARED CODE, PER-USER DATA. "Both homes
          # build" would not prove it — a shared module that baked duo-a's identity into duo-b would
          # still build. So this check pins the two halves separately, on the REALIZED homes:
          #
          #   shared CODE   — `shared/overlay.nix`'s marker package resolves to the SAME store path
          #                   in both closures (one derivation, not a per-user copy), and it is
          #                   really there: the check RUNS it out of each home-path, which is what
          #                   makes this an overlay proof rather than an overlay mention;
          #   per-user DATA — `shared/module.nix`, keyed on `config.identity.username`, renders two
          #                   DIFFERENT store paths, each carrying its own identity and NO trace of
          #                   the other's (name, email, or username).
          #
          # This is also why the check lives here rather than in `conformance/`: it needs both
          # home-manager and nixpkgs, and the synthetic suite's `toolkit.evalHome` has neither
          # (ADR-0004/0022). CI already runs `nix flake check` on this flake as a matrix entry.
          shared-code-per-user-data =
            let
              duoA = self.homeConfigurations.duo-a;
              duoB = self.homeConfigurations.duo-b;
              # Both halves are read out of the REALIZED activation package, never off the evaluated
              # config: the point is what actually lands in the user's home, not what the module said.
              cardOf = home: "${home.activationPackage}/home-files/.contract-shared-card";
              markerOf = home: "${home.activationPackage}/home-path/bin/contract-shared-marker";
            in
            pkgs.runCommand "shared-code-per-user-data" { } ''
              fail() {
                echo "shared-code-per-user-data: $1" >&2
                exit 1
              }

              # --- shared CODE: one overlay, one derivation, in BOTH closures ---
              markerA=$(readlink -f ${markerOf duoA})
              markerB=$(readlink -f ${markerOf duoB})
              [ -x "$markerA" ] || fail "duo-a's home-path has no runnable shared-overlay marker"
              [ -x "$markerB" ] || fail "duo-b's home-path has no runnable shared-overlay marker"
              [ "$markerA" = "$markerB" ] || fail "the shared overlay produced a DIFFERENT package per user ($markerA vs $markerB) — that is not shared code"
              "$markerA" | grep -q 'shared/overlay.nix' || fail "the marker in the closure did not come from the shared overlay"

              # --- per-user DATA: same module, two identities, two different outputs ---
              # Each home's card is a symlink into the store, so resolving it gives the derivation the
              # shared module rendered for THAT identity. Two distinct paths ⇒ genuinely keyed output.
              cardA=$(readlink -f ${cardOf duoA})
              cardB=$(readlink -f ${cardOf duoB})
              [ -f "$cardA" ] || fail "duo-a's realized home has no shared-module card"
              [ -f "$cardB" ] || fail "duo-b's realized home has no shared-module card"
              [ "$cardA" != "$cardB" ] || fail "the shared module rendered ONE output for two identities — it is not keyed on config.identity.username"

              grep -q '^username=duo-a$' "$cardA" || fail "duo-a's card is not keyed on duo-a's username"
              grep -q '^username=duo-b$' "$cardB" || fail "duo-b's card is not keyed on duo-b's username"
              grep -q 'Duo A Reference' "$cardA" || fail "duo-a's card lost duo-a's own identity"
              grep -q 'Duo B Reference' "$cardB" || fail "duo-b's card lost duo-b's own identity"

              # --- and neither carries a TRACE of the other's identity ---
              ! grep -q 'duo-b\|Duo B' "$cardA" || fail "duo-a's home leaks duo-b's identity — the shared module baked a user in"
              ! grep -q 'duo-a\|Duo A' "$cardB" || fail "duo-b's home leaks duo-a's identity — the shared module baked a user in"

              touch $out
            '';
        };
    };
}
