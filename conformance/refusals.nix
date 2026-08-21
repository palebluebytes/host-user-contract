# The load-bearing refusals, asserted on what they SAY (issue #64).
#
# `conformance/diagnostics.nix` proves the SHAPE of a message at its constructor. This domain proves
# the other half — that the guards which actually matter fill that shape with the right facts —
# for the four whose message IS the diagnosis rather than a label on it:
#
#   the home matrix's mode-row guard   write a key that is not a mode and the system silently bakes
#                                      the FULL set while reading as restricted. Nothing else
#                                      distinguishes that from a working restriction.
#   the coverage guard                 a member the mapper skipped loses its home-eval check
#                                      entirely, and a missing check reads EXACTLY like a passing
#                                      one. The message is the only thing that says otherwise.
#   selection's two refusals           "this user runs nothing this host runs" and "the producer
#                                      built nothing here for a mode both sides wanted" are one
#                                      `tryEval` failure with two owners and two different fixes.
#   the bind-setting collision         fires only if a feature is ever named `source`, so it will be
#                                      read exactly once, by somebody with no context for it.
#
# HOW, given that `tryEval` discards messages. Each of these kernels holds its guard chain apart
# from its work (`diag.firstRefusal` — see `diagnostics.nix`), so this domain reads what the kernel
# WOULD have said about input it would refuse. No assertion is provoked and no failure is caught:
# a refusal is just a string here.
#
# WHAT IS ASSERTED, AND WHAT DELIBERATELY IS NOT. Structure, never prose. Each case names the
# offenders that must appear and nothing about the wording around them, so a message stays free to
# be improved and cannot quietly stop naming who broke. That is this repo's "each error names the
# offending SYSTEMS and MODES, not a count" convention, which until now nothing enforced.
{
  lib,
  diag,
  homeMatrixWith,
  selectionWith,
  memberChecksWith,
  featureNamesWith,
  floorWith,
}:
let
  # The refusal a guard chain would raise, as the reader would meet it.
  refusalIn = it: diag.firstRefusal it.checks;
  # …and selection's, which is a branch rather than a chain: one of two refusals, or a verdict.
  selectionRefusal = args: diag.say (selectionWith args).refusal;

  # A synthetic three-mode world. Three rather than two because the contract's own registry has one
  # non-floor mode, so "more than one rich mode" and "these modes cut every entry of the bound" are
  # not expressible against it — the same reason both kernels take their bound explicitly.
  bound = [
    "cli"
    "gui"
    "phone"
  ];

  # ── The cases ────────────────────────────────────────────────────────────────────────────────
  # Each is one refusal, with the offenders its message MUST name. `offenders` is the whole claim
  # about content; everything else about the message is structure, asserted over all cases below.
  cases = [
    # THE ONE THE ISSUE LEADS WITH. `sudo` is a feature, not a mode: it rides the bind and never
    # keys a home, so a row naming it takes nothing away and the system bakes everything while
    # reading as restricted. The message must name the system AND the stray key — and the modes
    # that ARE available, since a reader who wrote `sudo` there does not know the difference yet.
    {
      name = "the home matrix names the system, the stray key, and the modes that exist";
      who = "mkHomeMatrix";
      message = refusalIn (homeMatrixWith {
        systems = {
          "x86_64-linux" = {
            sudo = false;
          };
        };
        upperBound = bound;
      });
      offenders = [
        "x86_64-linux"
        "sudo"
        "cli"
        "gui"
        "phone"
      ];
    }
    # A row that subtracts everything. The system and the modes it took away are both needed: which
    # row to edit, and which of its entries did the cutting.
    {
      name = "the home matrix names the system whose row empties it, and the modes that cut it";
      who = "mkHomeMatrix";
      message = refusalIn (homeMatrixWith {
        systems = {
          "aarch64-linux" = {
            cli = false;
            gui = false;
            phone = false;
          };
        };
        upperBound = bound;
      });
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
      message = refusalIn (homeMatrixWith {
        systems = {
          "x86_64-linux" = {
            gui = "false";
          };
        };
        upperBound = bound;
      });
      offenders = [
        "x86_64-linux"
        "gui"
      ];
    }
    # THE ORDER CLAIM, disguised as a case. A row that is not an attrset cannot be scanned for
    # non-booleans — `lib.attrNames` on a list throws — so this input reaches a named diagnosis only
    # because the chain short-circuits at the first failure, exactly as the `assert` chain it
    # replaced did. If `firstRefusal` ever evaluated every `ok`, this case would die on a raw Nix
    # error instead, which is the failure the guard exists to prevent.
    {
      name = "a malformed row is reported as a malformed row, not as a raw eval error";
      who = "mkHomeMatrix";
      message = refusalIn (homeMatrixWith {
        systems = {
          "x86_64-linux" = [ ];
        };
        upperBound = bound;
      });
      offenders = [ "x86_64-linux" ];
    }
    # SELECTION, refusal one: nothing common. The message must name the user and BOTH sides —
    # what the host runs and what the user publishes here — because the fix depends on which of
    # them is wrong, and they have different owners.
    {
      name = "selection names the user, what the host runs, and what the user publishes";
      who = "bindContractUser";
      message = selectionRefusal {
        who = "bindContractUser";
        subject = "ada";
        floor = "cli";
        runs = [ "cli" ];
        published = [ "gui" ];
      };
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
      message = selectionRefusal {
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
      };
      offenders = [
        "ada"
        "gui"
        "phone"
      ];
    }
    # THE COVERAGE GUARD. `cleo` is in the member set and has no home on this system; `ada` does.
    # The message must name the missing PAIR — the control below then asserts it does not name the
    # covered member, which is what makes this "names the offenders" rather than "names everybody".
    {
      name = "the coverage guard names the system/member pair that has no home";
      who = "mkMemberChecks";
      message = refusalIn (memberChecksWith {
        members = {
          ada = { };
          cleo = { };
        };
        homes = {
          "x86_64-linux" = {
            ada = { };
          };
        };
      });
      offenders = [ "x86_64-linux/cleo" ];
    }
    # …and the shape guard beneath it, which exists so the coverage diagnosis stays honest: an entry
    # that cannot be read must not be reported as one that holds nobody.
    {
      name = "a malformed `homes` entry names the system, rather than reading as an uncovered one";
      who = "mkMemberChecks";
      message = refusalIn (memberChecksWith {
        members = {
          ada = { };
        };
        homes = {
          "aarch64-linux" = [ ];
        };
      });
      offenders = [ "aarch64-linux" ];
    }
    # THE BIND-SETTING COLLISION — the message that will be read exactly once, by whoever named a
    # feature `source`, with no context for it. It must name the colliding name; "a feature collides
    # with a setting" would send them to read `bindSettings` to find out which.
    {
      name = "the bind-setting collision names the feature that collides";
      who = "features";
      message = refusalIn (featureNamesWith {
        source = { };
        sudo = { };
      });
      offenders = [ "source" ];
    }
    # The floor, in both directions. With NONE, the message names the modes the registry does have —
    # a reader who set no floor needs the candidate list, not the fact that the count was zero.
    {
      name = "a registry with no floor names the modes it does have";
      who = "modes";
      message = refusalIn (floorWith {
        cli = { };
        gui = { };
      });
      offenders = [
        "cli"
        "gui"
      ];
    }
    # …and with TWO, it names the two claiming it — which is the edit to make.
    {
      name = "a registry with two floors names both of them";
      who = "modes";
      message = refusalIn (floorWith {
        cli = {
          floor = true;
        };
        gui = {
          floor = true;
        };
        phone = { };
      });
      offenders = [
        "cli"
        "gui"
      ];
    }
  ];

  # Does this message name every offender it promised to?
  names = c: c.message != null && lib.all (o: lib.hasInfix o c.message) c.offenders;
in
{
  assertions =
    # One claim per case: the message names its offenders. This is the "names the offenders, not a
    # count" convention, enforced.
    map (c: {
      name = "refusals: ${c.name}";
      ok = names c;
    }) cases

    ++ [
      # ── The structural claims, over every case at once ─────────────────────────────────────
      # Each refusal names its refuser first. A reader who cannot tell which function refused
      # cannot go and look at it, and `who` is deliberately the PUBLIC name — the home-matrix
      # kernel is internal, so it says `mkHomeMatrix`.
      {
        name = "refusals: every refusal is prefixed with the public name of what refused";
        ok = lib.all (c: c.message != null && lib.hasPrefix "${c.who}: " c.message) cases;
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
          c.message != null
          && lib.hasSuffix "." c.message
          && !lib.hasInfix "  " c.message
          && !lib.hasInfix ".." c.message
          && !lib.hasInfix " ." c.message
          && !lib.hasInfix "\n" c.message
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
            m = refusalIn (memberChecksWith {
              members = {
                ada = { };
                cleo = { };
              };
              homes = {
                "x86_64-linux" = {
                  ada = { };
                };
              };
            });
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
            emptyMatrix = refusalIn (homeMatrixWith {
              systems = { };
              upperBound = bound;
            });
            emptyMembers = refusalIn (memberChecksWith {
              members = { };
              homes = {
                "x86_64-linux" = { };
              };
            });
          in
          lib.hasInfix "NOTHING while every output stayed green" emptyMatrix
          && lib.hasInfix "NOTHING while every output stayed green" emptyMembers;
      }

      # ── The controls ───────────────────────────────────────────────────────────────────────
      # Every claim above reads a refusal, so all of them would still pass if these kernels refused
      # EVERYTHING. These are the other direction: input each one accepts produces no refusal at
      # all, and the verdict is the real one.
      {
        name = "refusals: a well-formed matrix refuses nothing, and subtracts what its row names";
        ok =
          let
            it = homeMatrixWith {
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
        name = "refusals: a selection with one rich mode yields the mode and no refusal";
        ok =
          let
            it = selectionWith {
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
          !(it ? refusal) && it.mode == "gui";
      }
      {
        name = "refusals: fully covered members refuse nothing, and the systems are `homes`' own";
        ok =
          let
            it = memberChecksWith {
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
          diag.firstRefusal (featureNamesWith { sudo = { }; }).checks == null
          && diag.firstRefusal (floorWith reg).checks == null
          && (floorWith reg).floor == "cli";
      }
    ];
}
