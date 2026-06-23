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
    };
}
