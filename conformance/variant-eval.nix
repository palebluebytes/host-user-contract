# Conformance domain: the roster-generic VARIANT EVAL check (issue #49, decision #43).
#
# `mkVariantEvalCheck` proves ONE user's every baked variant EVALUATES on every system the
# repo bakes it for — the roster-generic replacement for the hand-written cross-arch eval
# checks every user's `checks.nix` used to carry. A consumer's mapper applies it per user
# over the derived roster, so a typical user ships no check file at all; what this domain
# proves is the helper's own logic — that it cannot pass vacuously (an emptied bake, an
# empty system list, a force that stops short) and that it fails loudly when any handed
# system × variant does not evaluate.
#
# COVERAGE NOTE — like `./confinement.nix`, this drives the helper through SYNTHETIC homes
# (plain attrsets shaped like the default force's attrpath): the contract has no home-manager
# (ADR-0004), so the `activationPackage.drvPath` default over a REAL home-manager home is only
# exercised in a consumer repo's own `checks`.
{
  lib,
  pkgs,
  mkVariantEvalCheck,
}:
let
  # A synthetic baked home carrying exactly the attrpath the DEFAULT `force` dereferences
  # (`home.activationPackage.drvPath`), so this domain exercises the default hook's shape —
  # though not a real home-manager home; see the coverage note above.
  home = label: {
    activationPackage.drvPath = "/nix/store/00000000000000000000000000000000-${label}.drv";
  };
  # A home whose force THROWS — the stand-in for the real hazard (a typo'd package name, a
  # module error). The helper deliberately runs no `tryEval`, so this must surface as a
  # failing check (the raw error), never be swallowed into a pass.
  brokenHome = {
    activationPackage.drvPath = throw "package 'emacs-pgtk' missing on this system";
  };

  # The decided reference shape (#43): a per-system, consumer-owned bake matrix —
  # x86_64 {base, gui}, aarch64 {base}. The helper takes it as handed and asserts ALL of it.
  matrix = {
    "x86_64-linux" = {
      base = home "base-x86";
      gui = home "gui-x86";
    };
    "aarch64-linux" = {
      base = home "base-arm";
    };
  };

  check =
    args:
    mkVariantEvalCheck (
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

  # A matrix with ONE broken variant on ONE system, everything else fine — for proving no
  # handed system is skipped (including the native one: the helper has no native/foreign
  # distinction, it forces the whole handed matrix).
  brokenOn =
    badSys:
    lib.mapAttrs (
      sys: variants: if sys == badSys then variants // { base = brokenHome; } else variants
    ) matrix;
in
{
  assertions = [
    {
      name = "mkVariantEvalCheck: passes over the reference bake matrix (every system × variant evaluates, #43)";
      ok = passes { };
    }
    {
      # The anti-vacuous claim: an accidentally-emptied bake (a filter gone wrong in the
      # consumer's mapper) must never read as a passing eval check.
      name = "mkVariantEvalCheck: fails when a system's variant set is empty (no vacuous pass)";
      ok = !(passes { homesFor = sys: if sys == "aarch64-linux" then { } else matrix.${sys}; });
    }
    {
      # Same trap one level up: a check over ZERO systems would pass vacuously forever.
      name = "mkVariantEvalCheck: fails when the systems list is empty (no vacuous pass)";
      ok = !(passes { systems = [ ]; });
    }
    {
      # A mapper handing something that is not a variant attrset at all is a broken harness,
      # reported as such rather than iterated over.
      name = "mkVariantEvalCheck: fails when homesFor returns a non-attrset (broken harness, not a pass)";
      ok = !(passes { homesFor = _: [ "not-an-attrset" ]; });
    }
    {
      # The claim the helper exists to make: a variant that does not evaluate on a handed
      # system fails the check — and there is no tryEval to swallow the underlying error.
      name = "mkVariantEvalCheck: fails when a variant's home throws at force (the eval error surfaces)";
      ok = !(passes { homesFor = sys: (brokenOn "aarch64-linux").${sys}; });
    }
    {
      # No handed system is skipped — including the one a runner would call native. The
      # helper forces the WHOLE handed matrix; "native is covered elsewhere" is not its model.
      name = "mkVariantEvalCheck: forces every handed system, the native one included (a broken x86 variant fails too)";
      ok = !(passes { homesFor = sys: (brokenOn "x86_64-linux").${sys}; });
    }
    {
      # The other way to be vacuous: a `force` that never reaches the derivation makes every
      # variant "evaluate". The `.drv` suffix assert breaks that LOUDLY instead of silently.
      name = "mkVariantEvalCheck: fails when force stops short of a .drv path (an under-forcing hook cannot pass)";
      ok = !(passes { force = _: "never forced"; });
    }
  ];

  # Execution proof: the check a consumer's mapper wires into `checks.<system>` per user is a
  # real derivation that BUILDS (the assertions above only observe its eval verdict).
  drvs.mkVariantEvalCheck = check { name = "conformance-variant-eval"; };
}
