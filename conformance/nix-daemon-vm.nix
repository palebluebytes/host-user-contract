# Runtime VM for the nix-daemon feature (ADR-0017, issue #15). Proves the grant/deny
# divide at runtime: a user granted nix-daemon is in nix-users and can talk to the
# daemon; a user denied it cannot. The host wires nix.settings.allowed-users = ["@nix-users"]
# — the daemon refuses connections from non-members. The runtime clamp is also proven:
# a user afforded no nix-daemon does not
# end up in the group (the realization drops it, as with all privileged groups).
#
# A build-time-binding seat (greeter off, CONTEXT.md): it binds users declaratively via `contract.users`
# and asserts the realization, so ./seat-vm.nix's `greeter = false` boot base is all it needs.
{
  pkgs,
  contractModule,
  system,
}:
let
  inherit
    (import ./seat-vm.nix {
      inherit pkgs system contractModule;
    })
    mkSeatVM
    ;
in
mkSeatVM {
  name = "contract-nix-daemon";
  greeter = false;

  seat = {
    # alice: granted nix-daemon → in nix-users → can use the daemon.
    contract.users.alice = {
      identity = {
        name = "Alice";
        email = "alice@example.invalid";
        username = "alice";
      };
      granted.nix-daemon = true;
    };

    # bob: no grant → not in nix-users → daemon-restricted.
    contract.users.bob = {
      identity = {
        name = "Bob";
        email = "bob@example.invalid";
        username = "bob";
      };
    };

    # carol: afforded nothing, so she is daemon-restricted. She cannot put herself in `nix-users`
    # either — an identity names no groups at all.
    contract.users.carol = {
      identity = {
        name = "Carol";
        email = "carol@example.invalid";
        username = "carol";
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

    # alice can reach the nix daemon: nix-store --add sends a request to the daemon; if
    # allowed, it returns a store path (exit 0). /nix/store itself is not a valid store path
    # for query commands, so we use --add on a temp file — the daemon must process it.
    machine.succeed("echo nix-daemon-alice-probe > /tmp/nixtest")
    machine.succeed("su -s /bin/sh -c 'nix-store --add /tmp/nixtest' alice")

    # bob cannot reach the daemon — nix-store --add is refused (exit non-zero)
    machine.fail("su -s /bin/sh -c 'nix-store --add /tmp/nixtest' bob")

    print(machine.succeed("id alice; id bob; id carol"))
  '';
}
