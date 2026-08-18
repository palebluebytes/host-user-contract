{
  description = "Reference HOST FLEET — a NixOS machine fleet that consumes the contract by binding the reference user fleet (examples/users) per user, turnkey, via bindContractUser + contract.affordances (ADR-0025). It shows the contract's reason to exist: two independently-owned repos (hosts, users) meeting at the binding. Positive-space reference with its own smoke/coherence checks (docs/adr/0022); it never re-bases the contract's synthetic conformance suite.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    contract.url = "path:../..";
    contract.inputs.nixpkgs.follows = "nixpkgs";
    # The user fleet, consumed exactly as a real host consumes a users repo: as a flake input
    # whose per-user `<u>-contractPackage` outputs this fleet binds. nixpkgs follows so there is
    # ONE nixpkgs across contract, users, and this fleet.
    users.url = "path:../users";
    users.inputs.nixpkgs.follows = "nixpkgs";
    users.inputs.contract.follows = "contract";
  };

  outputs =
    {
      nixpkgs,
      contract,
      users,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Host boilerplate shared by every machine (not part of any "example" — just enough to boot
      # an eval): tmpfs root, no bootloader.
      commonBase = {
        system.stateVersion = "25.11";
        nixpkgs.hostPlatform = system;
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "tmpfs";
          fsType = "tmpfs";
        };
      };

      # Each host lives in its own file (hosts/<name>.nix) and declares only what is DISTINCTIVE —
      # which users it binds, what it affords them, whether it is a seat or exposed. It gets the
      # `contract` and the pinned `users` flake, and binds each user with the canonical
      # `contract.lib.bindContractUser { usersFlake = users; username }` (ADR-0025/0026) — the
      # turnkey consumption convention: declare `contract.affordances` once, and each user's grant
      # is DERIVED as `affordances ∩ offer` (the host's affordance is the absolute veto; the user's
      # offer in the pinned flake completes it). The SAME user bound under different affordances on
      # different hosts is what makes any-host×any-user real — ada offers gui and gets it only where
      # gui is afforded. The contract umbrella + the shared base are merged in here.
      mkHost =
        hostFile:
        lib.nixosSystem {
          modules = [
            contract.nixosModules.default
            commonBase
            (import hostFile { inherit contract users; })
          ];
        };

      nixosConfigurations = {
        desk = mkHost ./hosts/desk.nix;
        vault = mkHost ./hosts/vault.nix;
        agent = mkHost ./hosts/agent.nix;
      };
    in
    {
      inherit nixosConfigurations;

      checks.${system} = {
        # Eval-level smoke/coherence: every host evaluates, every bound account realizes, ada's
        # gui↔cli divergence across hosts holds, cleo's docker comes only via the grant, and the
        # exposed agent evaluates coherently (exposure is a plain host fact). The positive-space
        # counterpart to the synthetic suite's adversarial probes.
        fleet-eval = import ./checks.nix {
          inherit lib pkgs nixosConfigurations;
        };

        # The runtime greeter path END-TO-END: a booted seat greeter-provisions ada from her
        # ORDINARY published home (`homes.<system>.ada.gui`, the same artifact a declarative bind
        # would activate) and observes it activate — the runtime half of the uniform flake-output
        # consumption convention (declarative binds a contractPackage via bindContractUser, the
        # greeter builds a home out of `homes`), the counterpart to the declarative binds above.
        # There is no `-greeter` artifact any more: grants stopped reaching homes (ADR-0032), so a
        # greeter-granted home had nothing left to differ in. Focused seat node (like the contract's
        # own greeter-provision-vm), not the full desk host, so the provisioned account never
        # collides with a declarative one.
        fleet-integration = import ./integration-vm.nix {
          # The seat scaffolding (boot base + greeter preamble + greetd wiring) is owned by the
          # contract's own mkSeatVM harness; reach it through the `contract` flake input's source
          # tree so this fleet edition binds the SAME atom the contract's greeter-provision-vm does,
          # rather than re-authoring the seat host inline.
          # NOTE (deliberate first-consumer coupling): this reaches a conformance-internal helper by
          # RAW PATH into the contract's source tree, so it breaks if `conformance/seat-vm.nix` moves.
          # Acceptable while this is the only external consumer; promote `mkSeatVM` to a named surface
          # (a flake output / testlib path) the moment a second consumer needs it.
          mkSeatVM =
            (import "${contract}/conformance/seat-vm.nix" {
              inherit pkgs system;
              contractModule = contract.nixosModules.default;
              greeterModule = contract.nixosModules.greeter;
            }).mkSeatVM;
          # The nested `homes` output, exactly as a greeter's `homeBuilder` reaches it:
          # `homes.<system>.<user>.<mode>`. `gui` because this seat runs a desktop session.
          homeActivation = users.homes.${system}.ada.gui.activationPackage;
          identityJson = "${users}/users/ada/identity.json";
          username = "ada";
        };
      };
    };
}
