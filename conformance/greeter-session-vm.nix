# Runtime VM for the greeter's SESSION RENDER (ADR-0026 step 8) — proves the bound
# `custom.greeter.session.<type>` backend brings up a LIVE graphical session, the render counterpart
# to greeter-vm's session SELECTION (which only checks which command is chosen).
#
# A real compositor/Xorg needs a logind SEAT session for DRM/KMS access — which greetd establishes
# (it creates the seat session and runs the session command AS the user). So this drives greetd's
# `initial_session` autologin into our `contract-greeter-session` launcher (run as the user, so it
# execs the backend in place), the same shape production uses. QEMU's virtio-gpu gives real DRM
# (software-rendered via llvmpipe), exactly as nixpkgs' own cage/sway graphical tests do. The
# compositor is supplied as a TEST binding (the contract ships none, ADR-0020) — the
# consumer-renders boundary, like the gui-union VM supplying SDDM/Plasma.
#
# Render is decoupled from provisioning here (alice is a declared account) — provisioning is proven
# in greeter-vm; this isolates "does the bound session backend actually come up live."
{
  pkgs,
  system,
  contractModule,
  greeterModule,
  sessionType,
}:
let
  marker = "/tmp/greeter-session-${sessionType}";

  # A tiny client with NO X dependency: it records it reached a live session, then idles so the
  # compositor/X server stays up while we assert. (A graphical client like xterm-under-Xwayland is
  # fragile and unnecessary — the display socket below already proves the server is live on DRM.)
  client = pkgs.writeShellScript "greeter-session-client" ''
    touch ${marker}
    exec ${pkgs.coreutils}/bin/sleep 600
  '';

  backends = {
    wayland = "${pkgs.cage}/bin/cage -- ${client}";
    # X11 launches via startx, which uses the system's setuid X wrapper (services.xserver below)
    # to start Xorg rootlessly on the seat's DRM, then runs the client.
    x11 = "${pkgs.xorg.xinit}/bin/startx ${client} -- :0 vt1";
  };

  liveChecks = {
    wayland = ''
      # A LIVE Wayland compositor on real DRM: its display socket lock exists (cage bound it after
      # acquiring the GPU), and the bound session's client reached the session.
      machine.wait_for_file("/run/user/1000/wayland-0.lock")
      machine.wait_for_file("${marker}")
      machine.screenshot("greeter-session-wayland")
    '';
    x11 = ''
      # A LIVE X server on real DRM: its socket exists (Xorg started on the GPU), and the client
      # reached the session.
      machine.wait_for_file("/tmp/.X11-unix/X0")
      machine.wait_for_file("${marker}")
      machine.screenshot("greeter-session-x11")
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-session-${sessionType}";

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

      # X11 needs the Xorg server + the setuid wrapper `startx` invokes to start it rootlessly on
      # the seat; Wayland (cage) needs neither. (No display manager — greetd is the seat's DM.)
      services.xserver.enable = sessionType == "x11";
      services.xserver.displayManager.startx.enable = sessionType == "x11";

      # The user whose session we render (declared — provisioning is proven separately in greeter-vm).
      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };

      # Enable the greeter and offer one desktop (the backend under test). greetd autologins alice
      # into our launcher, which (running AS alice, in greetd's seat session) resolves + execs it.
      custom.greeter.enable = true;
      custom.greeter.desktops.${sessionType} = {
        type = sessionType;
        command = backends.${sessionType};
      };
      custom.greeter.defaultDesktop = sessionType;
      services.greetd.settings.initial_session = lib.mkForce {
        user = "alice";
        command = "/run/current-system/sw/bin/contract-greeter-session alice /home/alice";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    ${liveChecks.${sessionType}}
  '';
}
