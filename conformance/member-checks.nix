# Conformance domain: the MEMBER-SET ADAPTER over the check kit (issue #60).
#
# `mkMemberChecks` applies the three shipped helpers — confinement, home-eval, credential
# posture — across a whole members in one call. The helpers' own logic is proven next door
# (./confinement.nix, ./home-eval.nix, ./identity-posture.nix); what this domain proves is
# everything the ADAPTER is responsible for:
#
#   - the SHAPE it yields: a confinement and a home-eval check per member, one posture check
#     over the members, each under the single-sourced name;
#   - that the members is what it maps over, so a member added to the members is covered with no
#     other edit — the whole reason the helpers are members-generic;
#   - that every guard SURVIVES the fold. An adapter is where anti-vacuity quietly dies: it could
#     `tryEval` a helper's verdict, filter a member out of the map, or hand a helper an empty
#     argument, and each of those reads as a green check set. So each helper's own failure mode is
#     re-driven THROUGH the adapter here, plus the two traps that exist only at this level (a
#     members with no members, homes that do not cover the members) — because a MISSING check and a
#     passing one look identical in `nix flake check` output.
#
# COVERAGE NOTE — as in ./confinement.nix and ./home-eval.nix, the homes here are synthetic: the
# contract has no home-manager (ADR-0004), so the adapter is driven with the `force` /
# `positiveControl` hooks pointed at the umbrella's own declared options. That the adapter FORWARDS
# those hooks is itself part of the surface, and is what makes this domain possible at all.
{
  lib,
  pkgs,
  toolkit,
  mkMembers,
  mkMemberChecks,
}:
let
  inherit (toolkit) evalHome referenceIdentity;

  # A synthetic members: plain `{ name; dir; identity; }` members, which is all the adapter consumes
  # (the DERIVATION of a member set from a directory is ./members.nix's subject, and the real derived one
  # is claimed against below). Built over the suite's REAL reference identity (ADR-0022), so the
  # posture claims run against a credential a consumer actually ships — `ada` carries `$y$`, the
  # public-repo posture `examples/users` chose.
  memberFor = n: {
    name = n;
    dir = ./fixtures/members/pip;
    identity = referenceIdentity // {
      username = n;
    };
  };
  membersOf = names: lib.genAttrs names memberFor;
  members = membersOf [
    "ana"
    "bo"
  ];

  # A member whose credential is a `$6$` sha512crypt hash — legal under ADR-0019's private-repo
  # posture, and therefore the offender a `require = "yescrypt"` members must reject.
  offender = memberFor "sixto" // {
    identity = referenceIdentity // {
      username = "sixto";
      hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
    };
  };

  # A synthetic built home, carrying the attrpath the `force` hook below dereferences — the
  # stand-in for a real `home.activationPackage.drvPath`, whose `.drv` suffix is what proves a home
  # was forced all the way to its derivation.
  builtHome = tag: {
    contract.requests.gui.desktop = "/nix/store/00000000000000000000000000000000-${tag}.drv";
  };
  # The consumer's per-system homes, DERIVED from the members exactly as a real mapper derives them:
  # two systems, one MODE each. Built as a function of the members so the growth claim below changes
  # the members and nothing else — the property under test.
  homesOver =
    r:
    lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
    ] (_: lib.mapAttrs (n: _: { cli = builtHome "${n}-cli"; }) r);

  # A module set that reopens a system channel (as in ./confinement.nix): a top-level freeform
  # accepts ANY key, so every out-of-universe probe becomes expressible while a legitimate home
  # option still evaluates.
  smuggledSystemChannel = {
    freeformType = lib.types.attrsOf lib.types.anything;
  };

  checksOver =
    args:
    mkMemberChecks (
      {
        inherit pkgs members;
        homes = homesOver members;
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

  # The REAL derived members (ADR-0022: the synthetic suite borrows real atoms from the positive-
  # space example, never the reverse) — the adapter must cover the fleet a consumer actually ships,
  # not only a member set shaped for it here.
  realMembers = mkMembers { usersDir = ../examples/users/users; };
  realChecks = checksOver {
    members = realMembers;
    homes = homesOver realMembers;
  };
in
{
  assertions = [
    {
      name = "members adapter: one call yields a confinement + a home-eval check per member, and one posture check";
      ok =
        lib.attrNames (checksOver { }) == [
          # `attrNames` is sorted, so this list is in NAME order, not emission order. Both
          # per-member checks now share the `home-` prefix, so they group in check output.
          "home-confinement-ana"
          "home-confinement-bo"
          "home-eval-ana"
          "home-eval-bo"
          "identity-posture"
        ];
    }
    {
      name = "members adapter: every check it yields passes over a confined members whose whole bake evaluates";
      ok = passes { };
    }
    {
      # The property the helpers are members-generic FOR, now at the call site: the check set follows
      # the members, so a user added to the users directory is covered without a consumer edit.
      name = "members adapter: a member added to the members gains its checks with no other change";
      ok =
        let
          grown = checksOver {
            members = members // membersOf [ "cy" ];
            homes = homesOver (members // membersOf [ "cy" ]);
          };
        in
        (grown ? "home-confinement-cy")
        && (grown ? "home-eval-cy")
        && lib.length (lib.attrNames grown) == 7;
    }
    {
      # Over the REAL reference fleet's derived members: every member, whoever they are today.
      name = "members adapter: covers every member of the reference fleet's derived members (ADR-0022)";
      ok =
        let
          names = lib.attrNames realMembers;
        in
        lib.all (n: (realChecks ? "home-confinement-${n}") && (realChecks ? "home-eval-${n}")) names
        && lib.length names > 1
        && lib.length (lib.attrNames realChecks) == 2 * lib.length names + 1;
    }
    {
      # The trap that exists only at THIS level: a fold over nobody yields an (almost) empty check
      # set, and a missing check reads exactly like a passing one.
      name = "members adapter: an empty members is a hard error, not a small check set";
      ok =
        !(passes {
          members = { };
          homes = homesOver { };
        });
    }
    {
      # The other adapter-level trap: homes that do not cover the members. The member is in the
      # members, so it must be checked — a mapper that skipped it loses that user's whole bake proof.
      name = "members adapter: a member with no baked homes on a system is a named error, not a skipped check";
      ok =
        !(passes {
          homes = lib.mapAttrs (
            sys: entry: if sys == "aarch64-linux" then removeAttrs entry [ "bo" ] else entry
          ) (homesOver members);
        });
    }
    {
      name = "members adapter: homes naming no system at all is a hard error (nothing to check a home against)";
      ok = !(passes { homes = { }; });
    }
    {
      name = "members adapter: a homes entry that is not an attrset is a broken harness, not a pass";
      ok = !(passes { homes.x86_64-linux = [ "not-an-attrset" ]; });
    }
    {
      # The two SHAPE guards under the diagnoses above: a member set handed as a list (the
      # `lib.attrValues` the posture helper wants, one call too early) and homes handed as
      # something other than a per-system attrset. Both must be told what they are, rather than
      # reported as EMPTY — which is a different mistake with a different fix.
      name = "members adapter: a member set or a homes that is not an attrset is named as a shape error";
      ok = !(passes { members = lib.attrValues members; }) && !(passes { homes = [ ]; });
    }
    {
      # --- the helpers' own guards, re-driven THROUGH the adapter ---
      # Confinement: a module set that reopens a system channel fails, even though its positive
      # control still evaluates.
      name = "members adapter: confinement still fails when a member's module set smuggles a system channel back in";
      ok = !(passes { buildHome = _member: mods: evalHome (mods ++ [ smuggledSystemChannel ]); });
    }
    {
      # Confinement's positive control: a builder that rejects EVERYTHING satisfies every negative
      # claim, and must not read as confinement through the adapter either.
      name = "members adapter: confinement still fails when the positive control does not evaluate";
      ok = !(passes { buildHome = _member: _mods: throw "this builder rejects everything"; });
    }
    {
      # Bake-eval: an accidentally-emptied bake. The member IS in `homes` (so the coverage guard
      # above is satisfied), but with no bakes — the helper's own anti-vacuous assert must fire.
      name = "members adapter: home-eval still fails when a member's homes are emptied";
      ok = !(passes { homes = lib.mapAttrs (_: lib.mapAttrs (_: _: { })) (homesOver members); });
    }
    {
      # The under-forcing hook: a `force` that never reaches a derivation makes every bake
      # "evaluate" and every probe "expressible". The adapter forwards it, so it breaks LOUDLY.
      name = "members adapter: a force that stops short of the derivation still fails (no vacuous pass)";
      ok = !(passes { force = _: "never forced"; });
    }
    {
      # Posture: the offender must be caught through the adapter, over the members' own identities.
      name = "members adapter: the posture still fails on a member carrying the wrong hash algorithm";
      ok =
        !(passes {
          members = members // {
            sixto = offender;
          };
          homes = homesOver (
            members
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
      name = "members adapter: `require` has no default — the posture stays the consumer's choice (ADR-0019)";
      ok =
        let
          formals = builtins.functionArgs mkMemberChecks;
        in
        # …while the two home-shape hooks DO default, which is what lets a home-manager consumer
        # pass neither and a hand-rolled (or synthetic) home override both.
        (formals ? require) && !formals.require && formals.force && formals.positiveControl;
    }
    {
      # The same posture is still a PARAMETER through the adapter: the `$6$` member a public repo
      # rejects is legal in a private one, which is the whole reason `require` is asked for.
      name = "members adapter: the same members passes under require = \"libc\" (the posture is a parameter, ADR-0019)";
      ok = passes {
        members = members // {
          sixto = offender;
        };
        homes = homesOver (
          members
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
  drvs.mkMemberChecks = pkgs.runCommand "conformance-members-checks" {
    memberChecks = lib.attrValues (checksOver { });
  } "touch $out";
}
