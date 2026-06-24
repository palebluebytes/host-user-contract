{
  description = "Example user flake (ADR-0023) — a home-manager config repo consumed by a host via the contract's bindUser. Its inputs exist only for standalone dev; when bound, the host supplies the canonical contract + pkgs.";

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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      identity = contract.lib.loadIdentity ./identity.json;

      # The home the contract umbrella + this user's module + identity render, parameterized by
      # the host's grant (hostFacts.granted) and any extra modules. The home.* fields are the
      # home-manager glue a BOUND path gets from the host; everything else mirrors what the
      # binding injects (identity, the read-only hostFacts projection).
      mkHome =
        {
          granted ? { },
          extra ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            contract.homeModules.default
            ./home.nix
            {
              inherit identity;
              home.username = "example";
              home.homeDirectory = "/home/example";
              home.stateVersion = "25.11";
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
    in
    {
      # Standalone build (`nix build .#homeConfigurations.example.activationPackage`): proves
      # the home module + identity.json build against the contract on their own.
      homeConfigurations.example = mkHome { };

      # The home a GREETER login renders: same module, but granted the safe set (greeterGrants,
      # what the runtime path auto-grants) and carrying a marker dotfile so the integration VM can
      # observe that a REAL home-manager home actually activated for the provisioned user.
      homeConfigurations.example-greeter = mkHome {
        granted = contract.greeterGrants;
        extra = [
          # The desktop-choice helper (ADR-0029): a real home imports it ALONGSIDE the umbrella so the
          # home's contract.requests.gui.desktop is auto-surfaced to ~/.contract-desktop for the greeter.
          contract.homeModules.greeterDesktop
          { home.file.".contract-home-active".text = "greeter-activated for ${identity.name}"; }
        ];
      };

      checks.${system} = {
        # The REAL home build step — the home module + identity.json + the contract umbrella
        # render a genuine home-manager generation (with an `activate` script, the shape the
        # greeter's provisioning helper consumes). The contract's OWN suite cannot cover this:
        # it needs home-manager, which the contract does not depend on (ADR-0020), so it lives
        # HERE, in the example flake that legitimately has home-manager — the model a real user
        # repo follows when it CIs its own home.
        home-build = self.homeConfigurations.example.activationPackage;

        # The greeter path END-TO-END on a booted host: the contract's reference greeter enabled,
        # the REAL greeter-bound home (built above by home-manager THROUGH the contract) provisioned
        # at runtime by contract-greeter-provision, and its marker dotfile observed in the new
        # account's home. This is the real-home counterpart to the contract's greeter-vm (which
        # proves the provisioning helper in isolation with a stub) — the genuine
        # build→provision→activate the runtime greeter performs, in the flake that has home-manager.
        greeter-provision = import ./integration-vm.nix {
          inherit pkgs system;
          contractModule = contract.nixosModules.default;
          greeterModule = contract.nixosModules.greeter;
          homeActivation = self.homeConfigurations.example-greeter.activationPackage;
          identityJson = ./identity.json;
          username = identity.username;
        };
      };
    };
}
