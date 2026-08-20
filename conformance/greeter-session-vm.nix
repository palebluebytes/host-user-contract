# Runtime VM for the greeter's SESSION RENDER (ADR-0021) — proves the bound
# `contract.greeter.desktops.<name>.command` brings up a LIVE graphical session, the render counterpart
# to greeter-provision-vm's session SELECTION (which only checks which command is chosen).
#
# A real compositor needs a logind SEAT session for DRM/KMS access — which greetd establishes
# (it creates the seat session and runs the session command AS the user). So this uses ./seat-vm.nix's
# live-session posture: greetd's `initial_session` autologins alice into our `contract-greeter-session`
# launcher (run as the user, so it execs the backend in place), the same shape production uses. QEMU's
# virtio-gpu gives real DRM (software-rendered via llvmpipe), exactly as nixpkgs' own cage/sway
# graphical tests do. The compositor is supplied as a TEST binding (the contract ships none, ADR-0002)
# — the consumer-renders boundary, like the gui-union VM supplying SDDM/Plasma.
#
# The session command is SELF-CONTAINED: the contract does not know or set the session type (wayland
# vs x11) — the seat's command owns that (ADR-0021). This test binds a Wayland compositor (cage); an
# x11 seat would bind a command that starts Xorg itself. Render is decoupled from provisioning here
# (alice is a declared account — the harness declares her for the autologin) — provisioning is proven
# in greeter-provision-vm; this isolates "does the bound session backend actually come up live."
{
  pkgs,
  system,
  contractModule,
  greeterModule,
}:
let
  inherit
    (import ./seat-vm.nix {
      inherit
        pkgs
        system
        contractModule
        greeterModule
        ;
    })
    mkSeatVM
    ;

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
mkSeatVM {
  name = "contract-greeter-session";
  graphical = true;
  autologin = "alice";

  # Offer one desktop (the self-contained Wayland command under test). greetd autologins alice into
  # our launcher, which (running AS alice, in greetd's seat session) resolves + execs it.
  seat = {
    contract.greeter.desktops.wayland.command = backend;
    contract.greeter.defaultDesktop = "wayland";
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
