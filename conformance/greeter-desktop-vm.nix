# Runtime VM: a REAL full desktop environment launched by the greeter (ADR-0029) — the
# non-technical-user target. Where greeter-session-vm proves the mechanism with lightweight
# compositors, this proves an actual DE (GNOME/Plasma) comes up live when the seat binds its
# session entry to a desktop and a user logs in — the same session command a display manager
# (GDM/SDDM) would exec, run instead by the greeter in greetd's seat session.
#
# Heavy by nature (a full DE closure booted under software-rendered virtio-gpu). The DE is supplied
# as a TEST binding (the contract ships none, ADR-0020) — the consumer-renders boundary.
{
  pkgs,
  system,
  contractModule,
  greeterModule,
  de,
}:
let
  lib = pkgs.lib;
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-desktop-${de.name}";

  node.pkgsReadOnly = false;
  enableOCR = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        contractModule
        greeterModule
        de.module
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

      # A full DE needs real RAM + GPU. virtio-gpu gives software-rendered DRM/KMS.
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
      hardware.graphics.enable = true;
      fonts.packages = [ pkgs.dejavu_fonts ];
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];

      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };

      # The seat offers the DE; the greeter launches its session entry as the user (greetd's seat
      # session gives it the systemd-user instance + D-Bus + DRM a full DE needs).
      custom.greeter.enable = true;
      custom.greeter.desktops.${de.name} = {
        type = "wayland";
        command = de.command;
      };
      custom.greeter.defaultDesktop = de.name;
      services.greetd.settings.initial_session = lib.mkForce {
        user = "alice";
        command = "/run/current-system/sw/bin/contract-greeter-session alice /home/alice";
      };
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
