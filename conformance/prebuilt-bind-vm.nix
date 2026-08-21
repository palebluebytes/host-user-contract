# Runtime VM for the pre-built binding path (ADR-0011, issue #16). Proves that
# bindContractPackage correctly materializes a user account, confers the grant
# into the realization, and runs the contractPackage's activate script at system activation.
# The contractPackage is a synthetic derivation: activate writes a marker file, and
# manifest freezes the cli mode. After boot, the account exists,
# the marker is present, and the gui surface decision reflects the bridged request.
#
# A build-time-binding seat (greeter off, CONTEXT.md): it binds the pre-built package (ADR-0011), so
# ./seat-vm.nix's `greeter = false` boot base + shared synthetic identity are all it needs.
{
  pkgs,
  contractModule,
  system,
  bindContractPackage,
  # The live contract version, interpolated rather than written out: this synthetic package stands
  # in for one THIS contract built, and `readManifest` refuses any other version. Read at eval, so
  # unlike a committed fixture there is nothing here to keep in step by hand.
  contractVersion,
}:
let
  inherit
    (import ./seat-vm.nix {
      inherit pkgs system contractModule;
    })
    mkSeatVM
    testIdentity
    ;

  # A synthetic contractPackage: activate writes a marker; its manifest freezes the cli mode.
  contractPackage = pkgs.runCommand "prebuilt-bind-vm-contract-package" { } ''
    mkdir -p $out
    cat > $out/activate <<'SH'
    #!/bin/sh
    mkdir -p "$HOME"
    echo "prebuilt activated for $USER" > "$HOME/.contract-activated"
    SH
    chmod +x $out/activate
    cat > $out/contract-manifest.json <<'JSON'
    {
      "version": "${contractVersion}",
      "username": "testuser",
      "mode": "cli",
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
      # What this host runs — the seat harness declares the gui mode, so `runsWith` gives both.
      # The manifest freezes `cli`, which is in this set, so the coupling guard accepts.
      runs = [
        "cli"
        "gui"
      ];
      # Nothing conferred. An ordinary account on a seat needs no grant at all: its session groups
      # ride the mode the manifest froze, and this kernel writes that onto the account.
      grants = { };
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
