{
  description = "The host↔user contract — shared schema, host-invariant realization, derivation logic, and conformance kit (ADR-0015, ADR-0020). Depends only on nixpkgs lib.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      kit = import ./kit.nix { inherit (nixpkgs) lib; };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # The umbrella kit (ADR-0020 Q2): one module per eval-side, closed over the
      # registry. A consumer imports these and binds the platform host-side.
      nixosModules.default = kit.nixosModule;
      homeModules.default = kit.homeModule;

      # The contract derivation functions (ADR-0020 Q4). The host applies the
      # fleet-bound ones (e.g. mkFeatureRecipients self.nixosConfigurations) itself.
      inherit (kit) lib;

      # Data surface the host reads where it wires grants, recipients, and the safe set.
      inherit (kit)
        features
        featureMeta
        featureGroups
        privilegedGroups
        safeSet
        ;

      # The contract's own conformance suite (ADR-0020 Q5): proves the contract's
      # promises against synthetic users on synthetic systems built from the umbrella —
      # no host repo. Independent CI; the host keeps only the thin coherence gate.
      checks = forAllSystems (system: {
        # Eval-level proof: grant/deny, the gui-session union DECISION, the clamp, the
        # exposed-host ban, and the users × archetypes matrix.
        conformance = import ./conformance {
          inherit system;
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit (self) safeSet featureGroups privilegedGroups;
          nixosSystem = nixpkgs.lib.nixosSystem;
        };

        # Runtime proof (a booted VM): the gui-session union RENDERS — one seat, two gui
        # users with different sessions ⇒ both plasma session files live + both accounts
        # activated. Uses a test-only SDDM/Plasma binding the suite supplies (the contract
        # itself is display-backend-agnostic). Moved here from the fleet (ADR-0020).
        conformance-vm = import ./conformance/vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
        };
      });

      # Dev shell for working on the contract: gh for the GitHub issue tracker
      # (see docs/agents/issue-tracker.md), nixpkgs-fmt for the Nix sources.
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = with nixpkgs.legacyPackages.${system}; [
            gh
            nixpkgs-fmt
          ];
        };
      });
    };
}
