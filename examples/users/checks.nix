# Reference USER FLEET checks — every claim this fleet makes about ITSELF, behind one explicit
# argument list. The flake beside this file states the fleet's own facts (who is here, what each
# system builds, how a home is composed, what credential posture this repo requires) and hands
# them over; nothing here reaches back into that flake's `let`. Same INTERFACE DISCIPLINE as the
# host fleet's `examples/fleet/checks.nix` — the edition this one was cut to match — though not the
# same return: that file answers with one derivation under one name, and this one with the whole
# attrset of checks its fleet publishes.
#
# There are no per-user checks — not "none yet": a user here ships its own files and the mapper
# next door carries no hook to pick a check file up with. Everything below is generic over the
# members handed in — save the one proof that is about a PAIR rather than about the members, and
# says so where it sits — so a new user is covered the moment its directory exists.
#
# Two kinds of claim live here, and the second is why this file is longer than the host fleet's:
#
#   - the contract's own CONSUMER CHECK KIT, folded over the members — the part every real users
#     repo runs, and the only part a consumer copying this fleet needs;
#   - three TEACHING EXTRAS a real users repo does NOT carry, each pinning something that would
#     otherwise be documented without being demonstrated, or would report green while proving
#     nothing. The reference fleets are teaching artifacts first (ADR-0022), so the commentary on
#     them is the artifact as much as the code is.
#
# THE THREE EXTRAS REPORT AS ONE (issue #91). They used to be three standalone derivations, each
# with a failure harness of its own — two separately-written shell `fail()`s and a `tryEval` behind
# an eval `assert` — so they surfaced as three opaque check names and a reader learnt only THAT
# something broke. They now go through the check kit's own claim report, the same one the
# conformance suite and the reference host fleet report through, in the two shapes it takes:
#
#   the posture offender probe is answerable at EVAL, so it is an eval claim and gets a named
#     `ok`/`FAIL` line;
#   the other two are only answerable from REALIZED content — what actually lands in a home — so
#     they stay execution proofs, threaded into the report as build inputs. Their `fail`s come from
#     the kit too (`mkProofPrelude`), which is the last thing this file had two copies of.
#
# Folding the two builds in does NOT make them more legible on failure, and it is not meant to: a
# failing execution proof kills the report before it prints, so a reader still meets
# `error: Cannot build …shared-code-per-user-data.drv` — which names it, as it always did. The
# prize is ONE SHAPE across the three reference artifacts.
#
# Returned as ONE attrset, merged by the flake into the row of the system it was given. That
# system is the seat tier on purpose: the aarch64 row is headless, so it publishes a single mode
# and has no second home for the mode-substitution proof to compare.
{
  # nixpkgs' lib, and the pkgs of the ONE system these checks run on — the same per-system memo
  # the producer made, never a second instantiation.
  lib,
  pkgs,
  # The contract flake itself, for the four surfaces reached here by name: `mkMemberChecks` (the
  # kit) and `mkIdentityPostureCheck` (which the offender probe calls a second time, deliberately,
  # to watch it refuse), plus the reporting pair `mkClaimReport`/`mkProofPrelude` — and
  # `floorMode`, the session shape the proofs compare against without naming a literal.
  contract,
  # WHO is here, WHAT was published for them, and HOW a home is composed — handed over rather
  # than re-derived, for the reason the flake states at the hand-over.
  members,
  homes,
  buildHome,
  # The system whose homes these checks read.
  system,
  # The credential posture the fleet REQUIRES of its own identities. No default, here or in the
  # kit: the posture is the consuming repo's own choice, and stating it is the point.
  require,
}:
let
  # Two projections OF the members handed in, for the sites that want a list rather than the
  # attrset: the member names (the mode-substitution proof walks them) and the members' identities
  # (the offender probe appends a synthetic identity to them). Projections, never a second
  # derivation of "who is here" or a second read of an identity.json.
  userNames = lib.attrNames members;
  memberIdentities = map (m: m.identity) (lib.attrValues members);

  # ── EVAL CLAIMS — what is decidable before anything is built ─────────────────────────────────
  claims = [
    {
      # The proof that the posture check in the kit fold below can actually FAIL. A teaching extra
      # a real users repo does not carry: a posture check that passes because its identity list is
      # empty reads identically to one that passes on merit.
      #
      # So: take the REAL derived members, append one synthetic `$6$` offender, and require that
      # the check rejects it. This claims something about the CALL SITE, not about the helper —
      # the helper's own refusals are the conformance suite's business.
      #
      # `tryEval` is the only way to ask it: the posture check refuses by throwing, and a throw is
      # not a value a claim can read. It is the verdict, not a harness — the reporting around it is
      # the report's now.
      #
      # WHEN THIS LINE READS `FAIL`, the posture check above it is vacuous: it would pass whatever
      # `./users` holds. Look first at whether the members still derives a non-empty identity list
      # from that directory.
      name = "identity posture: a `$6$` identity appended to the real members is REJECTED (so the posture check is not vacuous)";
      ok =
        let
          # Any real members identity will do as the base — the offender differs from it only in
          # the two fields the posture looks at — so it is taken from the derivation rather than by
          # naming a user this claim has no other business knowing.
          #
          # The offending hash is sha512crypt (`$6$`), which is exactly what the public-repo
          # posture exists to exclude (ADR-0004). So this probes the posture THIS fleet requires,
          # not postures in general: hand `require = "libc"` in and the offender stops offending,
          # and this line reads `FAIL` — correctly, and saying so.
          someRealIdentity = lib.head memberIdentities;
          offender = someRealIdentity // {
            username = "sixto";
            hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
          };
        in
        !(builtins.tryEval (
          contract.lib.mkIdentityPostureCheck {
            inherit pkgs require;
            identities = memberIdentities ++ [ offender ];
            name = "identity-posture-offender-probe";
          }
        )).success;
    }
  ];

  # ── EXECUTION PROOFS — what is only answerable from a home that actually got built ───────────

  # The claim the duo pair exists to prove: SHARED CODE, PER-USER DATA. Also kept deliberately as
  # a teaching extra — it is the one proof here that names users, because the arrangement it
  # proves is a property of that pair rather than of the members. "Both homes build" would not
  # prove it: a shared module that baked duo-a's identity into duo-b's home would still build. So
  # this pins the two halves separately, on the REALIZED homes:
  #
  #   shared CODE   — `shared/overlay.nix`'s marker package resolves to the SAME store path in
  #                   both closures (one derivation, not a per-user copy), and it is really there:
  #                   the proof RUNS it out of each home-path;
  #   per-user DATA — `shared/module.nix`, keyed on `config.contract.identity.username`, renders
  #                   two DIFFERENT store paths, each carrying its own identity and NO trace of
  #                   the other's.
  #
  # WHY THE VERDICT IS IN THE BUILD, and not an eval claim beside the one above: every question
  # here is about what LANDS in a home, and nothing but building one answers it.
  #
  # This is also why the proof lives with the fleet rather than in `conformance/`: it needs both
  # home-manager and nixpkgs, and the contract's synthetic suite has neither.
  sharedCodePerUserData =
    let
      # This proof's NAME, written once: it is the derivation's name, the label every `fail` below
      # prints, and the key it is reported under. Three uses of one string rather than three
      # strings that agree today.
      proof = "shared-code-per-user-data";
      # The floor home of each, so the pair is compared in the mode both certainly run in — the
      # shared arrangement is mode-independent, which is the point.
      duoA = homes.${system}.duo-a.${contract.floorMode};
      duoB = homes.${system}.duo-b.${contract.floorMode};
      # Both halves are read out of the REALIZED activation package, never off the evaluated
      # config: the point is what actually lands in the user's home.
      cardOf = home: "${home.activationPackage}/home-files/.contract-shared-card";
      markerOf = home: "${home.activationPackage}/home-path/bin/contract-shared-marker";
    in
    pkgs.runCommand proof { } (
      # `fail` comes from the check kit, which is the whole of what this proof used to write for
      # itself — twice, once here and once below, identical but for the label echoed.
      contract.lib.mkProofPrelude proof
      + ''
        # --- shared CODE: one overlay, one derivation, in BOTH closures ---
        markerA=$(readlink -f ${markerOf duoA})
        markerB=$(readlink -f ${markerOf duoB})
        [ -x "$markerA" ] || fail "duo-a's home-path has no runnable shared-overlay marker"
        [ -x "$markerB" ] || fail "duo-b's home-path has no runnable shared-overlay marker"
        [ "$markerA" = "$markerB" ] || fail "the shared overlay produced a DIFFERENT package per user ($markerA vs $markerB) — that is not shared code"
        "$markerA" | grep -q 'shared/overlay.nix' || fail "the marker in the closure did not come from the shared overlay"

        # --- per-user DATA: same module, two identities, two different outputs ---
        cardA=$(readlink -f ${cardOf duoA})
        cardB=$(readlink -f ${cardOf duoB})
        [ -f "$cardA" ] || fail "duo-a's realized home has no shared-module card"
        [ -f "$cardB" ] || fail "duo-b's realized home has no shared-module card"
        [ "$cardA" != "$cardB" ] || fail "the shared module rendered ONE output for two identities — it is not keyed on config.contract.identity.username"

        grep -q '^username=duo-a$' "$cardA" || fail "duo-a's card is not keyed on duo-a's username"
        grep -q '^username=duo-b$' "$cardB" || fail "duo-b's card is not keyed on duo-b's username"
        grep -q 'Duo A Reference' "$cardA" || fail "duo-a's card lost duo-a's own identity"
        grep -q 'Duo B Reference' "$cardB" || fail "duo-b's card lost duo-b's own identity"

        # --- and neither carries a TRACE of the other's identity ---
        ! grep -q 'duo-b\|Duo B' "$cardA" || fail "duo-a's home leaks duo-b's identity — the shared module baked a user in"
        ! grep -q 'duo-a\|Duo A' "$cardB" || fail "duo-b's home leaks duo-a's identity — the shared module baked a user in"

        touch $out
      ''
    );

  # The property the PER-MODE home system exists for, pinned so it cannot rot into a difference the
  # user never receives: somewhere in this members a MODE is load-bearing — a user whose homes
  # differ in realized CONTENT across the modes it runs in. Content is exactly what a bind cannot
  # change, so a mode that substitutes none is the one thing about modes this fleet would otherwise
  # document without demonstrating.
  #
  # Members-generic on purpose, unlike `sharedCodePerUserData` above: WHICH user substitutes
  # content per mode is that user's own story, told in its own `user.nix` (today duo-a's, whose two
  # modes name two different modules), so this names no user.
  #
  # A CONVERGENT PAIR IS NOT A FAILURE. A mode carries host-side weight a home never sees — `gui`
  # confers input groups and a display surface — so ada, cleo, duo-b and admin all run two modes
  # off one home's worth of content, deliberately and correctly (ADR-0027). What this proof refuses
  # is a FLEET in which NO pair diverges: keeping a worked example of the mechanism it documents is
  # a REFERENCE fleet's obligation (ADR-0022), and it is this repo's alone — no consumer owes it,
  # which is why the kit ships nothing for it.
  #
  # WHY THE VERDICT IS IN THE BUILD rather than in an eval claim beside the posture probe.
  # Divergence is only answerable from realized content, and both cheap eval-time approximations
  # lie:
  #
  #   drvPath        two modes naming ONE module land on the very same derivation — admin, whose
  #                  two homes are one derivation built twice — UNLESS the mode carries a
  #                  `desktop`, which the contract writes into the gui home. So ada, cleo and duo-b
  #                  differ by drvPath while substituting nothing.
  #   the declaration  comparing two `configuration` values compares MERGED `deferredModule`s,
  #                  whose wrapper records the option path each came through; every pair differs,
  #                  including duo-b's two references to one file.
  #
  # So the eval `assert` below claims only what is knowable before anything is built: that there is
  # a pair to compare at all. It stays an `assert` rather than joining the report's claims because
  # it is a PRECONDITION on the material this proof is assembled from, not a verdict the proof
  # reaches — and it fires at eval, ahead of every build, which is the most legible moment there
  # is. A report line saying the same thing would never be printed: the proof is a build input of
  # the report, so it takes the report down before the report can render anything.
  #
  # NOTHING IS SUBTRACTED, and that is a property of the contract rather than of this proof. The
  # contract used to compose `~/.contract-desktop` into every gui home out of the mode's `desktop`
  # parameter, so this comparison had to exclude that file by name or pass on a string the CONTRACT
  # wrote — the same emptiness as passing on the `mode` frozen into the manifest, one file over. The
  # parameter is published in the binding index now (ADR-0021), the contract composes no content at
  # all, and every difference this proof finds is therefore the USER's (ADR-0027).
  #
  # BOTH LANDING SITES are compared, because either alone fails the demonstration the other way
  # round: a home substituting `home.file` puts nothing in the profile, and one substituting
  # `home.packages` puts nothing in the dotfiles.
  #
  # Reads the SEAT system's homes with the rest of this file, and needs to: the aarch64 row is
  # headless, so it publishes ONE mode and there is no second home there to compare.
  modeSubstitutionIsLoadBearing =
    let
      # As above: this proof's name, written once and used everywhere it is said — including by the
      # eval refusal below, which is the last place in this file that used to spell a label by hand.
      proof = "mode-substitution-is-load-bearing";
      # Every (user, non-floor mode) pair the published homes hold on this system, paired against
      # that user's floor home. A member publishing NO floor home is skipped rather than reported:
      # declining the floor is a user's own decision (the shape an arm-tier gui-only user has), and
      # it leaves nothing to pair against.
      pairs = lib.concatMap (
        n:
        let
          published = homes.${system}.${n};
        in
        map (mode: {
          user = n;
          inherit mode;
          floor = published.${contract.floorMode};
          rich = published.${mode};
        }) (lib.filter (m: m != contract.floorMode) (lib.attrNames published))
      ) (lib.filter (n: homes.${system}.${n} ? ${contract.floorMode}) userNames);
      # The two places mode-specific content can LAND in a realized home.
      filesOf = home: "${home.activationPackage}/home-files";
      profileOf = home: "${home.activationPackage}/home-path";
    in
    assert lib.assertMsg (pairs != [ ]) (
      "${proof}: no member publishes a home for any mode BESIDE "
      + "${contract.floorMode} on ${system}, so there is no pair to compare and every "
      + "verdict below would be reached over nothing. Enable a second mode for a user the "
      + "${system} row builds."
    );
    pkgs.runCommand proof { } (
      contract.lib.mkProofPrelude proof
      + ''
        diverged=""
      ''
      + lib.concatMapStrings (p: ''
        # --- ${p.user}: ${contract.floorMode} vs ${p.mode} ---
        [ -d ${filesOf p.floor} ] || fail "${p.user}'s ${contract.floorMode} home realized no home-files tree at all — the comparison would be vacuous"
        [ -d ${filesOf p.rich} ] || fail "${p.user}'s ${p.mode} home realized no home-files tree at all — the comparison would be vacuous"
        [ -e ${profileOf p.floor} ] || fail "${p.user}'s ${contract.floorMode} home realized no home-path profile at all — the comparison would be vacuous"
        [ -e ${profileOf p.rich} ] || fail "${p.user}'s ${p.mode} home realized no home-path profile at all — the comparison would be vacuous"

        # The DOTFILES by content — the whole tree, with nothing set aside, because the contract
        # composes none of it (see above); and the PACKAGE PROFILE by resolved store path rather
        # than by walking two closures — a profile is input-addressed, so one package set is one
        # store path and two paths are two package sets. Minutes cheaper, same answer.
        if diff -r ${filesOf p.floor} ${filesOf p.rich} >/dev/null \
          && [ "$(readlink -f ${profileOf p.floor})" = "$(readlink -f ${profileOf p.rich})" ]; then
          echo "${p.user}: ${p.mode} receives exactly what ${contract.floorMode} receives — this mode substitutes no content (legitimate, ADR-0027)"
        else
          echo "${p.user}: ${p.mode} substitutes content against ${contract.floorMode}"
          diverged=yes
        fi
      '') pairs
      + ''
        [ -n "$diverged" ] || fail "NO reference user receives different content across the modes it runs in — every pair above realizes the same dotfiles AND the same package profile, so the one mechanism the per-mode build exists for has no worked example here. Restore the substitution: point a user's two modes at two DIFFERENT modules, each carrying the content that session can carry (see users/duo-a/user.nix)."
        touch $out
      ''
    );
in
# The whole check kit, folded over the members in ONE call — yielding `home-confinement-<user>`
# and `home-eval-<user>` per member plus one `identity-posture`, so this file names no check and
# no user:
#
#   - CONFINEMENT, per user: the contract's own suite proves the UMBRELLA declares no system
#     channel; that says nothing about whether the fleet's imports smuggled one back in. The check
#     probes the real builder handed in — an out-of-universe option must be unexpressible while a
#     legitimate home option still evaluates.
#   - HOME EVALUABILITY, per user: every home the fleet publishes for that user, on every system in
#     `homes`, forces to a derivation. The failing arch is always the one nothing builds by default
#     there, so an x86_64-only package added to shared content throws HERE rather than on the
#     aarch64 seat hours later.
#   - The CREDENTIAL POSTURE over the members' identities, ENFORCED rather than merely documented:
#     a member added with a `$6$` hash fails the flake check rather than being noticed in review,
#     or not.
#
# Each of those is a check in its own right, and stays one: they are what a CONSUMER runs, named
# per user so a failing member is named by the check that failed. The report beside them is the
# teaching extras, which are this repo's alone.
contract.lib.mkMemberChecks {
  inherit
    pkgs
    members
    homes
    buildHome
    require
    ;
}
// {
  # …and the three extras, through the ONE report the check kit owns — the same report the
  # conformance suite and `examples/fleet/checks.nix` deliver their verdicts through. The two
  # execution proofs keep the names they always had, so the `error: Cannot build …` a reader meets
  # when one fails still says which.
  reference-user-fleet-checks = contract.lib.mkClaimReport {
    inherit pkgs claims;
    name = "reference-user-fleet-checks";
    title = "reference user fleet — the teaching extras (what a real users repo does not carry)";
    proofs = {
      shared-code-per-user-data = sharedCodePerUserData;
      mode-substitution-is-load-bearing = modeSubstitutionIsLoadBearing;
    };
  };
}
