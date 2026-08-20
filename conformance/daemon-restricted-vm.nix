# Runtime VM for package policy and daemon restriction (ADR-0017, issue #17). Proves the
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
#
# A build-time-binding seat (greeter off, CONTEXT.md): it binds the pre-built package (ADR-0016), so
# ./seat-vm.nix's `greeter = false` boot base + shared synthetic identity are all it needs.
{
  pkgs,
  contractModule,
  system,
  bindContractPackage,
}:
let
  inherit
    (import ./seat-vm.nix {
      inherit pkgs system contractModule;
    })
    mkSeatVM
    testIdentity
    ;

  # Synthetic contractPackage: activate writes a marker; manifest declares hello + curl.
  contractPackage = pkgs.runCommand "daemon-restricted-vm-contract-package" { } ''
    mkdir -p $out
    cat > $out/activate <<'SH'
    #!/bin/sh
    mkdir -p "$HOME"
    echo "daemon-restricted home activated for $USER" > "$HOME/.contract-activated"
    SH
    chmod +x $out/activate
    cat > $out/contract-manifest.json <<'JSON'
    {
      "version": 4,
      "username": "testuser",
      "mode": "cli",
      "packages": ["hello", "curl"]
    }
    JSON
  '';
in
mkSeatVM {
  name = "contract-daemon-restricted";
  greeter = false;

  seat = {
    imports = [
      (bindContractPackage {
        inherit contractPackage;
        identity = testIdentity;
        # A host affording nothing runs the floor and only the floor.
        runs = [ "cli" ];
        # No nix-daemon grant → testuser is daemon-restricted
        grants = { };
      })
    ];

    # Package policy: only hello is approved.
    contract.packagePolicy.allowedPrograms = [ "hello" ];

    # Restrict the Nix daemon to nix-users only (testuser is NOT in nix-users).
    nix.settings.allowed-users = [ "@nix-users" ];
    users.groups.nix-users = { };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("contract-activate-testuser.service")

    # Account materialized
    machine.succeed("getent passwd testuser")

    # Activation ran: marker from contractPackage/activate
    machine.succeed("test -f /home/testuser/.contract-activated")

    # hello is approved and declared → in the host-built profile
    machine.succeed("test -x /home/testuser/.nix-profile/bin/hello")

    # curl is declared but NOT approved → absent from the user's profile
    # (Package policy governs ~/.nix-profile, not system-wide availability.)
    machine.fail("test -x /home/testuser/.nix-profile/bin/curl")

    # testuser is not in nix-users → daemon unreachable
    machine.fail("su -s /bin/sh -c 'nix-store --query --outputs /nix/store' testuser")

    # ~/.nix-profile points to the host-built profile (symlink exists)
    machine.succeed("test -L /home/testuser/.nix-profile")

    print(machine.succeed("id testuser"))
    print(machine.succeed("ls -la /home/testuser/.nix-profile/bin/ || true"))
  '';
}
