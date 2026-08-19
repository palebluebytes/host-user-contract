# The contract's CHECK KIT (issue #35) — proofs a CONSUMER runs over its OWN repo, shipped so
# every user/host repo calls one function instead of re-deriving a technique it can get subtly
# wrong. Distinct from `conformance/`, which proves the contract's own promises in isolation:
# these checks can only be run where the consumer's real material lives (its actual module
# imports, its actual members of identities, its actual per-system home matrix), which is exactly
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
  # How this file phrases every refusal (./diagnostics.nix) — the same owner `lib.nix` uses, so a
  # consumer meets one voice whether the contract refuses to bake or a check refuses its material.
  # NOTE the `who` here is the check's own `name`, which is the CONSUMER's label for a check it
  # owns — a different thing from a contract function naming itself, and deliberately kept.
  diag = import ./diagnostics.nix { inherit lib; };
  inherit (diag) showList showName;
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
  # because three functions now name them (`mkConfinementCheck`, `mkHomeEvalCheck`, and the
  # members adapter that forwards both): a second copy would drift the day home-manager renames an
  # attribute, leaving one check forcing a home the others do not.
  defaultForce = home: home.activationPackage.drvPath;
  defaultPositiveControl = {
    home.sessionVariables.CONTRACT_CONFINEMENT_CONTROL = "ok";
  };

  # The per-user check NAMES the members adapter publishes under (issue #60), stated once. Each was
  # previously spelled TWICE per call site — as the `checks.<system>` attribute AND as the check's
  # own `name`, which is what its failure message reports — so a renamed check could report itself
  # under a name no `nix flake check -L` output would show. One definition, both uses.
  checkNames = {
    confinement = user: "home-confinement-${user}";
    homeEval = user: "home-eval-${user}";
    # Not per-member: one posture claim over the whole members (see mkIdentityPostureCheck).
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
  #       buildHome = extraModules: mkHome { memberDir = ./users/ada; identity = adaId; extra = extraModules; };
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
    assert diag.must {
      ok = controlOk;
      who = name;
      problem = "the POSITIVE CONTROL did not evaluate";
      why =
        "This module set rejects even a legitimate home option, so its rejection of system options "
        + "proves nothing about confinement.";
      fix =
        "Fix the builder (or pass a `positiveControl` this home actually declares) before reading "
        + "this check.";
    };
    assert diag.must {
      ok = expressible == [ ];
      who = name;
      problem =
        "this module set has a SYSTEM CHANNEL — the out-of-universe option(s) "
        + "${showList expressible} are expressible in the home";
      why = "A user could reach host state directly (ADR-0002).";
      fix =
        "Something in the imports declares them (a freeform type, or a NixOS module pulled into "
        + "the home); remove it. If instead the home is never FORCED by `force`, every probe looks "
        + "expressible — check that `force` reaches the module merge (the default is "
        + "`home.activationPackage.drvPath`).";
    };
    okWitness pkgs name;

  # mkIdentityPostureCheck (issue #35): assert every identity in a repo's OWN members carry the
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
  #       identities = map contract.lib.loadIdentity memberPaths;  # derived, never hardcoded
  #       require = "yescrypt";
  #     }
  #
  # `require` has NO DEFAULT: the contract does not pick a repo's posture, so the caller must say
  # which one it is asserting. Known postures are `credentialPostures` above (ADR-0019's two:
  # `yescrypt`, `libc`); an unknown name is a loud error naming them, since a posture typo must
  # never read as "checked". `identities` is a LIST of loaded identities (`lib.attrValues` an
  # attrset members) — derive it from the users directory rather than hardcoding it, so a newly
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
        credentialPostures.${require} or (diag.stop {
          who = name;
          problem = "unknown credential posture ${showName require}";
          fix = "Known postures are ${showList (lib.attrNames credentialPostures)} (ADR-0019).";
        });
      # `loadIdentity` returns the identity.json RAW (the option submodule fills defaults only
      # once the value is assigned to an option), and `hashedPassword` is an OPTIONAL field — so a
      # member may legitimately have no such attribute. Default it to "" here, or the
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
    assert diag.must {
      ok = lib.isList identities;
      who = name;
      problem = "`identities` must be a LIST of loaded identities";
      fix = "An attrset member set is passed as `lib.attrValues members`.";
    };
    assert diag.must {
      ok = identities != [ ];
      who = name;
      problem = "no identities to check";
      why = diag.vacuity {
        subject = "identity list";
        verbs = "check";
      };
      fix =
        "Derive the members from the users directory (every subdir with an identity.json) so a "
        + "newly added user is covered rather than silently skipped.";
    };
    assert diag.must {
      ok = offenders == [ ];
      who = name;
      problem =
        "identity.json credential(s) do not carry the required posture ${posture.description}: "
        + "${lib.concatMapStringsSep ", " describe offenders}";
      why =
        "ADR-0019: the credential travels with the user as public data, and repo visibility picks "
        + "the hash strength.";
      fix = "Re-hash with `${posture.remedy}`.";
    };
    okWitness pkgs name;

  # mkHomeEvalCheck (issue #49, decision #43): prove ONE user's every published home EVALUATES
  # on every system the repo builds it for — the members-generic replacement for the hand-written
  # cross-arch eval checks each user's `checks.nix` used to carry. A consumer's mapper applies it
  # per user over the derived members (failure attribution rides the check name), so a typical
  # user ships no check file at all:
  #
  #     contract.lib.mkHomeEvalCheck {
  #       inherit pkgs;
  #       homesFor = sys: memberHomes.${sys}.${user};   # sys → { <mode> = home; }, ONE user's homes
  #       systems = repoSystems;                        # every system this repo bakes (a fleet fact)
  #     }
  #
  # Deliberately SHAPE-AGNOSTIC: "everything we publish, evaluates" is this helper's fact; WHICH
  # modes a fleet bakes per system is the consumer mapper's fact, guarded where its per-system
  # subtraction lives (the contract's mode set is only the upper bound, never a per-system baking
  # obligation). And it forces ALL handed systems, the native one included — redundant with
  # `checks = packages` build-depending on the native homes, but "the whole handed matrix
  # evaluates" is a simpler contract than "the complement of whatever else covers".
  #
  # Deliberately NO `tryEval` around the force: an eval failure propagates RAW as a failing check.
  # `tryEval` cannot tell "no aarch64 build upstream" from a typo'd package name — both would
  # collapse into one boolean — and the underlying error message is exactly the diagnostic the
  # check exists to surface (the reasoning the old hand-written checks documented).
  #
  # COVERAGE NOTE — like `mkConfinementCheck`, `conformance/home-eval.nix` drives this logic
  # through synthetic homes (it has to: ADR-0004). The `activationPackage.drvPath` default over a
  # REAL home-manager home is therefore only exercised in a consumer repo's own `checks` — keep it
  # in step with home-manager's attribute names.
  mkHomeEvalCheck =
    {
      homesFor,
      systems,
      pkgs,
      name ? "home-eval",
      # The same override hook as mkConfinementCheck: force a home hard enough to prove it
      # evaluates — by default its derivation path, the home-manager shape ~every consumer has.
      force ? defaultForce,
    }:
    let
      homesBySystem = lib.genAttrs systems homesFor;
      # Shape before emptiness, via the shared partition (`diag.byShape`) — this check is the one
      # that proved the rationale: folding both into one predicate made it report an entry holding
      # a single malformed home as "no homes for [x86_64-linux]".
      #
      # ENTRY, not "row": a row is the home matrix's per-system DECLARATION (`{ <mode> = bool; }`,
      # what a fleet writes), and this is the per-system value of `homes` (what a fleet BUILT).
      # They are one word apart in the mapper that produces both, so they do not share it here.
      byEntryShape = diag.byShape (sys: lib.isAttrs homesBySystem.${sys}) systems;
      malformedSystems = byEntryShape.malformed;
      emptySystems = lib.filter (sys: homesBySystem.${sys} == { }) byEntryShape.readable;
      # Every system × home whose forced value is NOT a `.drv` path. A home that does not
      # evaluate never lands here — its error propagates raw out of `force` (no tryEval, above) —
      # so an entry in this list means `force` stopped short of the derivation.
      unforced = lib.concatMap (
        sys:
        map (mode: "${sys}/${mode}") (
          lib.filter (mode: !lib.hasSuffix ".drv" (force homesBySystem.${sys}.${mode})) (
            lib.attrNames homesBySystem.${sys}
          )
        )
      ) byEntryShape.readable;
    in
    # Ordered deliberately: a SHAPE that cannot be read before anything is read off it, then
    # anti-vacuity, and only then evaluability — a check that forced nothing must report the
    # emptied entry, not read as "every home evaluates".
    #
    # The anti-vacuous assert EXTENDS issue #49's clause ("for every system in `systems`,
    # `homesFor sys` is a non-empty attrset") to the list itself, which that wording passes over:
    # `systems = [ ]` satisfies it for-all-vacuously, so the same emptied-entry hazard one level up
    # would read as green forever. Same species, same verdict — a derived system list that filters
    # down to nothing is a mapper bug, not a passing check.
    assert diag.must {
      ok = systems != [ ];
      who = name;
      problem = "the systems list is empty";
      why = diag.vacuity {
        subject = "systems list";
        verbs = "check";
      };
      fix =
        "Hand it every system this repo builds for (the fleet's system list, derived, never "
        + "hardcoded).";
    };
    assert diag.must {
      ok = malformedSystems == [ ];
      who = name;
      problem = "the homes for ${showList malformedSystems} are not attrsets";
      why =
        "An entry that cannot be read cannot be reported as EMPTY — which is what this check used "
        + "to say about an entry holding one malformed home, naming the wrong mistake to whoever "
        + "had to fix it.";
      fix = "`homesFor` returns `{ <mode> = home; }` — this user's built homes for that system.";
    };
    assert diag.must {
      ok = emptySystems == [ ];
      who = name;
      problem = "no homes for ${showList emptySystems}";
      why =
        "An accidentally-emptied entry (a per-system subtraction gone wrong in the mapper) must "
        + "fail here, never read as a passing eval check.";
      fix =
        "`homesFor` must return a NON-EMPTY attrset of this user's built homes for every handed "
        + "system.";
    };
    assert diag.must {
      ok = unforced == [ ];
      who = name;
      problem = "forcing ${showList unforced} did not yield a `.drv` path";
      why = "So \"this home evaluates\" was never actually proven.";
      fix =
        "`force` must reach the home's derivation (the default is "
        + "`home.activationPackage.drvPath`); a hook that stops short would make every "
        + "evaluability claim vacuous.";
    };
    okWitness pkgs name;

  # mkMemberChecks (issue #60): the MEMBER-SET ADAPTER over the three helpers above — ONE call takes a
  # consumer's members plus its own material (its home builder, its per-system homes, the credential
  # posture it has chosen) and yields the whole per-user check set, named.
  #
  # The helpers are members-generic for a reason: a hand-listed set always misses the entry someone
  # forgot to add. Applying them by hand re-introduced exactly that at the call site — two
  # `mapAttrs'` folds over the members, each check's name spelled twice, and two closures threaded
  # per user, re-typed in every consumer. The mapping is not a fleet's fact; it is the same fold
  # every consumer of the kit performs, so the contract performs it:
  #
  #     checks.<system> = packages.<system> // contract.lib.mkMemberChecks {
  #       inherit pkgs members homes;
  #       buildHome = member: extraModules: mkHome { inherit member extraModules; };
  #       require = "yescrypt";
  #     };
  #
  # yielding `home-confinement-<user>` and `home-eval-<user>` per member, plus one
  # `identity-posture` over the whole members — every name from `checkNames` above, so a call site
  # spells none of them.
  #
  # It REPLACES nothing. The three helpers stay public and separately callable: a single-user repo
  # has no members to adapt, and a repo that wants confinement alone should call for confinement
  # alone. This is the members fold over them, and it is written in terms of exactly the same
  # public arguments those calls take.
  #
  # SIGNATURE — what stays the consumer's, stays the consumer's:
  #   `members`    the ADR-0020 members (`mkMembers`, issue #57), the authority on WHO is
  #               checked. Derived, so a user added to the directory is covered the moment it
  #               exists; an EMPTY one is a hard error, since a check set over nobody is green
  #               forever.
  #   `homes`     the consumer's per-system homes AS IT ALREADY HOLDS THEM —
  #               `{ <system>.<user>.<mode> = home; }`. The systems checked are its own key set, so
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
  # LEVEL UP, where the fold is — a member set with no members, homes naming no system, and homes that
  # do not cover the members. Each of those yields a check set that is merely SMALLER, and a missing
  # check is indistinguishable from a passing one in `nix flake check` output. (Plus the two SHAPE
  # guards those diagnoses need to stay honest: a member set or a homes entry that is not an attrset gets
  # told so, rather than being reported as empty or iterated over.)
  #
  # The coverage rule is worth stating outright, because it is the one thing the adapter asks of a
  # consumer that the helpers do not: every member bakes on every system in `homes`. That is the
  # shape `mkHomeMatrix` already implies — its rows are per SYSTEM, not per user — and it is what
  # makes "who is unchecked" answerable at all. A fleet that genuinely bakes different members on
  # different systems is outside this fold and calls the three helpers per user, which is one more
  # reason they stay public.
  mkMemberChecks =
    {
      members,
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
      memberNames = lib.optionals (lib.isAttrs members) (lib.attrNames members);
      # The system entries that ARE `{ <user> = …; }` attrsets, and the ones that are not — shape
      # before emptiness, via the shared partition (`diag.byShape`). Here the verdict that needs a
      # readable entry is the coverage fold below, which can only ask a well-formed entry who it
      # holds; reporting a malformed one as "holds nobody" would name the wrong mistake.
      byEntryShape = diag.byShape (sys: lib.isAttrs homes.${sys}) systems;
      wellFormedSystems = byEntryShape.readable;
      malformedSystems = byEntryShape.malformed;
      # Every system × member the handed homes do NOT hold. Checked here rather than left to the
      # raw `attribute missing` a lookup would throw, because the diagnosis is specific: the members
      # is the authority on who exists, so a member with no homes is a gap in the mapper that built
      # them, not a member that should be skipped.
      uncovered = lib.concatMap (
        sys: map (n: "${sys}/${n}") (lib.filter (n: !(homes.${sys} ? ${n})) memberNames)
      ) wellFormedSystems;
    in
    # Ordered deliberately, as in the helpers: report a SHAPE that cannot be read before reading it,
    # and a set that would check NOBODY before reporting anything about what it checked.
    assert diag.must {
      ok = lib.isAttrs members;
      who = "mkMemberChecks";
      problem = "the member set is not an attrset";
      fix =
        "It is `mkMembers`'s own value (`{ <name> = { name; dir; identity; }; }`), keyed by member "
        + "name, not a list of members.";
    };
    assert diag.must {
      ok = members != { };
      who = "mkMemberChecks";
      problem = "the member set is empty";
      why = diag.vacuity {
        subject = "member set";
        verbs = "check";
      };
      fix =
        "Derive it from the users directory (`mkMembers { usersDir = ./users; }`), which refuses "
        + "an empty one at the source.";
    };
    assert diag.must {
      ok = shapelyHomes;
      who = "mkMemberChecks";
      problem = "`homes` is not an attrset";
      fix =
        "It is the consumer's per-system homes, keyed by system: "
        + "`{ <system> = { <user> = { <mode> = home; }; }; }`.";
    };
    assert diag.must {
      ok = homes != { };
      who = "mkMemberChecks";
      problem = "`homes` names no system";
      why = diag.vacuity {
        subject = "`homes`";
        verbs = "check";
      };
      fix = "Its key set is what the home-eval checks run over.";
    };
    assert diag.must {
      ok = malformedSystems == [ ];
      who = "mkMemberChecks";
      problem = "the `homes` entr(y/ies) for ${showList malformedSystems} are not attrsets";
      fix =
        "Each system's entry must be `{ <user> = { <mode> = home; }; }`, this repo's own built "
        + "homes for that system.";
    };
    assert diag.must {
      ok = uncovered == [ ];
      who = "mkMemberChecks";
      problem = "no built homes for ${showList uncovered}";
      why =
        "The MEMBER SET says who exists, so every member needs a home on every system in `homes`. "
        + "A member the mapper skipped would otherwise lose its home-eval check entirely, which "
        + "reads exactly like a passing one.";
      fix =
        "Build `homes` from the member set itself — or, if this fleet deliberately builds "
        + "different members on different systems, call the three helpers per user instead of "
        + "folding over the member set.";
    };
    lib.mapAttrs' (
      n: member:
      lib.nameValuePair (checkNames.confinement n) (mkConfinementCheck {
        inherit pkgs force positiveControl;
        name = checkNames.confinement n;
        # The consumer's builder, closed over THIS member: the check appends its probes to the
        # `extraModules` list, exactly as it does for a hand-written per-user call.
        buildHome = buildHome member;
      })
    ) members
    // lib.mapAttrs' (
      n: _:
      lib.nameValuePair (checkNames.homeEval n) (mkHomeEvalCheck {
        inherit pkgs systems force;
        name = checkNames.homeEval n;
        homesFor = sys: homes.${sys}.${n};
      })
    ) members
    // {
      # ONE posture claim over the whole members, not one per member: `require` is a fact about the
      # repo (ADR-0019 — its visibility picks the hash strength), and the helper's own message names
      # every offender it found, so a per-member split would only make the same failure noisier.
      ${checkNames.identityPosture} = mkIdentityPostureCheck {
        inherit pkgs require;
        name = checkNames.identityPosture;
        # The members' identities — already resolved by the members (issue #57), never re-read here.
        identities = map (m: m.identity) (lib.attrValues members);
      };
    };
in
{
  inherit
    outOfUniverseProbes
    mkConfinementCheck
    mkIdentityPostureCheck
    mkHomeEvalCheck
    mkMemberChecks
    ;
}
