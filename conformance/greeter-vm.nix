# Runtime VM for the greeter's provisioning CRUX + session selection (ADR-0018/0020, issue #2).
# The one part of the runtime path that needs a booted machine rather than a pure eval: the
# eval-free auth ordering and the safe-set bind are proven headless in ./default.nix; what only a
# real host can show is RUNTIME provisioning — materializing an account and realizing it OUTSIDE
# NixOS's declarative build-time model.
#
# It boots ONE seat host with `nixosModules.greeter` enabled (via ./seat-vm.nix's helpers-driven
# posture, greetd kept off the console) and drives the privileged helpers directly against a synthetic
# identity.json. `provision` no longer reproduces the account rule — it EVALUATES the shared
# `accountPlan` via `contract-account-plan` and renders the result (issue #31 follow-up). So this VM's
# job narrowed: it proves the shell RENDERER SURFACES that record onto a real account — password (so
# PAM works), GECOS, authorizedKeys, and groups — matching, FIELD FOR FIELD, the BUILD-TIME account
# the same `accountPlan` renders for this identity. The rule's OWN guarantees (the clamp, the
# empty-sshKey drop, key ordering) are proven WITHOUT a boot in ./account-plan.nix; here the observable
# clamp (a hostile `docker` dropped from the realized account) is the renderer surfacing that rule.
# It then proves session SELECTION
# (ADR-0021): the launcher picks the seat-default type, a home override flips it, and each
# execs the host-bound backend. Building a real home needs home-manager (the contract has none,
# ADR-0002), so the home here is the harness's stub activation package — the real-home end-to-end
# lives in examples/fleet (the consumer-renders boundary, like gui-union).
{
  pkgs,
  contractModule,
  greeterModule,
  accountPlan,
  greeterAffordances,
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
  # sha512-crypt of "correct-horse-battery-staple". It names NO groups — an identity cannot — so
  # every group the realized account ends up with came from the mode it was bound in.
  passwordHash = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
  identityAttrs = {
    name = "Example User";
    email = "example@user.invalid";
    username = "example";
    hashedPassword = passwordHash;
    sshKey = "ssh-ed25519 AAAAexamplekey example@user.invalid";
    trustedKeys = [ "ssh-ed25519 AAAAtrustedkey trusted@elsewhere" ];
  };
  identityJson = pkgs.writeText "identity.json" (builtins.toJSON identityAttrs);

  # The BUILD-TIME account for the SAME identity + the selected mode, rendered from the ONE shared
  # accountPlan (ADR-0020). `provision` now EVALUATES this same accountPlan at runtime (via
  # contract-account-plan) and renders it, so its realized account must match this record
  # field-for-field — the renderer-faithfulness this VM proves. `provision` adds the greeter-seat
  # marker (`greeter-users`) on top of the record's groups (the standing baseline it enrolls into),
  # so the expected supplementary group set is the record's groups ∪ that marker.
  # The seat runs the graphical mode, which is what gives a walk-up account its input groups —
  # nothing is granted at a greeter, because the safe set is empty.
  seatMode = "gui";
  buildTimePlan = accountPlan {
    identity = identityAttrs;
    grants = greeterAffordances;
    mode = seatMode;
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
    contract.greeter.desktops.gnome.command = "echo gnome > /tmp/desktop-launched";
    contract.greeter.desktops.plasma.command = "echo plasma > /tmp/desktop-launched";
    contract.greeter.defaultDesktop = "plasma";
    users.groups.docker = { };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The enabled greeter ships the privileged helpers.
    machine.succeed("command -v contract-greeter-provision contract-greeter-session")

    # The external user does NOT exist at build time — NixOS users are declarative.
    machine.fail("getent passwd example")

    # RUNTIME provision: the shell-side realization (ADR-0020).
    machine.succeed("contract-greeter-provision example ${identityJson} ${activationStub} tier1 ${seatMode}")
    machine.succeed("getent passwd example")

    # Account fully realized by RENDERING the record the shared accountPlan evaluates for this
    # identity + the safe-set grant (contract-account-plan) — so the realized account matches the
    # build-time accountPlan record (ADR-0020 build↔runtime parity), field for field:
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

    # (The empty-sshKey branch of the rule — primary dropped, trustedKeys alone — is proven without a
    # boot in ./account-plan.nix now that the rule has a single source; the VM no longer carries a
    # second `nokey` fixture for it.)

    # Per-user desktop SELECTION (ADR-0021): no home choice ⇒ the seat default (plasma) launches.
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")
    # The user's home chooses gnome ⇒ gnome launches instead.
    machine.succeed("echo gnome > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx gnome /tmp/desktop-launched")
    # A desktop the seat does NOT offer degrades to the default, never breaks the login (ADR-0021).
    machine.succeed("echo hyprland > /home/example/.contract-desktop")
    machine.succeed("contract-greeter-session example /home/example")
    machine.succeed("grep -qx plasma /tmp/desktop-launched")

    # Tier 2 (ephemeral) provisioning is designed-for but DEFERRED — the helper refuses it BY NAME,
    # before touching the account. Asserted on the message for the same reason the arity claims
    # below are: a bare `fail` cannot tell "refused because tier2 is deferred" from "died for some
    # other reason on the way", and the design point (ADR-0018) is that tier2 is refused rather
    # than silently downgraded to tier1's posture.
    machine.fail("contract-greeter-provision someone-else ${identityJson} ${activationStub} tier2 ${seatMode} 2> /tmp/tier2.err")
    machine.succeed("grep -q 'tier2 (ephemeral) provisioning is deferred' /tmp/tier2.err")
    # …and the refusal is BEFORE any account work: the user it names must not exist afterwards.
    machine.fail("getent passwd someone-else")

    # An unrecognised tier is refused too, and names the tier it got — the branch that catches a
    # seat whose `contract.greeter.tier` binding has drifted to a value the helper never knew.
    machine.fail("contract-greeter-provision someone-else ${identityJson} ${activationStub} tier9 ${seatMode} 2> /tmp/tier9.err")
    machine.succeed("grep -q \"unknown tier 'tier9'\" /tmp/tier9.err")
    machine.fail("getent passwd someone-else")

    # ARITY IS THE INTERFACE: five positional arguments, in a fixed order. A drifted caller must be
    # told SO — this guard exists for legibility, not for catching drift earlier, since the fleet VM
    # already caught it.
    #
    # So the claim is about the MESSAGE, not just the exit status: `set -u` already failed a
    # four-argument call with `$5: unbound variable`, so a bare `machine.fail` would pass against
    # the very behaviour this replaced and prove nothing (ADR-0022 — a negative claim that cannot
    # fail for the right reason is vacuous). stderr is captured to a file rather than piped, because
    # the helper runs under `pipefail` and a pipeline would conflate "refused" with "grep found it".
    # The five-argument call above is the positive control: this arity, and only this one, works.
    machine.fail("contract-greeter-provision example ${identityJson} ${activationStub} tier1 2> /tmp/arity-few.err")
    machine.succeed("grep -q 'expected 5 arguments, got 4' /tmp/arity-few.err")
    machine.succeed("grep -q 'usage: contract-greeter-provision' /tmp/arity-few.err")

    # …and the other direction, which `set -u` could never catch: a SIXTH argument was silently
    # ignored, so a caller passing one had no way to learn it was not being read.
    machine.fail("contract-greeter-provision example ${identityJson} ${activationStub} tier1 ${seatMode} extra 2> /tmp/arity-many.err")
    machine.succeed("grep -q 'expected 5 arguments, got 6' /tmp/arity-many.err")

    print(machine.succeed("id example; getent passwd example"))
  '';
}
