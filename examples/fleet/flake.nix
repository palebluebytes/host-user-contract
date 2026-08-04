{
  description = "Reference HOST FLEET — a NixOS machine fleet that consumes the contract by binding the reference user fleet (examples/users) per user via bindContractPackage (ADR-0016). It shows the contract's reason to exist: two independently-owned repos (hosts, users) meeting at the binding. Positive-space reference with its own smoke/coherence checks (docs/adr/0022); it never re-bases the contract's synthetic conformance suite.";

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

      # The ONE consumption convention: bind a user by its per-user contractPackage flake output,
      # loading the user's PUBLIC identity from the users repo the host pins (ADR-0006 data-before-
      # code: the host reads identity.json BEFORE any of the user's Nix). `grants` is the host's
      # sovereign decision — the sole enabler (ADR-0001). The SAME output bound with different
      # grants on different hosts is what makes any-host×any-user real.
      bindUserPkg =
        { name, grants }:
        contract.lib.bindContractPackage {
          contractPackage = users.packages.${system}."${name}-contractPackage";
          identity = contract.lib.loadIdentity "${users}/users/${name}/identity.json";
          inherit grants;
        };

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
      # which users it binds and with which grants, whether it is a seat or exposed. The contract
      # umbrella + the shared base are merged in here.
      mkHost =
        hostFile:
        lib.nixosSystem {
          modules = [
            contract.nixosModules.default
            commonBase
            (import hostFile { inherit contract bindUserPkg; })
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
        # `-greeter` home output (a sibling of `ada-contractPackage`, built from the same user with
        # the safe-set grant) and observes her real home activate — the runtime half of the uniform
        # flake-output consumption convention (declarative binds the contractPackage, the greeter
        # builds the greeter home), the
        # counterpart to the declarative binds above. Focused seat node (like the contract's own
        # greeter-vm), not the full desk host, so the provisioned account never collides with a
        # declarative one.
        fleet-integration = import ./integration-vm.nix {
          inherit pkgs system;
          contractModule = contract.nixosModules.default;
          greeterModule = contract.nixosModules.greeter;
          homeActivation = users.homeConfigurations.ada-greeter.activationPackage;
          identityJson = "${users}/users/ada/identity.json";
          username = "ada";
        };
      };
    };
}
