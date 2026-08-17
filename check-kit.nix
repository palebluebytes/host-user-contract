# The contract's CHECK KIT (issue #35) — proofs a CONSUMER runs over its OWN repo, shipped so
# every user/host repo calls one function instead of re-deriving a technique it can get subtly
# wrong. Distinct from `conformance/`, which proves the contract's own promises in isolation:
# these checks can only be run where the consumer's real material lives (its actual module
# imports, its actual roster of identities, its actual per-system bake matrix), which is exactly
# why the contract cannot make them for anyone and must hand them over as functions.
#
# Lib-only and package-free (ADR-0004): this file is a pure function of `lib`. Each check takes
# the caller's `pkgs` (for the trivial `runCommand` witness) and — crucially for the confinement
# check — the caller's OWN home builder, so the contract never needs home-manager to prove a
# home-manager module set. Every check fails LOUDLY at eval with a named message, the same
# posture as every other contract guard (`assert lib.assertMsg …`), so a failing check reports
# WHICH claim broke rather than a build log to read.
{ lib }:
let
  # The negative space itself (ADR-0002): system options a confined user home must be unable to
  # NAME. Each is a real NixOS/sops option a user might reach for to escalate; the home umbrella
  # declares none of them, so each throws "option does not exist" at eval. Single-sourced here and
  # read BOTH by `mkConfinementCheck` below and by the contract's own umbrella proof
  # (`conformance/confinement.nix`, via kit.internal) — one list of "what a user must not be able
  # to say", so a newly recognised escalation path cannot land in one copy and not the other.
  outOfUniverseProbes = {
    "users.users" = {
      users.users.root.hashedPassword = "!escalate";
    };
    "security.sudo" = {
      security.sudo.wheelNeedsPassword = false;
    };
    "boot.loader" = {
      boot.loader.grub.enable = true;
    };
    "sops.secrets" = {
      sops.secrets."steal".sopsFile = "/dev/null";
    };
    # A privileged group grab via the system account option (grants flow the other way — the host
    # adds groups `mkIf granted`, ADR-0003).
    "users.users.extraGroups" = {
      users.users.example.extraGroups = [ "wheel" ];
    };
  };

  # The credential postures — exactly the TWO ADR-0019 names, as prefix rules over
  # `identity.json`'s `hashedPassword` (a crypt hash's `$id$` prefix IS its algorithm label):
  # "**Private repo** — any libc-`crypt` hash (`$6$` sha512crypt is fine) … **Public / shared
  # repo** — **yescrypt** (`$y$`)". No third posture is invented here: a posture a repo can ask
  # for is a decision ADR-0019 made, and this table only spells each one once so no repo
  # hand-writes a `$y$` comparison. Each carries its remedy, so a failure says how to fix itself.
  credentialPostures = {
    # Public / shared repo: the hash is world-readable, so it must be memory-hard.
    yescrypt = {
      prefixes = [ "$y$" ];
      description = "yescrypt (`$y$`) — the public/shared-repo posture";
      remedy = "mkpasswd -m yescrypt";
    };
    # Private repo: any libc-crypt hash. Still rejects an EMPTY or non-crypt field — "some hash"
    # is a posture, "no credential at all" is not.
    libc = {
      prefixes = [
        "$y$"
        "$gy$"
        "$7$"
        "$6$"
        "$5$"
        "$2b$"
        "$2y$"
        "$2a$"
        "$1$"
      ];
      description = "any libc-crypt hash — the private-repo posture";
      remedy = "mkpasswd -m yescrypt (any libc method qualifies)";
    };
  };

  # What a passing check looks like: an empty witness derivation. Both checks fail at EVAL (a
  # named `assert`), so the derivation exists only to be something `checks.<system>.<name>` can
  # point at — single-sourced so the two cannot drift into different shapes.
  okWitness = pkgs: name: pkgs.runCommand "${name}-ok" { } "touch $out";

  # The two HOOK DEFAULTS the checks below share, stated once. `defaultForce` is home-manager's
  # activation derivation path — the home shape ~every consumer has — and `defaultPositiveControl`
  # a legitimate home-manager option (a session variable: no packages, no closure). Single-sourced
  # because three functions now name them (`mkConfinementCheck`, `mkVariantEvalCheck`, and the
  # roster adapter that forwards both): a second copy would drift the day home-manager renames an
  # attribute, leaving one check forcing a home the others do not.
  defaultForce = home: home.activationPackage.drvPath;
  defaultPositiveControl = {
    home.sessionVariables.CONTRACT_CONFINEMENT_CONTROL = "ok";
  };

  # The per-user check NAMES the roster adapter publishes under (issue #60), stated once. Each was
  # previously spelled TWICE per call site — as the `checks.<system>` attribute AND as the check's
  # own `name`, which is what its failure message reports — so a renamed check could report itself
  # under a name no `nix flake check -L` output would show. One definition, both uses.
  checkNames = {
    confinement = user: "home-confinement-${user}";
    variantEval = user: "variant-eval-${user}";
    # Not per-member: one posture claim over the whole roster (see mkIdentityPostureCheck).
    identityPosture = "identity-posture";
  };

  # mkConfinementCheck (issue #35): prove a consumer's REAL module set has no system channel.
  #
  # `conformance/confinement.nix` proves the contract UMBRELLA is confined — the right proof for
  # the contract's own suite, and only half the promise. A consumer needs the other half: that its
  # own imports (a shared home module, a sops-nix backend, an overlay's module) did not smuggle a
  # system channel back in. That proof can only run where those imports are, so the contract ships
  # the technique instead of the verdict.
  #
  # SIGNATURE — the caller passes its own home BUILDER, which is what keeps this package-free and
  # home-manager-free (ADR-0004): the contract never imports home-manager, it only applies a
  # function the consumer supplies. A typical user repo already has one:
  #
  #     contract.lib.mkConfinementCheck {
  #       inherit pkgs;
  #       buildHome = extraModules: mkHome { userDir = ./users/ada; identity = adaId; extra = extraModules; };
  #     }
  #
  # `buildHome` takes a LIST of extra modules (the check appends exactly one probe at a time) and
  # returns the consumer's evaluated home. `force` then forces that home hard enough to run the
  # module system's unmatched-definition check — by default `activationPackage.drvPath`, the
  # home-manager shape ~every consumer has; a hand-rolled `evalModules` home overrides it (e.g.
  # `force = c: c.some.declared.option`). It is a hook rather than an assumption because the
  # contract cannot know the consumer's home shape, and a home that is never forced would make the
  # whole check vacuous.
  #
  # It CANNOT pass vacuously, in either direction — the two ways this check is got wrong by hand:
  #   - reject-everything (a broken builder, a typo'd path): every out-of-universe probe "fails to
  #     evaluate" and the check looks green. The POSITIVE CONTROL closes this — a legitimate home
  #     option must still evaluate. This is the part people forget, so it is not optional here.
  #   - force-nothing (a lazily-returned home): every probe "evaluates" and the negative claims
  #     fail loudly. So an under-forcing `force` breaks the check LOUDLY rather than silently.
  #
  # An eval failure `tryEval` cannot catch (an infinite recursion from a module set that is BROKEN
  # rather than merely permissive) propagates raw: still a failing check, but reported as the
  # underlying error instead of the messages below.
  #
  # COVERAGE NOTE — `conformance/confinement.nix` drives this function's logic through a synthetic
  # home-manager-free builder (it has to: ADR-0004). The two DEFAULTS a real consumer relies on —
  # `force = home.activationPackage.drvPath` and the `home.sessionVariables` positive control —
  # are therefore only exercised where home-manager actually exists, i.e. in a consumer repo's own
  # `checks`. Keep them in step with home-manager's option names.
  mkConfinementCheck =
    {
      buildHome,
      pkgs,
      name ? "home-confinement",
      force ? defaultForce,
      # A legitimate home option — the control that proves the builder still says yes to something.
      # Defaults to a home-manager option (a session variable: no packages, no closure), since the
      # builder is a home-manager one by default.
      positiveControl ? defaultPositiveControl,
    }:
    let
      # Does the home still evaluate with this one extra module merged in? An UNDECLARED option
      # throws inside the module system, caught here as `success = false`.
      evaluates = mod: (builtins.tryEval (force (buildHome [ mod ]))).success;
      expressible = lib.filter (path: evaluates outOfUniverseProbes.${path}) (
        lib.attrNames outOfUniverseProbes
      );
      controlOk = evaluates positiveControl;
    in
    # Ordered deliberately: report a broken harness BEFORE reporting confinement, or a builder
    # that rejects everything would be read as a passing check with a strange name.
    assert lib.assertMsg controlOk (
      "${name}: the POSITIVE CONTROL did not evaluate — this module set rejects even a legitimate "
      + "home option, so its rejection of system options proves nothing about confinement. Fix the "
      + "builder (or pass a `positiveControl` this home actually declares) before reading this check."
    );
    assert lib.assertMsg (expressible == [ ]) (
      "${name}: this module set has a SYSTEM CHANNEL — the out-of-universe option(s) "
      + "[${lib.concatStringsSep ", " expressible}] are expressible in the home, so a user could "
      + "reach host state directly (ADR-0002). Something in the imports declares them (a freeform "
      + "type, or a NixOS module pulled into the home); remove it. If instead the home is never "
      + "FORCED by `force`, every probe looks expressible — check that `force` reaches the module "
      + "merge (the default is `home.activationPackage.drvPath`)."
    );
    okWitness pkgs name;

  # mkIdentityPostureCheck (issue #35): assert every identity in a repo's OWN roster carries the
  # login-credential posture that repo has chosen (ADR-0019).
  #
  # OPT-IN BY CONSTRUCTION, and that is the whole design. ADR-0019 makes the posture conditional
  # and consumer-owned — a private repo may legitimately ship `$6$` sha512crypt; a public/shared
  # repo wants yescrypt because its hash is world-readable. So `loadIdentity` imposes NO hash
  # policy: baking yescrypt into the loader would impose one repo's public posture on every
  # consumer, including the untrusted roaming single-user flakes the greeter exists for. A repo
  # states its own posture, once, by calling this:
  #
  #     contract.lib.mkIdentityPostureCheck {
  #       inherit pkgs;
  #       identities = map contract.lib.loadIdentity rosterPaths;  # derived, never hardcoded
  #       require = "yescrypt";
  #     }
  #
  # `require` has NO DEFAULT: the contract does not pick a repo's posture, so the caller must say
  # which one it is asserting. Known postures are `credentialPostures` above (ADR-0019's two:
  # `yescrypt`, `libc`); an unknown name is a loud error naming them, since a posture typo must
  # never read as "checked". `identities` is a LIST of loaded identities (`lib.attrValues` an
  # attrset roster) — derive it from the users directory rather than hardcoding it, so a newly
  # added user is covered instead of silently skipped; an empty list is a hard error rather than a
  # vacuous pass.
  mkIdentityPostureCheck =
    {
      identities,
      require,
      pkgs,
      name ? "identity-posture",
    }:
    let
      posture =
        credentialPostures.${require} or (throw (
          "${name}: unknown credential posture '${require}' — known postures are: "
          + "${lib.concatStringsSep ", " (lib.attrNames credentialPostures)} (ADR-0019)."
        ));
      # `loadIdentity` returns the identity.json RAW (the option submodule fills defaults only
      # once the value is assigned to an option), and `hashedPassword` is an OPTIONAL field — so a
      # roster entry may legitimately have no such attribute. Default it to "" here, or the
      # documented call above dies with `attribute 'hashedPassword' missing` instead of this
      # check's named verdict: an absent credential is a posture FAILURE, not a crash.
      hashOf = id: id.hashedPassword or "";
      satisfies = id: lib.any (p: lib.hasPrefix p (hashOf id)) posture.prefixes;
      offenders = lib.filter (id: !(satisfies id)) identities;
      # Name the offender and the algorithm it DOES carry. Only a well-formed `$id$` prefix is
      # echoed (a short alphanumeric algorithm label, never key material) — anything else is
      # reported as unrecognised rather than printed, so a plaintext or otherwise non-crypt field
      # is never quoted into a build log.
      describe =
        id:
        let
          hash = hashOf id;
          matched = builtins.match "\\$([a-zA-Z0-9]{1,6})\\$.*" hash;
          algorithm =
            if hash == "" then
              "no hash"
            else if matched == null then
              "<unrecognised, not a crypt hash>"
            else
              "'$" + lib.head matched + "$'";
        in
        "${id.username or "<identity with no username>"} (${algorithm})";
    in
    assert lib.assertMsg (lib.isList identities) (
      "${name}: `identities` must be a LIST of loaded identities; an attrset roster is passed as "
      + "`lib.attrValues roster`."
    );
    assert lib.assertMsg (identities != [ ]) (
      "${name}: no identities to check — a posture check over an empty roster passes vacuously "
      + "forever. Derive the roster from the users directory (every subdir with an identity.json) "
      + "so a newly added user is covered rather than silently skipped."
    );
    assert lib.assertMsg (offenders == [ ]) (
      "${name}: identity.json credential(s) do not carry the required posture "
      + "${posture.description}: ${lib.concatMapStringsSep ", " describe offenders}. "
      + "Re-hash with `${posture.remedy}` (ADR-0019: the credential travels with the user as "
      + "public data, and repo visibility picks the hash strength)."
    );
    okWitness pkgs name;

  # mkVariantEvalCheck (issue #49, decision #43): prove ONE user's every baked variant EVALUATES
  # on every system the repo bakes it for — the roster-generic replacement for the hand-written
  # cross-arch eval checks each user's `checks.nix` used to carry. A consumer's mapper applies it
  # per user over the derived roster (failure attribution rides the check name), so a typical
  # user ships no check file at all:
  #
  #     contract.lib.mkVariantEvalCheck {
  #       inherit pkgs;
  #       homesFor = sys: rosterHomes.${sys}.${user};   # sys → { <label> = home; }, ONE user's bake
  #       systems = repoSystems;                        # every system this repo bakes (a fleet fact)
  #     }
  #
  # Deliberately SHAPE-AGNOSTIC: "everything we bake, evaluates" is this helper's fact; WHICH
  # variants a fleet bakes per system is the consumer mapper's fact, guarded where its per-system
  # filter lives (the contract's `powerset(homeAffecting)` is only the upper bound a host could
  # grant, never a per-system baking obligation). And it forces ALL handed systems, the native one
  # included — redundant with `checks = packages` build-depending on the native homes, but "the
  # whole handed matrix evaluates" is a simpler contract than "the complement of whatever else
  # covers".
  #
  # Deliberately NO `tryEval` around the force: an eval failure propagates RAW as a failing check.
  # `tryEval` cannot tell "no aarch64 build upstream" from a typo'd package name — both would
  # collapse into one boolean — and the underlying error message is exactly the diagnostic the
  # check exists to surface (the reasoning the old hand-written checks documented).
  #
  # COVERAGE NOTE — like `mkConfinementCheck`, `conformance/variant-eval.nix` drives this logic
  # through synthetic homes (it has to: ADR-0004). The `activationPackage.drvPath` default over a
  # REAL home-manager home is therefore only exercised in a consumer repo's own `checks` — keep it
  # in step with home-manager's attribute names.
  mkVariantEvalCheck =
    {
      homesFor,
      systems,
      pkgs,
      name ? "variant-eval",
      # The same override hook as mkConfinementCheck: force a variant hard enough to prove it
      # evaluates — by default its derivation path, the home-manager shape ~every consumer has.
      force ? defaultForce,
    }:
    let
      homesBySystem = lib.genAttrs systems homesFor;
      # A bake that is not a non-empty attrset — an emptied variant set, or a mapper handing
      # something that is not a variant attrset at all.
      vacuousSystems = lib.filter (
        sys: !(lib.isAttrs homesBySystem.${sys}) || homesBySystem.${sys} == { }
      ) systems;
      # Every system × variant whose forced value is NOT a `.drv` path. A variant that does not
      # evaluate never lands here — its error propagates raw out of `force` (no tryEval, above) —
      # so an entry in this list means `force` stopped short of the derivation.
      unforced = lib.concatMap (
        sys:
        map (label: "${sys}/${label}") (
          lib.filter (label: !lib.hasSuffix ".drv" (force homesBySystem.${sys}.${label})) (
            lib.attrNames homesBySystem.${sys}
          )
        )
      ) systems;
    in
    # Ordered deliberately, anti-vacuous BEFORE evaluability: a check that forced nothing must
    # report the emptied bake, not read as "every variant evaluates".
    #
    # This first assert EXTENDS issue #49's anti-vacuous clause ("for every system in `systems`,
    # `homesFor sys` is a non-empty attrset") to the list itself, which that wording passes over:
    # `systems = [ ]` satisfies it for-all-vacuously, so the same emptied-bake hazard one level up
    # would read as green forever. Same species, same verdict — a derived system list that filters
    # down to nothing is a mapper bug, not a passing check.
    assert lib.assertMsg (systems != [ ]) (
      "${name}: the systems list is empty — a variant-eval check over zero systems passes "
      + "vacuously forever. Hand it every system this repo bakes (the fleet's system list, "
      + "derived, never hardcoded)."
    );
    assert lib.assertMsg (vacuousSystems == [ ]) (
      "${name}: no baked variants for [${lib.concatStringsSep ", " vacuousSystems}] — `homesFor` "
      + "must return a NON-EMPTY attrset of this user's baked homes for every handed system. An "
      + "accidentally-emptied bake (a per-system filter gone wrong in the mapper) must fail here, "
      + "never read as a passing eval check."
    );
    assert lib.assertMsg (unforced == [ ]) (
      "${name}: forcing [${lib.concatStringsSep ", " unforced}] did not yield a `.drv` path, so "
      + "\"this variant evaluates\" was never actually proven. `force` must reach the variant's "
      + "derivation (the default is `home.activationPackage.drvPath`); a hook that stops short "
      + "would make every evaluability claim vacuous."
    );
    okWitness pkgs name;

  # mkRosterChecks (issue #60): the ROSTER ADAPTER over the three helpers above — ONE call takes a
  # consumer's roster plus its own material (its home builder, its per-system homes, the credential
  # posture it has chosen) and yields the whole per-user check set, named.
  #
  # The helpers are roster-generic for a reason: a hand-listed set always misses the entry someone
  # forgot to add. Applying them by hand re-introduced exactly that at the call site — two
  # `mapAttrs'` folds over the roster, each check's name spelled twice, and two closures threaded
  # per user, re-typed in every consumer. The mapping is not a fleet's fact; it is the same fold
  # every consumer of the kit performs, so the contract performs it:
  #
  #     checks.<system> = packages.<system> // contract.lib.mkRosterChecks {
  #       inherit pkgs roster homes;
  #       buildHome = member: extraModules: mkHome { inherit member extraModules; };
  #       require = "yescrypt";
  #     };
  #
  # yielding `home-confinement-<user>` and `variant-eval-<user>` per roster member, plus one
  # `identity-posture` over the whole roster — every name from `checkNames` above, so a call site
  # spells none of them.
  #
  # It REPLACES nothing. The three helpers stay public and separately callable: a single-user repo
  # has no roster to adapt, and a repo that wants confinement alone should call for confinement
  # alone. This is the roster fold over them, and it is written in terms of exactly the same
  # public arguments those calls take.
  #
  # SIGNATURE — what stays the consumer's, stays the consumer's:
  #   `roster`    the ADR-0020 roster (`mkContractRoster`, issue #57), the authority on WHO is
  #               checked. Derived, so a user added to the directory is covered the moment it
  #               exists; an EMPTY one is a hard error, since a check set over nobody is green
  #               forever.
  #   `homes`     the consumer's per-system homes AS IT ALREADY HOLDS THEM —
  #               `{ <system>.<user>.<label> = home; }`. The systems checked are its own key set, so
  #               "which systems this fleet bakes" is read off the material rather than handed a
  #               second time and trusted to agree.
  #   `buildHome` `member: extraModules: home` — the consumer's own builder, curried per member.
  #               Same package-free injection `mkConfinementCheck` takes (ADR-0004): the contract
  #               applies a function it never imports.
  #   `require`   the credential posture, with NO DEFAULT here either. ADR-0019 makes it
  #               consumer-owned, and an adapter that picked one would impose a posture on every
  #               repo that adopted the adapter — precisely what the helper refuses to do.
  #   `force` / `positiveControl` — forwarded to the helpers unchanged, defaulting to the same
  #               home-manager hooks, so a hand-rolled (or synthetic) home is still checkable
  #               through the adapter rather than only through the helpers.
  #
  # Every anti-vacuity guard the helpers carry survives, because the adapter adds no `tryEval` and
  # no filtering: it passes the material through. What it adds is the traps that only exist ONE
  # LEVEL UP, where the fold is — a roster with no members, homes naming no system, and homes that
  # do not cover the roster. Each of those yields a check set that is merely SMALLER, and a missing
  # check is indistinguishable from a passing one in `nix flake check` output. (Plus the two SHAPE
  # guards those diagnoses need to stay honest: a roster or a homes row that is not an attrset gets
  # told so, rather than being reported as empty or iterated over.)
  #
  # The coverage rule is worth stating outright, because it is the one thing the adapter asks of a
  # consumer that the helpers do not: every member bakes on every system in `homes`. That is the
  # shape `mkBakeMatrix` already implies — its rows are per SYSTEM, not per user — and it is what
  # makes "who is unchecked" answerable at all. A fleet that genuinely bakes different members on
  # different systems is outside this fold and calls the three helpers per user, which is one more
  # reason they stay public.
  mkRosterChecks =
    {
      roster,
      homes,
      buildHome,
      require,
      pkgs,
      force ? defaultForce,
      positiveControl ? defaultPositiveControl,
    }:
    let
      shapelyHomes = lib.isAttrs homes;
      systems = lib.optionals shapelyHomes (lib.attrNames homes);
      memberNames = lib.optionals (lib.isAttrs roster) (lib.attrNames roster);
      # The system rows that ARE `{ <user> = …; }` attrsets, and the ones that are not. Split once:
      # the coverage fold below can only ask a well-formed row who it holds, and reporting a
      # malformed row as "holds nobody" would name the wrong mistake.
      wellFormedRows = lib.filter (sys: lib.isAttrs homes.${sys}) systems;
      malformedRows = lib.filter (sys: !(lib.isAttrs homes.${sys})) systems;
      # Every system × member the handed homes do NOT hold. Checked here rather than left to the
      # raw `attribute missing` a lookup would throw, because the diagnosis is specific: the roster
      # is the authority on who exists, so a member with no homes is a gap in the mapper that built
      # them, not a member that should be skipped.
      uncovered = lib.concatMap (
        sys: map (n: "${sys}/${n}") (lib.filter (n: !(homes.${sys} ? ${n})) memberNames)
      ) wellFormedRows;
    in
    # Ordered deliberately, as in the helpers: report a SHAPE that cannot be read before reading it,
    # and a set that would check NOBODY before reporting anything about what it checked.
    assert lib.assertMsg (lib.isAttrs roster) (
      "mkRosterChecks: the roster is not an attrset — it is `mkContractRoster`'s own value "
      + "(`{ <name> = { name; dir; identity; }; }`), keyed by member name, not a list of members."
    );
    assert lib.assertMsg (roster != { }) (
      "mkRosterChecks: the roster is empty — a check set over zero members is green forever, and "
      + "every proof the kit ships would silently apply to nothing. Derive it from the users "
      + "directory (`mkContractRoster { usersDir = ./users; }`), which refuses an empty one at the "
      + "source."
    );
    assert lib.assertMsg shapelyHomes (
      "mkRosterChecks: `homes` is not an attrset — it is the consumer's per-system homes, keyed by "
      + "system: `{ <system> = { <user> = { <label> = home; }; }; }`."
    );
    assert lib.assertMsg (homes != { }) (
      "mkRosterChecks: `homes` names no system — its key set is what the variant-eval checks run "
      + "over, so an empty one checks no bake at all."
    );
    assert lib.assertMsg (malformedRows == [ ]) (
      "mkRosterChecks: the `homes` row(s) for [${lib.concatStringsSep ", " malformedRows}] are not "
      + "attrsets — each system's row must be `{ <user> = { <label> = home; }; }`, this repo's own "
      + "baked homes for that system."
    );
    assert lib.assertMsg (uncovered == [ ]) (
      "mkRosterChecks: no baked homes for [${lib.concatStringsSep ", " uncovered}] — the ROSTER "
      + "says who exists, so every member needs a bake on every system in `homes`. A member the "
      + "mapper skipped would otherwise lose its variant-eval check entirely, which reads exactly "
      + "like a passing one. Build `homes` from the roster itself — or, if this fleet deliberately "
      + "bakes different members on different systems, call the three helpers per user instead of "
      + "folding over the roster."
    );
    lib.mapAttrs' (
      n: member:
      lib.nameValuePair (checkNames.confinement n) (mkConfinementCheck {
        inherit pkgs force positiveControl;
        name = checkNames.confinement n;
        # The consumer's builder, closed over THIS member: the check appends its probes to the
        # `extraModules` list, exactly as it does for a hand-written per-user call.
        buildHome = buildHome member;
      })
    ) roster
    // lib.mapAttrs' (
      n: _:
      lib.nameValuePair (checkNames.variantEval n) (mkVariantEvalCheck {
        inherit pkgs systems force;
        name = checkNames.variantEval n;
        homesFor = sys: homes.${sys}.${n};
      })
    ) roster
    // {
      # ONE posture claim over the whole roster, not one per member: `require` is a fact about the
      # repo (ADR-0019 — its visibility picks the hash strength), and the helper's own message names
      # every offender it found, so a per-member split would only make the same failure noisier.
      ${checkNames.identityPosture} = mkIdentityPostureCheck {
        inherit pkgs require;
        name = checkNames.identityPosture;
        # The members' identities — already resolved by the roster (issue #57), never re-read here.
        identities = map (m: m.identity) (lib.attrValues roster);
      };
    };
in
{
  inherit
    outOfUniverseProbes
    mkConfinementCheck
    mkIdentityPostureCheck
    mkVariantEvalCheck
    mkRosterChecks
    ;
}
