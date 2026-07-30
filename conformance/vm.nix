# Runtime VM for the gui-surface decision (session-agnostic, ADR-0021) — the one piece of the
# contract's regression gate that genuinely needs a booted machine rather than a pure eval (the
# eval-level decision lives in ./default.nix). Ported into the contract's own suite from its
# original in-repo location (ADR-0004: the generic suite — including this VM — ships with the
# contract and gets independent CI).
#
# It boots ONE single-seat host that grants gui to a user and proves the realization asked for a
# display surface (custom.gui.surface.enabled) AND that a host-side binding, reading only that
# neutral flag, renders a live session directory: the system's session directory contains a plasma
# session and the user account activated. That is the contract's claim — a granted gui user brings
# up a session on the seat — observed on a real machine, not just in the option tree.
#
# The contract is display-server-AGNOSTIC (ADR-0021): it decides `custom.gui.surface.enabled` and
# never knows or decides wayland vs x11 — the SESSION TYPE is wholly the seat's concern. So this
# suite supplies its OWN minimal test binding (SDDM + Plasma 6) to render the decision, exactly the
# role a host's gui-desktop binding plays in production. The shipped contract module stays neutral;
# the *test* picks a backend, the same way ./default.nix stubs the platform interface.
#
# Lean by design: the display-manager unit is present but not pulled in at boot (we only assert the
# assembled session *artifacts* + account activation), so the VM reaches multi-user without starting
# a graphical greeter.
{
  pkgs,
  contractModule,
  system,
}:
pkgs.testers.runNixOSTest {
  name = "contract-gui-surface";

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
      # Brings the `custom.users` schema + the host-invariant realization that derives the
      # session-agnostic gui-surface decision (custom.gui.surface.enabled). Depends only on lib —
      # no `self`, no `inputs`, so (unlike the fleet original) the node needs no specialArgs.
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

        # The suite's OWN test display binding — renders the neutral custom.gui.surface.enabled
        # flag with SDDM + Plasma 6. This is NOT part of the shipped contract (a real host supplies
        # its own gui-desktop binding); it lives here so the contract's runtime proof needs no host
        # repo. The SEAT (this binding) picks the session type — Plasma's default Wayland session —
        # not the contract (ADR-0021).
        services = lib.mkIf surface.enabled {
          displayManager.sddm.enable = lib.mkDefault true;
          displayManager.defaultSession = lib.mkDefault "plasma";
          desktopManager.plasma6.enable = lib.mkDefault true;
        };

        # One gui user on the seat, choosing a desktop by its free-form NAME. The realization sees
        # the grant and asks for a surface (custom.gui.surface.enabled); the session type its
        # desktop runs as is the seat binding's concern (ADR-0021).
        custom.users.aurelia = {
          identity = {
            name = "Aurelia Example";
            email = "aurelia@example.invalid";
            username = "aurelia";
          };
          granted.gui.enable = true;
          gui.desktop = "plasma";
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

      # The surface artifact: the seat binding rendered a live plasma session for the granted gui
      # user (Plasma's default is Wayland — the seat's choice, not the contract's).
      machine.succeed("ls ${sessions}/share/wayland-sessions/ | grep -qi plasma")

      # The gui user is realized as a real account on the booted host.
      machine.succeed("getent passwd aurelia")

      print(machine.succeed("ls ${sessions}/share/wayland-sessions/"))
    '';
}
