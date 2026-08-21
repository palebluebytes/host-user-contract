# The load-bearing refusals, asserted on what they SAY (issue #64).
#
# `conformance/diagnostics.nix` proves the SHAPE of a message at its constructor. This domain proves
# the other half — that the guards which actually matter fill that shape with the right facts —
# for the sites whose message IS the diagnosis rather than a label on one:
#
#   the bind's two refusals            the sharpest case, because the message is the REQUIREMENT.
#                                      "this user runs nothing this host runs" and "the producer
#                                      built nothing here for a mode both sides wanted" have
#                                      different causes, different fixes and different owners — and
#                                      under `tryEval` they are one indistinguishable failure.
#   the home matrix's mode-row guard   write a key that is not a mode and the system silently bakes
#                                      the FULL set while reading as restricted. Nothing else
#                                      distinguishes that from a working restriction.
#   the coverage guard                 a member the mapper skipped loses its home-eval check
#                                      entirely, and a missing check reads EXACTLY like a passing
#                                      one. The message is the only thing that says otherwise.
#   the bind-setting collision         fires only if a feature is ever named `source`, so it will be
#                                      read exactly once, by somebody with no context for it.
#
# HOW, given that `tryEval` discards messages. Each of these kernels is SPLIT (see
# `diagnostics.nix`), so this domain reads what the kernel WOULD have said about input it would
# refuse. No assertion is provoked and no failure is caught: a refusal is just a string here.
#
# WHAT IS ASSERTED, AND WHAT DELIBERATELY IS NOT. Structure, never prose. Each case names the
# offenders that must appear in its `problem` clause and nothing about the wording around them, so a
# message stays free to be improved and cannot quietly stop naming who broke. That is this repo's
# "each error names the offending SYSTEMS and MODES, not a count" convention, which until now
# nothing enforced.
{
  lib,
  diag,
  homeMatrixUnguarded,
  selectionUnguarded,
  bindModeUnguarded,
  memberChecksUnguarded,
  featureNamesUnguarded,
  floorUnguarded,
}:
let
  # A synthetic three-mode world. Three rather than two because the contract's own registry has one
  # non-floor mode, so "more than one rich mode" and "these modes cut every entry of the bound" are
  # not expressible against it — the same reason both kernels take their bound explicitly.
  bound = [
    "cli"
    "gui"
    "phone"
  ];

  # The two readings of a refusal. `message` is what the reader gets; `problem` is the clause that
  # must carry the offenders, and asserting against it rather than the whole message is not
  # pedantry: several `why`s name the modes of this contract or the features a host may afford as
  # BACKGROUND, so a guard that stopped naming its own offenders would still match them there and
  # read as though it named them. Scoped to the clause, it cannot.
  messageOf = c: diag.firstRefusal c.checks;
  problemOf = c: (diag.firstFailing c.checks).problem;

  # ── The cases ────────────────────────────────────────────────────────────────────────────────
  # Each is one refusal, with the offenders its `problem` MUST name.
  cases = [
    # THE BIND, refusal one — the matrix subtraction. `ada` runs in the phone mode and this host runs
    # it, but the producer's matrix took phone away for this system, so nothing built the home. Left
    # unsaid, selection falls back to the floor and activates a terminal home on a graphical seat
    # with no output at all. The message must name the user, the mode that went missing and the
    # system whose matrix row did it — those three are the edit.
    #
    # The missing mode is claimed as a RENDERED LIST rather than a bare name, and it has to be: a
    # subtracted mode is by construction a member of both sets this clause already names, so
    # `hasInfix "phone"` would match the host's run set and pass even if the subtraction itself
    # stopped being reported. `[phone]` appears only where the subtracted set is rendered.
    {
      name = "the matrix-subtraction refusal names the user, the missing mode and the system";
      who = "bindContractUser";
      checks =
        (bindModeUnguarded {
          username = "ada";
          system = "x86_64-linux";
          affordances = { };
          runs = bound;
          userModes = [
            "gui"
            "phone"
          ];
          published = [ "gui" ];
        }).checks;
      offenders = [
        "ada"
        "x86_64-linux"
        (diag.showList [ "phone" ])
      ];
    }
    # …and the affordance guard beside it, which is the same failure mode one rung down: a
    # misspelled feature affords nothing and the account comes up quietly less powerful than the
    # host meant. It must name what was misspelled.
    {
      name = "an unknown affordance is named, rather than silently conferring nothing";
      who = "bindContractUser";
      checks =
        (bindModeUnguarded {
          username = "ada";
          system = "x86_64-linux";
          affordances = {
            sudp = true;
          };
          runs = [ "cli" ];
          userModes = [ "cli" ];
          published = [ "cli" ];
        }).checks;
      offenders = [ "sudp" ];
    }
    # SELECTION, refusal one: nothing common. The message must name the user and BOTH sides — what
    # the host runs and what the user publishes here — because the fix depends on which of them is
    # wrong, and they have different owners.
    {
      name = "selection names the user, what the host runs, and what the user publishes";
      who = "bindContractUser";
      checks =
        (selectionUnguarded {
          who = "bindContractUser";
          subject = "ada";
          floor = "cli";
          runs = [ "cli" ];
          published = [ "gui" ];
        }).checks;
      offenders = [
        "ada"
        "cli"
        "gui"
      ];
    }
    # SELECTION, refusal two: two rich modes, which are incomparable by design. Naming BOTH is the
    # whole content — the reader has to remove one, and a count would not say which two.
    {
      name = "selection names both rich modes when it cannot break the tie";
      who = "bindContractUser";
      checks =
        (selectionUnguarded {
          who = "bindContractUser";
          subject = "ada";
          floor = "cli";
          runs = [
            "gui"
            "phone"
          ];
          published = [
            "gui"
            "phone"
          ];
        }).checks;
      offenders = [
        "ada"
        "gui"
        "phone"
      ];
    }
    # THE HOME MATRIX, the one the issue leads with. `sudo` is a feature, not a mode: it rides the
    # bind and never keys a home, so a row naming it takes nothing away and the system bakes
    # everything while reading as restricted. The clause must name the system AND the stray key.
    {
      name = "the home matrix names the system and the setting that is not a mode";
      who = "mkHomeMatrix";
      checks =
        (homeMatrixUnguarded {
          systems = {
            "x86_64-linux" = {
              sudo = false;
            };
          };
          upperBound = bound;
        }).checks;
      offenders = [
        "x86_64-linux"
        "sudo"
      ];
    }
    # A row that subtracts everything. The system and the modes it took away are both needed: which
    # row to edit, and which of its entries did the cutting.
    {
      name = "the home matrix names the system whose row empties it, and the modes that cut it";
      who = "mkHomeMatrix";
      checks =
        (homeMatrixUnguarded {
          systems = {
            "aarch64-linux" = {
              cli = false;
              gui = false;
              phone = false;
            };
          };
          upperBound = bound;
        }).checks;
      offenders = [
        "aarch64-linux"
        "cli"
        "gui"
        "phone"
      ];
    }
    # A row entry that is not a bool. `"false"` is the one that matters — it is truthy in the
    # reader's head and does nothing here — so the message names the system and the setting.
    {
      name = "the home matrix names the system and the non-boolean setting";
      who = "mkHomeMatrix";
      checks =
        (homeMatrixUnguarded {
          systems = {
            "x86_64-linux" = {
              gui = "false";
            };
          };
          upperBound = bound;
        }).checks;
      offenders = [
        "x86_64-linux"
        "gui"
      ];
    }
    # THE ORDER CLAIM, disguised as a case. A row that is not an attrset cannot be scanned for
    # non-booleans — `lib.attrNames` on a list throws — so this input reaches a named diagnosis only
    # because the chain short-circuits at the first failure, exactly as the `assert` chain it
    # replaced did. If `firstFailing` ever evaluated every `ok`, this case would die on a raw Nix
    # error instead, which is the failure the guard exists to prevent.
    {
      name = "a malformed row is reported as a malformed row, not as a raw eval error";
      who = "mkHomeMatrix";
      checks =
        (homeMatrixUnguarded {
          systems = {
            "x86_64-linux" = [ ];
          };
          upperBound = bound;
        }).checks;
      offenders = [ "x86_64-linux" ];
    }
    # THE COVERAGE GUARD. `cleo` is in the member set and has no home on this system; `ada` does.
    # The message must name the missing PAIR — the control below then asserts it does not name the
    # covered member, which is what makes this "names the offenders" rather than "names everybody".
    {
      name = "the coverage guard names the system/member pair that has no home";
      who = "mkMemberChecks";
      checks =
        (memberChecksUnguarded {
          members = {
            ada = { };
            cleo = { };
          };
          homes = {
            "x86_64-linux" = {
              ada = { };
            };
          };
        }).checks;
      offenders = [ "x86_64-linux/cleo" ];
    }
    # …and the shape guard beneath it, which exists so the coverage diagnosis stays honest: an entry
    # that cannot be read must not be reported as one that holds nobody.
    {
      name = "a malformed `homes` entry names the system, rather than reading as an uncovered one";
      who = "mkMemberChecks";
      checks =
        (memberChecksUnguarded {
          members = {
            ada = { };
          };
          homes = {
            "aarch64-linux" = [ ];
          };
        }).checks;
      offenders = [ "aarch64-linux" ];
    }
    # THE BIND-SETTING COLLISION — the message that will be read exactly once, by whoever named a
    # feature `source`, with no context for it. It must name the colliding name; "a feature collides
    # with a setting" would send them to read `bindSettings` to find out which.
    {
      name = "the bind-setting collision names the feature that collides";
      who = "features";
      checks =
        (featureNamesUnguarded {
          source = { };
          sudo = { };
        }).checks;
      offenders = [ "source" ];
    }
    # The floor, in both directions. With NONE, the message names the modes the registry does have —
    # a reader who set no floor needs the candidate list, not the fact that the count was zero.
    {
      name = "a registry with no floor names the modes it does have";
      who = "modes";
      checks =
        (floorUnguarded {
          cli = { };
          gui = { };
        }).checks;
      offenders = [
        "cli"
        "gui"
      ];
    }
    # …and with TWO, it names the two claiming it — which is the edit to make.
    {
      name = "a registry with two floors names both of them";
      who = "modes";
      checks =
        (floorUnguarded {
          cli = {
            floor = true;
          };
          gui = {
            floor = true;
          };
          phone = { };
        }).checks;
      offenders = [
        "cli"
        "gui"
      ];
    }
  ];

  # ── The two bind refusals, side by side ──────────────────────────────────────────────────────
  # Same host, same user, same shape of disappointment — and two entirely different causes. This
  # pair is what the distinguishability claims below are about.
  #
  # MATRIX-SUBTRACTED: both sides wanted gui, and the producer's row for this system took it away.
  # The published set is empty in consequence, which is exactly the case where selection's own
  # refusal would fire too and name the wrong cause — hence the bind checking first.
  subtracted = bindModeUnguarded {
    username = "ada";
    system = "x86_64-linux";
    affordances = { };
    runs = [
      "cli"
      "gui"
    ];
    userModes = [ "gui" ];
    published = [ ];
  };
  # UNSUPPORTED MODE: nothing was taken away — this user simply runs nothing this host runs.
  unsupported = selectionUnguarded {
    who = "bindContractUser";
    subject = "ada";
    floor = "cli";
    runs = [ "cli" ];
    published = [ "gui" ];
  };
in
{
  assertions =
    # One claim per case: the `problem` clause names its offenders. This is the "names the
    # offenders, not a count" convention, enforced.
    map (c: {
      name = "refusals: ${c.name}";
      ok =
        let
          p = problemOf c;
        in
        p != null && lib.all (o: lib.hasInfix o p) c.offenders;
    }) cases

    ++ [
      # ── The bind's two refusals are DISTINGUISHABLE ────────────────────────────────────────
      # The acceptance criterion this domain exists to make provable. Both fire for a user whose
      # session this host cannot give them, both are attributed to `bindContractUser` — so `who` is
      # NOT what tells them apart, and under `tryEval` neither is anything else. The clause is.
      {
        name = "refusals: the matrix-subtraction and unsupported-mode refusals are different messages";
        ok = messageOf subtracted != messageOf unsupported;
      }
      # …and each names its OWN cause rather than the other's. The matrix one names the system whose
      # row did it, because the fix is an edit to that row in the producer's repo; the unsupported
      # one names neither a system nor a matrix, because there is nothing there to edit — the fix is
      # the host's affordances or the user's declaration.
      {
        name = "refusals: only the matrix-subtraction refusal names a system and the matrix that took the mode";
        ok =
          let
            m = problemOf subtracted;
            u = problemOf unsupported;
          in
          lib.hasInfix "x86_64-linux" m
          && lib.hasInfix "home matrix" m
          && !lib.hasInfix "x86_64-linux" u
          && !lib.hasInfix "home matrix" u;
      }
      # WHICH of the two a reader gets when both would fire is the assert order inside
      # `bindContractUser`, not a property of either kernel — `conformance/turnkey-bind.nix` proves
      # that at the bind. What is provable here is that both DO fire on this input, which is what
      # makes the order matter at all: with an emptied published set, selection has its own refusal
      # ready and it would name the wrong cause.
      {
        name = "refusals: an emptied published set arms BOTH refusals, which is why the bind checks first";
        ok = messageOf subtracted != null && messageOf unsupported != null;
      }

      # ── The structural claims, over every case at once ─────────────────────────────────────
      # Each refusal names its refuser first. A reader who cannot tell which function refused
      # cannot go and look at it, and `who` is deliberately the PUBLIC name — the home-matrix
      # kernel is internal, so it says `mkHomeMatrix`.
      {
        name = "refusals: every refusal is prefixed with the public name of what refused";
        ok = lib.all (c: messageOf c != null && lib.hasPrefix "${c.who}: " (messageOf c)) cases;
      }
      # …and every one is a finished single-line sentence, with no doubled terminator, no doubled
      # space and no space before a full stop. These are the malformations a SITE can still cause
      # after the constructor has done its job — a `fix` written with a leading space, a `problem`
      # that already ended in punctuation of its own.
      #
      # What this cannot see is the constructor's own historical bug, where `problem` ran into `why`
      # with no terminator: once the clauses are one string there is no boundary left to check, and a
      # capital letter mid-message is ordinary here ("is a BOOL", "A FEATURE names a grant"). That is
      # why `conformance/diagnostics.nix` proves the joins where the clauses are still separate, and
      # this domain proves the facts. Neither half covers the other.
      {
        name = "refusals: every refusal is one terminated line, with no doubled or orphaned punctuation";
        ok = lib.all (
          c:
          let
            m = messageOf c;
          in
          m != null
          && lib.hasSuffix "." m
          && !lib.hasInfix "  " m
          && !lib.hasInfix ".." m
          && !lib.hasInfix " ." m
          && !lib.hasInfix "\n" m
        ) cases;
      }
      # NAMES, NOT EVERYBODY. The coverage guard's whole value is that it points at the gap, so a
      # message that named the covered member too would be a list of the member set with extra
      # steps. This is the sharp end of "not a count": a count and a full roster are the same
      # uselessness.
      {
        name = "refusals: the coverage guard names the uncovered member and not the covered one";
        ok =
          let
            m =
              diag.firstRefusal
                (memberChecksUnguarded {
                  members = {
                    ada = { };
                    cleo = { };
                  };
                  homes = {
                    "x86_64-linux" = {
                      ada = { };
                    };
                  };
                }).checks;
          in
          lib.hasInfix "cleo" m && !lib.hasInfix "ada" m;
      }
      # The empty-input refusals carry the VACUITY rationale rather than restating it — the argument
      # that a fold over nothing reports success while doing no work. There are no offenders to name
      # in this direction, so the rationale is the whole content.
      {
        name = "refusals: an empty matrix and an empty member set both carry the vacuity rationale";
        ok =
          let
            emptyMatrix =
              diag.firstRefusal
                (homeMatrixUnguarded {
                  systems = { };
                  upperBound = bound;
                }).checks;
            emptyMembers =
              diag.firstRefusal
                (memberChecksUnguarded {
                  members = { };
                  homes = {
                    "x86_64-linux" = { };
                  };
                }).checks;
          in
          lib.hasInfix "NOTHING while every output stayed green" emptyMatrix
          && lib.hasInfix "NOTHING while every output stayed green" emptyMembers;
      }
      # The mode-row guard's `why` names the modes that DO exist — asserted apart from the offender
      # claim above precisely because it is a different kind of fact. A reader who wrote `sudo` in a
      # matrix row does not yet know the difference between a feature and a mode, so the candidate
      # list is what turns the diagnosis into a fix.
      {
        name = "refusals: the mode-row guard also names the modes a row MAY take away";
        ok =
          let
            m =
              diag.firstRefusal
                (homeMatrixUnguarded {
                  systems = {
                    "x86_64-linux" = {
                      sudo = false;
                    };
                  };
                  upperBound = bound;
                }).checks;
          in
          lib.all (mode: lib.hasInfix mode m) bound;
      }

      # ── The controls ───────────────────────────────────────────────────────────────────────
      # Every claim above reads a refusal, so all of them would still pass if these kernels refused
      # EVERYTHING. These are the other direction: input each one accepts produces no refusal at
      # all, and the verdict is the real one.
      {
        name = "refusals: a well-formed matrix refuses nothing, and subtracts what its row names";
        ok =
          let
            it = homeMatrixUnguarded {
              systems = {
                "x86_64-linux" = { };
                "aarch64-linux" = {
                  gui = false;
                };
              };
              upperBound = bound;
            };
          in
          diag.firstRefusal it.checks == null
          && it.matrix."x86_64-linux" == bound
          &&
            it.matrix."aarch64-linux" == [
              "cli"
              "phone"
            ];
      }
      {
        name = "refusals: a selection with one rich mode refuses nothing and yields the rich mode";
        ok =
          let
            it = selectionUnguarded {
              who = "bindContractUser";
              subject = "ada";
              floor = "cli";
              runs = [
                "cli"
                "gui"
              ];
              published = [
                "cli"
                "gui"
              ];
            };
          in
          diag.firstRefusal it.checks == null && it.mode == "gui";
      }
      {
        name = "refusals: a bind whose published set covers what both sides run refuses nothing";
        ok =
          diag.firstRefusal
            (bindModeUnguarded {
              username = "ada";
              system = "x86_64-linux";
              affordances = { };
              runs = [
                "cli"
                "gui"
              ];
              userModes = [ "gui" ];
              published = [ "gui" ];
            }).checks == null;
      }
      {
        name = "refusals: fully covered members refuse nothing, and the systems are `homes`' own";
        ok =
          let
            it = memberChecksUnguarded {
              members = {
                ada = { };
              };
              homes = {
                "x86_64-linux" = {
                  ada = { };
                };
              };
            };
          in
          diag.firstRefusal it.checks == null && it.systems == [ "x86_64-linux" ];
      }
      {
        name = "refusals: a registry with no collision and exactly one floor refuses nothing";
        ok =
          let
            reg = {
              cli = {
                floor = true;
              };
              gui = { };
            };
          in
          diag.firstRefusal (featureNamesUnguarded { sudo = { }; }).checks == null
          && diag.firstRefusal (floorUnguarded reg).checks == null
          && (floorUnguarded reg).floor == "cli";
      }
    ];
}
