# Runtime VM for the greeter's provisioning CRUX + session selection (ADR-0010/0012, issue #2).
# The one part of the runtime path that needs a booted machine rather than a pure eval: the
# eval-free auth ordering and the safe-set bind are proven headless in ./default.nix; what only a
# real host can show is RUNTIME provisioning — materializing an account and realizing it OUTSIDE
# NixOS's declarative build-time model.
#
# It boots ONE seat host with `nixosModules.greeter` enabled (via ./seat-vm.nix's helpers-driven
# posture, greetd kept off the console) and drives the privileged helpers directly against a synthetic
# identity.json. It asserts that `provision` is the shell-side `realization.nix` (ADR-0012): the
# account is fully realized — password (so PAM works), GECOS, authorizedKeys, the user's SAFE
# declared groups, the greeter-seat baseline groups — with the privileged-group CLAMP reproduced at
# runtime (a hostile `docker` in identity.json is dropped). It then proves session SELECTION
# (ADR-0010 step 8): the launcher picks the seat-default type, a home override flips it, and each
# execs the host-bound backend. Building a real home needs home-manager (the contract has none,
# ADR-0004), so the home here is the harness's stub activation package — the real-home end-to-end
# lives in examples/fleet (the consumer-renders boundary, like gui-union).
{
  pkgs,
  contractModule,
  greeterModule,
  system,
}:
let
  seatVM = import ./seat-vm.nix {
    inherit
      pkgs
      system
      contractModule
      greeterModule
      ;
  };
  inherit (seatVM) mkSeatVM activationStub;

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
in
mkSeatVM {
  name = "contract-greeter-provision";

  # Offer two desktops as marker commands so per-user desktop SELECTION is observable, with `plasma`
  # the seat default. Each is self-contained (the seat owns the session type, ADR-0021) — here they
  # just record which desktop was selected. `docker` must EXIST for the clamp test to be meaningful
  # (so "not in docker" proves the clamp dropped it, not that the group was merely absent).
  seat = {
    custom.greeter.desktops.gnome.command = "echo gnome > /tmp/desktop-launched";
    custom.greeter.desktops.plasma.command = "echo plasma > /tmp/desktop-launched";
    custom.greeter.defaultDesktop = "plasma";
    users.groups.docker = { };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The enabled greeter ships the privileged helpers.
    machine.succeed("command -v contract-greeter-provision contract-greeter-session")

    # The external user does NOT exist at build time — NixOS users are declarative.
    machine.fail("getent passwd example")

    # RUNTIME provision: the shell-side realization (ADR-0012).
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

    # Per-user desktop SELECTION (ADR-0013): no home choice ⇒ the seat default (plasma) launches.
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")
    # The user's home chooses gnome ⇒ gnome launches instead.
    machine.succeed("echo gnome > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx gnome /tmp/desktop-launched")
    # A desktop the seat does NOT offer degrades to the default, never breaks the login (ADR-0013).
    machine.succeed("echo hyprland > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")

    # Tier 2 (ephemeral) provisioning is designed-for but DEFERRED — the helper refuses it.
    machine.fail("contract-greeter-provision someone-else ${identityJson} ${activationStub} tier2")

    print(machine.succeed("id example; getent passwd example"))
  '';
}
