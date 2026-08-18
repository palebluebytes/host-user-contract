# Conformance domain: the HOME MATRIX and its guards (issue #58, reshaped by ADR-0032).
#
# The contract's `modes` gives a producer the UPPER BOUND — every session shape a home could be
# built for. WHICH of those a system actually bakes stays the consuming fleet's topology
# (decision #43), and the matrix does not touch that: it takes the fleet's declaration and applies
# it. What the contract owns is the SHAPE of that declaration, because the failure mode is silent —
# a mode a system does not bake is a home that is never published, and a host that runs that mode
# binds a lesser one or none at all.
#
# So the subject here is the DIRECTION OF DEFAULT and what is left to guard once the shape carries
# it. A mode a system's row omits is USABLE, which is why a contract that gains one bakes it
# everywhere with no edit in any consumer repo — the claims below drive that through a synthetic
# THREE-mode bound, since the registry has two today. Three under-bakes an earlier shape needed
# asserts for are now unexpressible rather than caught (a row list disagreeing with the system
# list, an unclassified system, a claim of unrestrictedness contradicting the rule), so what
# remains to prove is the subtraction itself plus the four guards the type cannot make for us.
#
# The public `mkHomeMatrix` closes over the contract's own mode names; `homeMatrixOver` is the
# kernel taking the bound explicitly (kit.internal, the posture `floorOf` is exposed under).
# Both are driven here: the kernel for everything about the subtraction, the public entry point for
# the one claim only it can make — that the bound it narrows is the contract's own.
#
# Package-free and build-free: the matrix is plain eval-time data over a list of mode names, so
# every claim below is a `tryEval` over a value.
{
  lib,
  modes,
  homeMatrixOver,
  mkHomeMatrix,
}:
let
  modeNames = lib.attrNames modes;

  # The reference fleet's own shape (examples/users): a headless aarch64 tier beside x86 seats that
  # can run everything the contract names. Note what the rows say — the x86 row takes NOTHING away,
  # and the arm row names only `gui`. Neither enumerates a mode it permits, which is the whole point.
  referenceSystems = {
    x86_64-linux = { };
    aarch64-linux.gui = false;
  };
  over =
    args:
    homeMatrixOver (
      {
        systems = referenceSystems;
        upperBound = modeNames;
      }
      // args
    );
  # The guards fail by throwing at eval (a hard, named error, like every other contract guard), so
  # `tryEval` is how a claim observes the verdict.
  passes = args: (builtins.tryEval (over args)).success;
  matrix = over { };

  # A THREE-mode upper bound — the contract as it would be the day the registry gains `mobile`
  # (ADR-0032 names it as the shape a third takes). The fleet's rows above are handed over UNEDITED.
  threeModes = modeNames ++ [ "mobile" ];
  grown = over { upperBound = threeModes; };

  # An upper bound whose EVERY entry is the excluded mode, so the aarch64 row cuts all of it. Not
  # reachable while the floor is in the bound (the floor is never subtracted by a real fleet),
  # which is exactly why the emptied-row guard is stated rather than assumed.
  guiOnly = [ "gui" ];
in
{
  assertions = [
    {
      name = "home-matrix: a system whose row takes nothing away bakes every mode";
      ok = matrix."x86_64-linux" == modeNames;
    }
    {
      name = "home-matrix: a mode set false cuts exactly that mode";
      ok = matrix."aarch64-linux" == [ "cli" ];
    }
    {
      # Drop-in for `contract.modes`: a producer maps over the row the same way, and the row's
      # entries are plain mode NAMES — there is no record to pair a name up with wrongly.
      name = "home-matrix: each row is a list of the mode names a producer builds homes for";
      ok = lib.all (sys: lib.all lib.isString matrix.${sys}) (lib.attrNames matrix);
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
      # THE direction of default (issue #58): an OMITTED mode is usable. So `{ }` and an explicit
      # `gui = true` are the same declaration, and a fleet may write either — what it must NOT have
      # to do is enumerate what it permits, because the day the contract gains a mode, that
      # enumeration drops the new home in silence.
      name = "home-matrix: an omitted mode is usable — an explicit true is the same declaration";
      ok =
        over {
          systems = {
            x86_64-linux.gui = true;
            aarch64-linux.gui = false;
          };
        } == matrix;
    }
    {
      # A row is a BOOL per mode. A list (the shape an exclusion-list design would take) is a
      # broken declaration, reported as such rather than iterated over.
      name = "home-matrix: fails when a system's row is not an attrset of mode settings";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux = [ "gui" ];
          };
        });
    }
    {
      name = "home-matrix: fails when a mode setting is not a boolean";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.gui = "false";
          };
        });
    }
    {
      # A row names MODES. A FEATURE names a grant, and a grant rides the bind — it keys no home
      # at all (ADR-0032) — so the system would bake every mode while reading as restricted.
      name = "home-matrix: fails when a setting names a FEATURE rather than a mode";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.sudo = false;
          };
        });
    }
    {
      # `base` was the grant-less bake's label under the powerset this replaced. It names no mode
      # and no feature, so a declaration carried over from that dialect must be told so rather
      # than silently taking nothing away.
      name = "home-matrix: fails when a setting names a retired bake LABEL";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.base = false;
          };
        });
    }
    {
      name = "home-matrix: fails when a mode name is not in the contract at all (a typo)";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.Gui = false;
          };
        });
    }
    {
      # Checked on the KEY whatever the boolean says: `sudo = true` reads as though someone had
      # considered whether homes fan out on sudo, and they do not.
      name = "home-matrix: fails on a non-mode setting even when set true (the key is the mistake)";
      ok =
        !(passes {
          systems = referenceSystems // {
            aarch64-linux.sudo = true;
          };
        });
    }
    {
      # An emptied row would publish, bind and check nothing for that system while every output
      # stayed green — the same vacuity the member set and the eval check refuse.
      name = "home-matrix: fails when a system's row is emptied outright";
      ok = !(passes { upperBound = guiOnly; });
    }
    {
      name = "home-matrix: fails over zero systems (a matrix that bakes nothing is not a matrix)";
      ok = !(passes { systems = { }; });
    }
    {
      # The direction of default the design exists for, in the only form the registry cannot yet
      # show: the fleet's rows are unchanged, and the new mode lands on the unrestricted system.
      name = "home-matrix: a contract that gains a MODE extends an unrestricted system's row with no edit";
      ok = grown."x86_64-linux" == threeModes;
    }
    {
      # And on the RESTRICTED system too — it keeps only what its own row takes away. This is what
      # a per-system list of USABLE modes would have got wrong: `mobile` would have been dropped
      # from aarch64 in silence.
      name = "home-matrix: a new mode reaches a RESTRICTED system too — only its false mode is cut";
      ok =
        grown."aarch64-linux" == [
          "cli"
          "mobile"
        ];
    }
    {
      # Non-vacuity for the two claims above: the grown bound really is bigger than the contract's
      # own, so "the new mode propagated" is not a restatement of today's registry.
      name = "home-matrix: the three-mode fixture really exceeds the contract's own mode set";
      ok = lib.length threeModes > lib.length modeNames;
    }
    {
      # The one claim only the PUBLIC entry point can make: it narrows the contract's own mode
      # set, with no bound for a consumer to pass. That is what makes a registry change reach every
      # consumer's bake, and it is why the seam lives in kit.internal rather than on this surface.
      name = "home-matrix: the public entry point narrows the contract's OWN modes, no bound to pass";
      ok = mkHomeMatrix { systems = referenceSystems; } == matrix;
    }
  ];
}
