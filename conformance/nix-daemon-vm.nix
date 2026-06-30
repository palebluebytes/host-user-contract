# Runtime VM for the nix-daemon feature (ADR-0033, issue #15). Proves the grant/deny
# divide at runtime: a user granted nix-daemon is in nix-users and can talk to the
# daemon; a user denied it cannot. The host wires nix.settings.allowed-users = ["@nix-users"]
# — the daemon refuses connections from non-members. The runtime clamp is also proven:
# a user who self-declares nix-users in identity.extraGroups without the grant does not
# end up in the group (the realization drops it, as with all privileged groups).
{
  pkgs,
  contractModule,
  system,
}:
pkgs.testers.runNixOSTest {
  name = "contract-nix-daemon";
  node.pkgsReadOnly = false;

  nodes.machine =
    { ... }:
    {
      imports = [ contractModule ];

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

      # alice: granted nix-daemon → in nix-users → can use the daemon.
      custom.users.alice = {
        identity = {
          name = "Alice";
          email = "alice@example.invalid";
          username = "alice";
        };
        granted.nix-daemon.enable = true;
      };

      # bob: no grant → not in nix-users → daemon-restricted.
      custom.users.bob = {
        identity = {
          name = "Bob";
          email = "bob@example.invalid";
          username = "bob";
        };
      };

      # carol: self-declares nix-users in identity.extraGroups → realization clamps it.
      custom.users.carol = {
        identity = {
          name = "Carol";
          email = "carol@example.invalid";
          username = "carol";
          extraGroups = [ "nix-users" ];
        };
      };

      # The host restricts the daemon to nix-users members.
      nix.settings.allowed-users = [ "@nix-users" ];
      # nix-users group must exist for the group check to be meaningful.
      users.groups.nix-users = { };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # alice was granted nix-daemon → realization put her in nix-users
    machine.succeed("id -nG alice | tr ' ' '\\n' | grep -qx nix-users")

    # bob was not granted → not in nix-users
    machine.fail("id -nG bob | tr ' ' '\\n' | grep -qx nix-users")

    # carol self-declared nix-users but the realization CLAMPED it (privileged group)
    machine.fail("id -nG carol | tr ' ' '\\n' | grep -qx nix-users")

    # alice can reach the nix daemon (nix-store query succeeds)
    machine.succeed("su -s /bin/sh -c 'nix-store --query --outputs /nix/store' alice 2>&1 | grep -v 'Access denied'")

    # bob cannot reach the daemon (nix-store is refused)
    machine.fail("su -s /bin/sh -c 'nix-store --query --outputs /nix/store' bob")

    print(machine.succeed("id alice; id bob; id carol"))
  '';
}
