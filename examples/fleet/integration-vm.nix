# Greeter path END-TO-END with a REAL home (ADR-0006, issue #2), fleet edition — the runtime half
# of the uniform flake-output consumption convention. The declarative binds (hosts/*.nix) consume
# each user's `<u>-contractPackage` at EVAL; here a booted seat consumes the SAME user's ordinary
# published home (`homes.<system>.ada.gui`) at RUNTIME through the greeter, and observes it
# activate. Same user fleet, sibling outputs, two paths — and, since ADR-0032, the same home: a
# greeter binds what a declarative host binds, because no grant can make a home differ.
#
# It lives here, in the fleet flake that legitimately has home-manager (via the users input), for
# the reason the contract's own suite cannot host it: building a real home needs home-manager, and
# the contract depends only on nixpkgs `lib` (ADR-0004). It is a FOCUSED seat node (like the
# contract's greeter-provision-vm), not the full desk host config — so the runtime-provisioned account
# never collides with a declarative one, and the boot stays lean.
#
# It runs on the contract's own mkSeatVM harness (passed in from ./flake.nix, reached through the
# `contract` flake input): the helpers-driven posture (greetd off the console, we drive `provision`
# by hand), so this file declares only what it VARIES — the real home's closure pinned onto the seat
# and the runtime provisioning assertion.
{
  mkSeatVM,
  homeActivation,
  identityJson,
  username,
}:
mkSeatVM {
  name = "reference-fleet-integration";

  # Drive the provisioning helper by hand, so keep greetd off the console at boot (the same
  # helpers-driven posture the contract's greeter tests take).
  autologin = null;

  seat = {
    # The real home's closure must be on the VM. It is referenced from the testScript (an
    # interpolated store path), which the driver copies in, but pull it into the system closure
    # explicitly so the build dependency is unambiguous.
    environment.etc."reference-fleet-home".source = homeActivation;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The roaming user does not exist at build time — this seat never declared ${username}.
    machine.fail("getent passwd ${username}")

    # Runtime provision the REAL home from ada's published `homes` output: fully realize the
    # account from identity.json (shell-side realization, ADR-0012) and activate the actual
    # home-manager generation as that user.
    machine.succeed("contract-greeter-provision ${username} ${identityJson} ${homeActivation} tier1")
    machine.succeed("getent passwd ${username}")

    # The account is realized from the real identity (GECOS), not a stub.
    machine.succeed("getent passwd ${username} | cut -d: -f5 | grep -qi reference")

    # The real home-manager home actually activated: its profile is installed.
    machine.succeed("test -e /home/${username}/.nix-profile")

    # …and the home's OWN content landed, owned by the new account. The desktop-choice helper
    # The producer wrote the gui mode's own `desktop` parameter to ~/.contract-desktop, where the
    # greeter's launcher reads it — no manual step, and no marker module grafted onto the user to
    # make this observable: the dotfile comes from ada's own voice. It is also the proof that the
    # helper is composed by DEFAULT now (ADR-0032), since nothing here opts into it. ada requests
    # "plasma".
    machine.succeed("test -f /home/${username}/.contract-desktop")
    machine.succeed("grep -qx plasma /home/${username}/.contract-desktop")
    machine.succeed("stat -c %U /home/${username}/.contract-desktop | grep -qx ${username}")

    print(machine.succeed("ls -la /home/${username}"))
  '';
}
