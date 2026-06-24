# Runtime VM for the greeter's provisioning CRUX + session selection (ADR-0026/0028, issue #2).
# The one part of the runtime path that needs a booted machine rather than a pure eval: the
# eval-free auth ordering and the safe-set bind are proven headless in ./default.nix; what only a
# real host can show is RUNTIME provisioning — materializing an account and realizing it OUTSIDE
# NixOS's declarative build-time model.
#
# It boots ONE seat host with `nixosModules.greeter` enabled and drives the privileged helpers
# directly against a synthetic identity.json. It asserts that `provision` is the shell-side
# `realization.nix` (ADR-0028): the account is fully realized — password (so PAM works), GECOS,
# authorizedKeys, the user's SAFE declared groups, the greeter-seat baseline groups — with the
# privileged-group CLAMP reproduced at runtime (a hostile `docker` in identity.json is dropped).
# It then proves session SELECTION (ADR-0026 step 8): the launcher picks the seat-default type, a
# home override flips it, and each execs the host-bound backend. Building a real home needs
# home-manager (the contract has none, ADR-0020), so the home here is a stub activation package —
# the real-home end-to-end lives in examples/user (the consumer-renders boundary, like gui-union).
{
  pkgs,
  contractModule,
  greeterModule,
  system,
}:
let
  # A synthetic external identity (the inert data the eval-free auth reads). hashedPassword is the
  # sha512-crypt of "correct-horse-battery-staple"; extraGroups carries one safe group (audio) and
  # one privileged group (docker) so the runtime clamp is observable.
  passwordHash = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
  identityJson = pkgs.writeText "identity.json" (
    builtins.toJSON {
      name = "Example User";
      email = "example@user.invalid";
      username = "example";
      hashedPassword = passwordHash;
      sshKey = "ssh-ed25519 AAAAexamplekey example@user.invalid";
      trustedKeys = [ "ssh-ed25519 AAAAtrustedkey trusted@elsewhere" ];
      extraGroups = [
        "audio"
        "docker"
      ];
    }
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

      # Enable the reference greeter. Offer two desktops as marker commands so per-user desktop
      # SELECTION is observable, with `plasma` the seat default. Drive the helpers directly, so keep
      # boot lean by not pulling the interactive greetd login in (as gui-union does for its DM).
      custom.greeter.enable = true;
      custom.greeter.desktops.gnome = {
        type = "wayland";
        command = "echo gnome > /tmp/desktop-launched";
      };
      custom.greeter.desktops.plasma = {
        type = "wayland";
        command = "echo plasma > /tmp/desktop-launched";
      };
      custom.greeter.defaultDesktop = "plasma";
      systemd.services.greetd.wantedBy = lib.mkForce [ ];

      # `docker` must EXIST for the clamp test to be meaningful (so "not in docker" proves the
      # clamp dropped it, not that the group was merely absent). audio already exists by default.
      users.groups.docker = { };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The enabled greeter ships the privileged helpers.
    machine.succeed("command -v contract-greeter-provision contract-greeter-session")

    # The external user does NOT exist at build time — NixOS users are declarative.
    machine.fail("getent passwd example")

    # RUNTIME provision: the shell-side realization (ADR-0028).
    machine.succeed("contract-greeter-provision example ${identityJson} ${activationStub} tier1")
    machine.succeed("getent passwd example")

    # Account fully realized from identity.json + the safe-set grant:
    # - GECOS = name
    machine.succeed("getent passwd example | cut -d: -f5 | grep -qx 'Example User'")
    # - password = identity.hashedPassword (so PAM works — not a locked '!' entry)
    machine.succeed("test \"$(getent shadow example | cut -d: -f2)\" = '${passwordHash}'")
    # - authorizedKeys = sshKey + trustedKeys
    machine.succeed("grep -q AAAAexamplekey /home/example/.ssh/authorized_keys")
    machine.succeed("grep -q AAAAtrustedkey /home/example/.ssh/authorized_keys")
    # - safe declared group conferred; greeter-seat baseline groups enrolled
    machine.succeed("id -nG example | tr ' ' '\\n' | grep -qx audio")
    machine.succeed("id -nG example | tr ' ' '\\n' | grep -qx greeter-users")
    machine.succeed("id -nG example | tr ' ' '\\n' | grep -qx uinput")
    # - the CLAMP: a privileged group declared in identity.json is dropped at runtime
    machine.fail("id -nG example | tr ' ' '\\n' | grep -qx docker")
    # - the home activated AS the user
    machine.succeed("test -f /home/example/.contract-home-activated")

    # Per-user desktop SELECTION (ADR-0029): no home choice ⇒ the seat default (plasma) launches.
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")
    # The user's home chooses gnome ⇒ gnome launches instead.
    machine.succeed("echo gnome > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx gnome /tmp/desktop-launched")
    # A desktop the seat does NOT offer degrades to the default, never breaks the login (ADR-0029).
    machine.succeed("echo hyprland > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")

    # Tier 2 (ephemeral) provisioning is designed-for but DEFERRED — the helper refuses it.
    machine.fail("contract-greeter-provision someone-else ${identityJson} ${activationStub} tier2")

    print(machine.succeed("id example; getent passwd example"))
  '';
}
