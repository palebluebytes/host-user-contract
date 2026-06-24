# Runtime VM: DIFFERENT graphical systems booting ONE AFTER ANOTHER on one seat (ADR-0026).
# The single-seat counterpart to the wayland↔x11 handoff question: a Wayland user's session ends,
# then a DIFFERENT Wayland compositor comes up on the same seat — proving the seat can host distinct
# desktop systems sequentially (DRM master released by the first, acquired by the next, within one
# greetd seat session). Staying within Wayland keeps it off the flaky cross-type (Wayland↔X11) DRM
# handoff, which is pure logind/backend behaviour, not contract logic.
#
# greetd's `initial_session` runs ONE command — here a script that launches compositor A, waits for
# it to exit, then compositor B. Each runs a client that records it reached a live session. Two
# genuinely different wlroots compositors are used: cage (single-window kiosk) and sway (tiling WM).
#
# NOTE on GNOME: gnome-shell/mutter standalone (no GDM) does not start-and-cleanly-exit when launched
# as a bare greetd session command — a full DE expects a display manager + systemd user session, not
# the greeter's bare session exec. So "a GNOME session then another" is a display-MANAGER scenario,
# not a greeter-session-launch one; the greeter's job (decide the type, exec the host-bound backend)
# is what this proves, with two compositors that DO launch+exit cleanly. A seat that wants GNOME binds
# a GNOME launcher to custom.greeter.session.wayland; rendering a full DE is the host backend's concern
# (the consumer-renders boundary), exactly as the gui-union VM renders Plasma via a host SDDM binding.
{
  pkgs,
  system,
  contractModule,
  greeterModule,
}:
let
  # sway exits after recording its marker (a tiling WM doesn't self-exit, so we tell it to).
  swayConfig = pkgs.writeText "greeter-seq-sway.conf" ''
    exec ${pkgs.writeShellScript "sway-once" ''
      touch /tmp/seq-sway
      exec ${pkgs.sway}/bin/swaymsg exit
    ''}
  '';

  # The bound Wayland backend: compositor A (cage) then compositor B (sway), in sequence. cage exits
  # when its client exits; sway exits via swaymsg. Each marker proves that compositor initialised the
  # GPU far enough to run its client.
  sequence = pkgs.writeShellScript "greeter-session-sequence" ''
    ${pkgs.cage}/bin/cage -- ${pkgs.writeShellScript "cage-once" "touch /tmp/seq-cage"}
    ${pkgs.sway}/bin/sway -c ${swayConfig}
  '';
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-session-sequence";

  node.pkgsReadOnly = false;
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

      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
      };

      custom.greeter.enable = true;
      custom.greeter.desktops.sequence = {
        type = "wayland";
        command = "${sequence}";
      };
      custom.greeter.defaultDesktop = "sequence";
      services.greetd.settings.initial_session = lib.mkForce {
        user = "alice";
        command = "/run/current-system/sw/bin/contract-greeter-session alice /home/alice";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # Compositor A (cage) comes up first and runs its client.
    machine.wait_for_file("/tmp/seq-cage")
    # Then a DIFFERENT compositor (sway) comes up on the same seat and runs its client.
    machine.wait_for_file("/tmp/seq-sway")

    # They ran in order on one seat: the first compositor's marker predates the second's.
    machine.succeed("test /tmp/seq-cage -ot /tmp/seq-sway")
  '';
}
