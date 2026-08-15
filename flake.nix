{
  description = "The host↔user contract — shared schema, host-invariant realization, derivation logic, and conformance kit (ADR-0001, ADR-0004). Depends only on nixpkgs lib.";

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
      # The umbrella kit (ADR-0004 Q2): one module per eval-side, closed over the
      # registry. A consumer imports these and binds the platform host-side.
      #
      # `nixosModules` is deliberately NOT a single `default` (ADR-0008): `default` is the
      # schema + realization + features every host wants; `greeter` is the opt-in reference
      # runtime greeter (greetd + the eval-free bind→provision flow) a SEAT host enables and a
      # headless host omits — à-la-carte justified precisely by that split.
      nixosModules.default = kit.nixosModule;
      nixosModules.greeter = kit.greeterModule;
      homeModules.default = kit.homeModule;
      # Opt-in home helper (ADR-0013): materialises ~/.contract-desktop from the home's
      # contract.requests.gui.desktop, so the greeter's launcher reads the user's desktop choice.
      # Separate from default because it touches home-manager's `home.file` (default stays
      # tracer-pure — evaluable with no home-manager, ADR-0008).
      homeModules.greeterDesktop = kit.homeGreeterDesktopModule;
      # Legacy-spelling alias: `homeModules` is the modern name (mirrors nixosModules/darwinModules
      # and home-manager's own `<x>Modules.default` outputs), but the older `homeManagerModules`
      # spelling is still common in the wild, so expose the same values under it for discoverability.
      # Same modules, no divergence — prefer `homeModules` in new consumers.
      homeManagerModules = self.homeModules;

      # The contract derivation functions (ADR-0004 Q4).
      inherit (kit) lib;

      # Data surface the host reads where it wires grants and the safe set, the home-affecting
      # feature set a PRODUCER narrows hostFacts.granted with (and derives its variant set from,
      # ADR-0028), plus the identity.json convention (filename + schema) a greeter authenticates on.
      inherit (kit)
        features
        featureGroups
        privilegedGroups
        safeSet
        homeAffecting
        greeterGrants
        tier1EvalConfig
        identityFile
        identitySchema
        ;

      # The contract's own conformance suite (ADR-0004 Q5): proves the contract's
      # promises against synthetic users on synthetic systems built from the umbrella —
      # no host repo. Independent CI; the host keeps only the thin coherence gate.
      checks = forAllSystems (system: {
        # Eval-level proof: grant/deny, the session-agnostic gui-surface DECISION, the clamp, the
        # exposed-host ban, and the users × archetypes matrix.
        conformance = import ./conformance {
          inherit system;
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          homeModule = self.homeModules.default;
          homeGreeterDesktopModule = self.homeModules.greeterDesktop;
          inherit (self)
            safeSet
            homeAffecting
            greeterGrants
            tier1EvalConfig
            featureGroups
            privilegedGroups
            ;
          inherit (self.lib)
            loadIdentity
            traceUser
            mkConfinementCheck
            mkIdentityPostureCheck
            mkContractUser
            mkContractUsers
            bindContractUser
            renderNixConfig
            ;
          # Internal derivation logic (ADR-0026): not flake outputs, but the in-repo
          # conformance suite proves them in isolation.
          inherit (kit.internal)
            mkContractPackage
            mkContractPackageForHome
            bindContractPackage
            accountPlan
            writeManifest
            readManifest
            manifestFileName
            outOfUniverseProbes
            ;
          nixosSystem = nixpkgs.lib.nixosSystem;
        };

        # Runtime proof (a booted VM): the session-agnostic gui-surface decision RENDERS — one seat,
        # a granted gui user ⇒ custom.gui.surface.enabled, a test SDDM/Plasma binding renders a live
        # plasma session + the account activated. The seat picks the session type, not the contract
        # (ADR-0021). Uses a test-only SDDM/Plasma binding the suite supplies. Moved here from its
        # original in-repo home (ADR-0004).
        gui-surface-vm = import ./conformance/vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
        };

        # Runtime proof of the greeter's provisioning CRUX (ADR-0006, issue #2): a booted seat
        # host with nixosModules.greeter enabled materializes the example user's account and
        # activates a built home at runtime — the declarative→runtime bridge eval cannot show.
        greeter-provision-vm = import ./conformance/greeter-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          # The shared plan + the fixed runtime grant, so the VM proves build↔runtime parity by
          # rendering the build-time account for its fixture identity and asserting `provision`
          # reproduces it (ADR-0012, issue #31).
          inherit (kit.internal) accountPlan;
          inherit (self) greeterGrants;
          inherit system;
        };

        # Session RENDER (ADR-0013 step 8): the bound desktop's self-contained command brings up a
        # LIVE session on real virtio-gpu DRM, via greetd-as-user. The seat owns the session type
        # (ADR-0021), so one Wayland (cage) boot exercises the render; the sequence VM below proves
        # two different desktops one-after-another on one seat. Heavy (a real graphical boot) — the
        # render counterpart to greeter-provision-vm's selection. A real GNOME/Plasma is the same shape with a
        # heavier command (the consumer-renders boundary, like the gui-surface VM's SDDM/Plasma).
        greeter-session = import ./conformance/greeter-session-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };
        greeter-session-sequence = import ./conformance/greeter-session-sequence-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };

        # The FULL real bind loop (issue #2): drive the actual contract-greeter-bind orchestrator
        # end-to-end — archive → eval-free Tier-1 auth → a reference homeBuilder's real runtime
        # `nix build` → provision → session — the one truly-runtime step the other greeter tests
        # stop short of. Offline; the fixture home is a minimal real derivation (the bind LOOP, not
        # a home-manager closure, which `home-build` already proves).
        greeter-bind-loop = import ./conformance/bind-loop-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };

        # A REAL full desktop environment launched by the greeter (ADR-0013) — the non-technical-user
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
            # the session and takes the seat — the seat's GNOME binding (a host concern, ADR-0013).
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

        # Runtime proof of the nix-daemon feature (ADR-0017, issue #15): a system with
        # nix.settings.allowed-users = ["@nix-users"] where one user is granted nix-daemon
        # (in nix-users → can use the daemon) and one is not (daemon-restricted).
        nix-daemon-vm = import ./conformance/nix-daemon-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
        };

        # Runtime proof of the pre-built binding path (ADR-0016, issue #16): a system that
        # uses bindContractPackage to bind the example user, boots, and verifies the account
        # materializes and the activation script runs.
        prebuilt-bind-vm = import ./conformance/prebuilt-bind-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
          inherit (kit.internal) bindContractPackage;
        };

        # Runtime proof of package policy + daemon restriction (ADR-0017, issue #17): host
        # denies nix-daemon, sets allowedPrograms = ["hello"]; contractPackage declares hello
        # and curl; after activation hello works from PATH and curl does not.
        daemon-restricted-vm = import ./conformance/daemon-restricted-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
          inherit (kit.internal) bindContractPackage;
        };
      });

      # `nix fmt`: treefmt over the whole tree — nixfmt (RFC 166) for Nix, ruff for Python, shfmt for
      # shell. All formatters come from nixpkgs, so the contract flake still inputs only nixpkgs (no
      # treefmt-nix/git-hooks.nix inputs, ADR-0004). Config: ./treefmt.toml.
      formatter = forAllSystems (
        system:
        let
          p = nixpkgs.legacyPackages.${system};
        in
        p.writeShellApplication {
          name = "treefmt";
          runtimeInputs = [
            p.treefmt
            p.nixfmt
            p.ruff
            p.shfmt
          ];
          text = ''exec treefmt "$@"'';
        }
      );

      # Dev shell: the project's tools (`nix develop`). Formatting (treefmt + the per-language
      # formatters) and linting (statix/deadnix for Nix, ruff for Python, shellcheck for shell), plus
      # gh for the issue tracker. The shellHook points git at the committed pre-commit hook.
      devShells = forAllSystems (
        system:
        let
          p = nixpkgs.legacyPackages.${system};
        in
        {
          default = p.mkShellNoCC {
            packages = [
              p.gh
              p.treefmt
              p.nixfmt
              p.ruff
              p.shfmt
              p.statix
              p.deadnix
              p.shellcheck
            ];
            shellHook = ''
              git config --local core.hooksPath .githooks 2>/dev/null || true
              echo "contract dev shell · nix fmt (treefmt) · lint: statix/deadnix/ruff/shellcheck · hooks: .githooks"
            '';
          };
        }
      );
    };
}
