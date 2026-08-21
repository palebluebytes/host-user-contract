{
  description = "Reference HOST FLEET — a NixOS machine fleet that consumes the contract by binding the reference user fleet (examples/users) per user, turnkey, via bindContractUser. It shows the contract's reason to exist: two independently-owned repos (hosts, users) meeting at the binding. Positive-space reference with its own smoke/coherence checks; it never re-bases the contract's synthetic conformance suite.";

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
      # what the MACHINE can run (`contract.modes`) and what each PERSON may do (their entry in
      # `contract.lib.bindContractUsers { source; users; }`). Those are the whole consumer surface,
      # and they are two surfaces rather than one because they answer different questions: a
      # display is a fact about hardware, and sudo is a judgement about somebody.
      #
      # The SAME user bound on different machines is what makes any-host × any-user real — ada is a
      # desktop account on desk and a terminal one on agent, from one identity and one source,
      # because the hardware differs and not because anybody decided anything about her. The
      # contract umbrella + the shared base are merged here.
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
        # would activate) and observes it activate — the runtime half of one consumption
        # convention. There is no greeter-specific artifact: a grant can never reach a home, so a
        # greeter-granted home would have nothing to differ in. Focused seat node (like the
        # contract's own greeter-provision-vm), not the full desk host, so the provisioned account
        # never collides with a declarative one.
        fleet-integration = import ./integration-vm.nix rec {
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
          # The MODE the greeter selected. `gui` here because a greeter seat declares
          # `contract.modes = [ "gui" ]`, so it runs { cli, gui } and ada publishes both. It is
          # named ONCE and used twice — to select the home below, and (threaded into the VM) as
          # `provision`'s mode argument — because the account plan folds the selected mode's groups
          # in, so a home built for one mode must never be provisioned under another (ADR-0012).
          mode = "gui";
          # The nested `homes` output, exactly as a greeter's `homeBuilder` reaches it:
          # `homes.<system>.<user>.<mode>`.
          homeActivation = users.homes.${system}.ada.${mode}.activationPackage;
          identityJson = "${users}/users/ada/identity.json";
          username = "ada";
        };
      };
    };
}
