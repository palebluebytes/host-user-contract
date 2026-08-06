# Runtime VM for the greeter's provisioning CRUX + session selection (ADR-0010/0012, issue #2).
# The one part of the runtime path that needs a booted machine rather than a pure eval: the
# eval-free auth ordering and the safe-set bind are proven headless in ./default.nix; what only a
# real host can show is RUNTIME provisioning — materializing an account and realizing it OUTSIDE
# NixOS's declarative build-time model.
#
# It boots ONE seat host with `nixosModules.greeter` enabled (via ./seat-vm.nix's helpers-driven
# posture, greetd kept off the console) and drives the privileged helpers directly against a synthetic
# identity.json. It asserts that `provision` is the runtime adapter over the shared `accountPlan`
# (ADR-0012, issue #31): the account it realizes at runtime — password (so PAM works), GECOS,
# authorizedKeys, the clamped declared groups + the greeter-seat baseline — reproduces, FIELD FOR
# FIELD, the BUILD-TIME account the same `accountPlan` renders for this identity. The privileged-group
# CLAMP is thus proven from the ONE shared plan (a hostile `docker` in identity.json is dropped), and
# build↔runtime parity is proven by construction, not by parallel hand-checks. It then proves session SELECTION
# (ADR-0010 step 8): the launcher picks the seat-default type, a home override flips it, and each
# execs the host-bound backend. Building a real home needs home-manager (the contract has none,
# ADR-0004), so the home here is the harness's stub activation package — the real-home end-to-end
# lives in examples/fleet (the consumer-renders boundary, like gui-union).
{
  pkgs,
  contractModule,
  greeterModule,
  accountPlan,
  greeterGrants,
  system,
}:
let
  inherit (pkgs) lib;
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
  identityAttrs = {
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
  };
  identityJson = pkgs.writeText "identity.json" (builtins.toJSON identityAttrs);

  # The BUILD-TIME account for the SAME identity + the safe-set grant, rendered from the ONE shared
  # accountPlan the build-time realization.nix also renders (ADR-0012, issue #31). The runtime
  # `provision` is a second adapter over this exact plan, so its realized account must reproduce it
  # field-for-field — that is the build↔runtime parity this VM proves, from the shared plan rather
  # than by parallel hand-checks. `provision` adds the greeter-seat marker (`greeter-users`) on top
  # of the plan's groups (the standing baseline it enrolls into), so the expected supplementary
  # group set is the plan's `extraGroups` ∪ that marker.
  buildTimePlan = accountPlan {
    identity = identityAttrs;
    grants = greeterGrants;
  };
  expectedGroups = lib.sort (a: b: a < b) (
    lib.unique (buildTimePlan.extraGroups ++ [ "greeter-users" ])
  );
  expectedGroupsCsv = lib.concatStringsSep "," expectedGroups;
  # The authorized_keys `provision` must write, one key per line (jq -r's trailing newline included) —
  # as a store file so the exact-and-in-order comparison needs no multi-line Python string literal.
  expectedKeysFile = pkgs.writeText "expected-authorized-keys" (
    lib.concatMapStrings (k: "${k}\n") buildTimePlan.authorizedKeys
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

    # Account fully realized from identity.json + the safe-set grant, and — the issue #31 claim —
    # realized IDENTICALLY to the build-time account the shared accountPlan renders for this identity
    # (ADR-0012 build↔runtime parity), field for field:
    # - GECOS = the plan's description
    machine.succeed("getent passwd example | cut -d: -f5 | grep -qx '${buildTimePlan.description}'")
    # - password = the plan's hashedPassword (so PAM works — not a locked '!' entry)
    machine.succeed("test \"$(getent shadow example | cut -d: -f2)\" = '${buildTimePlan.hashedPassword}'")
    # - authorizedKeys = the plan's keys (primary sshKey + trustedKeys), exactly and in order
    machine.succeed("diff ${expectedKeysFile} /home/example/.ssh/authorized_keys")
    # - the CLAMP: a privileged group declared in identity.json is dropped at runtime
    machine.fail("id -nG example | tr ' ' '\\n' | grep -qx docker")
    # - EXACT group parity: the realized supplementary groups (all but the user's own primary group)
    #   equal the plan's clamped+granted groups ∪ the greeter-seat marker — no group missing, none
    #   extra. This is the runtime clamp AND the build↔runtime parity, proven from the shared plan.
    machine.succeed(
        "test \"$(id -nG example | tr ' ' '\\n' | grep -vx example | sort | paste -sd, -)\""
        " = ${lib.escapeShellArg expectedGroupsCsv}"
    )
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
