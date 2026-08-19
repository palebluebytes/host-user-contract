# The diagnostic module: the ONE owner of what the contract says when it refuses.
#
# An error message is the contract's interface at the moment it matters most — the reader has
# already lost, and the message is the whole of what they get. It was also the least consistent
# surface here: 32 hand-rolled `assertMsg`/`throw` sites across `lib.nix` and `check-kit.nix`, with
# FOUR conventions for naming the offending function (a `context` argument, a hardcoded literal, a
# `name ?` parameter, and one function naming its caller), list rendering inlined fifteen times, two
# separators, three quoting styles, and one recurring rationale retyped five times.
#
# So the shape is stated once and the sites state only their own facts. Every diagnostic answers the
# same four questions, in the same order:
#
#   who      which function is refusing — the PUBLIC name a caller knows it by, which is not always
#            the function raising the error (the home-matrix kernel is internal, so it says
#            `mkHomeMatrix`; that is now an explicit field rather than an accident of copied text)
#   problem  what is wrong, naming the offenders — never a count
#   why      what it would cost to let this pass
#   fix      what to write instead
#
# `why` and `fix` are optional, but dropping them is a choice a reader of the call site can see. The
# real point is that a site cannot ACCIDENTALLY omit the prefix, invent a third separator, or
# re-argue the vacuity rationale in slightly different words.
#
# NOT exposed on the public surface: this is how the contract phrases its own refusals, not a
# facility a consumer builds on. The check kit's helpers take a `name` so a CONSUMER can label a
# check it owns; that is a different thing and it stays.
{ lib }:
rec {
  # The bracketed list, spelled once. Every message that names offenders renders them this way, so
  # `[a, b]` never becomes `a; b` in the next message a reader meets.
  showList = xs: "[" + lib.concatStringsSep ", " xs + "]";

  # One name, quoted. The convention is single quotes; it was variously `'x'`, bare `x` and
  # `'${toString x}'` before.
  showName = n: "'${toString n}'";

  # "<key> [a, b], <key> [c]" — for a diagnostic whose offenders are grouped under something (the
  # home matrix reports offending axes PER SYSTEM). `offendersIn` is a function from key to list.
  showPer =
    offendersIn: keys:
    lib.concatMapStringsSep ", " (k: "${toString k} ${showList (offendersIn k)}") keys;

  # The message itself. Sites hand facts; this owns the punctuation — which is the point: the first
  # version of this module ran `problem` into `why` with only a space between them, producing
  # "…x86_64-linux [sudo] The axes of this contract are…". A site cannot get that wrong now, because
  # a site no longer writes it.
  #
  # `problem` is a CLAUSE, not a sentence: sites write "the matrix is empty", never "The matrix is
  # empty." — the terminator is added here so it is one rule rather than thirty.
  say =
    let
      # Terminate a clause unless it already ends in punctuation of its own (several `problem`s end
      # in a rendered list, `]`, and several `why`s are whole sentences).
      period =
        t: if lib.hasSuffix "." t || lib.hasSuffix "?" t || lib.hasSuffix "!" t then t else "${t}.";
    in
    {
      who,
      problem,
      why ? null,
      fix ? null,
    }:
    "${who}: ${period problem}"
    + lib.optionalString (why != null) " ${period why}"
    + lib.optionalString (fix != null) " ${period fix}";

  # A guard that reads as one: the condition sits WITH its explanation rather than three lines
  # above it, which is what let the two drift at several sites.
  #
  #   assert diag.must { ok = xs != [ ]; who = "…"; problem = "…"; why = …; fix = "…"; };
  must =
    {
      ok,
      who,
      problem,
      why ? null,
      fix ? null,
    }:
    lib.assertMsg ok (say {
      inherit
        who
        problem
        why
        fix
        ;
    });

  # The unconditional refusal — a `throw` in message form, for the sites that are a fallthrough
  # rather than a test (no `member` to resolve from, no unique maximum to select).
  stop = args: throw (say args);

  # THE VACUITY RATIONALE, stated once (it was retyped five times, in five wordings).
  #
  # It is the argument behind every empty-input refusal in this repo: a fold over nothing produces
  # nothing and reports success, so the failure is INVISIBLE — green output with no work done. That
  # is why an empty roster, an empty matrix, an emptied `homes` entry and an identity-less posture check are
  # all hard errors rather than benign no-ops. `subject` names the empty thing; `verbs` names what
  # it would silently skip.
  vacuity =
    {
      subject,
      verbs ? "build, publish and check",
    }:
    "An empty ${subject} would ${verbs} NOTHING while every output stayed green, "
    + "so this is an error rather than a silent pass.";

  # THE SHAPE-BEFORE-EMPTINESS PARTITION, stated once (it was retyped three times, in three
  # wordings — `mkContractFleet`, `mkHomeEvalCheck` and `mkMemberChecks`).
  #
  # Shape and emptiness are two DIFFERENT mistakes, and one predicate folding them together reports
  # the wrong one: an entry holding a single malformed home is not empty, yet it once failed with
  # "no homes for [x86_64-linux]". So the emptiness verdict — and every other verdict that has to
  # READ a value — may only be asked of the values it can read, which means the readable set and the
  # malformed set must be exact COMPLEMENTS. A partition makes that structural; two hand-written
  # negated filters make it a rule the pair have to keep agreeing on, and the agreement is exactly
  # what drifts.
  #
  # `readable`/`malformed` rather than `lib.partition`'s `right`/`wrong`, so the caller's next line
  # says which of the two it is asking about instead of leaving a reader to work out which way round
  # the predicate ran.
  byShape =
    pred: names:
    let
      split = lib.partition pred names;
    in
    {
      readable = split.right;
      malformed = split.wrong;
    };
}
