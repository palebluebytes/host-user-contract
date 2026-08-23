# Conformance domain: STRUCTURAL confinement.
#
# A user's home is a home-manager module with NO system channel: a system option (`users.users`,
# `security.sudo`, `boot.*`, `sops.*`) is *unexpressible* in the user's world, not merely rejected
# or denied downstream. Host-affecting effects reach a user only through what the HOST afforded at
# the bind, which is a decision the user never participates in.
#
# The proof is that these paths are UNDECLARED in the contract home umbrella (modules.nix's
# `homeModule` declares `identity` and nothing else — no freeformType anywhere). So a home that
# sets one throws "option does not exist" at eval. Privilege escalation is impossible because the
# vocabulary to request it does not exist — structural, not a blocklist.
#
# It ALSO proves the shipped `mkConfinementCheck` — the same technique lifted into
# `../check-kit.nix` so a CONSUMER can run it over its OWN real module set (this suite can only
# reach the umbrella; a consumer's imports are where a system channel actually gets smuggled back
# in). The helper's own failure modes are the point: it must reject a smuggled channel, and it must
# NOT pass by rejecting everything (the positive control) or by never forcing the home at all.
{
  lib,
  pkgs,
  toolkit,
  mkConfinementCheck,
  outOfUniverseProbes,
  identitySchema,
}:
let
  inherit (toolkit)
    evalHome
    homeForce
    homePositiveControl
    homeOptionPaths
    ;

  # What the home umbrella is allowed to declare, DERIVED rather than listed: the identity option
  # set is the whole surface, and its field names are already projected out of `identity.nix` by
  # `identity-json.nix`. So this expectation cannot drift from the options it describes — adding a
  # field to the single identity source moves both sides at once, and adding an option that is NOT
  # an identity field moves only one.
  expectedHomeSurface = lib.sort (a: b: a < b) (
    map (f: "identity.${f}") (identitySchema.required ++ identitySchema.optional)
  );

  # Does a one-module home evaluate against the contract umbrella? Force a declared attr
  # (`identity.username`, always present — the synthetic home eval supplies it): building `config`
  # runs the module system's unmatched-definition check across ALL definitions, so an
  # UNDECLARED system option makes this throw — caught as `success = false`. A `false` therefore
  # means "this path is unexpressible", never an unrelated eval error.
  evaluates = mod: (builtins.tryEval (homeForce (evalHome [ mod ]))).success;

  # The system options that are out-of-universe for a home — the negative space itself, read from
  # `../check-kit.nix` (via kit.internal) so the umbrella's proof here and the probe set the shipped
  # `mkConfinementCheck` runs at a consumer are ONE list. Two copies of "what a user must not be
  # able to say" would drift the day a new escalation path is added to only one of them.
  unexpressibleAssertions = lib.mapAttrsToList (path: mod: {
    name = "confinement: `${path}` is unexpressible in the user home (no system channel)";
    ok = !(evaluates mod);
  }) outOfUniverseProbes;

  # --- the shipped consumer check ---
  # A stand-in for a consumer's real home builder. A consumer passes its own `mkHome` (a
  # home-manager configuration, forced through `activationPackage.drvPath`); the contract has no
  # home-manager, so the synthetic umbrella eval plays that role and the force hook points at a
  # declared attr instead. The helper's LOGIC is what is under test here — that the umbrella itself
  # is confined is the block above.
  checkOver =
    args:
    mkConfinementCheck (
      {
        inherit pkgs;
        buildHome = evalHome;
        force = homeForce;
        # The default positive control is a home-manager option, which this home-manager-free
        # builder cannot declare; an optional identity field is the equivalent legitimate option
        # here.
        positiveControl = homePositiveControl;
      }
      // args
    );
  # Does the check PASS? It fails by throwing at eval (a hard, named error, like every other
  # contract guard), so `tryEval` is how a test observes the verdict.
  checkPasses = args: (builtins.tryEval (checkOver args)).success;

  # A module set that smuggles a system channel back in — the hazard the consumer check exists
  # for: a top-level freeform accepts ANY key, so every out-of-universe probe becomes expressible
  # while a legitimate home option still evaluates. Confinement is gone; the positive control alone
  # would not notice.
  smuggledSystemChannel = {
    freeformType = lib.types.attrsOf lib.types.anything;
  };
in
{
  assertions = unexpressibleAssertions ++ [
    {
      # Positive control: confinement is structural, not a broken harness that rejects
      # everything. A legitimate home option (an optional identity field) evaluates.
      name = "confinement: a legitimate home option still evaluates (not a reject-everything harness)";
      ok = evaluates homePositiveControl;
    }
    {
      # The home umbrella declares no `contract` namespace at all: a user's voice lives in its
      # `user.nix`, one level up, and is not a home-manager module. So a home trying to speak
      # outward — to enable a mode, or to name its own desktop — is an eval error rather than a
      # declaration nothing reads, and the two places a value could have lived cannot disagree.
      name = "confinement: a home cannot declare its own modes — `contract.*` is not a home namespace";
      ok =
        !(evaluates { contract.gui.enable = true; }) && !(evaluates { contract.gui.desktop = "plasma"; });
    }
    {
      # The surface ENUMERATED, which is a different claim from every probe above it. A probe says
      # one named path is absent, and a check passes everything it does not name (ADR-0006) — so the
      # day an option is added to the home umbrella, no probe notices and the comments describing
      # the surface quietly go stale. This lists every path the umbrella declares and compares it
      # to the identity option set, so ANY change to what a home may say fails here by name.
      name = "confinement: the home umbrella declares exactly the identity option set and nothing else";
      ok = homeOptionPaths == expectedHomeSurface;
    }
    {
      name = "mkConfinementCheck: passes over a confined real module set (issue #35)";
      ok = checkPasses { };
    }
    {
      # The claim the consumer check exists to make: a module set that reopens a system channel
      # FAILS, even though its positive control still evaluates.
      name = "mkConfinementCheck: fails when the module set smuggles a system channel back in";
      ok =
        !(checkPasses {
          buildHome = mods: evalHome (mods ++ [ smuggledSystemChannel ]);
        });
    }
    {
      # The part people forget. A harness that rejects EVERYTHING satisfies every negative claim;
      # only the positive control tells confinement from a broken builder.
      name = "mkConfinementCheck: fails when the positive control does not evaluate (rejects-everything is not confinement)";
      ok =
        !(checkPasses {
          buildHome = _: throw "this builder rejects everything";
        });
    }
    {
      # The other way to be vacuous: a `force` that never forces the module merge makes every
      # probe look expressible, so the negative claims fail — the check cannot silently pass.
      name = "mkConfinementCheck: fails when the builder's home is never forced (no vacuous pass)";
      ok = !(checkPasses { force = _: "never forced"; });
    }
  ];

  # Execution proof: the check the consumer actually wires into `checks.<system>` is a real
  # derivation that BUILDS (the assertions above only observe its eval verdict).
  drvs.mkConfinementCheck = checkOver { name = "conformance-home-confinement"; };
}
