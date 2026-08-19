# Conformance domain: the FLEET-LEVEL producer (ADR-0029's second amendment, issue #62) —
# `mkContractFleet`, the members-and-matrix rung above `mkContractUsers`.
#
# Two tracks, because the subject has two halves that want opposite material:
#
#   the PROBE track  — a RECORDING `buildHome` and a FAKE `pkgsFor`, so every claim about what the
#                      fold hands its injected closure is read straight off the recorded arguments.
#                      This is the same posture `contract-home.nix` takes with its recording
#                      `homeManagerConfiguration` stub, and it is what lets a two-system fleet be
#                      proven here at all: nothing is built, and no home-manager is anywhere near it
#                      (ADR-0004/0022).
#   the OUTPUT track — the real `pkgs` and a synthetic already-evaluated home, so the three
#                      published attributes (`packages`, `contractUsers`, and the bakes behind them)
#                      are pinned on the real bake path rather than on a stub of it.
#
# All five returned attributes are covered, because a returned value nobody pins is a rule nobody
# holds. So are the traps that only exist at THIS rung, where the fold is: a member set with no
# members, a matrix naming no system, a row that is not a list, a row that names no mode, a
# `pkgsFor` that answers about the wrong system, and a `buildHome` that ignores one of the three
# arguments it is handed.
{
  lib,
  pkgs,
  system,
  loadIdentity,
  mkContractFleet,
  mkContractUsers,
}:
let
  # Two members, hand-built as in ./turnkey-bind.nix, so these stay claims about the FLEET rather
  # than about `mkMembers` (which ./members.nix owns). Their identities come from the reference
  # fleet — the suite borrows real atoms from the positive-space example, never the reverse
  # (ADR-0022).
  mkMember = name: {
    inherit name;
    dir = ../examples/users/users + "/${name}";
    identity = loadIdentity (../examples/users/users + "/${name}/identity.json");
  };
  members = {
    ada = mkMember "ada";
    ben = mkMember "ben";
  };

  # ── The probe track ──────────────────────────────────────────────────────────────────────────
  # The reference fleet's own shape, in miniature: an x86 tier that runs every mode and a headless
  # arm tier that runs `cli` alone. Two systems and two modes is the smallest matrix that can tell
  # "the row's mode" from "the fleet's modes" and "this system's pkgs" from "the pkgs".
  probeMatrix = {
    x86_64-linux = [
      "cli"
      "gui"
    ];
    aarch64-linux = [ "cli" ];
  };

  # A FAKE `pkgs`: the one attribute the producer reads (`stdenv.hostPlatform.system`, which is how
  # `mkContractUsers` refuses to key one system's outputs by another's name), plus a FUNCTION.
  #
  # The function is the memoization probe, and it is why this is a proof rather than a comment.
  # Nix compares two values by POINTER first, so a value compared against itself is `true` without
  # ever looking inside; two SEPARATELY CONSTRUCTED attrsets carrying a lambda have no such
  # shortcut and comparing them is not an equality that holds. So `homeGotThePkgs == memoEntry`
  # answers "is this the same value?" rather than "does it look the same?" — which is exactly the
  # question, since the rule at stake ("`import nixpkgs` is not memoized across applications, so
  # instantiate once per SYSTEM") is about identity and nothing else. The negative control below
  # applies `pkgsFor` a second time and shows that comparison does NOT hold, so the positive claim
  # cannot pass by structural coincidence.
  probePkgsFor = sys: {
    stdenv.hostPlatform.system = sys;
    probe = x: x;
  };

  # The RECORDING builder: it returns what it was handed, so every claim about what the fold passes
  # its injected closure is read off the result. It carries the minimum HOME shape the fold really
  # requires and no more — the user's VOICE — because publication is driven by `supports`
  # (ADR-0032 §6), so which homes a fleet publishes cannot be answered without reading them. It
  # carries no `activationPackage` and no `home.*`: nothing on this track bakes, and a fold that
  # quietly required MORE than the voice would be a contract the signature does not state.
  recordingBuildHome = args: {
    recorded = args;
    config.contract = {
      wants = probeWants;
      supports = probeSupports;
    };
  };
  # Every mode supported, so the probe track's claims are about the FOLD and not about the cut;
  # the cut has its own claim on the output track below.
  probeSupports = {
    cli = true;
    gui = true;
  };
  probeWants = {
    gui = true;
    sudo = false;
    containers = false;
    virtualization = false;
    nix-daemon = false;
  };

  probeFleet = mkContractFleet {
    inherit members;
    homeMatrix = probeMatrix;
    pkgsFor = probePkgsFor;
    buildHome = recordingBuildHome;
  };
  recordedFor =
    sys: user: mode:
    probeFleet.homes.${sys}.${user}.${mode}.recorded;

  # Every cell the matrix implies, listed independently of the fold so the cross-product claim is
  # not read out of the very value it is judging.
  expectedCells = lib.concatMap (
    sys: lib.concatMap (n: map (mode: "${sys}/${n}/${mode}") probeMatrix.${sys}) (lib.attrNames members)
  ) (lib.attrNames probeMatrix);
  actualCells = lib.concatMap (
    sys:
    lib.concatMap (n: map (mode: "${sys}/${n}/${mode}") (lib.attrNames probeFleet.homes.${sys}.${n})) (
      lib.attrNames probeFleet.homes.${sys}
    )
  ) (lib.attrNames probeFleet.homes);

  # Is this comparison a HOLDING equality? Comparing two separately built values that carry a
  # function is either `false` or an error depending on the evaluator's mood, and the claim wants
  # neither — so both collapse to "no" and only a real `true` is a yes.
  sameValue = a: b: (builtins.tryEval (a == b)).value or false;

  # `pkgsFor` must be applied ONCE PER SYSTEM, which also means never for a system the matrix does
  # not name. This one throws for anything else, so a whole fleet forced through it is the proof.
  strictPkgsFor =
    sys:
    if probeMatrix ? ${sys} then
      probePkgsFor sys
    else
      throw "pkgsFor was applied to ${sys}, which the matrix does not name";
  strictFleet = mkContractFleet {
    inherit members;
    homeMatrix = probeMatrix;
    pkgsFor = strictPkgsFor;
    buildHome = recordingBuildHome;
  };
  strictlyForced = builtins.tryEval (builtins.deepSeq strictFleet.homes true);

  # ── The guards ────────────────────────────────────────────────────────────────────────────────
  # Each is the whole fleet with ONE thing wrong, forced through `homes` — the attribute every
  # other one is derived from, so a guard that did not fire would be visible as a fleet that built.
  brokenBy =
    args:
    builtins.tryEval (
      builtins.deepSeq
        (mkContractFleet (
          {
            inherit members;
            homeMatrix = probeMatrix;
            pkgsFor = probePkgsFor;
            buildHome = recordingBuildHome;
          }
          // args
        )).homes
        true
    );
  emptyMembers = brokenBy { members = { }; };
  unshapelyMembers = brokenBy { members = [ (mkMember "ada") ]; };
  emptyMatrix = brokenBy { homeMatrix = { }; };
  unshapelyMatrix = brokenBy { homeMatrix = [ ]; };
  unshapelyRow = brokenBy {
    homeMatrix = probeMatrix // {
      aarch64-linux = {
        cli = true;
      };
    };
  };
  emptyRow = brokenBy {
    homeMatrix = probeMatrix // {
      aarch64-linux = [ ];
    };
  };
  # The one disagreement between the matrix and the material that IS expressible: the matrix says a
  # row is a system's, and `pkgsFor` answers about a different one. (The members and the matrix
  # cannot disagree at all — the cross-product is hard-wired, which the cells claim above pins —
  # so this is where a "which system is this?" mistake actually lands.)
  crossedPkgs = brokenBy { pkgsFor = _: probePkgsFor "riscv64-linux"; };

  # ── The output track ─────────────────────────────────────────────────────────────────────────
  # One system (the suite's own), the real `pkgs`, and a synthetic already-evaluated home — the
  # same stand-in ./turnkey-bind.nix and ./contract-package.nix use, since the builder needs
  # home-manager and this suite has none (ADR-0004). The end-to-end half, a REAL `mkContractHome`
  # result driven through this producer, is `examples/users`' own `nix flake check` (ADR-0022).
  activationStub = pkgs.runCommand "fleet-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';
  # The full want set a real home eval yields: every registry feature present, one bool each.
  syntheticWants = {
    gui = true;
    sudo = false;
    containers = false;
    virtualization = false;
    nix-daemon = false;
  };
  # …and the full support set: every registry mode present, one bool each. These members run in
  # both modes, so both are published; the gui-only member below is the case where the cut bites.
  syntheticSupports = {
    cli = true;
    gui = true;
  };
  mkSyntheticHome =
    {
      username,
      supports ? syntheticSupports,
    }:
    {
      activationPackage = activationStub;
      config = {
        contract.requests = {
          gui.desktop = "plasma";
        };
        contract.wants = syntheticWants;
        contract.supports = supports;
        home = {
          packages = [ pkgs.hello ];
          inherit username;
        };
      };
    };

  outputMatrix.${system} = [
    "cli"
    "gui"
  ];
  buildSyntheticHome = { member, ... }: mkSyntheticHome { username = member.name; };
  outputFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome = buildSyntheticHome;
  };

  # PARITY with the rung below: for one system, the fleet must emit exactly what `mkContractUsers`
  # emits over the same built rows. `mkContractFleet` adds the fold, never a second bake — so if
  # these ever differ, the fleet has grown an opinion of its own.
  builtRows = lib.mapAttrs (
    _: member:
    lib.genAttrs outputMatrix.${system} (
      mode:
      buildSyntheticHome {
        inherit member mode;
        inherit pkgs;
      }
    )
  ) members;
  usersOut = mkContractUsers {
    inherit pkgs members;
    homes = builtRows;
  };

  # PUBLICATION IS DRIVEN BY `supports` (ADR-0032 §6): the matrix says what a SYSTEM builds and the
  # user says which of those it can run in, so what is published is the intersection. A gui-only
  # member on a two-mode system therefore publishes ONE home, and the cli home the fold built for
  # it is simply never published.
  guiOnlyFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome =
      { member, ... }:
      mkSyntheticHome {
        username = member.name;
        supports = {
          cli = false;
          gui = true;
        };
      };
  };
  # …and the same members one system over, on a row that subtracts EVERY mode they support. The
  # cut comes out empty, and that is not an error here: the matrix is fail-OPEN on coverage
  # (ADR-0032 §6), so a system that bakes none of a user's modes simply publishes nothing for that
  # user THERE. The refusal belongs to the bind, which is where a host and a user meet with nothing
  # in common and the diagnostic can name both sides.
  uncoveredFleet = mkContractFleet {
    inherit members;
    homeMatrix.${system} = [ "cli" ];
    pkgsFor = _: pkgs;
    buildHome =
      { member, ... }:
      mkSyntheticHome {
        username = member.name;
        supports = {
          cli = false;
          gui = true;
        };
      };
  };

in
{
  assertions = [
    # --- the returned surface: all five attributes ---
    {
      name = "mkContractFleet: `systems` is the matrix's key set, derived and never stated twice";
      ok = probeFleet.systems == lib.attrNames probeMatrix;
    }
    {
      name = "mkContractFleet: `homes` is <system>.<user>.<mode>, one entry per matrix row";
      ok =
        lib.attrNames probeFleet.homes == [
          "aarch64-linux"
          "x86_64-linux"
        ]
        &&
          lib.attrNames probeFleet.homes.x86_64-linux == [
            "ada"
            "ben"
          ]
        &&
          lib.attrNames probeFleet.homes.x86_64-linux.ada == [
            "cli"
            "gui"
          ]
        # The headless tier's row runs `cli` alone — the matrix is honoured per system, not
        # flattened into one set of modes.
        && lib.attrNames probeFleet.homes.aarch64-linux.ada == [ "cli" ];
    }
    {
      # The cross-product is HARD-WIRED: every member is built for every mode in its system's row.
      # This is also why the members and the matrix cannot disagree — there is no third list to
      # drift.
      name = "mkContractFleet: every member is built for every mode in its row, and nothing else";
      ok = actualCells == expectedCells && expectedCells != [ ];
    }
    {
      name = "mkContractFleet: `pkgsBySystem` holds one entry per system, each `pkgsFor` of it";
      ok =
        lib.attrNames probeFleet.pkgsBySystem == probeFleet.systems
        && probeFleet.pkgsBySystem.aarch64-linux.stdenv.hostPlatform.system == "aarch64-linux";
    }

    # --- what the injected closure is handed (the "buildHome ignores an argument" traps) ---
    {
      # The MEMBER itself, not its name: the fold hands over the resolved value, so a builder never
      # re-derives a path and the identity.json behind it is read once for the whole fleet.
      name = "mkContractFleet: buildHome is handed the MEMBER, identity and all";
      ok =
        (recordedFor "x86_64-linux" "ben" "cli").member == members.ben
        && (recordedFor "x86_64-linux" "ben" "cli").member.identity.username == "ben";
    }
    {
      # The cell's own MODE — a builder that ignored this would see one mode for every home, and
      # `cli` and `gui` would be the same build under two names.
      name = "mkContractFleet: buildHome is handed its OWN cell's mode, per home";
      ok =
        (recordedFor "x86_64-linux" "ada" "cli").mode == "cli"
        && (recordedFor "x86_64-linux" "ada" "gui").mode == "gui"
        && (recordedFor "aarch64-linux" "ada" "cli").mode == "cli";
    }
    {
      # THAT system's pkgs — a builder handed one system's pkgs for every row would bake the arm
      # tier on x86 and nothing would say so.
      name = "mkContractFleet: buildHome is handed the pkgs of the system whose row it is building";
      ok =
        (recordedFor "aarch64-linux" "ben" "cli").pkgs.stdenv.hostPlatform.system == "aarch64-linux"
        && (recordedFor "x86_64-linux" "ben" "gui").pkgs.stdenv.hostPlatform.system == "x86_64-linux";
    }

    # --- pkgs is instantiated once per system, proven ---
    {
      # The POSITIVE claim: the pkgs a home is handed IS the memo entry, not an equal-looking
      # rebuild of it. See `probePkgsFor` for why this comparison answers identity.
      name = "mkContractFleet: every home is handed the memo entry for its system, not a fresh application";
      ok =
        sameValue (recordedFor "x86_64-linux" "ada" "cli").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "x86_64-linux" "ada" "gui").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "x86_64-linux" "ben" "cli").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "aarch64-linux" "ada" "cli").pkgs probeFleet.pkgsBySystem.aarch64-linux;
    }
    {
      # The NEGATIVE CONTROL, without which the claim above could pass by structural coincidence: a
      # SECOND application of the very same `pkgsFor` is not that value. This is the rule the
      # producers used to carry as prose — function application is not memoized — asserted rather
      # than described.
      name = "mkContractFleet: a second application of pkgsFor is NOT the memo entry (the control)";
      ok = !(sameValue (probePkgsFor "x86_64-linux") probeFleet.pkgsBySystem.x86_64-linux);
    }
    {
      # …and once per system means never for a system the matrix does not name: this `pkgsFor`
      # throws for anything else, and the whole fleet still forces.
      name = "mkContractFleet: pkgsFor is applied only for the systems the matrix names";
      ok = strictlyForced.success && strictlyForced.value;
    }

    # --- the fold's own traps ---
    {
      name = "mkContractFleet: an empty member set is a hard error, never a fleet that builds nobody";
      ok = !emptyMembers.success;
    }
    {
      name = "mkContractFleet: a member set that is not an attrset is told so";
      ok = !unshapelyMembers.success;
    }
    {
      name = "mkContractFleet: a matrix naming no system is a hard error";
      ok = !emptyMatrix.success;
    }
    {
      name = "mkContractFleet: a matrix that is not an attrset is told so";
      ok = !unshapelyMatrix.success;
    }
    {
      name = "mkContractFleet: a row that is not a list is told so, not iterated over";
      ok = !unshapelyRow.success;
    }
    {
      name = "mkContractFleet: a row naming no mode at all is a hard error";
      ok = !emptyRow.success;
    }
    {
      name = "mkContractFleet: a pkgsFor answering about another system is a named error";
      ok = !crossedPkgs.success;
    }
    {
      # The members/matrix DISAGREEMENT, which at this rung is unexpressible rather than guarded —
      # and that is a claim worth pinning rather than asserting in prose. One rung down,
      # `mkContractUsers` must refuse a `homes` key its member set does not hold: a hand-listed
      # name that has drifted from the directory. Here there is no hand-listed name to drift,
      # because the fleet derives BOTH sides — the keys it hands over are the member set's own, on
      # every system. So the guard below it can never fire through this path, which is only true
      # while the fold keeps deriving them; if it ever took a member list of its own, this goes red.
      name = "mkContractFleet: the members and the matrix cannot disagree — every row's keys ARE the member set's";
      ok = lib.all (
        sys: lib.attrNames probeFleet.homes.${sys} == lib.attrNames members
      ) probeFleet.systems;
    }

    # --- the published outputs, on the real bake path ---
    {
      # Nested by system, so `inherit (fleet) packages contractUsers;` is the flake outputs.
      name = "mkContractFleet: `packages` is nested by system and names every user × published mode";
      ok =
        lib.attrNames outputFleet.packages == [ system ]
        &&
          lib.attrNames outputFleet.packages.${system} == [
            "ada-contractPackage-cli"
            "ada-contractPackage-gui"
            "ben-contractPackage-cli"
            "ben-contractPackage-gui"
          ];
    }
    {
      name = "mkContractFleet: `contractUsers` is nested by system and carries the binding index";
      ok =
        lib.attrNames outputFleet.contractUsers == [ system ]
        &&
          lib.attrNames outputFleet.contractUsers.${system} == [
            "ada"
            "ben"
          ]
        &&
          # The index entry is the coin's own: the member's identity, the harvested offer, and one
          # contractPackage per PUBLISHED mode, keyed by that mode.
          outputFleet.contractUsers.${system}.ada.identity == members.ada.identity
        && outputFleet.contractUsers.${system}.ada.offer == syntheticWants
        &&
          lib.attrNames outputFleet.contractUsers.${system}.ada.contractPackages == [
            "cli"
            "gui"
          ];
    }
    {
      # The fleet adds the fold and nothing else: for one system it must emit exactly what the rung
      # below emits over the same filled rows.
      name = "mkContractFleet: matches mkContractUsers over the same rows, for one system";
      ok =
        outputFleet.packages.${system} == usersOut.packages.${system}
        && outputFleet.contractUsers.${system} == usersOut.contractUsers.${system};
    }

    # --- publication is driven by `supports` (ADR-0032 §6) ---
    {
      # The system BUILDS both modes and the member runs in one, so one is published. `homes` is
      # the published set, not the built one — a home nobody could bind is not a flake output.
      name = "mkContractFleet: a gui-only member publishes its gui home alone, though the row built both";
      ok =
        lib.attrNames guiOnlyFleet.homes.${system}.ada == [ "gui" ]
        && lib.attrNames guiOnlyFleet.contractUsers.${system}.ada.contractPackages == [ "gui" ]
        &&
          lib.attrNames guiOnlyFleet.packages.${system} == [
            "ada-contractPackage-gui"
            "ben-contractPackage-gui"
          ];
    }
    {
      # …and the cut coming out EMPTY publishes nothing there, without refusing. A producer must
      # not get to decide what a self-contained user may BE on the strength of one system's
      # topology: the user is unchanged and still publishable elsewhere, and the host that runs
      # only what this system does not bake meets the refusal at its own bind, where the selection
      # can name what it runs against what the user offers.
      name = "mkContractFleet: a system baking none of a member's modes publishes nothing for it there";
      ok =
        uncoveredFleet.homes.${system}.ada == { }
        && uncoveredFleet.contractUsers.${system}.ada.contractPackages == { }
        && uncoveredFleet.packages.${system} == { };
    }
  ];
}
