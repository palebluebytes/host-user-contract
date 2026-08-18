# Conformance domain: the HOME MATRIX and its guards (issue #58).
#
# `homes` gives a producer the UPPER BOUND — one entry per combination of the bake axes.
# WHICH of that set a system actually bakes stays the consuming fleet's topology (decision #43),
# and the matrix does not touch that: it takes the fleet's declaration and applies it. What the
# contract owns is the SHAPE of that declaration, because the failure mode is silent —
# `bindContractUser` binds the maximal bake that DOES exist, so an under-baked set costs a home
# its content with nothing objecting.
#
# So the subject here is the DIRECTION OF DEFAULT and what is left to guard once the shape carries
# it. An axis a system's row omits is USABLE, which is why a contract that gains one bakes it
# everywhere with no edit in any consumer repo — the claims below drive that through a synthetic
# two-axis bound, since the registry has a single axis today. Three under-bakes an earlier shape
# needed asserts for are now unexpressible rather than caught (a row list disagreeing with the
# system list, an unclassified system, a claim of unrestrictedness contradicting the rule), so what
# remains to prove is the narrowing itself plus the four guards the type cannot make for us.
#
# The public `mkHomeMatrix` closes over the contract's own `homes`; `homeMatrixOver` is the
# kernel taking the bound explicitly (kit.internal, the posture `homeAxes` is exposed under).
# Both are driven here: the kernel for everything about the narrowing, the public entry point for
# the one claim only it can make — that the bound it narrows is the contract's own.
#
# Package-free and build-free: the matrix is plain eval-time data over `homes`, so every claim
# below is a `tryEval` over a value.
{
  lib,
  homes,
  homeMatrixOver,
  mkHomeMatrix,
}:
let
  # A synthetic bake entry, shaped exactly like a `homes` one (`{ grants; label; }`). Written
  # out here rather than borrowed so this domain can hand the kernel an upper bound the REGISTRY
  # does not have — a second axis — and prove the propagation the fleet cannot demonstrate until
  # some future feature sets `needsOwnHome`.
  #
  # The label mirrors the contract's own rule — the SORTED grant names, empty ⇒ `base` — so a
  # multi-axis fixture entry is labelled the way a real `homes` entry would be. The matrix itself
  # never reads `label`; the fidelity is so these claims quote the labels a producer would publish.
  homeOf = names: {
    grants = lib.genAttrs names (_: {
      enable = true;
    });
    label = if names == [ ] then "base" else lib.concatStringsSep "-" (lib.sort (a: b: a < b) names);
  };
  labelsOf = map (v: v.label);

  # The reference fleet's own shape (examples/users): a headless aarch64 tier beside x86 seats that
  # can use everything the contract names. Note what the rows say — the x86 row takes NOTHING away,
  # and the arm row names only `gui`. Neither enumerates an axis it permits, which is the whole point.
  referenceSystems = {
    x86_64-linux = { };
    aarch64-linux.gui = false;
  };
  over =
    args:
    homeMatrixOver (
      {
        systems = referenceSystems;
        upperBound = homes;
      }
      // args
    );
  # The guards fail by throwing at eval (a hard, named error, like every other contract guard), so
  # `tryEval` is how a claim observes the verdict.
  passes = args: (builtins.tryEval (over args)).success;
  matrix = over { };

  # A TWO-axis upper bound — the contract as it would be the day a second feature sets
  # `needsOwnHome`. The fleet's rows above are handed over UNEDITED.
  twoAxes = map homeOf [
    [ ]
    [ "gui" ]
    [ "ai" ]
    [
      "gui"
      "ai"
    ]
  ];
  grown = over { upperBound = twoAxes; };

  # An upper bound whose EVERY entry carries the excluded axis, so the aarch64 row cuts all of it.
  # Not reachable from a powerset (the grant-less entry always survives), which is exactly why the
  # empty-bake guard is stated rather than assumed.
  guiOnly = [ (homeOf [ "gui" ]) ];
in
{
  assertions = [
    {
      name = "home-matrix: a system whose row takes nothing away bakes the full home set";
      ok = matrix."x86_64-linux" == homes;
    }
    {
      name = "home-matrix: an axis set false cuts exactly the bakes carrying it";
      ok = labelsOf matrix."aarch64-linux" == [ "base" ];
    }
    {
      # Drop-in for `contract.homes`: a producer maps over the row the same way, so `label`
      # still travels with `grants` and cannot be paired up wrongly.
      name = "home-matrix: each row carries the same { grants; label; } entries a producer maps over";
      ok =
        let
          row = matrix."aarch64-linux";
        in
        lib.length row == 1 && (lib.head row).grants == { } && (lib.head row).label == "base";
    }
    {
      name = "home-matrix: the matrix is keyed by exactly the systems declared";
      ok =
        lib.attrNames matrix == [
          "aarch64-linux"
          "x86_64-linux"
        ];
    }
    {
      # THE direction of default (issue #58): an OMITTED axis is usable. So `{ }` and an explicit
      # `gui = true` are the same declaration, and a fleet may write either — what it must NOT have
      # to do is enumerate what it permits, because the day the contract gains an axis, that
      # enumeration drops the new bake in silence.
      name = "home-matrix: an omitted axis is usable — an explicit true is the same declaration";
      ok =
        over {
          systems = {
            x86_64-linux.gui = true;
            aarch64-linux.gui = false;
          };
        } == matrix;
    }
    {
      # A row is a BOOL per axis. A list (the shape an exclusion-list design would take) is a
      # broken declaration, reported as such rather than iterated over.
      name = "home-matrix: fails when a system's row is not an attrset of axis settings";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux = [ "gui" ];
          };
        });
    }
    {
      name = "home-matrix: fails when an axis setting is not a boolean";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.gui = "false";
          };
        });
    }
    {
      # An axis name is a FEATURE name. A bind-riding feature names nothing the bake fans out on
      # (no bake is baked per `sudo`), so the system would silently bake the full set while
      # reading as restricted.
      name = "home-matrix: fails when a setting names a feature that is not a bake axis";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.sudo = false;
          };
        });
    }
    {
      # The failure mode the issue names outright: a declaration written against LABELS rather
      # than features. `base` is a real label of this contract and no feature at all.
      name = "home-matrix: fails when a setting names a bake LABEL rather than a feature";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.base = false;
          };
        });
    }
    {
      name = "home-matrix: fails when a feature name is not in the contract at all (a typo)";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.Gui = false;
          };
        });
    }
    {
      # Checked on the KEY whatever the boolean says: `sudo = true` reads as though someone had
      # considered whether the bake fans out on sudo, and it does not.
      name = "home-matrix: fails on a non-axis setting even when set true (the key is the mistake)";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.sudo = true;
          };
        });
    }
    {
      # An emptied bake would publish, bind and check nothing for that system while every output
      # stayed green — the same vacuity the members and the eval check refuse.
      name = "home-matrix: fails when a system's bake is emptied outright";
      ok = !(passes { upperBound = guiOnly; });
    }
    {
      name = "home-matrix: fails over zero systems (a matrix that bakes nothing is not a matrix)";
      ok = !(passes { systems = { }; });
    }
    {
      # The direction of default the design exists for, in the only form the registry cannot yet
      # show: the fleet's rows are unchanged, and the new axis lands on the unrestricted system.
      name = "home-matrix: a contract that gains an axis extends an unrestricted system's bake with no edit";
      ok =
        labelsOf grown."x86_64-linux" == [
          "base"
          "gui"
          "ai"
          "ai-gui"
        ];
    }
    {
      # And on the RESTRICTED system too — it keeps only what its own row takes away. This is what
      # a per-system list of USABLE features would have got wrong: `ai` would have been dropped
      # from aarch64 in silence, the same bug as a label list one rung up.
      name = "home-matrix: a new axis reaches a RESTRICTED system too — only its false axis is cut";
      ok =
        labelsOf grown."aarch64-linux" == [
          "base"
          "ai"
        ];
    }
    {
      # Non-vacuity for the two claims above: the grown bound really is bigger than the contract's
      # own, so "the new axis propagated" is not a restatement of today's registry.
      name = "home-matrix: the two-axis fixture really exceeds the contract's own home set";
      ok = lib.length twoAxes > lib.length homes;
    }
    {
      # The one claim only the PUBLIC entry point can make: it narrows the contract's own bake
      # set, with no bound for a consumer to pass. That is what makes a registry change reach every
      # consumer's bake, and it is why the seam lives in kit.internal rather than on this surface.
      name = "home-matrix: the public entry point narrows the contract's OWN homes, no bound to pass";
      ok = mkHomeMatrix { systems = referenceSystems; } == matrix;
    }
  ];
}
