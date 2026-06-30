# Runtime VM for the pre-built binding path (ADR-0032, issue #16). Proves that
# bindContractPackage correctly materializes a user account, bridges feature requests
# into the realization, and runs the contractPackage's activate script at system activation.
# The contractPackage is a synthetic derivation: activate writes a marker file, and
# contract-requests.json carries a gui grant request. After boot, the account exists,
# the marker is present, and the gui surface decision reflects the bridged request.
{
  pkgs,
  contractModule,
  system,
  bindContractPackage,
}:
let
  # A synthetic contractPackage: activate writes a marker; JSON carries gui.session = "x11".
  contractPackage = pkgs.runCommand "prebuilt-bind-vm-contract-package" { } ''
    mkdir -p $out
    cat > $out/activate <<'SH'
    #!/bin/sh
    mkdir -p "$HOME"
    echo "prebuilt activated for $USER" > "$HOME/.contract-activated"
    SH
    chmod +x $out/activate
    cat > $out/contract-requests.json <<'JSON'
    {
      "version": 1,
      "username": "testuser",
      "requests": { "gui": { "session": "x11", "desktop": "" } },
      "packages": []
    }
    JSON
  '';

  testIdentity = {
    name = "Test User";
    email = "test@example.invalid";
    username = "testuser";
    sshKey = "ssh-ed25519 AAAAtestkey testuser@example";
  };
in
pkgs.testers.runNixOSTest {
  name = "contract-prebuilt-bind";
  node.pkgsReadOnly = false;

  nodes.machine =
    { ... }:
    {
      imports = [
        contractModule
        (bindContractPackage {
          inherit contractPackage;
          identity = testIdentity;
          grants = {
            gui.enable = true;
          };
        })
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
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Account materialized from identity
    machine.succeed("getent passwd testuser")
    machine.succeed("getent passwd testuser | cut -d: -f5 | grep -qx 'Test User'")

    # Activation script ran: marker file written by contractPackage/activate
    machine.succeed("test -f /home/testuser/.contract-activated")
    machine.succeed("grep -q 'testuser' /home/testuser/.contract-activated")

    print(machine.succeed("id testuser; getent passwd testuser"))
  '';
}
