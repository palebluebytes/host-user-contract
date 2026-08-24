# Shared conformance fixtures for the seat runtime VMs — the standing seat-host scaffolding seat
# tests otherwise re-author (each posture takes the subset it needs): the bootable base every seat
# shares (hostPlatform + no-bootloader + tmpfs root + stateVersion), the greeter-seat preamble +
# greetd wiring (greeter seats), a shared synthetic identity (build-time-binding seats), plus the
# activation stub and the ssh-signing fixtures. It plays the role ./toolkit.nix plays for the eval
# side: each seat VM file becomes a focused record of what it VARIES — the users/grants, the binding,
# the assertion — handed to `mkSeatVM`. Built per-VM in ./flake.nix (no host repo, no host bindings,
# ADR-0002).
#
# It has one consumer OUTSIDE this directory — the reference host fleet's end-to-end greeter test —
# which reaches it as the `testing.mkSeatHarness` flake output, published through ./testing.nix
# (ADR-0022). So the file may move freely, but what it RETURNS is a shipped surface: renaming an
# attribute below is a change to the contract's testing surface, not a refactor of the suite.
#
# Two binding-mode postures (CONTEXT.md) share the boot base: the RUNTIME-binding seats — the GREETER
# seats (greeter-provision / -session / -sequence / -desktop / -bind-loop and the fleet integration
# VM) — add the greeter preamble; the BUILD-TIME-binding seats (prebuilt-bind / daemon-restricted /
# nix-daemon / gui-surface) keep the greeter off and bind their realization at build time. `greeter ?
# true` selects between them, so `greeterModule` is required only by the greeter callers (asserted in
# mkSeatVM).
{
  pkgs,
  system,
  contractModule,
  greeterModule ? null,
}:
let
  lib = pkgs.lib;

  # The bootable base every seat host shares (config-only so it composes in an `imports` list): no
  # bootloader, a tmpfs root, a pinned stateVersion. The contract umbrella is imported by mkSeatVM
  # alongside it; the greeter preamble below is layered on only for greeter seats.
  bootBase = {
    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = system;
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
  };

  # The greeter-seat preamble: enable the reference runtime greeter (ADR-0017). Layered on top of the
  # boot base for greeter seats only; mkSeatVM imports greeterModule alongside it.
  greeterPreamble = {
    contract.greeter.enable = true;
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

  # A shared synthetic identity — the inert public data (name/email/username/sshKey) a plain-bind seat
  # materializes an account from. Owned here so the prebuilt-bind / daemon-restricted VMs bind the
  # same atom rather than re-authoring identical `testIdentity` blocks.
  testIdentity = {
    name = "Test User";
    email = "test@example.invalid";
    username = "testuser";
    sshKey = "ssh-ed25519 AAAAtestkey testuser@example";
  };

  # The ssh-signing fixtures — the host's Tier-1 trust anchor (ADR-0019): a signer keypair built at
  # test-build time, with its PUBLIC key surfaced for `contract.greeter.trustedSigners`. Owned here so
  # the seat VMs that drive the signed-auth path (the bind-loop / examples-integration VMs, issue
  # #32) bind the same atom rather than each re-authoring the ssh-keygen dance.
  signer = pkgs.runCommand "seat-vm-signer" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -q -t ed25519 -N "" -C seat-vm-signer -f $out/key
  '';
  signerPub = lib.removeSuffix "\n" (builtins.readFile "${signer}/key.pub");
in
{
  inherit signer signerPub testIdentity;

  # The seat-VM harness: given a record of what a seat VM VARIES — its name, whether it enables the
  # reference greeter, whether it needs a graphical (virtio-gpu) boot, whether greetd autologs a user
  # into the session launcher, the seat module it binds (users/grants/desktops + any per-VM knobs),
  # and its testScript — assemble the full `runNixOSTest`. Owns the boot base + (for greeter seats)
  # the greeter preamble + greetd wiring, so each caller declares only its variation.
  mkSeatVM =
    {
      name,
      testScript,
      greeter ? true,
      graphical ? false,
      autologin ? null,
      seat ? { },
      # WHAT THIS MACHINE CAN RUN. Defaults to a seat with a display, because that is what this
      # harness builds — and because it is now the thing that decides whether a greeter offers a
      # walk-up user a graphical session at all. A VM that models a headless box passes `[ ]`.
      modes ? [ "gui" ],
    }:
    # A greeter seat must be handed the greeter module; otherwise `null` would splice into the
    # imports list below and fail with a cryptic module-eval error instead of naming the contract.
    assert lib.assertMsg (greeter -> greeterModule != null)
      "mkSeatVM: `greeter = true` requires a `greeterModule` — hand `nixosModules.greeter` to the seat harness";
    pkgs.testers.runNixOSTest (
      {
        inherit name testScript;

        # The contract umbrella imports insecure-packages.nix (writes nixpkgs.config), which conflicts
        # with the driver's default read-only nixpkgs, so let the node own its pkgs as a real host does.
        node.pkgsReadOnly = false;

        nodes.machine = {
          contract.modes = modes;

          imports = [
            contractModule
            bootBase
          ]
          ++ lib.optionals greeter [
            greeterModule
            greeterPreamble
            (greetdWiring autologin)
          ]
          ++ [ seat ]
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
