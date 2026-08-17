# Conformance domain: the ROSTER ADAPTER over the check kit (issue #60).
#
# `mkRosterChecks` applies the three shipped helpers — confinement, variant-eval, credential
# posture — across a whole roster in one call. The helpers' own logic is proven next door
# (./confinement.nix, ./variant-eval.nix, ./identity-posture.nix); what this domain proves is
# everything the ADAPTER is responsible for:
#
#   - the SHAPE it yields: a confinement and a variant-eval check per member, one posture check
#     over the roster, each under the single-sourced name;
#   - that the roster is what it maps over, so a member added to the roster is covered with no
#     other edit — the whole reason the helpers are roster-generic;
#   - that every guard SURVIVES the fold. An adapter is where anti-vacuity quietly dies: it could
#     `tryEval` a helper's verdict, filter a member out of the map, or hand a helper an empty
#     argument, and each of those reads as a green check set. So each helper's own failure mode is
#     re-driven THROUGH the adapter here, plus the two traps that exist only at this level (a
#     roster with no members, homes that do not cover the roster) — because a MISSING check and a
#     passing one look identical in `nix flake check` output.
#
# COVERAGE NOTE — as in ./confinement.nix and ./variant-eval.nix, the homes here are synthetic: the
# contract has no home-manager (ADR-0004), so the adapter is driven with the `force` /
# `positiveControl` hooks pointed at the umbrella's own declared options. That the adapter FORWARDS
# those hooks is itself part of the surface, and is what makes this domain possible at all.
{
  lib,
  pkgs,
  toolkit,
  mkContractRoster,
  mkRosterChecks,
}:
let
  inherit (toolkit) evalHome referenceIdentity;

  # A synthetic roster: plain `{ name; dir; identity; }` members, which is all the adapter consumes
  # (the DERIVATION of a roster from a directory is ./roster.nix's subject, and the real derived one
  # is claimed against below). Built over the suite's REAL reference identity (ADR-0022), so the
  # posture claims run against a credential a consumer actually ships — `ada` carries `$y$`, the
  # public-repo posture `examples/users` chose.
  memberFor = n: {
    name = n;
    dir = ./fixtures/roster/pip;
    identity = referenceIdentity // {
      username = n;
    };
  };
  rosterOf = names: lib.genAttrs names memberFor;
  roster = rosterOf [
    "ana"
    "bo"
  ];

  # A member whose credential is a `$6$` sha512crypt hash — legal under ADR-0019's private-repo
  # posture, and therefore the offender a `require = "yescrypt"` roster must reject.
  offender = memberFor "sixto" // {
    identity = referenceIdentity // {
      username = "sixto";
      hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
    };
  };

  # A synthetic baked home, carrying the attrpath the `force` hook below dereferences — the stand-in
  # for a real `home.activationPackage.drvPath`, whose `.drv` suffix is what proves a variant was
  # forced all the way to its derivation.
  bakedHome = label: {
    contract.requests.gui.desktop = "/nix/store/00000000000000000000000000000000-${label}.drv";
  };
  # The consumer's per-system homes, DERIVED from the roster exactly as a real mapper derives them:
  # two systems, one bake each. Built as a function of the roster so the growth claim below changes
  # the roster and nothing else — the property under test.
  homesOver =
    r:
    lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
    ] (_: lib.mapAttrs (n: _: { base = bakedHome "${n}-base"; }) r);

  # A module set that reopens a system channel (as in ./confinement.nix): a top-level freeform
  # accepts ANY key, so every out-of-universe probe becomes expressible while a legitimate home
  # option still evaluates.
  smuggledSystemChannel = {
    freeformType = lib.types.attrsOf lib.types.anything;
  };

  checksOver =
    args:
    mkRosterChecks (
      {
        inherit pkgs roster;
        homes = homesOver roster;
        # The consumer's builder, per member. This one ignores the member (the synthetic umbrella
        # eval is the same for all of them); a real one resolves the member's own `home.nix`.
        buildHome = _member: evalHome;
        require = "yescrypt";
        # The home-manager-free hooks the contract's own suite must use (ADR-0004): a declared
        # umbrella option in place of `activationPackage.drvPath`, and the sanctioned request
        # channel in place of a home-manager session variable.
        force = c: c.contract.requests.gui.desktop;
        positiveControl = {
          contract.requests.gui.desktop = "plasma";
        };
      }
      // args
    );

  # Every check in the set, forced to its verdict. Each check fails by THROWING at eval (a named
  # assert, like every other contract guard), and an attrset's own evaluation forces none of its
  # values — so a test that only looked at the names would read a set of broken checks as fine.
  verdictsOf = set: lib.foldl' (acc: v: builtins.seq v acc) (lib.attrNames set) (lib.attrValues set);
  passes = args: (builtins.tryEval (verdictsOf (checksOver args))).success;

  # The REAL derived roster (ADR-0022: the synthetic suite borrows real atoms from the positive-
  # space example, never the reverse) — the adapter must cover the fleet a consumer actually ships,
  # not only a roster shaped for it here.
  realRoster = mkContractRoster { usersDir = ../examples/users/users; };
  realChecks = checksOver {
    roster = realRoster;
    homes = homesOver realRoster;
  };
in
{
  assertions = [
    {
      name = "roster adapter: one call yields a confinement + a variant-eval check per member, and one posture check";
      ok =
        lib.attrNames (checksOver { }) == [
          "home-confinement-ana"
          "home-confinement-bo"
          "identity-posture"
          "variant-eval-ana"
          "variant-eval-bo"
        ];
    }
    {
      name = "roster adapter: every check it yields passes over a confined roster whose whole bake evaluates";
      ok = passes { };
    }
    {
      # The property the helpers are roster-generic FOR, now at the call site: the check set follows
      # the roster, so a user added to the users directory is covered without a consumer edit.
      name = "roster adapter: a member added to the roster gains its checks with no other change";
      ok =
        let
          grown = checksOver {
            roster = roster // rosterOf [ "cy" ];
            homes = homesOver (roster // rosterOf [ "cy" ]);
          };
        in
        (grown ? "home-confinement-cy")
        && (grown ? "variant-eval-cy")
        && lib.length (lib.attrNames grown) == 7;
    }
    {
      # Over the REAL reference fleet's derived roster: every member, whoever they are today.
      name = "roster adapter: covers every member of the reference fleet's derived roster (ADR-0022)";
      ok =
        let
          names = lib.attrNames realRoster;
        in
        lib.all (n: (realChecks ? "home-confinement-${n}") && (realChecks ? "variant-eval-${n}")) names
        && lib.length names > 1
        && lib.length (lib.attrNames realChecks) == 2 * lib.length names + 1;
    }
    {
      # The trap that exists only at THIS level: a fold over nobody yields an (almost) empty check
      # set, and a missing check reads exactly like a passing one.
      name = "roster adapter: an empty roster is a hard error, not a small check set";
      ok =
        !(passes {
          roster = { };
          homes = homesOver { };
        });
    }
    {
      # The other adapter-level trap: homes that do not cover the roster. The member is in the
      # roster, so it must be checked — a mapper that skipped it loses that user's whole bake proof.
      name = "roster adapter: a member with no baked homes on a system is a named error, not a skipped check";
      ok =
        !(passes {
          homes = lib.mapAttrs (
            sys: rows: if sys == "aarch64-linux" then removeAttrs rows [ "bo" ] else rows
          ) (homesOver roster);
        });
    }
    {
      name = "roster adapter: homes naming no system at all is a hard error (nothing to check a bake against)";
      ok = !(passes { homes = { }; });
    }
    {
      name = "roster adapter: a homes row that is not an attrset is a broken harness, not a pass";
      ok = !(passes { homes.x86_64-linux = [ "not-an-attrset" ]; });
    }
    {
      # --- the helpers' own guards, re-driven THROUGH the adapter ---
      # Confinement: a module set that reopens a system channel fails, even though its positive
      # control still evaluates.
      name = "roster adapter: confinement still fails when a member's module set smuggles a system channel back in";
      ok = !(passes { buildHome = _member: mods: evalHome (mods ++ [ smuggledSystemChannel ]); });
    }
    {
      # Confinement's positive control: a builder that rejects EVERYTHING satisfies every negative
      # claim, and must not read as confinement through the adapter either.
      name = "roster adapter: confinement still fails when the positive control does not evaluate";
      ok = !(passes { buildHome = _member: _mods: throw "this builder rejects everything"; });
    }
    {
      # Variant-eval: an accidentally-emptied bake. The member IS in `homes` (so the coverage guard
      # above is satisfied), but with no variants — the helper's own anti-vacuous assert must fire.
      name = "roster adapter: variant-eval still fails when a member's bake is emptied";
      ok = !(passes { homes = lib.mapAttrs (_: lib.mapAttrs (_: _: { })) (homesOver roster); });
    }
    {
      # The under-forcing hook: a `force` that never reaches a derivation makes every variant
      # "evaluate" and every probe "expressible". The adapter forwards it, so it breaks LOUDLY.
      name = "roster adapter: a force that stops short of the derivation still fails (no vacuous pass)";
      ok = !(passes { force = _: "never forced"; });
    }
    {
      # Posture: the offender must be caught through the adapter, over the roster's own identities.
      name = "roster adapter: the posture still fails on a member carrying the wrong hash algorithm";
      ok =
        !(passes {
          roster = roster // {
            sixto = offender;
          };
          homes = homesOver (
            roster
            // {
              sixto = offender;
            }
          );
        });
    }
    {
      # The posture stays the CONSUMER's choice: the adapter picks none, so omitting `require` is a
      # call error rather than a quiet default (ADR-0019 — the repo's visibility picks the strength,
      # and an adapter that defaulted would impose one repo's posture on every adopter that never
      # thought about it). Read off the SIGNATURE rather than by calling without it: a missing
      # required argument is one of the few eval errors `tryEval` does not catch, so the "it throws"
      # spelling would take this whole suite down instead of reporting a claim.
      name = "roster adapter: `require` has no default — the posture stays the consumer's choice (ADR-0019)";
      ok =
        let
          formals = builtins.functionArgs mkRosterChecks;
        in
        # …while the two home-shape hooks DO default, which is what lets a home-manager consumer
        # pass neither and a hand-rolled (or synthetic) home override both.
        (formals ? require) && !formals.require && formals.force && formals.positiveControl;
    }
    {
      # The same posture is still a PARAMETER through the adapter: the `$6$` member a public repo
      # rejects is legal in a private one, which is the whole reason `require` is asked for.
      name = "roster adapter: the same roster passes under require = \"libc\" (the posture is a parameter, ADR-0019)";
      ok = passes {
        roster = roster // {
          sixto = offender;
        };
        homes = homesOver (
          roster
          // {
            sixto = offender;
          }
        );
        require = "libc";
      };
    }
  ];

  # Execution proof: the checks a consumer actually wires into `checks.<system>` are real
  # derivations that BUILD (the assertions above only observe their eval verdicts). Built through
  # one node so the suite's own drv keys stay plain names.
  drvs.mkRosterChecks = pkgs.runCommand "conformance-roster-checks" {
    rosterChecks = lib.attrValues (checksOver { });
  } "touch $out";
}
