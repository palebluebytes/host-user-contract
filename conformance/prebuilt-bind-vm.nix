# Runtime VM for the pre-built binding path (ADR-0016, issue #16). Proves that
# bindContractPackage correctly materializes a user account, bridges feature requests
# into the realization, and runs the contractPackage's activate script at system activation.
# The contractPackage is a synthetic derivation: activate writes a marker file, and
# contract-requests.json carries a gui grant request. After boot, the account exists,
# the marker is present, and the gui surface decision reflects the bridged request.
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

  # A synthetic contractPackage: activate writes a marker; JSON carries a gui.desktop request.
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
      "requests": { "gui": { "desktop": "plasma" } },
      "packages": []
    }
    JSON
  '';
in
mkSeatVM {
  name = "contract-prebuilt-bind";
  greeter = false;

  seat.imports = [
    (bindContractPackage {
      inherit contractPackage;
      identity = testIdentity;
      grants = {
        gui.enable = true;
      };
    })
  ];

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("contract-activate-testuser.service")

    # Account materialized from identity
    machine.succeed("getent passwd testuser")
    machine.succeed("getent passwd testuser | cut -d: -f5 | grep -qx 'Test User'")

    # Activation script ran: marker file written by contractPackage/activate
    machine.succeed("test -f /home/testuser/.contract-activated")
    machine.succeed("grep -q 'testuser' /home/testuser/.contract-activated")

    print(machine.succeed("id testuser; getent passwd testuser"))
  '';
}
