# Runtime VM smoke for the gui-session union (ADR-0019) — the one piece of the
# contract's regression gate that genuinely needs a booted machine rather than a pure
# eval (the eval-level decision lives in ./default.nix). Ported into the contract's own
# suite from the fleet, where it lived at `parts/checks/host-user-contract-vm` (ADR-0020:
# the generic suite — including this VM — ships with the contract and gets independent CI).
#
# It boots ONE single-seat host that grants gui to two users with *different*
# `gui.session` preferences (Wayland + X11) and proves the realization derived a display
# surface offering BOTH sessions: the live system's session directory contains a plasma
# Wayland session AND a plasma X11 session, and both user accounts activated. That is the
# coexistence claim — two users log into their own session on one seat — observed on a
# real machine, not just in the option tree.
#
# The contract is display-backend-agnostic (it decides `custom.gui.surface`; a host's
# binding renders it — ADR-0021 review), so this suite supplies its OWN minimal test
# binding (SDDM + Plasma 6) to render the decision, exactly the role a host's
# gui-desktop binding plays in production. The shipped contract module stays neutral; the
# *test* picks a backend, the same way ./default.nix stubs the platform interface.
#
# Lean by design: the display-manager unit is present but not pulled in at boot (we only
# assert the assembled session *artifacts* + account activation), so the VM reaches
# multi-user without starting a graphical greeter.
{
  pkgs,
  contractModule,
  system,
}:
pkgs.testers.runNixOSTest {
  name = "contract-gui-union";

  # The contract umbrella imports insecure-packages.nix, which writes `nixpkgs.config`
  # (the single permittedInsecurePackages writer). That conflicts with the test driver's
  # default read-only nixpkgs, so let the node own its pkgs as a real host does.
  node.pkgsReadOnly = false;

  nodes.machine =
    {
      config,
      lib,
      ...
    }:
    let
      surface = config.custom.gui.surface;
    in
    {
      # Brings the `custom.users` schema + the host-invariant realization that derives
      # the gui-session decision (custom.gui.surface). Depends only on lib — no `self`,
      # no `inputs`, so (unlike the fleet original) the node needs no specialArgs.
      imports = [ contractModule ];

      config = {
        system.stateVersion = "25.11";
        nixpkgs.hostPlatform = system;
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "tmpfs";
          fsType = "tmpfs";
        };

        # Stub the platform interface (as ./default.nix does): the contract's own CI binds
        # no real secrets backend; a no-op keeps the suite robust if a future system-side
        # secret feature reads custom.platform.secretFile during eval.
        custom.platform = {
          secretFile = _: builtins.toFile "stub-secret" "";
          secretPath = _: builtins.toFile "stub-secret" "";
        };

        # Keep the boot lean: the greeter need not run for the session files to be
        # assembled into the system (they come from the session packages, not the DM
        # unit), so we reach multi-user without a graphical login.
        systemd.services.display-manager.wantedBy = lib.mkForce [ ];

        # The suite's OWN test display binding — renders custom.gui.surface with SDDM +
        # Plasma 6. This is NOT part of the shipped contract (a real host supplies its own
        # gui-desktop binding); it lives here so the contract's runtime proof needs no
        # host repo. Mirrors the rendering bits of a production gui-desktop binding.
        services = lib.mkIf surface.enabled {
          displayManager.sddm.enable = lib.mkDefault true;
          displayManager.defaultSession = lib.mkDefault "plasma";
          desktopManager.plasma6.enable = lib.mkDefault true;
          # Offer X11 iff some granted gui user wants it.
          xserver.enable = lib.mkDefault surface.x11;
          # plasma6 defaults the Wayland greeter on; keep it when the union includes a
          # Wayland user, override it off when the union is X11-only (ADR-0019 priority).
          displayManager.sddm.wayland.enable = lib.mkIf (!surface.wayland) (lib.mkOverride 900 false);
        };

        # Two gui users on one seat, each wanting a different session. The host grants gui
        # to both; the realization unions their sessions (ADR-0019).
        custom.users.aurelia = {
          identity = {
            name = "Aurelia Wayland";
            email = "aurelia@example.invalid";
            username = "aurelia";
          };
          granted.gui.enable = true;
          gui.session = "wayland";
        };
        custom.users.borealis = {
          identity = {
            name = "Borealis X11";
            email = "borealis@example.invalid";
            username = "borealis";
          };
          granted.gui.enable = true;
          gui.session = "x11";
        };
      };
    };

  # `nodes` lets us interpolate the *derived* session directory the live system was built
  # with, then assert against it inside the booted VM.
  testScript =
    { nodes, ... }:
    let
      sessions = nodes.machine.services.displayManager.sessionData.desktops;
    in
    ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      # The union artifact: the host offers BOTH a Wayland and an X11 plasma session, so
      # each granted gui user logs into their own on this single seat.
      machine.succeed("ls ${sessions}/share/wayland-sessions/ | grep -qi plasma")
      machine.succeed("ls ${sessions}/share/xsessions/ | grep -qi plasma")

      # Both gui users are realized as real accounts on the booted host.
      machine.succeed("getent passwd aurelia")
      machine.succeed("getent passwd borealis")

      print(machine.succeed("ls ${sessions}/share/wayland-sessions/ ${sessions}/share/xsessions/"))
    '';
}
