# Runtime VM smoke for the greeter's PROVISIONING crux (ADR-0022, issue #2, slice 3) — the one
# part of the runtime path that genuinely needs a booted machine rather than a pure eval. The
# eval-free auth ordering and the safe-set bind are proven headless in ./default.nix (the auth
# script is even EXECUTED there); what only a real host can show is the genuinely-novel step:
# materializing a user account and ACTIVATING a built home at RUNTIME, outside NixOS's
# declarative build-time user model.
#
# It boots ONE seat host with `nixosModules.greeter` enabled, then drives the privileged
# `contract-greeter-provision` helper directly — binding the EXAMPLE user repo (its username
# read from examples/user/identity.json, so this replicates the external user the greeter would
# fetch). Like the gui-union VM supplies its own SDDM/Plasma to render the gui DECISION, this
# test supplies its own stand-in home-ACTIVATION package (what the host's `homeBuilder` binding
# would produce) — building a real home-manager activation package needs home-manager, which the
# contract does not depend on (ADR-0020), the same boundary bindUserModule draws against hmStub.
#
# What the VM proves that eval cannot: the helper creates a (Tier-1, persisted) account that did
# NOT exist at build time, runs the home activation AS that user, and refuses Tier-2 (ephemeral,
# deferred). That is the declarative-contract → runtime-login bridge ADR-0022 calls the crux.
{
  pkgs,
  contractModule,
  greeterModule,
  system,
}:
let
  # The external user the greeter binds — its identity read from the example repo, exactly the
  # data the eval-free auth step reads with jq before any Nix runs.
  exampleUser = (builtins.fromJSON (builtins.readFile ../examples/user/identity.json)).username;

  # The test's stand-in for what `homeBuilder` returns: a home-ACTIVATION package shaped like a
  # home-manager one ($out/activate), which on activation writes a marker into the user's home.
  # The contract is home-manager-agnostic (it binds + grants; the host builds the home), so the
  # suite supplies the rendering — the same role SDDM/Plasma play in the gui-union VM.
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
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-provision";

  # The contract umbrella imports insecure-packages.nix (writes nixpkgs.config), which conflicts
  # with the driver's default read-only nixpkgs, so let the node own its pkgs as a real host does.
  node.pkgsReadOnly = false;

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

      # Enable the reference greeter: this puts the bind/auth/provision scripts on PATH and fixes
      # the runtime grant to the safe set. We drive the provisioning helper directly, so keep the
      # boot lean by not pulling the interactive greetd login in at boot (it would just wait on a
      # tty for a flake URL) — the same lean-boot move the gui-union VM makes for its DM.
      custom.greeter.enable = true;
      systemd.services.greetd.wantedBy = lib.mkForce [ ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The enabled greeter ships the privileged provisioning helper.
    machine.succeed("command -v contract-greeter-provision")

    # The external user does NOT exist at build time — NixOS users are declarative.
    machine.fail("getent passwd ${exampleUser}")

    # The crux: at RUNTIME the helper materializes the (Tier-1, persisted) account and activates
    # the built home AS that user — the declarative-contract → runtime-login bridge.
    machine.succeed("contract-greeter-provision ${exampleUser} ${activationStub} tier1")
    machine.succeed("getent passwd ${exampleUser}")
    machine.succeed("test -f /home/${exampleUser}/.contract-home-activated")
    machine.succeed("stat -c %U /home/${exampleUser}/.contract-home-activated | grep -qx ${exampleUser}")

    # Tier 2 (untrusted, ephemeral) provisioning is designed-for but DEFERRED — the helper
    # refuses it rather than pretending to provide it (ADR-0022).
    machine.fail("contract-greeter-provision someone-else ${activationStub} tier2")

    print(machine.succeed("getent passwd ${exampleUser}"))
  '';
}
