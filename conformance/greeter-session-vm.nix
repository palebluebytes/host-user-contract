# Runtime VM for the greeter's SESSION RENDER (ADR-0010 step 8) — proves the bound
# `custom.greeter.desktops.<name>.command` brings up a LIVE graphical session, the render counterpart
# to greeter-vm's session SELECTION (which only checks which command is chosen).
#
# A real compositor needs a logind SEAT session for DRM/KMS access — which greetd establishes
# (it creates the seat session and runs the session command AS the user). So this drives greetd's
# `initial_session` autologin into our `contract-greeter-session` launcher (run as the user, so it
# execs the backend in place), the same shape production uses. QEMU's virtio-gpu gives real DRM
# (software-rendered via llvmpipe), exactly as nixpkgs' own cage/sway graphical tests do. The
# compositor is supplied as a TEST binding (the contract ships none, ADR-0004) — the
# consumer-renders boundary, like the gui-union VM supplying SDDM/Plasma.
#
# The session command is SELF-CONTAINED: the contract does not know or set the session type (wayland
# vs x11) — the seat's command owns that (ADR-0021). This test binds a Wayland compositor (cage); an
# x11 seat would bind a command that starts Xorg itself. Render is decoupled from provisioning here
# (alice is a declared account) — provisioning is proven in greeter-vm; this isolates "does the bound
# session backend actually come up live."
{
  pkgs,
  system,
  contractModule,
  greeterModule,
}:
let
  marker = "/tmp/greeter-session";

  # A tiny client with NO X dependency: it records it reached a live session, then idles so the
  # compositor stays up while we assert. (A graphical client like xterm-under-Xwayland is fragile
  # and unnecessary — the display socket below already proves the server is live on DRM.)
  client = pkgs.writeShellScript "greeter-session-client" ''
    touch ${marker}
    exec ${pkgs.coreutils}/bin/sleep 600
  '';

  # The seat's self-contained Wayland session command (cage kiosk compositor running the client).
  backend = "${pkgs.cage}/bin/cage -- ${client}";
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-session";

  # The contract umbrella writes nixpkgs.config (insecure-packages.nix); let the node own its pkgs.
  node.pkgsReadOnly = false;
  # Real DRM/KMS for the compositor (software-rendered), as nixpkgs' cage/sway tests do.
  enableOCR = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        contractModule
        greeterModule
      ];

      system.stateVersion = "25.11";
      nixpkgs.hostPlatform = system;
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "tmpfs";
        fsType = "tmpfs";
      };
      custom.platform = {
        secretFile = _: builtins.toFile "stub-secret" "";
        secretPath = _: builtins.toFile "stub-secret" "";
      };

      hardware.graphics.enable = true;
      fonts.packages = [ pkgs.dejavu_fonts ];
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];

      # The user whose session we render (declared — provisioning is proven separately in greeter-vm).
      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };

      # Enable the greeter and offer one desktop (the self-contained Wayland command under test).
      # greetd autologins alice into our launcher, which (running AS alice, in greetd's seat session)
      # resolves + execs it.
      custom.greeter.enable = true;
      custom.greeter.desktops.wayland.command = backend;
      custom.greeter.defaultDesktop = "wayland";
      services.greetd.settings.initial_session = lib.mkForce {
        user = "alice";
        command = "/run/current-system/sw/bin/contract-greeter-session alice /home/alice";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # A LIVE Wayland compositor on real DRM: its display socket lock exists (cage bound it after
    # acquiring the GPU), and the bound session's client reached the session.
    machine.wait_for_file("/run/user/1000/wayland-0.lock")
    machine.wait_for_file("${marker}")
    machine.screenshot("greeter-session-wayland")
  '';
}
