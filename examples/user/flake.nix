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
    in
    {
      # Standalone build (`nix build .#homeConfigurations.example.activationPackage`): proves
      # the home module + identity.json build against the contract on their own. The home.*
      # fields below are home-manager glue the BOUND path gets from the host; the contract
      # umbrella + the loaded identity + the read-only hostFacts mirror what bindUser injects.
      homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          contract.homeModules.default
          ./home.nix
          {
            identity = contract.lib.loadIdentity ./identity.json;
            home.username = "example";
            home.homeDirectory = "/home/example";
            home.stateVersion = "25.11";
          }
        ];
        extraSpecialArgs = {
          hostFacts = {
            exposed = false;
            platform = system;
            granted = { };
          };
        };
      };

      # CI for the user repo itself: building the home activation package proves the REAL home
      # build step — the home module + identity.json + the contract umbrella render a genuine
      # home-manager generation (with an `activate` script, the shape the greeter's provisioning
      # helper consumes). This is the one step the contract's OWN suite cannot cover: it needs
      # home-manager, which the contract does not depend on (ADR-0020), so it lives HERE, in the
      # example user flake that legitimately has home-manager — exactly the model a real user repo
      # follows when it CIs its own home. (`nix flake check` in this directory.)
      checks.${system}.home-build = self.homeConfigurations.example.activationPackage;
    };
}
