{
  description = "The host↔user contract — shared schema, host-invariant realization, derivation logic, and conformance kit. Depends only on nixpkgs lib.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The contract version. Single-sourced in ./version.nix, which release-please owns and
      # `manifest.nix` also imports — see that file for why it is not inlined here.
      version = import ./version.nix;
      kit = import ./kit.nix { inherit (nixpkgs) lib; };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # The umbrella kit: one module per eval-side, closed over the registries.
      #
      # `nixosModules` is deliberately NOT a single `default`: `default` is the schema +
      # realization every host wants; `greeter` is the opt-in reference runtime greeter (greetd +
      # the eval-free bind→select→provision flow) a SEAT host enables and a headless host omits.
      nixosModules.default = kit.nixosModule;
      nixosModules.greeter = kit.greeterModule;
      homeModules.default = kit.homeModule;
      # The home baseline: the standing home-manager hygiene every produced home starts from —
      # every line mkDefault, so a user's plain definition wins per-option. `lib.mkContractHome`
      # composes it by default; exposed here so a consumer building homes by hand can opt in.
      # Separate from `default` because it references home-manager option paths, and the default
      # umbrella must stay evaluable with no home-manager present.
      homeModules.baseline = kit.homeBaselineModule;
      # Legacy-spelling alias: `homeModules` is the modern name (mirrors nixosModules/darwinModules
      # and home-manager's own `<x>Modules.default` outputs), but the older `homeManagerModules`
      # spelling is still common in the wild, so expose the same values under it for discoverability.
      # Same modules, no divergence — prefer `homeModules` in new consumers.
      homeManagerModules = self.homeModules;

      # The contract derivation functions.
      inherit (kit) lib;

      # The contract version — `nix eval <contract>#contractVersion`. The same value a manifest
      # declares and `readManifest` gates on, exposed so a fleet can record which contract a host is
      # running without git archaeology. Semantics live in docs/adr/0024; while it reads `0.x`, a
      # breaking change arrives as a MINOR bump, so read the CHANGELOG rather than the digit.
      contractVersion = version;

      # Data surface: the FEATURE vocabulary a host affords out of (per user), the MODE vocabulary
      # a producer bakes over and BOTH parties declare under (a user says which it runs in, a host
      # says which it can run), what a greeter confers, and the identity.json convention (filename
      # + schema) a greeter authenticates on.
      inherit (kit)
        features
        featureGroups
        privilegedGroups
        safeSet
        modes
        floorMode
        greeterAffordances
        tier1EvalConfig
        identityFile
        identitySchema
        ;

      # The contract's own conformance suite: proves the contract's
      # promises against synthetic users on synthetic systems built from the umbrella —
      # no host repo. Independent CI; the host keeps only the thin coherence gate.
      checks = forAllSystems (system: {
        # Eval-level proof: grant/deny, the session-agnostic gui-surface DECISION, the clamp, the
        # exposed-host ban, and the users × archetypes matrix.
        conformance = import ./conformance {
          inherit system;
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};
          nixosSystem = nixpkgs.lib.nixosSystem;
          # The suite reads what it needs off these two, rather than this file re-listing every
          # name a domain happens to want. `self` deliberately, not `kit`: the suite then exercises
          # the REAL flake outputs, so an output wired to the wrong kit attr fails here instead of
          # shipping. `kit` is passed only for `internal` — the in-repo kernels that are not
          # outputs (ADR-0014).
          inherit self kit;
        };

        # Runtime proof (a booted VM): the session-agnostic gui-surface decision RENDERS — one seat,
        # a machine declaring the gui mode ⇒ contract.display.enabled, a test SDDM/Plasma binding renders a live
        # plasma session + the account activated. The seat picks the session type, not the contract
        # (ADR-0021). Uses a test-only SDDM/Plasma binding the suite supplies. Moved here from its
        # original in-repo home (ADR-0002).
        gui-surface-vm = import ./conformance/vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
        };

        # Runtime proof of the greeter's provisioning CRUX (ADR-0018, issue #2): a booted seat
        # host with nixosModules.greeter enabled materializes the example user's account and
        # activates a built home at runtime — the declarative→runtime bridge eval cannot show.
        greeter-provision-vm = import ./conformance/greeter-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          # The shared plan + what a greeter affords, so the VM proves build↔runtime parity by
          # rendering the build-time account for its fixture identity and asserting `provision`
          # reproduces it.
          inherit (kit.internal) accountPlan;
          inherit (self) greeterAffordances;
          inherit system;
        };

        # Session RENDER (ADR-0021 step 8): the bound desktop's self-contained command brings up a
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
        # a home-manager closure, which the example user flake's package builds already prove).
        greeter-bind-loop = import ./conformance/bind-loop-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          greeterModule = self.nixosModules.greeter;
          inherit system;
        };

        # A REAL full desktop environment launched by the greeter (ADR-0021) — the non-technical-user
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
            # the session and takes the seat — the seat's GNOME binding (a host concern, ADR-0021).
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

        # Runtime proof of the nix-daemon feature (ADR-0016, issue #15): a system with
        # nix.settings.allowed-users = ["@nix-users"] where one user is granted nix-daemon
        # (in nix-users → can use the daemon) and one is not (daemon-restricted).
        nix-daemon-vm = import ./conformance/nix-daemon-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
        };

        # Runtime proof of the pre-built binding path (ADR-0011, issue #16): a system that
        # uses bindContractPackage to bind the example user, boots, and verifies the account
        # materializes and the activation script runs.
        prebuilt-bind-vm = import ./conformance/prebuilt-bind-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
          inherit (kit.internal) bindContractPackage contractVersion;
        };

        # Runtime proof of package policy + daemon restriction (ADR-0016, issue #17): host
        # denies nix-daemon, sets allowedPrograms = ["hello"]; contractPackage declares hello
        # and curl; after activation hello works from PATH and curl does not.
        daemon-restricted-vm = import ./conformance/daemon-restricted-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          contractModule = self.nixosModules.default;
          inherit system;
          inherit (kit.internal) bindContractPackage contractVersion;
        };
      });

      # `nix fmt`: treefmt over the whole tree — nixfmt (RFC 166) for Nix, ruff for Python, shfmt for
      # shell. All formatters come from nixpkgs, so the contract flake still inputs only nixpkgs (no
      # treefmt-nix/git-hooks.nix inputs, ADR-0002). Config: ./treefmt.toml.
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
