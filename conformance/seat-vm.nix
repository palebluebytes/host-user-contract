# Shared conformance fixtures for the greeter-family runtime VMs — the standing seat-host
# scaffolding every seat test otherwise re-authors: the bootable base (hostPlatform + no-bootloader
# + tmpfs root + stateVersion), the greeter-seat preamble (contract + greeter modules,
# `custom.greeter.enable`, the greetd wiring), the activation stub, and the ssh-signing fixtures. It
# plays the role ./toolkit.nix plays for the eval side: each greeter VM file (./greeter-vm.nix,
# ./greeter-session-vm.nix, ./greeter-session-sequence-vm.nix, ./greeter-desktop-vm.nix) becomes a
# focused record of what it VARIES — the users/grants, the desktop binding, the assertion — handed
# to `mkSeatVM`. Built per-VM in ./flake.nix (no host repo, no host bindings, ADR-0004 Q5).
{
  pkgs,
  system,
  contractModule,
  greeterModule,
}:
let
  lib = pkgs.lib;

  # The bootable base + greeter-seat preamble every seat host shares (config-only so it composes in
  # an `imports` list): no bootloader, a tmpfs root, a pinned stateVersion, and the reference greeter
  # enabled (ADR-0008). The contract umbrella + greeter modules are imported by mkSeatVM alongside it.
  bootBase = {
    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = system;
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
    custom.greeter.enable = true;
  };

  # Real DRM/KMS for a live compositor: QEMU virtio-gpu (software-rendered via llvmpipe), exactly as
  # nixpkgs' own cage/sway graphical tests do. Shared by every seat VM that brings up a live session.
  graphicalBase = {
    hardware.graphics.enable = true;
    fonts.packages = [ pkgs.dejavu_fonts ];
    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
  };

  # The greetd wiring, by boot posture. `autologin == null` ⇒ the HELPERS-DRIVEN posture: greetd
  # stays off the console at boot so the test drives the privileged helpers by hand
  # (greeter-provision). A username ⇒ the LIVE-SESSION posture: declare the account (uid 1000) and
  # autologin them into the session launcher, which — running AS the user in greetd's seat session —
  # resolves + execs the bound desktop (greeter-session / -sequence / -desktop).
  greetdWiring =
    autologin:
    if autologin == null then
      (
        { lib, ... }:
        {
          systemd.services.greetd.wantedBy = lib.mkForce [ ];
        }
      )
    else
      (
        { lib, ... }:
        {
          users.users.${autologin} = {
            isNormalUser = true;
            uid = 1000;
          };
          services.greetd.settings.initial_session = lib.mkForce {
            user = autologin;
            command = "/run/current-system/sw/bin/contract-greeter-session ${autologin} /home/${autologin}";
          };
        }
      );

  # The ssh-signing fixtures — the host's Tier-1 trust anchor (ADR-0011): a signer keypair built at
  # test-build time, with its PUBLIC key surfaced for `custom.greeter.trustedSigners`. Owned here so
  # the seat VMs that drive the signed-auth path (the bind-loop / examples-integration VMs, issue
  # #32) bind the same atom rather than each re-authoring the ssh-keygen dance.
  signer = pkgs.runCommand "seat-vm-signer" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -q -t ed25519 -N "" -C seat-vm-signer -f $out/key
  '';
  signerPub = lib.removeSuffix "\n" (builtins.readFile "${signer}/key.pub");
in
{
  inherit signer signerPub;

  # The seat-VM harness: given a record of what a greeter-family VM VARIES — its name, whether it
  # needs a graphical (virtio-gpu) boot, whether greetd autologs a user into the session launcher,
  # the seat module it binds (desktops + defaultDesktop + any per-VM knobs), and its testScript —
  # assemble the full `runNixOSTest`. Owns the boot base + greeter-seat preamble + greetd wiring, so
  # each caller declares only its variation.
  mkSeatVM =
    {
      name,
      testScript,
      graphical ? false,
      autologin ? null,
      seat ? { },
    }:
    pkgs.testers.runNixOSTest (
      {
        inherit name testScript;

        # The contract umbrella imports insecure-packages.nix (writes nixpkgs.config), which conflicts
        # with the driver's default read-only nixpkgs, so let the node own its pkgs as a real host does.
        node.pkgsReadOnly = false;

        nodes.machine = {
          imports = [
            contractModule
            greeterModule
            bootBase
            (greetdWiring autologin)
            seat
          ]
          ++ lib.optional graphical graphicalBase;
        };
      }
      # A live compositor is software-rendered on virtio-gpu; OCR off (we assert artifacts/markers).
      // lib.optionalAttrs graphical { enableOCR = false; }
    );

  # The test's stand-in for what `homeBuilder` returns: a home-activation package shaped like a
  # home-manager one ($out/activate) that writes a marker into the user's home on activation.
  activationStub = pkgs.runCommand "home-activation-stub" { } ''
    mkdir -p $out
    cat > $out/activate <<'SH'
    #!/bin/sh
    set -e
    mkdir -p "$HOME"
    echo "stub home-manager activation for $USER" > "$HOME/.contract-home-activated"
    SH
    chmod +x $out/activate
  '';
}
