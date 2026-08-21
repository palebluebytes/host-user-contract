# diagnostics.nix — the SHAPE of a refusal, proven as a unit (issue #64).
#
# WHY THIS DOMAIN EXISTS. Every other refusal in this suite is driven through `builtins.tryEval`,
# which returns `{ success = false; value = false; }` and DISCARDS the message. So fifty guard
# sites prove that things fail and nothing proves what a reader is told when they do — and a
# reader who has hit a guard has already lost, so the message is the whole of what they get.
#
# `diagnostics.nix` is the one place where that is fixable, because it is the one CONSTRUCTOR: every
# message in this repo is `diag.say`'s output, so the shape rules — the `<who>: ` prefix, one
# terminator per clause, `[a, b]` for a list, the vacuity rationale — are properties of a pure
# function that can simply be called. No `tryEval`, no assertion, no guard.
#
# THE BUG THIS WOULD HAVE CAUGHT. The first version of the module ran `problem` into `why` with only
# a space between them, producing "…x86_64-linux [sudo] The modes of this contract are…" across
# EVERY message in the repo. The full suite passed; it was found by evaluating a failing case by
# hand. The `problem` and `why` claims below are that bug, written down.
#
# WHY THE FACTS HERE ARE SYNTHETIC. The claims assert message text exactly — which would be
# intolerable against a real guard, where it would freeze wording that should stay free to improve.
# It is fine here because every input below is this file's own invention: `who = "who"` is nobody,
# so an exact claim about the output pins the SHAPE and pins no prose. The claims about real
# messages are the other half of this domain's answer, and they assert structure only
# (`./refusals.nix`).
{
  lib,
  diag,
}:
let
  # The message a reader would actually see, for facts that name nothing real.
  says = args: diag.say ({ who = "who"; } // args);
  # The two malformations the constructor exists to make unwriteable, as predicates over any
  # message: a clause that ran into the next one, and a clause terminated twice.
  ranOn = m: lib.hasInfix "  " m;
  doubled = m: lib.hasInfix ".." m;
  # `must`/`stop` REFUSE by throwing, so reaching them needs the same `tryEval` as any other guard —
  # which is the point: what is proven here is that they refuse at all, and `say` above is what
  # proves what they would have said.
  refuses = thunk: !(builtins.tryEval thunk).success;

  # A guard chain with nothing wrong, and two things that are — for the `firstFailing`/`mustAll`
  # claims at the end. Two bad ones because "the FIRST failure is reported" needs a second to not
  # report.
  passing = [
    {
      ok = true;
      who = "who";
      problem = "unreachable";
    }
    {
      ok = true;
      who = "who";
      problem = "also unreachable";
    }
  ];
  firstBad = {
    ok = false;
    who = "who";
    problem = "the first thing wrong";
  };
  secondBad = {
    ok = false;
    who = "who";
    problem = "the second thing wrong";
  };
in
{
  assertions = [
    # ── say: the prefix ──────────────────────────────────────────────────────────────────────
    # A message names its refuser FIRST, and the separator is `": "`. This is the one part of the
    # shape a reader uses before reading anything else — it is how they know which function to go
    # and look at — and it is the part a site can no longer get wrong because a site no longer
    # writes it.
    {
      name = "diagnostics: say prefixes the message with `<who>: `";
      ok = says { problem = "something is wrong"; } == "who: something is wrong.";
    }

    # ── say: one terminator per clause ───────────────────────────────────────────────────────
    # `problem` is written as a CLAUSE — sites write "the matrix is empty", never "The matrix is
    # empty." — so the terminator is added here, once, rather than being a rule thirty sites keep.
    {
      name = "diagnostics: say terminates a `problem` that ends in no punctuation";
      ok = lib.hasSuffix "empty." (says {
        problem = "the matrix is empty";
      });
    }
    # …and does not terminate it twice. A site that DID write a sentence gets its own punctuation
    # back unchanged, so the rule degrades gracefully rather than producing "empty..".
    {
      name = "diagnostics: say leaves a `problem` that ends in `.` alone";
      ok = says { problem = "the matrix is empty."; } == "who: the matrix is empty.";
    }
    # The other two terminators the module recognises, so a question and an exclamation survive a
    # trip through it as written.
    {
      name = "diagnostics: say leaves a `?` or `!` ending alone";
      ok =
        says { problem = "did you mean the mode?"; } == "who: did you mean the mode?"
        && says { problem = "never write this!"; } == "who: never write this!";
    }
    # A `problem` ending in a RENDERED LIST is the common case (most messages name their offenders
    # last), and `]` is not punctuation — so it gets a terminator, which is what stops the list from
    # running into the sentence after it.
    {
      name = "diagnostics: say terminates a `problem` that ends in a rendered list";
      ok =
        says { problem = "offending modes: ${diag.showList [ "gui" ]}"; } == "who: offending modes: [gui].";
    }

    # ── say: THE REGRESSION ──────────────────────────────────────────────────────────────────
    # The actual bug, written down: `problem` ran into `why` with only a space between them. Every
    # message in the repo read "…[sudo] The modes of this contract are…" and the whole suite stayed
    # green, because nothing anywhere looked at a message.
    {
      name = "diagnostics: say separates `problem` from `why` with a terminator, not a bare space";
      ok =
        says {
          problem = "the matrix is empty";
          why = "An empty matrix would build nothing";
        } == "who: the matrix is empty. An empty matrix would build nothing.";
    }
    # The same joint one rung further along, and the full four-part message: who, problem, why, fix,
    # in that order. The ORDER is a claim of its own — a reader gets what is wrong, then what it
    # would cost to allow it, then what to write instead — and nothing else in the repo states it.
    {
      name = "diagnostics: say renders who, problem, why, fix in that order, each terminated once";
      ok =
        says {
          problem = "the matrix is empty";
          why = "An empty matrix would build nothing";
          fix = "Name a system";
        } == "who: the matrix is empty. An empty matrix would build nothing. Name a system.";
    }

    # ── say: the optional clauses ────────────────────────────────────────────────────────────
    # `why` and `fix` are optional, and omitting one must leave NO trace — no orphan separator, no
    # trailing space. A message that ends in whitespace reads as truncated.
    {
      name = "diagnostics: an omitted `why`/`fix` leaves no separator or trailing space";
      ok =
        let
          m = says { problem = "the matrix is empty"; };
        in
        m == "who: the matrix is empty." && !ranOn m;
    }
    # A `fix` with no `why` closes the gap rather than leaving one: the clauses are independent, not
    # a sequence where dropping the middle one shows.
    {
      name = "diagnostics: a `fix` with no `why` follows the problem directly";
      ok =
        says {
          problem = "the matrix is empty";
          fix = "Name a system";
        } == "who: the matrix is empty. Name a system.";
    }

    # ── say: the two malformations, over every combination ───────────────────────────────────
    # The claims above pin specific outputs; this one is the net under them. Every combination of
    # present/absent clauses, checked for the run-on and the doubled terminator — so a future
    # rewrite of the separator logic cannot pass the cases above by accident and break a case
    # nobody thought to write.
    {
      name = "diagnostics: no combination of clauses produces a run-on or a doubled terminator";
      ok =
        let
          # Each clause in a terminated and an unterminated spelling, plus absent, since the
          # interesting failures are at the joins between them.
          variants = [
            null
            "a clause"
            "A sentence."
          ];
          messages = lib.concatMap (
            why:
            lib.concatMap (
              fix:
              map (problem: says { inherit problem why fix; }) [
                "a problem"
                "A problem."
              ]
            ) variants
          ) variants;
        in
        !lib.any ranOn messages && !lib.any doubled messages;
    }

    # ── the renderers ────────────────────────────────────────────────────────────────────────
    # `[a, b]` — spelled once so it never becomes `a; b` in the next message a reader meets. The
    # empty case is included because several offender lists are empty in the passing direction and
    # a message that renders `[]` is a message whose predicate is wrong.
    {
      name = "diagnostics: showList renders `[a, b]`, and `[]` when empty";
      ok =
        diag.showList [ ] == "[]"
        && diag.showList [ "a" ] == "[a]"
        &&
          diag.showList [
            "a"
            "b"
          ] == "[a, b]";
    }
    # One name, single-quoted. It was variously `'x'`, bare `x` and `'${toString x}'` before this
    # existed, which is why it exists.
    {
      name = "diagnostics: showName single-quotes one name";
      ok = diag.showName "ada" == "'ada'";
    }
    # The GROUPED rendering — offenders under the thing they offend in, which is how the home matrix
    # reports per system. Note it composes with `showList` rather than re-spelling the brackets.
    {
      name = "diagnostics: showPer renders `<key> [a, b], <key> [c]`";
      ok =
        diag.showPer
          (
            k:
            if k == "s1" then
              [
                "a"
                "b"
              ]
            else
              [ "c" ]
          )
          [
            "s1"
            "s2"
          ] == "s1 [a, b], s2 [c]";
    }
    # …and the single-key case, because a message reading "system(s) s1 [gui] build NO home" is what
    # a reader actually meets far more often than the plural one.
    {
      name = "diagnostics: showPer with one key renders no separator";
      ok = diag.showPer (_: [ "gui" ]) [ "s1" ] == "s1 [gui]";
    }

    # ── vacuity: the rationale, single-sourced ───────────────────────────────────────────────
    # THE argument behind every empty-input refusal in this repo — a fold over nothing produces
    # nothing and reports success, so the failure is invisible. It was retyped five times in five
    # wordings before it moved here.
    {
      name = "diagnostics: vacuity names the subject and the default verbs";
      ok =
        diag.vacuity { subject = "matrix"; }
        == "An empty matrix would build, publish and check NOTHING while every output stayed green, "
        + "so this is an error rather than a silent pass.";
    }
    # …and a site may narrow the verbs to what IT would skip, which is the only part a site varies.
    {
      name = "diagnostics: vacuity takes the verbs a site would skip";
      ok = lib.hasInfix "would check NOTHING" (
        diag.vacuity {
          subject = "member set";
          verbs = "check";
        }
      );
    }
    # The composition claim, and the reason `vacuity` is a whole SENTENCE rather than a clause: it is
    # written to be handed to `why`, so it must already carry its terminator and come back
    # unchanged. Every empty-input guard in the repo goes through this join.
    {
      name = "diagnostics: vacuity survives `say`'s termination unchanged";
      ok =
        let
          m = says {
            problem = "the matrix is empty";
            why = diag.vacuity { subject = "matrix"; };
          };
        in
        !doubled m && !ranOn m && lib.hasInfix "silent pass." m;
    }

    # ── must / stop: they actually refuse ────────────────────────────────────────────────────
    # `must` is the guard form, and its passing direction must be usable as an `assert` condition —
    # `true`, not a truthy string.
    {
      name = "diagnostics: must passes as `true` when its condition holds";
      ok =
        diag.must {
          ok = true;
          who = "who";
          problem = "unreachable";
        } == true;
    }
    # …and refuses when it does not. This is the ONE claim in this domain that needs `tryEval`,
    # because refusing is the thing being claimed; what it SAYS is `say`'s business, proven above.
    {
      name = "diagnostics: must refuses when its condition fails";
      ok = refuses (
        diag.must {
          ok = false;
          who = "who";
          problem = "the matrix is empty";
        }
      );
    }
    # `stop` is the unconditional form — the fallthrough sites with no test to write (no `member` to
    # resolve from, no unique maximum to select). It refuses on sight.
    {
      name = "diagnostics: stop refuses unconditionally";
      ok = refuses (
        diag.stop {
          who = "who";
          problem = "there is no source";
        }
      );
    }

    # ── firstFailing / firstRefusal / mustAll: a guard chain as data ─────────────────────────
    # The seam every `…Unguarded` in the repo is built on, and `conformance/refusals.nix` reads
    # through. Its own properties are provable here for the same reason the rest of this file is:
    # a chain that has not been asserted on is just a list.
    #
    # Nothing wrong means NO refusal — the direction every `…Unguarded` control depends on, and the
    # one that would make the whole of `refusals.nix` vacuous if it were wrong.
    {
      name = "diagnostics: a chain with nothing wrong yields no failing check and no message";
      ok = diag.firstFailing passing == null && diag.firstRefusal passing == null;
    }
    # The empty chain is the same answer, not an error. `lib.head [ ]` would throw, so this is the
    # base case being right rather than merely untested.
    {
      name = "diagnostics: an empty chain yields no refusal";
      ok = diag.firstFailing [ ] == null && diag.firstRefusal [ ] == null;
    }
    # FIRST failure wins, in written order — which is the whole of what the `assert` chains this
    # replaced guaranteed, and what lets a site order its checks most-specific-first.
    {
      name = "diagnostics: the FIRST failing check is the one reported, not a later one";
      ok =
        (diag.firstFailing (
          passing
          ++ [
            firstBad
            secondBad
          ]
        )).problem == "the first thing wrong";
    }
    # …and it SHORT-CIRCUITS: nothing after the first failure is forced. Not an optimisation — a
    # site's later checks may assume what an earlier one established (a matrix row cannot be scanned
    # for non-booleans until it is known to be an attrset), so evaluating them all would replace a
    # named diagnosis with a raw eval error. Proven by putting a check that THROWS when forced after
    # the failing one: reaching a message at all is the claim.
    {
      name = "diagnostics: no check after the first failure is forced";
      ok =
        (diag.firstFailing [
          firstBad
          {
            ok = throw "this check was forced";
            who = "who";
            problem = "unreachable";
          }
        ]).problem == "the first thing wrong";
    }
    # `firstRefusal` is `say` over that check — the same message a lone `must` would have raised, so
    # a site does not change what it says by moving into a chain.
    {
      name = "diagnostics: a chain's refusal is exactly what `say` makes of its failing check";
      ok =
        diag.firstRefusal [ firstBad ] == diag.say {
          who = "who";
          problem = "the first thing wrong";
        };
    }
    # `mustAll` is the assert over it, in both directions — passing as literal `true` so it is
    # usable as an `assert` condition, and refusing otherwise.
    {
      name = "diagnostics: mustAll passes as `true` when every check holds, and refuses when one does not";
      ok =
        diag.mustAll passing == true && diag.mustAll [ ] == true && refuses (diag.mustAll [ firstBad ]);
    }
  ];
}
