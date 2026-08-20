# Runtime VM: a REAL full desktop environment launched by the greeter (ADR-0013) — the
# non-technical-user target. Where greeter-session-vm proves the mechanism with lightweight
# compositors, this proves an actual DE (GNOME/Plasma) comes up live when the seat binds its
# session entry to a desktop and a user logs in — the same session command a display manager
# (GDM/SDDM) would exec, run instead by the greeter in greetd's seat session.
#
# Uses ./seat-vm.nix's live-session posture (greetd autologins alice into the session launcher).
# Heavy by nature (a full DE closure booted under software-rendered virtio-gpu). The DE is supplied
# as a TEST binding (the contract ships none, ADR-0004) — the consumer-renders boundary.
{
  pkgs,
  system,
  contractModule,
  greeterModule,
  de,
}:
let
  lib = pkgs.lib;
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
in
mkSeatVM {
  name = "contract-greeter-desktop-${de.name}";
  graphical = true;
  autologin = "alice";

  # The seat offers the DE; the greeter launches its session entry as the user (greetd's seat session
  # gives it the systemd-user instance + D-Bus + DRM a full DE needs). The DE's session-entry command
  # is self-contained (the seat owns the session type, ADR-0021). A full DE needs real RAM + GPU.
  seat = {
    imports = [ de.module ];
    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    contract.greeter.desktops.${de.name}.command = de.command;
    contract.greeter.defaultDesktop = de.name;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # The real DE's compositor + shell come up live, as the user.
    ${lib.concatMapStringsSep "\n" (
      p: "machine.wait_until_succeeds(\"pgrep -u alice -f ${p}\", timeout=240)"
    ) de.procs}
    machine.wait_for_file("/run/user/1000/wayland-0.lock")
    machine.screenshot("greeter-desktop-${de.name}")
  '';
}
