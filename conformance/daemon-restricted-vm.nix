# Runtime VM for package policy and daemon restriction (ADR-0033, issue #17). Proves the
# full #17 guarantee: a daemon-restricted user (nix-daemon denied) whose contractPackage
# declares hello + curl, with allowedPrograms = ["hello"], ends up with:
#   - hello available in PATH (approved + declared)
#   - curl absent from PATH (declared but not approved)
#   - nix daemon unreachable (no daemon access)
#   - home config deployed (activate ran, dotfiles present)
#
# The contractPackage is a synthetic derivation: activate writes a marker and the JSON
# manifest declares ["hello", "curl"]. The host sets allowedPrograms = ["hello"], so
# bindContractPackage builds a profile with only pkgs.hello and links it to ~/.nix-profile.
{
  pkgs,
  contractModule,
  system,
  bindContractPackage,
}:
let
  # Synthetic contractPackage: activate writes a marker; manifest declares hello + curl.
  contractPackage = pkgs.runCommand "daemon-restricted-vm-contract-package" { } ''
    mkdir -p $out
    cat > $out/activate <<'SH'
    #!/bin/sh
    mkdir -p "$HOME"
    echo "daemon-restricted home activated for $USER" > "$HOME/.contract-activated"
    SH
    chmod +x $out/activate
    cat > $out/contract-requests.json <<'JSON'
    {
      "version": 1,
      "username": "testuser",
      "requests": { "gui": { "session": "x11", "desktop": "" } },
      "packages": ["hello", "curl"]
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
  name = "contract-daemon-restricted";
  node.pkgsReadOnly = false;

  nodes.machine =
    { ... }:
    {
      imports = [
        contractModule
        (bindContractPackage {
          inherit contractPackage;
          identity = testIdentity;
          # No nix-daemon grant → testuser is daemon-restricted
          grants = { };
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

      # Package policy: only hello is approved.
      custom.host.packagePolicy.allowedPrograms = [ "hello" ];

      # Restrict the Nix daemon to nix-users only (testuser is NOT in nix-users).
      nix.settings.allowed-users = [ "@nix-users" ];
      users.groups.nix-users = { };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Account materialized
    machine.succeed("getent passwd testuser")

    # Activation ran: marker from contractPackage/activate
    machine.succeed("test -f /home/testuser/.contract-activated")

    # hello is approved and declared → in the host-built profile → on PATH
    machine.succeed("su -s /bin/sh -c 'hello' testuser")

    # curl is declared but NOT approved → absent from PATH
    machine.fail("su -s /bin/sh -c 'curl --version' testuser")

    # testuser is not in nix-users → daemon unreachable
    machine.fail("su -s /bin/sh -c 'nix-store --query --outputs /nix/store' testuser")

    # ~/.nix-profile points to the host-built profile (symlink exists)
    machine.succeed("test -L /home/testuser/.nix-profile")

    print(machine.succeed("id testuser"))
    print(machine.succeed("ls -la /home/testuser/.nix-profile/bin/ || true"))
  '';
}
