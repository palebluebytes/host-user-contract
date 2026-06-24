# Greeter path END-TO-END with a REAL home (issue #2) — the integration test the contract's own
# suite cannot host, because building a real home needs home-manager and the contract depends only
# on nixpkgs `lib` (ADR-0020). It lives in the example user flake, which legitimately has
# home-manager, exactly as a consuming host does: the contract DECIDES (bind + grant + provision
# mechanism), the consumer RENDERS (a real home-manager home) — the same split the gui-union VM
# draws by supplying its own SDDM/Plasma.
#
# Where the contract's `greeter-vm` proves `contract-greeter-provision` in isolation against a STUB
# activation package, this proves the genuine build→provision→activate the runtime greeter
# performs: a real greeter-bound home — built by home-manager THROUGH the contract, granted the safe
# set (greeterGrants) — is provisioned at RUNTIME onto a booted seat host, and its marker dotfile is
# observed in the freshly-materialized account's home. (The remaining truly-runtime step — building
# that home AT login from a fetched flake under restricted eval — stays deferred per ADR-0022; here
# the real home is built at test-build time and provisioned, which is the faithful, feasible
# end-to-end.)
{
  pkgs,
  system,
  contractModule,
  greeterModule,
  homeActivation,
  identityJson,
  username,
}:
pkgs.testers.runNixOSTest {
  name = "contract-greeter-provision-real-home";

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

      # Enable the reference greeter (puts the provisioning helper on PATH, fixes the grant to the
      # safe set). We drive the helper directly, so keep boot lean by not pulling the interactive
      # greetd login in at boot — the same move the gui-union and greeter-vm tests make.
      custom.greeter.enable = true;
      systemd.services.greetd.wantedBy = lib.mkForce [ ];

      # The real home's closure must be on the VM. It is referenced from the testScript (an
      # interpolated store path), which the driver copies in, but pull it into the system closure
      # explicitly so the build dependency is unambiguous.
      environment.etc."contract-example-home".source = homeActivation;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The external user does not exist at build time — NixOS users are declarative.
    machine.fail("getent passwd ${username}")

    # Runtime provision the REAL greeter-bound home: fully realize the account from identity.json
    # (shell-side realization.nix, ADR-0028) and activate the actual home-manager generation as
    # that user.
    machine.succeed("contract-greeter-provision ${username} ${identityJson} ${homeActivation} tier1")
    machine.succeed("getent passwd ${username}")

    # The account is realized from the real identity (GECOS), not a stub.
    machine.succeed("getent passwd ${username} | cut -d: -f5 | grep -qi example")

    # The real home-manager home actually activated: its profile is installed and the marker
    # dotfile the greeter-bound home carries is present in the new account's home.
    machine.succeed("test -e /home/${username}/.nix-profile")
    machine.succeed("test -f /home/${username}/.contract-home-active")
    machine.succeed("grep -q greeter-activated /home/${username}/.contract-home-active")
    machine.succeed("stat -c %U /home/${username}/.contract-home-active | grep -qx ${username}")

    print(machine.succeed("ls -la /home/${username}"))
  '';
}
