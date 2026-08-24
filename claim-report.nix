# The CLAIM REPORT — the one owner of how a suite of named claims reports itself.
#
# Three places in this repo ran a list of named claims, printed an `ok`/`FAIL` line each, and exited
# non-zero if any failed. Two spelled it out near-verbatim — same filter, same rendering, same exit —
# and the third had no collector at all, so its proofs surfaced as opaque check names behind
# separately-invented shell harnesses. The format had no owner, so the copies were free to diverge
# and a fourth site could only invent a fourth spelling.
#
# This is the CHECK KIT's kind of thing (ADR-0025): the contract ships the technique a consumer runs
# over its own repo, never the verdict. It is lib-only and package-free (ADR-0002) — `pkgs` arrives
# as an argument, exactly as it does for the four proof helpers next door.
#
# TWO KINDS OF CLAIM, because a suite has two:
#
#   an EVAL CLAIM       `{ name; ok; }` — a boolean already decided, rendered as a line.
#   an EXECUTION PROOF  `{ <name> = <derivation>; }` — a claim whose BEING BUILT is the verdict.
#                       Threaded in as the report's own build inputs, so building the report builds
#                       every proof, and a proof that cannot build takes the report down with it.
#                       That is the whole mechanism: a proof rendered into the report TEXT and not
#                       depended on would be decoration, which is why the values are checked to be
#                       derivations rather than trusted.
#
# WHERE THE VERDICT LIVES. The eval claims are folded at eval, but the exit is in the BUILDER — so a
# consumer's `checks.<system>.<report>` fails the way every other check fails, and `nix flake check`
# needs no special case. It also means a caller cannot observe the refusal without building, which is
# what the suite's own two build-direction proofs exist for.
#
# AND THE SHELL SIDE OF THE SAME QUESTION. `mkClaimReport` decides at EVAL; an execution proof decides
# in SHELL, so "how does a proof say it failed?" is a second thing with no owner — and it went the
# same way the report format did. The reference user fleet's two realized-content proofs each opened
# with their own `fail()`, identical but for the label they echoed (issue #91). `mkProofPrelude` below
# is that owner: one definition, parameterised by the proof's own name. It ships here rather than in
# `check-kit.nix` for the reason that file's sibling import already gives — this pair is about
# REPORTING, and everything in the kit proper is a proof.
{ lib, diag }:
let
  inherit (diag) showList showName;
in
{
  # mkClaimReport `{ name; claims; pkgs; title ? name; proofs ? { } }` → the report derivation.
  #
  #     contract.lib.mkClaimReport {
  #       inherit pkgs;
  #       name = "my-fleet-checks";
  #       title = "my fleet — every host evaluates, every account realizes";
  #       claims = [ { name = "…"; ok = …; } … ];
  #       proofs = { some-vm-test = …; };
  #     }
  #
  # `name` is the DERIVATION's name — what `nix flake check -L` prints and what a `checks.<system>`
  # attribute points at. `title` is the prose header the report opens with. Two fields rather than
  # one, and both required, because they answer to different rules: a store name may not carry
  # spaces, and a header that says what this suite IS wants them.
  mkClaimReport =
    {
      # The eval claims, in the order they will be reported. A LIST, not an attrset: order is part
      # of what a report says — a broken harness reported before the claims it would have made.
      claims,
      # The caller's own label for a report it owns (ADR-0025's posture for the whole kit): the
      # store name, and the prose header it opens with.
      name,
      title,
      # The consumer's package set, for the report derivation itself. An argument, never an input.
      pkgs,
      proofs ? { },
    }:
    let
      # How a claim REFERS TO ITSELF in a diagnosis. A claim missing its own name has only its
      # position left — and that is precisely the claim a caller most needs pointed at, since it is
      # the one they cannot find by searching for its text.
      refer =
        i: c:
        if c ? name && lib.isString c.name then
          # Escaped, not rendered: a name is only ever an OFFENDER here when something is wrong with
          # it, and one of those things is carrying a newline — which would put the diagnostic's own
          # offender list across two lines, in the one module whose job is a single voice.
          showName (lib.replaceStrings [ "\n" ] [ "\\n" ] c.name)
        else
          "claim #${toString i}";
      indexed = lib.imap0 (i: c: { inherit i c; }) claims;
      offenders = pred: map ({ i, c }: refer i c) (lib.filter ({ c, ... }: pred c) indexed);

      unnamed = offenders (c: !(c ? name) || !lib.isString c.name);
      # A report line IS one line. A name carrying a newline breaks the `ok`/`FAIL` column it is
      # supposed to sit in — and worse, a line of it reading `EOF` would close the report's own
      # heredoc early and hand whatever followed to the shell.
      multiline = offenders (c: c ? name && lib.isString c.name && lib.hasInfix "\n" c.name);
      verdictless = offenders (c: !(c ? ok));
      nonBoolean = offenders (c: c ? ok && !lib.isBool c.ok);
      # Proof values that are not derivations. A string here would become a plain environment
      # variable: rendered into the report, depended on by nothing, and silently proving nothing.
      undepended = map showName (lib.filter (n: !lib.isDerivation proofs.${n}) (lib.attrNames proofs));

      failed = lib.filter (c: !c.ok) claims;
      # The report body. Built here rather than in the builder so the rendering has ONE owner and a
      # site cannot re-invent the column widths.
      claimLines = lib.concatMapStringsSep "\n" (
        c: "  ${if c.ok then "ok  " else "FAIL"}  ${c.name}"
      ) claims;
      # Only when there are proofs: the reference host fleet's report is all eval claims, and an
      # empty section under a heading reads like something went missing.
      proofLines = lib.optionalString (proofs != { }) (
        "\n\nexecution proofs (built ⇒ ok):\n"
        + lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "  ${n}: ${v}") proofs)
      );
    in
    # Ordered deliberately, and the order is the same rule the rest of this repo follows: material
    # that cannot be READ is refused before anything is read off it, and anti-vacuity before the
    # verdicts — a report that folded over nothing must never reach the rendering at all.
    #
    # `mustAll` short-circuits left to right, so each check may assume the ones above it: the
    # per-claim scans below are only reachable once `claims` is known to be a list.
    assert diag.mustAll [
      {
        ok = lib.isList claims;
        who = name;
        problem = "its `claims` is not a list";
        why =
          "The report renders its claims IN ORDER, and an attrset has no order to render — a "
          + "reader could not tell a broken harness from the claims it would have made.";
        fix = "Hand a list of `{ name; ok; }`, in the order they should be reported.";
      }
      {
        ok = claims != [ ];
        who = name;
        problem = "its claim list is empty";
        why = diag.vacuity {
          subject = "claim list";
          verbs = "check";
        };
        fix =
          "Hand it the claims this report exists to make. A report of execution proofs alone is "
          + "not a report — thread those in as `proofs`, beside claims that say what they mean.";
      }
      {
        ok = unnamed == [ ];
        who = name;
        problem = "these claims carry no name: ${showList unnamed}";
        why =
          "A report line IS the name — an unnameable verdict would print as a bare `ok` a reader "
          + "cannot act on, and could not be found by searching for it.";
        fix = "Give each claim a `name` describing what it claims, as a string.";
      }
      {
        ok = multiline == [ ];
        who = name;
        problem = "these claims carry a name spanning more than one line: ${showList multiline}";
        why =
          "A report is one line per claim, so the rest of a multi-line name would render outside "
          + "the `ok`/`FAIL` column it belongs to — and a line of it reading `EOF` would close the "
          + "report's own heredoc and hand the remainder to the shell.";
        fix = "Say it in one line; the reasoning belongs in a comment beside the claim.";
      }
      {
        ok = verdictless == [ ];
        who = name;
        problem = "these claims carry no `ok` verdict: ${showList verdictless}";
        why =
          "The report would throw `attribute 'ok' missing` from inside a function the caller did "
          + "not write, naming neither this report nor the claim that lacked it.";
        fix = "Give each claim an `ok` boolean — the verdict the line reports.";
      }
      {
        ok = nonBoolean == [ ];
        who = name;
        problem = "these claims carry a non-boolean verdict: ${showList nonBoolean}";
        why =
          "A truthy string reads as a pass to a person and is a type error to the filter, so the "
          + "same value would render `ok` here and throw one line later.";
        fix = "Make each `ok` a genuine boolean; compute the comparison rather than reporting it.";
      }
      {
        ok = lib.isAttrs proofs;
        who = name;
        problem = "its `proofs` is not an attrset";
        why =
          "Each proof is read BY NAME — the name is what the report prints beside it and what the "
          + "derivation carries it under — so a list has nothing for either to use.";
        fix = "Hand `{ <name> = <derivation>; }`, or omit `proofs` if this report has none.";
      }
      {
        ok = undepended == [ ];
        who = name;
        problem = "these execution proofs are not derivations: ${showList undepended}";
        why =
          "A proof's whole verdict is that it BUILT. A non-derivation becomes a plain environment "
          + "variable — rendered in the report, depended on by nothing — so it would report `ok` "
          + "without ever having run.";
        fix = "Pass the derivation itself, not a path or a name.";
      }
    ];
    # The proofs ARE the derivation's environment, which is what makes them build inputs rather than
    # text — the one line in this file that carries the mechanism.
    pkgs.runCommand name proofs ''
      cat <<'EOF'
      ${title}:
      ${claimLines}${proofLines}
      EOF
      ${lib.optionalString (failed != [ ]) ''
        cat >&2 <<'EOF'
        ${name}: FAILED — ${showList (map (c: c.name) failed)}
        EOF
        exit 1
      ''}
      touch $out
    '';

  # mkProofPrelude `<proof name>` → the shell an EXECUTION PROOF opens its builder with.
  #
  #     pkgs.runCommand "shared-code-per-user-data" { } (
  #       contract.lib.mkProofPrelude "shared-code-per-user-data"
  #       + ''
  #         [ -x "$marker" ] || fail "the home-path has no runnable marker"
  #         touch $out
  #       ''
  #     )
  #
  # It defines exactly one thing — `fail <message>`, which writes `<proof name>: <message>` to stderr
  # and exits non-zero. Small enough that every site was happy to retype it, which is precisely how
  # two copies came to exist with nothing keeping them in step.
  #
  # The NAME is the caller's own (ADR-0025's posture for the whole kit), and it is what makes a
  # failure legible: a proof's message lands in a build log beside everything else Nix is doing, so
  # one that does not say WHICH proof wrote it leaves a reader to guess.
  #
  # It returns TEXT rather than wrapping the derivation, because a proof's builder is the proof: the
  # comparisons are the interesting part and they must stay readable at the call site, not be handed
  # to a combinator as a string argument.
  mkProofPrelude =
    name:
    let
      # Characters that would not make a bad LABEL but a live shell: the name is interpolated into a
      # double-quoted `echo`, so a quote closes it, a `$` or a backtick expands inside it, and a
      # backslash escapes whatever follows. A proof runs in a sandbox holding the very homes it is
      # judging, so this is the difference between a mislabelled failure and arbitrary shell.
      escapes = lib.filter (c: lib.hasInfix c name) [
        "\""
        "$"
        "`"
        "\\"
      ];
      # The one instruction two of the guards below both end on. Written once, for the reason the
      # diagnostic module states about its own vacuity rationale: a sentence retyped is a sentence
      # free to be retyped DIFFERENTLY the next time.
      handTheName = "Hand the proof's own name — the same string its `runCommand` is named with.";
    in
    assert diag.mustAll [
      {
        ok = lib.isString name;
        who = "mkProofPrelude";
        problem = "its proof name is not a string";
        why =
          "The name is echoed beside every message this prelude's `fail` writes, and a non-string "
          + "would throw from inside the interpolation rather than from the call site.";
        fix = handTheName;
      }
      {
        ok = name != "";
        who = "mkProofPrelude";
        problem = "its proof name is empty";
        why =
          "Every failure would print a bare `: <message>` — anonymous in a build log carrying "
          + "every other proof's output, which is the one thing the name exists to prevent.";
        fix = handTheName;
      }
      {
        ok = !(lib.hasInfix "\n" name);
        who = "mkProofPrelude";
        problem = "its proof name spans more than one line";
        why =
          "A failure is ONE line, `<proof>: <message>`; the rest of a multi-line name would land "
          + "on lines of its own, reading as output from something else entirely.";
        fix = "Say it in one line; the reasoning belongs in a comment beside the proof.";
      }
      {
        ok = escapes == [ ];
        who = "mkProofPrelude";
        problem = "its proof name carries shell syntax: ${showList (map showName escapes)}";
        why =
          "The name goes inside a double-quoted `echo`, so these do not label the failure — they "
          + "END the quoting or expand within it, and the remainder runs as shell in a sandbox "
          + "holding whatever the proof was given to judge.";
        fix = "Name a proof the way a derivation is named: letters, digits and dashes.";
      }
    ];
    ''
      fail() {
        echo "${name}: $1" >&2
        exit 1
      }
    '';
}
