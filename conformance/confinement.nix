# Conformance domain: STRUCTURAL confinement (ADR-0002, issue #1 acceptance criterion 2).
#
# The user surface is a home-manager module with NO system channel. Host-affecting effects
# leave the user ONLY as `contract.requests` the host harvests and applies `mkIf granted`
# (proven in ./bind.nix / ./requests.nix). This file proves the OTHER half of that promise —
# the negative space: a system option (`users.users`, `security.sudo`, `boot.*`, `sops.*`) is
# *unexpressible* in the user's world, not merely rejected or `mkIf`-denied downstream.
#
# The proof is that these paths are UNDECLARED in the contract home umbrella (modules.nix's
# `homeModule` declares only `identity`, `custom.home.profiles`, and the fully-typed
# `contract.wants` / `contract.requests` namespaces — no freeformType anywhere since ADR-0028). So a home that
# sets one throws "option does not exist" at eval, exactly as a stray `home.packages` does in
# the headless traceUser inspector. This is the SAME universe traceUser harvests in (../lib.nix),
# so what is unexpressible here is unexpressible in a real bound user. Privilege escalation is
# impossible because the vocabulary to request it does not exist — structural, not a blocklist.
#
# It ALSO proves the shipped `mkConfinementCheck` (issue #35) — the same technique lifted into
# `../checks.nix` so a CONSUMER can run it over its OWN real module set (this suite can only reach
# the umbrella; a consumer's imports are where a system channel actually gets smuggled back in).
# The helper's own failure modes are the point: it must reject a smuggled channel, and it must NOT
# pass by rejecting everything (the positive control) or by never forcing the home at all.
{
  lib,
  pkgs,
  toolkit,
  mkConfinementCheck,
  outOfUniverseProbes,
}:
let
  inherit (toolkit) evalHome;

  # Does a one-module home evaluate against the contract umbrella? Force a declared attr
  # (`contract.requests.gui.desktop`, always present via its "" default): building `config`
  # runs the module system's unmatched-definition check across ALL definitions, so an
  # UNDECLARED system option makes this throw — caught as `success = false`. A `false` therefore
  # means "this path is unexpressible", never an unrelated eval error.
  evaluates = mod: (builtins.tryEval ((evalHome [ mod ]).contract.requests.gui.desktop)).success;

  # The system options ADR-0002 names as out-of-universe — the negative space itself, read from
  # `../checks.nix` (via kit.internal) so the umbrella's proof here and the probe set the shipped
  # `mkConfinementCheck` runs at a consumer are ONE list. Two copies of "what a user must not be
  # able to say" would drift the day a new escalation path is added to only one of them.
  unexpressibleAssertions = lib.mapAttrsToList (path: mod: {
    name = "confinement: `${path}` is unexpressible in the user home (no system channel, ADR-0002)";
    ok = !(evaluates mod);
  }) outOfUniverseProbes;

  # --- the shipped consumer check (issue #35) ---
  # A stand-in for a consumer's real home builder. A consumer passes its own `mkHome` (a
  # home-manager configuration, forced through `activationPackage.drvPath`); the contract has no
  # home-manager (ADR-0004), so the synthetic umbrella eval plays that role and the force hook
  # points at a declared attr instead. The helper's LOGIC is what is under test here — that the
  # umbrella itself is confined is the block above.
  checkOver =
    args:
    mkConfinementCheck (
      {
        inherit pkgs;
        buildHome = evalHome;
        force = c: c.contract.requests.gui.desktop;
        # The default positive control is a home-manager option, which this home-manager-free
        # builder cannot declare; the sanctioned request channel is the equivalent legitimate
        # option here (and exercises the parameter).
        positiveControl = {
          contract.requests.gui.desktop = "plasma";
        };
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
      # everything. A legitimate host-affecting request (the user's ONLY channel) evaluates.
      name = "confinement: a legitimate contract.requests still evaluates (the sanctioned channel)";
      ok = evaluates { contract.requests.gui.desktop = "plasma"; };
    }
    {
      # Until ADR-0028 the freeformType inside `contract.requests` ACCEPTED a system-shaped key as
      # an inert (never-bridged) request, so this claim read "inert under contract.requests, fatal
      # at top level". With the freeform gone the namespace is fully typed and the same key throws
      # in BOTH positions. Confinement itself is unchanged (an inert request never reached system
      # state either way); what changed is that the typo-net now covers the request namespace too.
      name = "confinement: `users.users` is unexpressible at top level AND inside contract.requests";
      ok =
        !(evaluates { contract.requests.users.users.root = "inert-request"; })
        && !(evaluates { users.users.root.hashedPassword = "!escalate"; });
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
