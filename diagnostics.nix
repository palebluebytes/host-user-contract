# The diagnostic module: the ONE owner of what the contract says when it refuses.
#
# An error message is the contract's interface at the moment it matters most — the reader has
# already lost, and the message is the whole of what they get. So the SHAPE is stated once here and
# the sites state only their own facts. Every diagnostic answers the same four questions, in the
# same order:
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

  # ── A GUARD CHAIN AS DATA (issue #64) ────────────────────────────────────────────────────────
  # THE ARGUMENT, STATED ONCE — every `…Unguarded` in this repo cites this block rather than
  # re-making it. `must` and `stop` REFUSE, and a refusal's message is then unreachable:
  # `builtins.tryEval` — the only way a test can drive a refusal at all — returns `{ success =
  # false; value = false; }` and DISCARDS it. So a guard proves that it FIRES and nothing proves
  # what a reader is told, which for several of them is the whole difference between a diagnosis
  # and a silent misconfiguration.
  #
  # A site whose messages are load-bearing that way SPLITS IN TWO:
  #
  #   fooUnguarded = args: let … in { <the work>; checks = [ { ok; who; problem; … } … ]; };
  #   foo          = args: let it = fooUnguarded args; in assert mustAll it.checks; it.<the work>;
  #
  # `foo` is unchanged for every caller. `fooUnguarded` lets the suite READ what `foo` would have
  # said about input it would refuse, with no assertion involved and no failure provoked. The work
  # it returns beside the checks is only valid once they pass — that is the point of the name, and
  # each site says which of its fields is unsafe to force unguarded.
  #
  # WHICH FORM TO REACH FOR: `must` for a lone guard, which is most of them; the split only for a
  # message that carries a DIAGNOSIS a reader could not reconstruct — one where a wrong answer and
  # a silent success look the same. It is not a house style, and `mustAll [ c ]` is `must c`.

  # The first check that fails, or `null`. SHORT-CIRCUITING, which is not an optimisation: it forces
  # each `ok` left to right and stops at the first failure, exactly as the `assert` chain this
  # replaces did, so a later check may still assume what an earlier one established — a row cannot
  # be scanned for non-booleans until it is known to be an attrset.
  firstFailing =
    checks:
    if checks == [ ] then
      null
    else if (lib.head checks).ok then
      firstFailing (lib.tail checks)
    else
      lib.head checks;

  # …and the message it would raise. Split from `firstFailing` because the two answer different
  # questions: the suite asserts offenders against the `problem` CLAUSE — a name that appeared only
  # in the surrounding `why` or `fix` would be a message that stopped naming its offenders while
  # still reading as though it named them — and a reader gets the whole thing.
  firstRefusal =
    checks:
    let
      c = firstFailing checks;
    in
    if c == null then null else say (builtins.removeAttrs c [ "ok" ]);

  # `must` for a whole chain, with the same first-failure-wins order.
  mustAll =
    checks:
    let
      refusal = firstRefusal checks;
    in
    lib.assertMsg (refusal == null) refusal;
}
