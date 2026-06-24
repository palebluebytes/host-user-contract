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
      #
      # `nixosModules` is deliberately NOT a single `default` (ADR-0024): `default` is the
      # schema + realization + features every host wants; `greeter` is the opt-in reference
      # runtime greeter (greetd + the eval-free bind→provision flow) a SEAT host enables and a
      # headless host omits — à-la-carte justified precisely by that split.
      nixosModules.default = kit.nixosModule;
      nixosModules.greeter = kit.greeterModule;
      homeModules.default = kit.homeModule;

      # The contract derivation functions (ADR-0020 Q4). The host applies the
      # fleet-bound ones (e.g. mkFeatureRecipients self.nixosConfigurations) itself.
      inherit (kit) lib;

      # Data surface the host reads where it wires grants, recipients, and the safe set,
      # plus the identity.json convention (filename + schema) a greeter authenticates on.
      inherit (kit)
        features
        featureMeta
        featureGroups
        privilegedGroups
        safeSet
        greeterGrants
        tier1EvalConfig
        identityFile
        identitySchema
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
          greeterModule = self.nixosModules.greeter;
          homeModule = self.homeModules.default;
          inherit (self)
            safeSet
            greeterGrants
            tier1EvalConfig
            featureGroups
            privilegedGroups
            ;
          inherit (self.lib)
            loadIdentity
            bindUser
            bindUserModule
            renderNixConfig
            ;
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

        # Runtime proof of the greeter's provisioning CRUX (ADR-0022, issue #2): a booted seat
        # host with nixosModules.greeter enabled materializes the example user's account and
        # activates a built home at runtime — the declarative→runtime bridge eval cannot show.
        greeter-vm = import ./conformance/greeter-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };

        # Session RENDER (ADR-0029 step 8): the bound desktop brings up a LIVE session on real
        # virtio-gpu DRM, via greetd-as-user. Wayland (cage) and X11 as separate boots, plus two
        # different desktops one-after-another on one seat. Heavy (a real graphical boot) — the
        # render counterpart to greeter-vm's selection. A real GNOME/Plasma is the same shape with a
        # heavier command (the consumer-renders boundary, like the gui-union VM's SDDM/Plasma).
        greeter-session-wayland = import ./conformance/greeter-session-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          sessionType = "wayland";
          inherit system;
        };
        greeter-session-x11 = import ./conformance/greeter-session-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          sessionType = "x11";
          inherit system;
        };
        greeter-session-sequence = import ./conformance/greeter-session-sequence-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };

        # A REAL full desktop environment launched by the greeter (ADR-0029) — the non-technical-user
        # target. The seat enables the DE and binds its session entry to a desktop; a greeter login
        # brings it up live, exactly as a display manager would exec it. Heavy (a full DE closure).
        greeter-desktop-plasma = import ./conformance/greeter-desktop-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
          de = {
            name = "plasma";
            module = {
              services.desktopManager.plasma6.enable = true;
            };
            command = "${
              nixpkgs.legacyPackages.${system}.kdePackages.plasma-workspace
            }/bin/startplasma-wayland";
            procs = [
              "kwin_wayland"
              "plasmashell"
            ];
          };
        };
        greeter-desktop-gnome = import ./conformance/greeter-desktop-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
          de = {
            name = "gnome";
            module = {
              services.desktopManager.gnome.enable = true;
            };
            # GNOME 50's gnome-session starts gnome-shell as a systemd USER service, detached from
            # greetd's login session, so mutter can't find its seat ("no matching session"). Launch
            # gnome-shell as a DIRECT CHILD of the greetd session (as kwin/cage/sway run) so it is in
            # the session and takes the seat — the seat's GNOME binding (a host concern, ADR-0029).
            command =
              let
                p = nixpkgs.legacyPackages.${system};
              in
              "${p.writeShellScript "gnome-wayland" ''
                export XDG_SESSION_TYPE=wayland
                export XDG_CURRENT_DESKTOP=GNOME
                export XDG_DATA_DIRS=/run/current-system/sw/share
                exec ${p.gnome-shell}/bin/gnome-shell --wayland --display-server
              ''}";
            procs = [ "gnome-shell" ];
          };
        };
      });

      # `nix fmt` canonical formatter: nixfmt (RFC 166), the official successor to the
      # now-deprecated nixpkgs-fmt. Unlike nixpkgs-fmt it enforces a single function-arg
      # comma style, so the whole tree stays consistent (`nix fmt`, or `nixfmt --check` in CI).
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      # Dev shell for working on the contract: gh for the GitHub issue tracker
      # (see docs/agents/issue-tracker.md), nixfmt for the Nix sources (`nix fmt`).
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = with nixpkgs.legacyPackages.${system}; [
            gh
            nixfmt
          ];
        };
      });
    };
}
