# Conformance domain: the members-generic HOME EVAL check (issue #49, decision #43).
#
# `mkHomeEvalCheck` proves ONE user's every published home EVALUATES on every system the
# repo builds it for — the members-generic replacement for the hand-written cross-arch eval
# checks every user's `checks.nix` used to carry. A consumer's mapper applies it per user
# over the derived members, so a typical user ships no check file at all; what this domain
# proves is the helper's own logic — that it cannot pass vacuously (an emptied entry, an
# empty system list, a force that stops short), that it fails loudly when any handed
# system × home does not evaluate, and that each of those failures is reported as ITSELF.
#
# COVERAGE NOTE — like `./confinement.nix`, this drives the helper through SYNTHETIC homes
# (plain attrsets shaped like the default force's attrpath): the contract has no home-manager
# so the `activationPackage.drvPath` default over a REAL home-manager home is only
# exercised in a consumer repo's own `checks`.
{
  lib,
  pkgs,
  mkHomeEvalCheck,
}:
let
  # A synthetic built home carrying exactly the attrpath the DEFAULT `force` dereferences
  # (`home.activationPackage.drvPath`), so this domain exercises the default hook's shape —
  # though not a real home-manager home; see the coverage note above.
  home = mode: {
    activationPackage.drvPath = "/nix/store/00000000000000000000000000000000-${mode}.drv";
  };
  # A home whose force THROWS — the stand-in for the real hazard (a typo'd package name, a
  # module error). The helper deliberately runs no `tryEval`, so this must surface as a
  # failing check (the raw error), never be swallowed into a pass.
  brokenHome = {
    activationPackage.drvPath = throw "package 'emacs-pgtk' missing on this system";
  };

  # The decided reference shape (#43): a consumer's per-system entries, keyed by MODE —
  # x86_64 {cli, gui}, aarch64 {cli}. The helper takes it as handed and asserts ALL of it.
  matrix = {
    "x86_64-linux" = {
      cli = home "cli-x86";
      gui = home "gui-x86";
    };
    "aarch64-linux" = {
      cli = home "cli-arm";
    };
  };

  check =
    args:
    mkHomeEvalCheck (
      {
        inherit pkgs;
        homesFor = sys: matrix.${sys};
        systems = lib.attrNames matrix;
      }
      // args
    );
  # The check fails by throwing at eval (a hard, named error, like every other contract
  # guard), so `tryEval` is how a test observes the verdict.
  passes = args: (builtins.tryEval (check args)).success;

  # A matrix with ONE broken bake on ONE system, everything else fine — for proving no
  # handed system is skipped (including the native one: the helper has no native/foreign
  # distinction, it forces the whole handed matrix).
  brokenOn =
    badSys:
    lib.mapAttrs (sys: entry: if sys == badSys then entry // { cli = brokenHome; } else entry) matrix;

  # THE MISLEADING-MESSAGE CASE (issue #67, second guard defect). SHAPE and EMPTINESS were folded
  # into one predicate, so an entry that is not an attrset — a list holding one home, say — failed
  # with *"no homes for [x86_64-linux]"*. The entry is not empty; it holds a home in the wrong shape,
  # and the message named the wrong mistake to whoever had to fix it. The two predicates are split
  # now, and the two fixtures below drive them SEPARATELY: an unreadable entry and an emptied one are
  # different mistakes with different diagnoses.
  #
  # What cannot be asserted here is the message TEXT — `tryEval` discards it, as this suite records
  # wherever it drives a named error. So the split is pinned the only way eval allows: each shape
  # is refused on its own, and the emptiness verdict is structurally unreachable for an entry the
  # check could not read (the partition makes the two sets exact complements rather than two
  # hand-written predicates that have to keep agreeing).
  entryHoldingAHomeInTheWrongShape = {
    homesFor = sys: if sys == "x86_64-linux" then [ (home "cli-x86") ] else matrix.${sys};
  };
  emptiedEntry = {
    homesFor = sys: if sys == "x86_64-linux" then { } else matrix.${sys};
  };
in
{
  assertions = [
    {
      name = "mkHomeEvalCheck: passes over the reference home matrix (every system × home evaluates, #43)";
      ok = passes { };
    }
    {
      # The anti-vacuous claim: an accidentally-emptied entry (a subtraction gone wrong in the
      # consumer's mapper) must never read as a passing eval check.
      name = "mkHomeEvalCheck: fails when a system's home set is empty (no vacuous pass)";
      ok = !(passes emptiedEntry);
    }
    {
      # Same trap one level up: a check over ZERO systems would pass vacuously forever.
      name = "mkHomeEvalCheck: fails when the systems list is empty (no vacuous pass)";
      ok = !(passes { systems = [ ]; });
    }
    {
      # THE MISLEADING-MESSAGE CASE (issue #67): an entry that HOLDS a home but is not an attrset is
      # a broken harness, and must be reported as one rather than as "no homes" — it is not empty.
      # Paired with the emptiness claim above, this is the split: two shapes, two refusals.
      name = "mkHomeEvalCheck: an entry holding a home in the wrong shape is refused as a SHAPE error, not as empty";
      ok = !(passes entryHoldingAHomeInTheWrongShape);
    }
    {
      # The claim the helper exists to make: a home that does not evaluate on a handed
      # system fails the check — and there is no tryEval to swallow the underlying error.
      name = "mkHomeEvalCheck: fails when a published home throws at force (the eval error surfaces)";
      ok = !(passes { homesFor = sys: (brokenOn "aarch64-linux").${sys}; });
    }
    {
      # No handed system is skipped — including the one a runner would call native. The
      # helper forces the WHOLE handed matrix; "native is covered elsewhere" is not its model.
      name = "mkHomeEvalCheck: forces every handed system, the native one included (a broken x86 bake fails too)";
      ok = !(passes { homesFor = sys: (brokenOn "x86_64-linux").${sys}; });
    }
    {
      # The other way to be vacuous: a `force` that never reaches the derivation makes every
      # bake "evaluate". The `.drv` suffix assert breaks that LOUDLY instead of silently.
      name = "mkHomeEvalCheck: fails when force stops short of a .drv path (an under-forcing hook cannot pass)";
      ok = !(passes { force = _: "never forced"; });
    }
  ];

  # Execution proof: the check a consumer's mapper wires into `checks.<system>` per user is a
  # real derivation that BUILDS (the assertions above only observe its eval verdict).
  drvs.mkHomeEvalCheck = check { name = "conformance-home-eval"; };
}
