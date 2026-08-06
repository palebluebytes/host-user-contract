# Greeter path END-TO-END with a REAL home (ADR-0006, issue #2), fleet edition — the runtime half
# of the uniform flake-output consumption convention. The declarative binds (hosts/*.nix) consume
# each user's `<u>-contractPackage` at EVAL; here a booted seat consumes a SIBLING output of the same
# user (ada's `-greeter` home, built from the same user with the safe-set grant) at RUNTIME through
# the greeter, and observes her real home activate. Same user fleet, sibling outputs, two paths.
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

    # Runtime provision the REAL greeter-bound home from ada's greeter-home flake output: fully realize
    # the account from identity.json (shell-side realization, ADR-0012) and activate the actual
    # home-manager generation as that user.
    machine.succeed("contract-greeter-provision ${username} ${identityJson} ${homeActivation} tier1")
    machine.succeed("getent passwd ${username}")

    # The account is realized from the real identity (GECOS), not a stub.
    machine.succeed("getent passwd ${username} | cut -d: -f5 | grep -qi reference")

    # The real home-manager home actually activated: its profile is installed and the marker
    # dotfile the greeter-bound home carries is present in the new account's home.
    machine.succeed("test -e /home/${username}/.nix-profile")
    machine.succeed("test -f /home/${username}/.contract-home-active")
    machine.succeed("grep -q greeter-activated /home/${username}/.contract-home-active")
    machine.succeed("stat -c %U /home/${username}/.contract-home-active | grep -qx ${username}")

    # The desktop-choice helper (ADR-0013) auto-surfaced the home's contract.requests.gui.desktop to
    # ~/.contract-desktop, where the greeter's launcher reads it — no manual step. ada requests "plasma".
    machine.succeed("test -f /home/${username}/.contract-desktop")
    machine.succeed("grep -qx plasma /home/${username}/.contract-desktop")

    print(machine.succeed("ls -la /home/${username}"))
  '';
}
