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
# members, a matrix naming no system, a row that is not a list, a row that names no home, a
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
  # The reference fleet's own shape, in miniature: an x86 tier that bakes everything and a headless
  # arm tier that bakes `base` alone. Two systems and two labels is the smallest matrix that can
  # tell "the row's grants" from "the fleet's grants" and "this system's pkgs" from "the pkgs".
  guiGrants = {
    gui.enable = true;
  };
  probeMatrix = {
    x86_64-linux = [
      {
        grants = { };
        label = "base";
      }
      {
        grants = guiGrants;
        label = "gui";
      }
    ];
    aarch64-linux = [
      {
        grants = { };
        label = "base";
      }
    ];
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
  # its injected closure is read off the result. It is deliberately NOT home-shaped — nothing on
  # this track bakes, and a fold that quietly required home-shape from `buildHome` would be a
  # contract the signature does not state.
  recordingBuildHome = args: { recorded = args; };

  probeFleet = mkContractFleet {
    inherit members;
    homeMatrix = probeMatrix;
    pkgsFor = probePkgsFor;
    buildHome = recordingBuildHome;
  };
  recordedFor =
    sys: user: label:
    probeFleet.homes.${sys}.${user}.${label}.recorded;

  # Every cell the matrix implies, listed independently of the fold so the cross-product claim is
  # not read out of the very value it is judging.
  expectedCells = lib.concatMap (
    sys:
    lib.concatMap (n: map (row: "${sys}/${n}/${row.label}") probeMatrix.${sys}) (lib.attrNames members)
  ) (lib.attrNames probeMatrix);
  actualCells = lib.concatMap (
    sys:
    lib.concatMap (
      n: map (label: "${sys}/${n}/${label}") (lib.attrNames probeFleet.homes.${sys}.${n})
    ) (lib.attrNames probeFleet.homes.${sys})
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
        grants = { };
        label = "base";
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
  # The full want set a real home eval yields: every registry feature present, `.enable` a bool.
  syntheticWants = {
    gui.enable = true;
    sudo.enable = false;
    containers.enable = false;
    virtualization.enable = false;
    nix-daemon.enable = false;
  };
  # `stamp` is what `mkContractHome` attaches to its result (issue #56) — the grant-key the home was
  # BUILT under. Taking it as an argument is what lets the cases below build a home that agrees with
  # its row, one that does not, and one that carries no marker at all.
  mkSyntheticHome =
    { username, stamp }:
    {
      activationPackage = activationStub;
      config = {
        contract.requests = {
          gui.desktop = "plasma";
        };
        contract.wants = syntheticWants;
        home = {
          packages = [ pkgs.hello ];
          inherit username;
        };
      };
    }
    // lib.optionalAttrs (stamp != null) { contractBakedGrantKey = stamp; };

  outputMatrix.${system} = [
    {
      grants = { };
      label = "base";
    }
    {
      grants = guiGrants;
      label = "gui";
    }
  ];
  # An HONEST builder: it stamps each home with the key of the grants it was actually handed, which
  # is what `mkContractHome` does and what a producer's `{ grants; home }` pairing must survive.
  honestBuildHome =
    { member, grants, ... }:
    mkSyntheticHome {
      username = member.name;
      stamp = lib.sort (a: b: a < b) (lib.filter (f: grants.${f}.enable or false) (lib.attrNames grants));
    };
  outputFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome = honestBuildHome;
  };

  # PARITY with the rung below: for one system, the fleet must emit exactly what `mkContractUsers`
  # emits over the same filled rows. `mkContractFleet` adds the fold, never a second bake — so if
  # these ever differ, the fleet has grown an opinion of its own.
  filledRows = lib.mapAttrs (
    _: member:
    map (
      row:
      row
      // {
        home = honestBuildHome {
          inherit member;
          inherit (row) grants;
          inherit pkgs;
        };
      }
    ) outputMatrix.${system}
  ) members;
  usersOut = mkContractUsers {
    inherit pkgs members;
    homes = filledRows;
  };

  # A builder that IGNORES its `grants` argument while still stamping — the exact failure a fold
  # between a matrix and a bake can introduce, and the one that used to be invisible: it publishes a
  # `base` home under the `gui` grant-key, and every downstream guard reads that key rather than the
  # home. The pairing guard (issue #56) must survive the new layer, so this is a hard eval error by
  # BOTH routes out of the bake — the index's grant-key and the published package's name.
  ignoresGrantsFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome =
      { member, ... }:
      mkSyntheticHome {
        username = member.name;
        stamp = [ ];
      };
  };
  # `deepSeq` because the guard rides each bake RECORD: a bare `tryEval` over the mapped list would
  # force only the list itself and report success while every element was still an unforced throw.
  ignoredIndex = builtins.tryEval (
    builtins.deepSeq (map (
      b: b.grantKey
    ) ignoresGrantsFleet.contractUsers.${system}.ada.contractPackages) true
  );
  ignoredPackageNames = builtins.tryEval (lib.attrNames ignoresGrantsFleet.packages.${system});

  # …and its complement, which is ADR-0029's first-amendment guarantee held across this layer: a
  # home built WITHOUT `mkContractHome` carries no marker, so the cross-check is SKIPPED rather than
  # fired and the fleet bakes it exactly as before. The fold never learns which builder made a home,
  # which is the whole reason `buildHome` is injected.
  unmarkedFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome =
      { member, ... }:
      mkSyntheticHome {
        username = member.name;
        stamp = null;
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
      name = "mkContractFleet: `homes` is <system>.<user>.<label>, one entry per matrix row";
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
            "base"
            "gui"
          ]
        # The headless tier's row bakes `base` alone — the matrix is honoured per system, not
        # flattened into one set of labels.
        && lib.attrNames probeFleet.homes.aarch64-linux.ada == [ "base" ];
    }
    {
      # The cross-product is HARD-WIRED: every member bakes every home in its system's row. This is
      # also why the members and the matrix cannot disagree — there is no third list to drift.
      name = "mkContractFleet: every member bakes every home in its system's row, and nothing else";
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
        (recordedFor "x86_64-linux" "ben" "base").member == members.ben
        && (recordedFor "x86_64-linux" "ben" "base").member.identity.username == "ben";
    }
    {
      # The ROW's grants, per cell — a builder that ignored this would see one grant set for every
      # home, and `base` and `gui` would be the same build under two names.
      name = "mkContractFleet: buildHome is handed its OWN row's grants, per home";
      ok =
        (recordedFor "x86_64-linux" "ada" "base").grants == { }
        && (recordedFor "x86_64-linux" "ada" "gui").grants == guiGrants
        && (recordedFor "aarch64-linux" "ada" "base").grants == { };
    }
    {
      # THAT system's pkgs — a builder handed one system's pkgs for every row would bake the arm
      # tier on x86 and nothing would say so.
      name = "mkContractFleet: buildHome is handed the pkgs of the system whose row it is building";
      ok =
        (recordedFor "aarch64-linux" "ben" "base").pkgs.stdenv.hostPlatform.system == "aarch64-linux"
        && (recordedFor "x86_64-linux" "ben" "gui").pkgs.stdenv.hostPlatform.system == "x86_64-linux";
    }

    # --- pkgs is instantiated once per system, proven ---
    {
      # The POSITIVE claim: the pkgs a home is handed IS the memo entry, not an equal-looking
      # rebuild of it. See `probePkgsFor` for why this comparison answers identity.
      name = "mkContractFleet: every home is handed the memo entry for its system, not a fresh application";
      ok =
        sameValue (recordedFor "x86_64-linux" "ada" "base").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "x86_64-linux" "ada" "gui").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "x86_64-linux" "ben" "base").pkgs probeFleet.pkgsBySystem.x86_64-linux
        && sameValue (recordedFor "aarch64-linux" "ada" "base").pkgs probeFleet.pkgsBySystem.aarch64-linux;
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
      name = "mkContractFleet: a row naming no home at all is a hard error";
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
      name = "mkContractFleet: `packages` is nested by system and names every user × home";
      ok =
        lib.attrNames outputFleet.packages == [ system ]
        &&
          lib.attrNames outputFleet.packages.${system} == [
            "ada-contractPackage-base"
            "ada-contractPackage-gui"
            "ben-contractPackage-base"
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
          # contractPackage per home carrying its grant-key.
          outputFleet.contractUsers.${system}.ada.identity == members.ada.identity
        && outputFleet.contractUsers.${system}.ada.offer == syntheticWants
        &&
          map (b: b.grantKey) outputFleet.contractUsers.${system}.ada.contractPackages == [
            [ ]
            [ "gui" ]
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

    # --- the bake pairing survives the new layer (issue #56) ---
    {
      name = "mkContractFleet: a buildHome that ignores its `grants` fails the bake by the index";
      ok = !ignoredIndex.success;
    }
    {
      name = "mkContractFleet: …and by the published package name — both routes out of the bake";
      ok = !ignoredPackageNames.success;
    }
    {
      # ADR-0029's first-amendment guarantee, held one layer up: the fold never learns which builder
      # made a home, so an unmarked one still bakes.
      name = "mkContractFleet: a home built WITHOUT mkContractHome carries no marker and still bakes";
      ok =
        !(unmarkedFleet.homes.${system}.ada.gui ? contractBakedGrantKey)
        &&
          map (b: b.grantKey) unmarkedFleet.contractUsers.${system}.ada.contractPackages == [
            [ ]
            [ "gui" ]
          ];
    }
  ];
}
