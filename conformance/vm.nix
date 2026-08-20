# Runtime VM for the display-surface decision (session-agnostic) — the one piece of the
# contract's regression gate that genuinely needs a booted machine rather than a pure eval (the
# eval-level decision lives in ./default.nix). Ported into the contract's own suite from its
# original in-repo location (ADR-0002: the generic suite — including this VM — ships with the
# contract and gets independent CI).
#
# It boots ONE single-seat host that grants gui to a user and proves the realization asked for a
# display surface (contract.display.enabled) AND that a host-side binding, reading only that
# neutral flag, renders a live session directory: the system's session directory contains a plasma
# session and the user account activated. That is the contract's claim — a granted gui user brings
# up a session on the seat — observed on a real machine, not just in the option tree.
#
# The contract is display-server-AGNOSTIC (ADR-0021): it decides `contract.display.enabled` and
# never knows or decides wayland vs x11 — the SESSION TYPE is wholly the seat's concern. So this
# suite supplies its OWN minimal test binding (SDDM + Plasma 6) to render the decision, exactly the
# role a host's gui-desktop binding plays in production. The shipped contract module stays neutral;
# the *test* picks a backend.
#
# A build-time-binding seat (greeter off, CONTEXT.md): the gui-surface decision is a realization
# concern, not a greeter one, so it takes ./seat-vm.nix's `greeter = false` boot base. Lean by design:
# the display-manager
# unit is present but not pulled in at boot (we only assert the assembled session *artifacts* +
# account activation), so the VM reaches multi-user without starting a graphical greeter.
{
  pkgs,
  contractModule,
  system,
}:
let
  inherit
    (import ./seat-vm.nix {
      inherit pkgs system contractModule;
    })
    mkSeatVM
    ;
in
mkSeatVM {
  name = "contract-gui-surface";
  greeter = false;

  seat =
    {
      config,
      lib,
      ...
    }:
    let
      surface = config.contract.display;
    in
    {
      # Keep the boot lean: the greeter need not run for the session files to be
      # assembled into the system (they come from the session packages, not the DM
      # unit), so we reach multi-user without a graphical login.
      systemd.services.display-manager.wantedBy = lib.mkForce [ ];

      # The suite's OWN test display binding — renders the neutral contract.display.enabled
      # flag with SDDM + Plasma 6. This is NOT part of the shipped contract (a real host supplies
      # its own gui-desktop binding); it lives here so the contract's runtime proof needs no host
      # repo. The SEAT (this binding) picks the session type — Plasma's default Wayland session —
      # not the contract.
      services = lib.mkIf surface.enabled {
        displayManager.sddm.enable = lib.mkDefault true;
        displayManager.defaultSession = lib.mkDefault "plasma";
        desktopManager.plasma6.enable = lib.mkDefault true;
      };

      # A seat that declares it has a display, and one account bound in the graphical mode. The
      # realization asks for a surface because the MACHINE runs that mode — not because anybody
      # was granted anything, and the account below holds no grant at all. Which desktop the user
      # logs into rides inside their home (the gui mode's own `desktop` parameter), and the
      # session type it runs as is the seat binding's concern.
      contract.modes = [ "gui" ];

      contract.users.aurelia = {
        identity = {
          name = "Aurelia Example";
          email = "aurelia@example.invalid";
          username = "aurelia";
        };
        mode = "gui";
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

      # The surface artifact: the seat binding rendered a live plasma session because the MACHINE
      # declared it runs one (Plasma's default is Wayland — the seat's choice, not the contract's).
      machine.succeed("ls ${sessions}/share/wayland-sessions/ | grep -qi plasma")

      # The gui user is realized as a real account on the booted host.
      machine.succeed("getent passwd aurelia")

      print(machine.succeed("ls ${sessions}/share/wayland-sessions/"))
    '';
}
