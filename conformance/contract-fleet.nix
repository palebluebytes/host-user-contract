# Conformance domain: the FLEET-LEVEL producer — `mkContractFleet`, the members-and-matrix rung
# above `mkContractUsers`.
#
# Two tracks, because the subject has two halves that want opposite material:
#
#   the PROBE track  — a RECORDING `buildHome` and a FAKE `pkgsFor`, so every claim about what the
#                      fold hands its injected closure is read straight off the recorded arguments.
#                      This is the same posture `contract-home.nix` takes with its recording
#                      `homeManagerConfiguration` stub, and it is what lets a two-system fleet be
#                      proven here at all: nothing is built, and no home-manager is anywhere near
#                      it.
#   the OUTPUT track — the real `pkgs` and a synthetic already-evaluated home, so the three
#                      published attributes (`packages`, `contractUsers`, and the homes behind them)
#                      are pinned on the real producer path rather than on a stub of it.
#
# All six returned attributes are covered, because a returned value nobody pins is a rule nobody
# holds. So are the traps that only exist at THIS rung, where the fold is: a member set with no
# members, a matrix naming no system, a row that is not a list, a row that names no mode, a
# `pkgsFor` that answers about the wrong system, a `buildHome` that ignores one of the three
# arguments it is handed, and a `defaultSystem` the matrix does not name.
{
  lib,
  pkgs,
  system,
  toolkit,
  mkContractFleet,
  mkContractUsers,
}:
let
  inherit (toolkit) evalDeclaration;
  # The two reference members this domain folds over, borrowed BY ROLE through the toolkit's
  # reference seam (./toolkit.nix) — the suite takes real atoms from the positive-space example,
  # never the reverse, and it does so without naming a path or a person.
  inherit (toolkit.referenceUsers) portable cliOnly;
  portableName = portable.name;
  cliOnlyName = cliOnly.name;
  # The pair as `attrNames` yields it — sorted, so a rename cannot silently reorder an expectation.
  memberNames = lib.sort (a: b: a < b) [
    portableName
    cliOnlyName
  ];
  # The names the producer publishes for those two members over a set of modes, under whichever
  # naming RULE is being pinned — `<user>-contractPackage-<mode>` for a binding artifact,
  # `<user>-<mode>` for the home-manager CLI adapter. Derived rather than typed out, because the
  # rule is the claim; ONE helper rather than two, because the spelling is all that differs.
  publishedNames =
    render: modes: lib.sort (a: b: a < b) (lib.concatMap (n: map (render n) modes) memberNames);
  expectedPackageNames = publishedNames (n: m: "${n}-contractPackage-${m}");
  expectedAdapterNames = publishedNames (n: m: "${n}-${m}");

  # Their DECLARATION is the one field this domain replaces, so these stay claims about the FLEET
  # rather than about `mkMembers` (which ./members.nix owns): a member carries its declaration, and
  # the declaration is what decides which modes get built — the fold builds this system's row ∩
  # what the user runs in. So the declaration is a parameter here, and the publication claims below
  # vary it rather than varying a home.
  bothModes = evalDeclaration [
    {
      contract.cli.enable = true;
      contract.gui.enable = true;
    }
  ];
  guiOnly = evalDeclaration [ { contract.gui.enable = true; } ];
  mkMemberWith = declaration: member: member // { inherit declaration; };
  mkMember = mkMemberWith bothModes;
  membersRunning = declaration: {
    ${portableName} = mkMemberWith declaration portable;
    ${cliOnlyName} = mkMemberWith declaration cliOnly;
  };
  members = membersRunning bothModes;

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
  # its injected closure is read off the result. It carries no home SHAPE — no `activationPackage`,
  # no `config` — because a fold that quietly required more of a home than the signature states
  # would be a contract nobody wrote down. Which homes get published is answered from the MEMBER's
  # declaration, one step before any home exists, so this track never has to fabricate a home shape
  # to satisfy the producer.
  #
  # `freshlyBuilt` is the one thing beside the recording, and it is what makes "never a second
  # build" a CLAIM rather than a hope. Every leaf the fold hands a builder is shared by
  # construction — the member, the `pkgsBySystem` entry, a mode string — so two SEPARATE
  # applications for one cell would compare equal on the recording alone. A lambda constructed per
  # application does not: see `probePkgsFor` for the pointer rule this rests on.
  recordingBuildHome = args: {
    recorded = args;
    freshlyBuilt = x: x;
  };

  # The probe track's material, spelled ONCE: every fleet below is this with one thing changed, so
  # a claim and the guard that contradicts it cannot drift apart in the parts neither is about.
  probeFleetWith =
    args:
    mkContractFleet (
      {
        inherit members;
        homeMatrix = probeMatrix;
        pkgsFor = probePkgsFor;
        buildHome = recordingBuildHome;
      }
      // args
    );
  probeFleet = probeFleetWith { };
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
  strictFleet = probeFleetWith { pkgsFor = strictPkgsFor; };
  strictlyForced = builtins.tryEval (builtins.deepSeq strictFleet.homes true);

  # ── The guards ────────────────────────────────────────────────────────────────────────────────
  # Each is the whole fleet with ONE thing wrong, forced through ONE attribute. WHICH attribute is
  # itself load-bearing, which is why it is a parameter: the fold's own guards are forced through
  # `homes` — the attribute every other one is derived from, so a guard that did not fire would be
  # visible as a fleet that built — and the ADAPTER's are forced through `homeConfigurations`,
  # which is half of the claim that they ride the adapter rather than the fold.
  forcedThrough = attr: args: builtins.tryEval (builtins.deepSeq (probeFleetWith args).${attr} true);
  brokenBy = forcedThrough "homes";
  emptyMembers = brokenBy { members = { }; };
  unshapelyMembers = brokenBy { members = [ (mkMember portable) ]; };
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
  # home-manager and this suite has none. The end-to-end half, a REAL `mkContractHome` result
  # driven through this producer, is `examples/users`' own `nix flake check`.
  activationStub = pkgs.runCommand "fleet-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';
  mkSyntheticHome = username: {
    activationPackage = activationStub;
    config.home = {
      packages = [ pkgs.hello ];
      inherit username;
    };
  };

  outputMatrix.${system} = [
    "cli"
    "gui"
  ];
  buildSyntheticHome = { member, ... }: mkSyntheticHome member.name;
  outputFleet = mkContractFleet {
    inherit members;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome = buildSyntheticHome;
  };

  # PARITY with the rung below: for one system, the fleet must emit exactly what `mkContractUsers`
  # emits over the same built homes. `mkContractFleet` adds the fold, never a second bake — so if
  # these ever differ, the fleet has grown an opinion of its own.
  builtHomes = lib.mapAttrs (
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
    homes = builtHomes;
  };

  # PUBLICATION IS THE INTERSECTION: the matrix says what a SYSTEM builds and the user's own
  # declaration says which session shapes it runs in, so a gui-only member on a two-mode system
  # publishes ONE home — and the cli home is never BUILT either, because the fold intersects before
  # it builds rather than building everything and discarding.
  guiOnlyFleet = mkContractFleet {
    members = membersRunning guiOnly;
    homeMatrix = outputMatrix;
    pkgsFor = _: pkgs;
    buildHome = buildSyntheticHome;
  };
  # …and the same members on a row that subtracts EVERY mode they run in. The intersection comes
  # out empty, and that is not an error here: the matrix is fail-OPEN on coverage, so a system that
  # bakes none of a user's modes simply publishes nothing for that user THERE — an index entry that
  # still says which modes the user runs in, with no contractPackages behind it. The refusal
  # belongs to the bind, which is where a host and a user meet with nothing in common and the
  # diagnostic can name both sides.
  uncoveredFleet = mkContractFleet {
    members = membersRunning guiOnly;
    homeMatrix.${system} = [ "cli" ];
    pkgsFor = _: pkgs;
    buildHome = buildSyntheticHome;
  };

  # ── The home-manager CLI adapter ─────────────────────────────────────────────────────────────
  # The one returned attribute that is about a SINGLE system, so it takes material of its own. On
  # the probe track, so the claims are read off recorded arguments — and because `<user>-cli`
  # exists on BOTH of the probe matrix's systems, which is what makes "the DEFAULT system's homes"
  # a claim the names alone cannot make.
  adapterFleet = probeFleetWith { defaultSystem = "x86_64-linux"; };
  # A REBUILD of one of that fleet's cells, from the same three arguments the fold hands over. The
  # negative control for the identity claim: this is what a second build of one home looks like,
  # and it must not compare equal to the published one.
  rebuiltCell = recordingBuildHome {
    member = members.${portableName};
    mode = "cli";
    pkgs = adapterFleet.pkgsBySystem.x86_64-linux;
  };
  # The MIXED shape a real users repo has, in one adapter: a member running two modes beside a
  # member running one. A fleet where every member ran a single mode could not tell a correct
  # adapter from one that kept only the first entry per user.
  mixedModeFleet = probeFleetWith {
    members = {
      ${portableName} = mkMemberWith bothModes portable;
      ${cliOnlyName} = mkMemberWith guiOnly cliOnly;
    };
    defaultSystem = "x86_64-linux";
  };
  expectedMixedNames = lib.sort (a: b: a < b) [
    "${portableName}-cli"
    "${portableName}-gui"
    "${cliOnlyName}-gui"
  ];
  # One system, so there is nothing for `defaultSystem` to choose between and it is not asked for.
  soleSystemFleet = probeFleetWith { homeMatrix.aarch64-linux = [ "cli" ]; };
  # …and that same sole system baking none of anybody's modes: the intersection is empty and the
  # adapter is EMPTY rather than a refusal, which is the same fail-open posture the index takes.
  uncoveredAdapterFleet = probeFleetWith {
    members = membersRunning guiOnly;
    homeMatrix.aarch64-linux = [ "cli" ];
  };
  # The adapter's own refusals, forced through the adapter ALONE.
  forcedAdapter = forcedThrough "homeConfigurations";
  ambiguousAdapter = forcedAdapter { };
  strayDefaultSystem = forcedAdapter { defaultSystem = "riscv64-linux"; };

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
        && lib.attrNames probeFleet.homes.x86_64-linux == memberNames
        &&
          lib.attrNames probeFleet.homes.x86_64-linux.${portableName} == [
            "cli"
            "gui"
          ]
        # The headless tier's row runs `cli` alone — the matrix is honoured per system, not
        # flattened into one set of modes.
        && lib.attrNames probeFleet.homes.aarch64-linux.${portableName} == [ "cli" ];
    }
    {
      # The cross-product is HARD-WIRED: every member is built for every mode in its system's row.
      # This is also why the members and the matrix cannot disagree — there is no third list to
      # drift.
      name = "mkContractFleet: every member is built for every mode in its row, and nothing else";
      ok = actualCells == expectedCells && expectedCells != [ ];
    }
    {
      # The FLAT adapter, over the default system's homes and nothing else. Its whole reason for
      # living here is that the naming rule is an EXTERNAL constraint every users repo meets
      # identically, so the rule is what is pinned: `<user>-<mode>`, one entry per published home.
      name = "mkContractFleet: `homeConfigurations` is the flat <user>-<mode> adapter over the default system";
      ok =
        lib.attrNames adapterFleet.homeConfigurations == expectedAdapterNames [
          "cli"
          "gui"
        ];
    }
    {
      # NEVER A SECOND BUILD. Both systems' rows publish a `<user>-cli`, so an adapter folding over
      # the wrong system — or building the homes a second time — would still produce the names
      # above. This is the claim those names cannot make: each entry IS the published home, by
      # identity, and it is the DEFAULT system's.
      name = "mkContractFleet: every adapter entry IS the published home of the default system, not a rebuild";
      ok =
        lib.all (
          n:
          lib.all
            (m: sameValue adapterFleet.homeConfigurations."${n}-${m}" adapterFleet.homes.x86_64-linux.${n}.${m})
            [
              "cli"
              "gui"
            ]
        ) memberNames
        &&
          (adapterFleet.homeConfigurations."${portableName}-cli").recorded.pkgs.stdenv.hostPlatform.system
          == "x86_64-linux";
    }
    {
      # The CONTROL for the claim above, without which it could pass over a fleet that rebuilt
      # every home: an actual second build from the same three arguments is NOT that value. See
      # `recordingBuildHome` for what makes the two distinguishable at all.
      name = "mkContractFleet: a second build of one cell is NOT the published home (the control)";
      ok = !(sameValue rebuiltCell adapterFleet.homes.x86_64-linux.${portableName}.cli);
    }
    {
      # The shape a real users repo has: a member running two modes and a member running one, in
      # one adapter, each spelled the same way. There is no bare `<user>` name beside the single
      # entry, because there is no privileged mode to give it to.
      name = "mkContractFleet: a member running ONE mode gets one adapter entry, beside a two-mode member's two";
      ok = lib.attrNames mixedModeFleet.homeConfigurations == expectedMixedNames;
    }
    {
      # A fleet baking for one system has nothing to choose between, so it is not made to say.
      name = "mkContractFleet: a fleet baking for ONE system needs no `defaultSystem`";
      ok = lib.attrNames soleSystemFleet.homeConfigurations == expectedAdapterNames [ "cli" ];
    }
    {
      # …and the default system baking none of anybody's modes yields an EMPTY adapter rather than
      # a refusal — the same fail-open posture the index takes below. There is no
      # `home-manager switch` to be had either way, and inventing a refusal here would make a
      # producer decide what a self-contained user may be on the strength of one system's topology.
      name = "mkContractFleet: a default system baking none of anybody's modes yields an EMPTY adapter";
      ok = uncoveredAdapterFleet.homeConfigurations == { };
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
        (recordedFor "x86_64-linux" cliOnlyName "cli").member == members.${cliOnlyName}
        && (recordedFor "x86_64-linux" cliOnlyName "cli").member.identity.username == cliOnlyName;
    }
    {
      # The cell's own MODE — a builder that ignored this would see one mode for every home, and
      # `cli` and `gui` would be the same build under two names.
      name = "mkContractFleet: buildHome is handed its OWN cell's mode, per home";
      ok =
        (recordedFor "x86_64-linux" portableName "cli").mode == "cli"
        && (recordedFor "x86_64-linux" portableName "gui").mode == "gui"
        && (recordedFor "aarch64-linux" portableName "cli").mode == "cli";
    }
    {
      # THAT system's pkgs — a builder handed one system's pkgs for every row would bake the arm
      # tier on x86 and nothing would say so.
      name = "mkContractFleet: buildHome is handed the pkgs of the system whose row it is building";
      ok =
        (recordedFor "aarch64-linux" cliOnlyName "cli").pkgs.stdenv.hostPlatform.system == "aarch64-linux"
        && (recordedFor "x86_64-linux" cliOnlyName "gui").pkgs.stdenv.hostPlatform.system == "x86_64-linux";
    }

    # --- pkgs is instantiated once per system, proven ---
    {
      # The POSITIVE claim: the pkgs a home is handed IS the memo entry, not an equal-looking
      # rebuild of it. See `probePkgsFor` for why this comparison answers identity.
      name = "mkContractFleet: every home is handed the memo entry for its system, not a fresh application";
      ok =
        sameValue (recordedFor "x86_64-linux" portableName "cli").pkgs probeFleet.pkgsBySystem.x86_64-linux
        &&
          sameValue (recordedFor "x86_64-linux" portableName "gui").pkgs
            probeFleet.pkgsBySystem.x86_64-linux
        &&
          sameValue (recordedFor "x86_64-linux" cliOnlyName "cli").pkgs
            probeFleet.pkgsBySystem.x86_64-linux
        &&
          sameValue (recordedFor "aarch64-linux" portableName "cli").pkgs
            probeFleet.pkgsBySystem.aarch64-linux;
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
      # A CLI fragment carries a user and a mode and nowhere to put a system, so a multi-system
      # fleet has to say which one — and the refusal rides the ADAPTER rather than the fold, which
      # is the second half of this claim: the same fleet's homes force fine. A fleet that never
      # publishes the adapter is never charged for one, exactly as it is never charged for a
      # `pkgsFor` it does not reach.
      name = "mkContractFleet: a multi-system fleet naming no `defaultSystem` refuses at the ADAPTER alone";
      ok =
        !ambiguousAdapter.success && (builtins.tryEval (builtins.deepSeq probeFleet.homes true)).success;
    }
    {
      name = "mkContractFleet: a `defaultSystem` the matrix does not name is a named error";
      ok = !strayDefaultSystem.success;
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
          lib.attrNames outputFleet.packages.${system} == expectedPackageNames [
            "cli"
            "gui"
          ];
    }
    {
      name = "mkContractFleet: `contractUsers` is nested by system and carries the binding index";
      ok =
        lib.attrNames outputFleet.contractUsers == [ system ]
        && lib.attrNames outputFleet.contractUsers.${system} == memberNames
        &&
          # The index entry is the coin's own: the member's identity, the modes it runs in, and one
          # contractPackage per PUBLISHED mode, keyed by that mode.
          outputFleet.contractUsers.${system}.${portableName}.identity == members.${portableName}.identity
        &&
          outputFleet.contractUsers.${system}.${portableName}.modes == [
            "cli"
            "gui"
          ]
        &&
          lib.attrNames outputFleet.contractUsers.${system}.${portableName}.contractPackages == [
            "cli"
            "gui"
          ];
    }
    {
      # The fleet adds the fold and nothing else: for one system it must emit exactly what the rung
      # below emits over the same built homes.
      name = "mkContractFleet: matches mkContractUsers over the same homes, for one system";
      ok =
        outputFleet.packages.${system} == usersOut.packages.${system}
        && outputFleet.contractUsers.${system} == usersOut.contractUsers.${system};
    }

    # --- publication is the row ∩ what the user runs in ---
    {
      # The system's row names both modes and the member runs in one, so one home exists. The fold
      # intersects before it builds: a home nobody could bind is never built, let alone published.
      name = "mkContractFleet: a gui-only member publishes its gui home alone, though the row names both";
      ok =
        lib.attrNames guiOnlyFleet.homes.${system}.${portableName} == [ "gui" ]
        && lib.attrNames guiOnlyFleet.contractUsers.${system}.${portableName}.contractPackages == [ "gui" ]
        && lib.attrNames guiOnlyFleet.packages.${system} == expectedPackageNames [ "gui" ];
    }
    {
      # …and the intersection coming out EMPTY publishes nothing there, without refusing. A
      # producer must not get to decide what a self-contained user may BE on the strength of one
      # system's topology: the user is unchanged and still publishable elsewhere, and the host that
      # runs only what this system does not bake meets the refusal at its own bind, where the
      # selection can name what it runs against what the user publishes.
      #
      # The index entry SURVIVES, carrying the modes the user runs in and no contractPackages —
      # which is what lets that bind-side refusal name both sides instead of reporting a user the
      # flake has never heard of.
      name = "mkContractFleet: a system baking none of a member's modes publishes nothing for it there";
      ok =
        uncoveredFleet.homes.${system}.${portableName} == { }
        && uncoveredFleet.contractUsers.${system}.${portableName}.contractPackages == { }
        && uncoveredFleet.contractUsers.${system}.${portableName}.modes == [ "gui" ]
        && uncoveredFleet.packages.${system} == { };
    }
  ];
}
