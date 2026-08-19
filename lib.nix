# The contract's derivation logic — pure functions over the registry and its projections.
# The public producer/consumer coin is `mkContractUser`/`mkContractUsers` (bake a user, or a
# whole members, into contractPackages + the binding index) and `bindContractUser` (a host
# binds one indexed user, grant = affordances ∩ offer); `traceUser` is the home-manager-free
# dry-run inspector. `mkContractPackageForHome`/`mkContractPackage`/`bindContractPackage` are
# the INTERNAL kernels those speak through (package-level, one rung below the user-level public
# surface). `runtimeEligibleFeature` is a PRIVATE predicate — `safeSet` is its only reader and the
# only form anything outside this file needs. `renderNixConfig`
# is the one public greeter helper here; `safeSet` is the derived value.
{
  lib,
  registry,
  modeRegistry,
  manifest,
  grantLib,
  featureConfigOptions,
}:
let
  # How this file phrases every refusal (./diagnostics.nix): one prefix rule, one list rendering,
  # one vacuity rationale. Sites below hand facts, never punctuation.
  diag = import ./diagnostics.nix { inherit lib; };
  inherit (diag) showList showName;
  # A feature is runtime/greeter-eligible iff it declares no privilegedGroups (ADR-0002,
  # slice 15). The feature is self-describing: checking `f.privilegedGroups == []` replaces
  # the cross-list intersection that was needed when `privilegedGroups` was a separate,
  # hand-maintained list in kit.nix. (The contract carries no secret-bearing features, so
  # there is no secret dimension to this predicate.)
  runtimeEligibleFeature =
    feature:
    let
      f = registry.${feature} or { };
    in
    (f.privilegedGroups or [ ]) == [ ];

  # The runtime-eligible feature names — the safe set (ADR-0002, slice 15).
  safeSet = lib.filter runtimeEligibleFeature (lib.attrNames registry);

  # --- the MODE projections (ADR-0032) ---
  # The mode names — the contract's whole session-shape vocabulary, read straight off
  # `modes.nix`. This is what a per-system matrix row may name, what a user's `contract.supports`
  # declares over, and what a home is keyed by.
  #
  # It replaces `homeAxes` and the `homes` POWERSET that was derived from it. Not a rename: modes
  # are mutually exclusive, so N of them yield at most N homes per user rather than 2ⁿ, and there
  # is no combination anywhere downstream to label, pair or narrow (ADR-0032).
  modeNames = lib.attrNames modeRegistry;

  # floorOf: the ONE mode a registry declares as its FLOOR — the mode every host runs, the
  # fallback of every selection, and the reason `runs` never comes out empty.
  #
  # Takes the registry EXPLICITLY, as `homeMatrixOver` takes its upper bound and for the same
  # reason: the contract's own registry has exactly one floor by construction, so the two failures
  # this guards — none, and more than one — are only demonstrable against a synthetic registry.
  # `floorMode` below is this closed over the real one.
  floorOf =
    reg:
    let
      floors = lib.filter (m: reg.${m}.floor or false) (lib.attrNames reg);
    in
    assert diag.must {
      ok = lib.length floors == 1;
      who = "modes";
      problem =
        if floors == [ ] then
          "no mode is the floor (modes: ${showList (lib.attrNames reg)})"
        else
          "more than one mode is the floor: ${showList floors}";
      why =
        "Exactly one mode is the floor: it is what a host runs when it affords nothing and what "
        + "selection falls back to, so a registry with none leaves a headless host running no mode "
        + "at all, and one with two leaves the fallback undecided.";
      fix = "Set `floor = true;` on exactly one entry of `modes.nix`.";
    };
    lib.head floors;

  # The contract's own floor. Read off the registry FLAG, never by name: the selection algorithm
  # below names no mode, for the same reason `keyLabel`'s output was documented as cosmetic — a
  # literal `"cli"` in the algorithm would make the flag decorative.
  floorMode = floorOf modeRegistry;

  # The FEATURE whose grant is associated with a mode, or `null` for the floor. One-way: a host
  # affording that feature RUNS this mode (`runsFor` below), but the mode never implies the grant
  # — `wants.<f>` stays independently vetoable, and a cli-mode user can still be given gui's
  # groups (ADR-0032, rejected "make the mode imply the grant").
  grantOfMode = mode: modeRegistry.${mode}.grant or null;

  # runsFor: the modes a host RUNS, derived from the features it affords (ADR-0032 §4).
  #
  #   runs = { the floor } ∪ { m | m's associated grant is afforded }
  #
  # A host declares `contract.affordances` and NOTHING else; there is no second host-side namespace
  # for modes. That is the point: two declarations that must agree, with nothing forcing them to,
  # is precisely the defect class this restructuring removes — deriving makes the disagreement
  # UNWRITEABLE, the same move ADR-0030 made dropping `system` in favour of reading it off `pkgs`.
  #
  # Takes the afforded feature NAMES (what `grantedNamesOf` yields off a host's affordances), so
  # this reads no config and can be driven over any affordance set.
  runsFor =
    afforded:
    lib.filter (
      m:
      m == floorMode
      || (
        let
          g = grantOfMode m;
        in
        g != null && lib.elem g afforded
      )
    ) modeNames;

  # selectModeOver: THE SELECTION (ADR-0032 §5), as a kernel over an explicit floor.
  #
  #   1. `modes = runs ∩ published`. Empty ⇒ a hard error naming both sets.
  #   2. A NON-FLOOR mode in that set wins. TWO non-floor modes ⇒ a hard error: a host claiming two
  #      rich modes must say which it means.
  #   3. Otherwise the floor.
  #
  # NO MODE NAME APPEARS IN THE ALGORITHM. The floor is a parameter read off the registry flag, for
  # the same reason `keyLabel`'s output was documented as cosmetic: a literal here would make the
  # flag decorative and a second mode's arrival a code change.
  #
  # The floor is EXPLICIT for the reason `homeMatrixOver` takes its upper bound: with one non-floor
  # mode in the registry, "two non-floor modes" is only demonstrable against a synthetic world.
  # `who`/`subject` are the diagnostic's own facts, since this kernel is never called directly and
  # naming itself would name a function no caller has heard of.
  selectModeOver =
    {
      who,
      subject,
      floor,
      # The modes the host RUNS (`runsFor` of its affordances).
      runs,
      # The modes this user PUBLISHES here — the key set of its binding index's contractPackages,
      # which IS its `supports` as narrowed by the producer's matrix. Read from there rather than
      # published a second time as its own field: two declarations that must agree is the defect
      # class ADR-0032 removes.
      published,
    }:
    let
      candidates = lib.filter (m: lib.elem m published) runs;
      rich = lib.filter (m: m != floor) candidates;
      show = "this host runs ${showList runs}; ${showName subject} publishes ${showList published}";
    in
    if candidates == [ ] then
      diag.stop {
        inherit who;
        problem = "no mode is common to the host and ${showName subject} — ${show}";
        why =
          "A mode is what a home IS, so a mismatch is a REFUSAL rather than a silently lesser home "
          + "(ADR-0032 narrows ADR-0002's degradation posture to grants). Every SEAT still binds "
          + "every user: what refuses is an operator naming a user whose session shape this host "
          + "cannot run.";
        fix = "Afford the feature that mode is run under, or bind a user that supports one of them.";
      }
    else if lib.length rich > 1 then
      diag.stop {
        inherit who;
        problem = "more than one rich mode is available for ${showName subject}: ${showList rich} — ${show}";
        why =
          "Rich modes are incomparable by design — a phone and a desktop are not ordered against "
          + "each other — so a host offering two of them has not said which session it means, and "
          + "no ordering exists here to break the tie.";
        fix = "Narrow the host's affordances, or the user's `contract.supports`, to one of them.";
      }
    else if rich != [ ] then
      lib.head rich
    else
      floor;

  # The HOME MATRIX kernel (issue #58, reshaped by ADR-0032): narrow an upper bound of MODES to
  # what each system bakes, and guard the narrowing. `homeMatrixOver` takes the bound explicitly;
  # the public `mkHomeMatrix` below is this closed over the contract's own mode names, so no
  # consumer-facing argument exists for the suite's sake. INTERNAL, exposed only so the conformance
  # suite can drive a synthetic THREE-mode bound — the propagation this design exists for cannot
  # otherwise be shown until the registry itself grows a third mode.
  #
  # WHICH modes a fleet bakes per system stays the consumer's fleet fact (decision #43): the
  # matrix is the caller's declaration, and this only applies it. What the CONTRACT owns is the
  # SHAPE of that declaration, because the failure mode is silent: an omitted mode is a home that
  # is never published, and a host that runs it then binds a lesser one or none at all.
  #
  # So the declaration is per-MODE and OPEN by default: a mode a system's row omits is usable, and
  # a system's row states only what it takes AWAY. That is ADR-0002's "one mechanism, opposite
  # defaults" read for coverage rather than privilege: fail-CLOSED is right where the risk of the
  # unknown is admitting something, fail-OPEN where the risk is omitting it. Under-baking is silent
  # and costly; over-baking wastes build time and nothing else. A contract that gains a MODE
  # therefore bakes it EVERYWHERE — on the restricted systems too — with no edit in any consumer
  # repo. This is the one property of the original grant-axis matrix that ADR-0032 does not
  # invalidate, which is why the matrix survives the restructuring as a SUBTRACTION rather than
  # disappearing with the powerset it used to narrow.
  #
  # The three under-bakes an earlier shape needed asserts for are UNEXPRESSIBLE rather than caught:
  # the matrix is keyed by system, so its rows and its system list cannot disagree; presence in it
  # IS the classification, so no system can go unclassified; and an unrestricted system is one whose
  # row takes nothing away, which no separate claim can contradict. What remains guarded is what
  # the type cannot say.
  homeMatrixOver =
    {
      # The fleet's whole home matrix, in ONE fact: `{ <system> = { <mode> = bool; }; }` — which
      # systems this repo bakes, and, per system, which modes its SEATS can run. A mode a row
      # OMITS is usable (absent ⇒ true), so `{ }` is a system that can run everything the contract
      # names and `{ gui = false; }` is a headless tier. A system absent from the matrix is not
      # baked at all.
      systems,
      # The bound to narrow — the contract's own `modes` for the public entry point.
      upperBound,
    }:
    let
      systemNames = lib.attrNames systems;
      rowOf = sys: systems.${sys};
      settingsIn = sys: lib.attrNames (rowOf sys);
      # The modes a system's seats CANNOT run: the `false` entries of its row, and only those.
      unusableIn = sys: lib.filter (m: !(rowOf sys).${m}) (settingsIn sys);
      # The subtraction itself: drop every mode this system's seats cannot run.
      matrix = lib.genAttrs systemNames (sys: lib.filter (m: !lib.elem m (unusableIn sys)) upperBound);

      malformedRows = lib.filter (sys: !lib.isAttrs (rowOf sys)) systemNames;
      nonBoolIn = sys: lib.filter (m: !lib.isBool (rowOf sys).${m}) (settingsIn sys);
      byNonBool = lib.filter (sys: nonBoolIn sys != [ ]) systemNames;
      # Checked on the KEY whatever the boolean says: `sudo = true` is as much a mistake about what
      # a row names as `sudo = false` is, and reads as though it had been considered.
      nonModesIn = sys: lib.filter (m: !lib.elem m upperBound) (settingsIn sys);
      byNonMode = lib.filter (sys: nonModesIn sys != [ ]) systemNames;
      emptied = lib.filter (sys: matrix.${sys} == [ ]) systemNames;
    in
    # Ordered so a broken declaration reports before any verdict about the modes, most specific
    # first: no systems at all, then a row of the wrong shape, then a non-boolean setting, then a
    # setting that names nothing the contract runs — and only then the one verdict about what IS
    # baked.
    assert diag.must {
      ok = systems != { };
      who = "mkHomeMatrix";
      problem = "the matrix is empty";
      why = diag.vacuity { subject = "matrix"; };
      fix =
        "`systems` is `{ <system> = { <mode> = bool; }; }`: one entry per system this repo builds "
        + "for, `{ }` for a system whose seats can run every mode the contract names.";
    };
    assert diag.must {
      ok = malformedRows == [ ];
      who = "mkHomeMatrix";
      problem = "the row(s) for ${showList malformedRows} are not attrsets";
      fix =
        "Each system's row is `{ <mode> = bool; }`, and `{ }` for a system that can run every mode "
        + "the contract names.";
    };
    assert diag.must {
      ok = byNonBool == [ ];
      who = "mkHomeMatrix";
      problem = "non-boolean mode setting(s): ${diag.showPer nonBoolIn byNonBool}";
      why = "Each mode in a row is a BOOL — `false` where that system's seats cannot run it.";
      fix = "An omitted mode is usable, so a row states only what it takes away.";
    };
    assert diag.must {
      ok = byNonMode == [ ];
      who = "mkHomeMatrix";
      problem = "setting(s) that are not MODES: ${diag.showPer nonModesIn byNonMode}";
      why =
        "The modes of this contract are ${showList upperBound} — a home is built for exactly one "
        + "of them. A FEATURE (`sudo`, `gui`) names a grant, which rides the bind and no longer "
        + "keys a home at all (ADR-0032), so the system would build every mode while reading as "
        + "restricted.";
      fix = "Name the MODES a system's seats cannot run.";
    };
    assert diag.must {
      ok = emptied == [ ];
      who = "mkHomeMatrix";
      problem = "system(s) ${diag.showPer unusableIn emptied} build NO home at all";
      why =
        "Those modes cut every entry of the upper bound ${showList upperBound}. "
        + diag.vacuity {
          subject = "row";
          verbs = "publish, bind and check";
        };
      fix = "Leave a system out of the matrix entirely if this fleet does not build for it.";
    };
    matrix;

  # mkHomeMatrix (issue #58): the PUBLIC per-system home matrix — `homeMatrixOver` closed over the
  # contract's own mode names, which is what makes a registry that gains a mode reach every
  # consumer's published homes with no edit. Returns `{ <system> = [ <mode> ]; }`, so a producer maps over a row
  # exactly as it would over the whole mode set. See `homeMatrixOver` above for the declaration shape
  # and the guards.
  mkHomeMatrix =
    { systems }:
    homeMatrixOver {
      inherit systems;
      upperBound = modeNames;
    };

  # The request→feature-configuration bridge, shared by BOTH binding shapes (the headless
  # tracer below and the real `bindContractPackage`). Given a user's harvested `contract.requests`
  # and the set of features the host GRANTED, copy each granted feature's request params into
  # the system-side feature-configuration shape the realization consumes (ADR-0003) — the two
  # shapes are identical (both are featureConfigOptions), so it is a direct copy. Only KNOWN
  # granted features with request data are bridged; an ungranted request is never copied, so
  # requesting an ungranted feature is a silent no-op (ADR-0002: "the grant is the sole
  # enabler; degradation is silent"). `requests` is a value in the tracer and a CONFIG
  # REFERENCE in the module — the fold is identical either way.
  # The granted-feature-names projection — single-sourced from the injected grantLib (issue #28),
  # the same fold realization.nix and greeter.nix read grants through. Aliased to a local name here
  # because the derivation logic below reads it heavily (the tracer, the index projection, the
  # turnkey grant derivation).
  grantedNamesOf = grantLib.grantedNames;
  bridgeRequests =
    requests: grantedNames:
    lib.foldl' (
      acc: f: if requests ? ${f} then acc // { ${f} = requests.${f}; } else acc
    ) { } grantedNames;

  # The UNTOUCHED value of every request namespace — `featureConfigOptions` evaluated with no
  # definitions at all. `contract.requests` is fully typed and carries no freeform (ADR-0028), so
  # every declared feature key is ALWAYS present on a harvested home whether or not the user said
  # anything: "did this home ask for gui's parameters?" cannot be answered by key presence, only by
  # comparison against this. Derived from the same option fragments the umbrella declares the
  # namespace from, so the baseline cannot drift from the schema. (Bare `lib.evalModules` — no
  # home-manager, ADR-0004.)
  defaultRequests = (lib.evalModules { modules = [ { options = featureConfigOptions; } ]; }).config;
  # The features a harvested `contract.requests` actually CARRIES DATA for: those whose namespace
  # differs from the untouched default above. A feature absent from the attrset entirely (a
  # synthetic home that names only the keys it sets) carries nothing, same as one left at its
  # default.
  requestingFeatures =
    requests:
    lib.filter (f: (requests.${f} or defaultRequests.${f}) != defaultRequests.${f}) (
      lib.attrNames defaultRequests
    );

  # The system account fragment a bind PRODUCES, given the user's identity, the host's grants,
  # and the user's harvested `contract.requests`: the account the realization materializes, the
  # grants that power it, and the granted requests bridged into feature configuration. BOTH the
  # `traceUser` inspector and the real `bindContractPackage` emit exactly this — the tracer nested
  # under `system`, the module at top level — so they share their whole output shape, not just the
  # bridge step, and differ only in where `requests` come from (a harvested home eval vs a
  # pre-built manifest) and what wrapper they return.
  mkUserAccount =
    {
      identity,
      grants,
      requests,
    }:
    {
      inherit identity;
      granted = grants;
    }
    // bridgeRequests requests (grantedNamesOf grants);
  # mkContractPackage (ADR-0016, issue #14): assemble the pre-built binding artifact from an
  # already-evaluated home. The user's CI calls this and publishes the result; the host pins it
  # as a flake input. `activationPackage` is the home-manager activation package (has
  # `$out/activate`); `requests` is the evaluated `contract.requests` attrset; `packages` is the
  # list of package derivations from `home.packages` — pname/name is extracted for the manifest
  # (the host needs names, not store paths); `username` is the account name; `mode` is the session
  # shape the home was BUILT for — frozen into the manifest so a host `bindContractPackage` can
  # prove it actually runs that mode (ADR-0016's coupling guard as ADR-0032 §8 restates it: the
  # grant no longer changes a home, so the MODE is what a bind must not contradict).
  #
  # The manifest is serialized to a store path at EVAL TIME via the `manifest` module's `writeManifest`
  # (`builtins.toFile`, pure, no IFD), then copied into the derivation during the build. The manifest
  # module OWNS the schema (version, field set, filename); this producer only projects its inputs into
  # that shape — package DERIVATIONS to package NAMES (the host needs names, not store paths). The
  # derivation is content-addressed: the same home eval always produces the same store path, covering
  # both activate and the requests.
  mkContractPackage =
    {
      pkgs,
      activationPackage,
      requests,
      packages,
      username,
      mode,
    }:
    let
      packageNames = map (p: p.pname or (builtins.parseDrvName p.name).name) packages;
      manifestFile = manifest.writeManifest {
        inherit username requests mode;
        packages = packageNames;
      };
    in
    pkgs.runCommand "contract-package-${username}" { } ''
      mkdir -p $out
      cp ${activationPackage}/activate $out/activate
      chmod +x $out/activate
      cp ${manifestFile} $out/${manifest.manifestFileName}
    '';

  # assertNoVetoedRequests (issue #59): the second bake-time guard on a user's home — the two
  # halves of the user's VOICE (ADR-0028) held to each other. `contract.wants` (which features) and
  # `contract.requests` (their parameters) are typed independently, so one home can veto a feature
  # and still carry its parameters. Those parameters can then never bridge on ANY host, because the
  # grant is `affordances ∩ offer` and the user's side of that intersection is already empty. That
  # is dead data in the user's own repo: exactly the class ADR-0028 closed the freeform to catch,
  # arriving through the other half of the voice.
  #
  # It is NOT the ADR-0002 case, which stands unchanged. A request for a feature the user WANTS but
  # this host does not grant is INERT, never an error — the host's veto degrades silently by design,
  # because a roaming home must bind everywhere. Only the USER's own veto is unrescuable, and so a
  # defect rather than a degradation. The two are told apart on `wants` alone, which is why this
  # reads nothing else: no host is consulted here at all.
  #
  # Absence reads as EMPTY on both halves — an unnamed feature carries no request data, and an
  # unnamed want asks for nothing — so a hand-built home naming only the keys it sets is judged on
  # what it actually said. The message therefore states the want half as "does not ask for", which is
  # true whether the home wrote `enable = false` or never named the feature; a real harvested home
  # always carries every declared key (no freeform, ADR-0028), so the two coincide there.
  assertNoVetoedRequests =
    { username, home }:
    let
      wants = home.config.contract.wants;
      vetoed = lib.filter (f: !(wants.${f} or false)) (requestingFeatures home.config.contract.requests);
    in
    diag.must {
      ok = vetoed == [ ];
      who = "mkContractUser";
      problem =
        "self-contradictory voice for ${showName username} — it sets "
        + "`contract.requests.<f>.*` for ${showList vetoed} while its `contract.wants` asks for "
        + "none of them";
      why =
        "A feature the USER vetoed can never be granted by any host (the grant is affordances ∩ "
        + "offer), so those parameters can never bridge — they are dead data in the user's own "
        + "home. (A request for a feature the user DOES want but a HOST does not grant is inert by "
        + "design, ADR-0002; this is the other case.)";
      fix = "Want the feature, or drop its requests.";
    };

  # harvestVoice (ADR-0028/0032): the user's WHOLE voice, read off the homes it was built as, and
  # held to itself. Both halves live in the user's own home, and both are read here because this is
  # the only place every one of a user's homes is in scope at once:
  #
  #   offer      `contract.wants` — WHICH features this user asks a host for. Published in the
  #              binding index; `bindContractUser` derives the grant as `affordances ∩ offer`.
  #   supported  `contract.supports` — WHICH MODES this home can run in. It is the PUBLICATION set:
  #              a producer publishes one home per supported mode, and a host binds the mode it
  #              runs.
  #
  # Both must be MODE-INVARIANT, and for the same reason in two directions. An offer that varied by
  # mode would be circular — the grant is derived FROM the offer, so it cannot also depend on what
  # the host afforded. A `supports` that varied by mode would make the published set depend on
  # which mode happened to be evaluated first, which is a coin toss dressed as a declaration.
  #
  # Reading `supports` forces the module FIXPOINT but not `activationPackage`, so the published set
  # is decided before any derivation is instantiated. Stated because otherwise it quietly becomes a
  # double evaluation: the homes are handed in already built (as thunks), and only their `config`
  # is forced here.
  #
  # PUBLICATION IS DRIVEN BY `supports`, so it is decided here too and returned as `published`: the
  # handed homes cut to the modes the user actually supports. One owner of the rule, applied
  # wherever the answer is needed (the producer coin, and the fleet's `homes` output).
  #
  # `homes` is `{ <mode> = home; }` — what the caller BUILT, which is its system's matrix row. The
  # published set is that ∩ `supports`, so a mode the user supports but this system does not bake
  # is simply absent — and a system that builds NONE of them publishes nothing for that user there,
  # which is not an error here. The matrix is fail-OPEN on coverage (ADR-0032 §6) and the refusal
  # belongs at the BIND, where a host meets a user with nothing in common and the selection can
  # name what it runs against what the user offers. Refusing here would instead make one system's
  # topology decide what a self-contained user may BE, which is the opposite of the north star.
  harvestVoice =
    { username, homes }:
    let
      voiceOf = h: h.config.contract;
      voices = map voiceOf (lib.attrValues homes);
      # Each half compared as its enabled-NAME projection, which is the whole observable content of
      # a bool-per-key set and exactly what downstream consumes.
      offeredNames = map (v: grantedNamesOf v.wants) voices;
      supportedNames = map (v: lib.filter (m: v.supports.${m} or false) modeNames) voices;
      first = lib.head voices;
      supported = lib.head supportedNames;
      # Supporting a mode while vetoing the grant that mode is associated with: issue #59's rule
      # one layer up. The user has asked to be built for a session shape and refused the very
      # feature a host confers to run it, so no host can rescue it.
      contradictory = lib.filter (
        m:
        let
          g = grantOfMode m;
        in
        g != null && !(first.wants.${g} or false)
      ) supported;
      allSame = names: lib.all (n: n == lib.head names) names;
      published = lib.filterAttrs (m: _: lib.elem m supported) homes;
    in
    # Ordered so the emptiest mistake reports first: nothing to harvest at all, then each half's
    # invariance (a varying half makes every verdict below it a coin toss), then what the harvested
    # values SAY.
    assert diag.must {
      ok = homes != { };
      who = "mkContractUser";
      problem = "${showName username} declares no homes";
      why = "There is no evaluated home to harvest `contract.wants`/`contract.supports` from.";
      fix = "A user must build at least one home.";
    };
    assert diag.must {
      ok = allSame offeredNames;
      who = "mkContractUser";
      problem =
        "mode-varying offer for ${showName username} — its `contract.wants` differs across "
        + "its homes: ${lib.concatMapStringsSep ", " showList offeredNames}";
      why =
        "An offer that depends on `hostFacts` is circular: the grant is DERIVED from the offer "
        + "(affordances ∩ offer), so it cannot also be an input to it.";
      fix = "Declare `contract.wants` the same way in every home this user builds.";
    };
    assert diag.must {
      ok = allSame supportedNames;
      who = "mkContractUser";
      problem =
        "mode-varying `supports` for ${showName username} — it differs across its homes: "
        + "${lib.concatMapStringsSep ", " showList supportedNames}";
      why =
        "`supports` decides WHICH homes are published, so one that varies by mode would make the "
        + "published set depend on which mode happened to be evaluated first.";
      fix = "Declare `contract.supports` the same way in every home this user builds.";
    };
    assert diag.must {
      ok = supported != [ ];
      who = "mkContractUser";
      problem = "${showName username} supports no mode";
      why =
        "A user that can run in no session shape is uninstallable: nothing is published for it, so "
        + "every host that tried to bind it would find an empty index entry rather than a refusal. "
        + "There is no default, deliberately — a default would set a user's essential nature "
        + "without the user having said anything.";
      fix =
        "Declare at least one, e.g. `contract.supports.gui = true;` for an ordinary desktop user "
        + "(the modes are ${showList modeNames}).";
    };
    assert diag.must {
      ok = contradictory == [ ];
      who = "mkContractUser";
      problem =
        "self-contradictory voice for ${showName username} — it supports "
        + "${showList contradictory} while its `contract.wants` refuses the grant each of those "
        + "modes is run under";
      why =
        "A host confers that grant in order to run that mode, so a user vetoing it can never be "
        + "given the session it asked to be built for — a contradiction no host can rescue.";
      fix = "Want the grant, or drop the mode from `contract.supports`.";
    };
    {
      inherit published;
      offer = first.wants;
    };

  # mkContractPackageForHome (ADR-0016, issue #23): the OPTIONAL home-manager producer adapter. It mirrors
  # `bindContractPackage`'s turnkey-ness on the PRODUCER side — since ~every producer builds its
  # home with home-manager, each one otherwise hand-rolls the identical adapter that reads the four
  # disassembled primitives (`activationPackage`, `requests`, `packages`, `username`) off its home.
  # This lifts that recurring wrapper into the contract so a producer calls `{ home; mode; pkgs; }`.
  #
  # It does NOT import home-manager (ADR-0004 package-free preserved): it only READS attributes off
  # an already-evaluated `home` (`activationPackage`, `config.contract.requests`,
  # `config.home.{packages,username}`), never importing the builder. The generic `mkContractPackage`
  # stays builder-agnostic (a hand-rolled or future nix-darwin home still calls the core directly);
  # this is a thin convenience over it. `pkgs` stays a parameter so one call emits packages for more than one system.
  # INTERNAL: the public producer surface is `mkContractUser`/`mkContractUsers`, which bake through this.
  #
  # `mode` is carried through to the manifest and nothing else, and it is REQUIRED: a published
  # artifact always belongs to a mode, so a default would only let one be published claiming none.
  # There is no pairing to verify here any more (ADR-0032): the coin publishes each home under the
  # very key it was built for, so a producer has no `{ grants; home }` record left to re-pair
  # wrongly and the marker+cross-check that guarded that pairing (issue #56) are both gone.
  mkContractPackageForHome =
    {
      home,
      pkgs,
      mode,
    }:
    mkContractPackage {
      inherit pkgs mode;
      username = home.config.home.username;
      activationPackage = home.activationPackage;
      requests = home.config.contract.requests;
      packages = home.config.home.packages;
    };

  # THE ADR-0020 LAYOUT, spelled once (issue #57): a users directory holds one subdirectory per
  # user, and each holds that user's `identity.json` + `home.nix`. Every site that must name one of
  # those paths reads it through these three — the members derivation below, and the two members-less
  # fallbacks the coin and the home builder keep for a single-user repo — so the layout is ONE edit
  # rather than the four transcriptions this replaces. They are also why the join is spelled one way:
  # path concatenation, never string interpolation of the directory (which would coerce it into a
  # store path at a different moment than its siblings).
  memberDirIn = usersDir: name: usersDir + "/${name}";
  identityFileIn = memberDir: memberDir + "/identity.json";
  homeFileIn = memberDir: memberDir + "/home.nix";

  # WHO a call is about, resolved ONCE. Every public producer takes either a `member` (a
  # `mkMembers` entry, whose identity the members already resolved) or the pieces to build one
  # — `name` + `usersDir` for the coin, `memberDir` for the home builder — because one user is not a
  # members and a single-user repo must bake without constructing one (ADR-0026's amendment).
  #
  # That dual input used to be normalised at THREE sites, with three error texts and two
  # DISAGREEING precedence rules: the coin held a passed `name` to the member's and refused a
  # mismatch, while the builder let `memberDir`/`identity` silently OVERRIDE the member's. Both rules
  # were defended in comments and neither was visible from a signature.
  #
  # One rule now: **a member answers every field, and a field passed beside a member must agree with
  # it.** Nothing is silently overridden — a disagreement is the same species of mispairing the
  # retired bake pairing rejected one rung down (issue #56, deleted by ADR-0032 along with the
  # grants↔home pairing it protected), where one user's material reaches an output under another's
  # name. The members-LESS shapes are untouched: they are simply the case with no member to
  # agree with, so composing a home from one directory while holding an identity from elsewhere
  # (which the suite drives) still works exactly as before.
  #
  # The three fields resolve independently and LAZILY, so each caller forces only what it uses — the
  # coin never asks for `dir`, the builder never asks for `name` — and an unresolvable field is a
  # named error only where it is actually needed.
  resolveMember =
    {
      # The public function name, for the errors. This helper is never called directly, so naming
      # itself would name a function the caller has not heard of.
      context,
      # How THIS caller can be handed a user directory, in its own argument names — the coin takes
      # `usersDir` + `name`, the builder takes `memberDir`, and neither accepts the other's. A shared
      # resolver must not tell a caller to pass an argument that function does not have.
      dirRoutes,
      # Kit-injected, via the caller: ADR-0009's single identity loader.
      loadIdentity,
      member ? null,
      name ? null,
      usersDir ? null,
      memberDir ? null,
      identity ? null,
    }:
    let
      restates =
        field: passed: mine:
        if passed == null || passed == mine then
          mine
        else
          diag.stop {
            who = context;
            problem = "the `${field}` passed disagrees with the member's";
            why =
              "A member is the resolved answer to who this user is — the name its outputs are "
              + "published under, the directory its home is composed from, and the identity both "
              + "carry — so a field beside it may restate that answer but never replace it.";
            fix = "Pass the member alone, or a `${field}` that matches it.";
          };
      unresolvable =
        field: hint:
        diag.stop {
          who = context;
          problem = "there is no `${field}` to work from";
          fix = "Pass a `member` (a `mkMembers` entry, which carries all three), or ${hint}.";
        };
      dir =
        if member != null then
          restates "memberDir" memberDir member.dir
        else if memberDir != null then
          memberDir
        else if usersDir != null && name != null then
          memberDirIn usersDir name
        else
          unresolvable "user directory" dirRoutes;
    in
    {
      inherit dir;
      name =
        if member != null then
          restates "name" name member.name
        else if name != null then
          name
        else
          unresolvable "name" "the `name` this user's outputs are published under";
      identity =
        if member != null then
          restates "identity" identity member.identity
        else if identity != null then
          identity
        else
          loadIdentity (identityFileIn dir);
    };

  # mkMembers (ADR-0020, issue #57): the contract's ONE answer to "who is in this users
  # repo, and what is each identity" — the ADR-0020 directory layout, stated once. Given a
  # `usersDir`, it returns `{ <name> = { name; dir; identity; }; }`: every subdirectory holding an
  # `identity.json` is a MEMBER, keyed by its directory name, carrying that directory and the
  # identity resolved through the contract's single loader (ADR-0009).
  #
  # It exists because the layout rule was spelled in FOUR places — a producer's own `readDir` filter,
  # its identity map, `mkContractUser`'s index resolution, and `mkContractHome`'s `identity` default —
  # so each identity.json was read two or three times per evaluation, by three owners, and a change
  # to the layout would have to find all four. ADR-0009 made the contract the single identity LOADER;
  # this makes it the single resolution SITE. A member is what the coin and the home builder now take
  # (`member`), so nothing downstream re-derives a path from a name.
  #
  # LIFTABILITY is preserved (ADR-0020, wayfinder #39): this reads `users/<u>/` and nothing else — no
  # index file, no manifest, no knowledge at the users-repo root — so lifting one user out into its
  # own repo stays a literal directory move, and a single-user repo that never calls this can still
  # bake through `mkContractUser` directly.
  #
  # The two non-members are skipped rather than reported: a directory whose `home.nix` has landed but
  # whose `identity.json` has not is a half-added user (deriving a member there would throw on a file
  # that does not exist), and a non-directory entry at the root is a README or a shared/ sibling. What
  # is NOT skipped is the whole directory yielding nothing: a memberless `usersDir` is the wrong-path
  # mistake (off by a level, or renamed), and it must be a named error rather than an empty members —
  # everything downstream maps over the members, so an empty one bakes, publishes and checks NOTHING
  # while every flake output stays green (the same vacuity `mkIdentityPostureCheck` refuses).
  mkMembers =
    {
      # Kit-injected (a caller never passes it): the identity.json loader, ADR-0009's single loader.
      loadIdentity,
      # The ADR-0020 users directory — the parent of the per-user subdirectories.
      usersDir,
    }:
    let
      entries = builtins.readDir usersDir;
      names = lib.filter (
        n: entries.${n} == "directory" && builtins.pathExists (identityFileIn (memberDirIn usersDir n))
      ) (lib.attrNames entries);
    in
    assert diag.must {
      ok = names != [ ];
      who = "mkMembers";
      problem =
        "${showName usersDir} holds no member — no subdirectory of it has an `identity.json`. "
        + "Entries seen: ${showList (lib.attrNames entries)}";
      why = diag.vacuity { subject = "member set"; };
      fix = "A users directory is the ADR-0020 layout `users/<u>/identity.json`.";
    };
    lib.genAttrs names (
      name:
      let
        dir = memberDirIn usersDir name;
      in
      {
        inherit name dir;
        identity = loadIdentity (identityFileIn dir);
      }
    );

  # mkContractUser (ADR-0025, issue #25): the SINGULAR turnkey PRODUCER — the producer twin of the
  # consumer's `bindContractUser` (make one contract-user ⇄ bind one contract-user). A single-user
  # repo calls it once; `mkContractUsers` (below) is nothing but this mapped over the members. It
  # bakes ONE user's homes and emits the same flake-output shape a host consumes — ready to
  # `inherit … packages contractUsers`:
  #   - the named packages `<user>-contractPackage-<mode>` (built via mkContractPackageForHome
  #     — so this stays package-free, only READING attributes off an already-evaluated home, ADR-0004), and
  #   - the pure `contractUsers.<sys>.<user>` BINDING INDEX entry
  #     `{ identity; offer; contractPackages = { <mode> = package; }; }`. The index is plain data,
  #     so a host's `bindContractUser` selects by reading it — never by building every home to
  #     inspect a baked manifest (the ADR-0016 "can't read manifests cheaply" trap, sidestepped).
  #
  # WHO this user is comes in one of two ways (issue #57), resolved by the shared `resolveMember`.
  # Preferred: a `member` — a `mkMembers` entry `{ name; dir; identity; }`, whose identity is
  # ALREADY resolved, so this re-derives no path and the `identity.json` is read once per evaluation
  # for the whole repo. Otherwise: `name` + `usersDir`, and the ADR-0020 path is resolved through the
  # kit-injected `loadIdentity` (ADR-0009) — the shape a SINGLE-USER repo keeps, since one user is
  # not a member set, and constructing one to bake it would be ceremony.
  #
  # `homes` is `{ <mode> = home; }` — the modes this system BUILT for this user, which is its
  # matrix row. The KEY is the whole of what a home is published as, so nothing is re-paired here
  # and there is no record to get wrong: the mode a home was built for and the mode it is published
  # under are the same value by construction (ADR-0032 §6). `loadIdentity` is injected by the kit
  # (like `homeModule` for `traceUser`) so the users flake calls this without wiring the loader
  # itself. `pkgs` is a parameter so one call can emit multi-arch outputs, and the system the
  # outputs are keyed by is read off it rather than passed a second time.
  #
  # WHAT IS PUBLISHED is `supports` ∩ what was built, not everything that was built (ADR-0032 §6):
  # a producer's matrix says what a SYSTEM can bake and the user says which of those it can run in,
  # and only the intersection is a home anybody could bind. `harvestVoice` owns that cut along with
  # every guard over the voice it reads to make it — the harvested `offer`, its mode-invariance and
  # `supports`', the at-least-one-mode rule, and the mode-without-its-grant contradiction.
  #
  # The remaining per-home guard is issue #59's: a home carrying `contract.requests` data for a
  # feature its own `contract.wants` vetoes fails the bake, because that is the one contradiction no
  # host can rescue. It stays per-home because a home's REQUESTS may legitimately differ across
  # modes, where its `wants` may not — see `assertNoVetoedRequests`.
  mkContractUser =
    {
      loadIdentity,
      pkgs,
      # A member (see mkMembers). Supplies both the name and the resolved identity.
      member ? null,
      # The user's name + directory, for a caller with no members. Passing either BESIDE a member is
      # allowed only while the two agree — see `resolveMember`.
      name ? null,
      usersDir ? null,
      homes,
    }:
    let
      # The system the outputs are keyed by, read off the caller's own `pkgs` — the same rule
      # `mkContractHome` and `bindContractUser` apply. It used to be a second parameter, which made
      # this the one function on the surface where a caller could key its packages by a system its
      # `pkgs` was not built for, with nothing to catch it.
      system = pkgs.stdenv.hostPlatform.system;
      # Who this user is — one resolution, shared with the home builder (see `resolveMember`). The
      # identity is read at most once per evaluation: from the member if there is one (the members
      # already read the file), otherwise from the ADR-0020 path.
      who = resolveMember {
        context = "mkContractUser";
        dirRoutes = "`usersDir` beside the `name`, to resolve the ADR-0020 path under";
        inherit
          loadIdentity
          member
          name
          usersDir
          ;
      };
      inherit (who) identity;
      userName = who.name;
      # The user's harvested VOICE, every guard over it, and the cut it decides: which of the built
      # homes are PUBLISHED (see `harvestVoice`).
      voice = harvestVoice {
        username = userName;
        inherit homes;
      };
      inherit (voice) offer;
      # The voice guards ride the whole bake RECORD as well as the published `offer`, for the same
      # reason the request guard does: the repo that owns a self-contradictory voice is the USER's,
      # whose flake check builds the PACKAGES and never reads the index a host binds through. A
      # guard reachable only through `offer` would leave that repo green. `seq` forces the harvest
      # to weak head normal form, which is exactly far enough to run every assert inside it.
      voiceHolds = builtins.seq voice true;
      # One package per PUBLISHED mode, keyed by that mode — so the key a host selects on, the name
      # the package is published under, and the field frozen into its manifest are one value read
      # three ways, and there is nothing to pair.
      built = lib.mapAttrs (
        mode: home:
        assert voiceHolds;
        assert assertNoVetoedRequests {
          username = userName;
          inherit home;
        };
        mkContractPackageForHome { inherit pkgs home mode; }
      ) voice.published;
    in
    {
      packages.${system} = lib.mapAttrs' (
        mode: package: lib.nameValuePair "${userName}-contractPackage-${mode}" package
      ) built;
      contractUsers.${system}.${userName} = {
        inherit identity offer;
        contractPackages = built;
      };
    };

  # mkContractUsers (ADR-0025, issue #25): the MEMBER-SET convenience — `mkContractUser` mapped over a
  # whole multi-user repo and its outputs merged, so a `users` flake bakes its entire members in ONE
  # call and `inherit … packages contractUsers`. It is the turnkey producer for the multi-user shape
  # (ADR-0020) exactly as `bindContractUser` is the turnkey consumer; the singular `mkContractUser`
  # is the true per-user partner underneath. Each input user is its `{ <mode> = home; }` map,
  # forwarded to `mkContractUser` (the offer is harvested from each home, ADR-0028 — a users entry
  # carries no `offer` field). Adds no logic of its own beyond the members fold — the per-user bake,
  # naming, and index shape all live in `mkContractUser`.
  #
  # WHO the users are is a `members` (issue #57): the `mkMembers` attrset, whose member for
  # each `users` key supplies that user's directory and already-resolved identity. `users` keys stay
  # the caller's own list because WHICH members it builds homes for, and which homes, is the producer's
  # home matrix — the same fleet fact the per-system mode subtraction is (decision #43), and not
  # something the contract opines on. A key the members does NOT hold is the other story: that is a
  # hand-listed name that has drifted from the directory, so it is a named error rather than
  # baking for nobody. (The pre-members `usersDir` shape still works, and resolves per user as before.)
  mkContractUsers =
    {
      loadIdentity,
      pkgs,
      members ? null,
      usersDir ? null,
      homes,
    }:
    let
      # Read off `pkgs`, as in `mkContractUser` — this only merges what that emits, so the two
      # cannot key their outputs by different systems.
      system = pkgs.stdenv.hostPlatform.system;
      memberFor =
        name:
        if members == null then
          null
        else
          members.${name} or (diag.stop {
            who = "mkContractUsers";
            problem =
              "${showName name} is not a member — its `homes` entry names somebody the users "
              + "directory does not hold (members: ${showList (lib.attrNames members)})";
            why =
              "A `homes` key is a member to build for, so a name that has drifted from the "
              + "directory is an error, not an empty build.";
          });
      outs = lib.mapAttrsToList (
        name: userHomes:
        mkContractUser {
          inherit
            loadIdentity
            pkgs
            usersDir
            name
            ;
          member = memberFor name;
          homes = userHomes;
        }
      ) homes;
    in
    # The ANTI-VACUITY guard its three siblings all carry and this one did not (issue #67):
    # `mkContractUser` refuses a user that "declares no homes", `mkMemberChecks` refuses a member
    # set that "would check NOTHING while every output stayed green", and `mkContractFleet` guards
    # both of its inputs. `mkContractUsers { homes = { }; }` deep-forced to empty outputs and
    # reported success — the exact shape of failure every one of those refusals exists to catch,
    # in the one place nothing was looking.
    assert diag.must {
      ok = lib.isAttrs homes;
      who = "mkContractUsers";
      problem = "`homes` is not an attrset";
      fix = "It is `{ <user> = { <mode> = home; }; }`, keyed by the member each home set belongs to.";
    };
    assert diag.must {
      ok = homes != { };
      who = "mkContractUsers";
      problem = "`homes` names no user";
      why = diag.vacuity { subject = "`homes`"; };
      fix =
        "Its key set is who this call bakes for — derive it from the member set, which "
        + "`mkMembers` already refuses to leave empty.";
    };
    {
      packages.${system} = lib.foldl' (acc: o: acc // o.packages.${system}) { } outs;
      contractUsers.${system} = lib.foldl' (acc: o: acc // o.contractUsers.${system}) { } outs;
    };

  # mkContractFleet (ADR-0029's second amendment, issue #62): the FLEET-LEVEL producer — one rung
  # above `mkContractUsers`, owning the residual JOIN that a multi-user, multi-system producer was
  # otherwise left holding. Given WHO is here (`members`, issue #57) and WHAT each system bakes
  # (`homeMatrix`, issue #58), it builds every member's every home on every system and emits the
  # whole published producer surface:
  #
  #   { homes; packages; contractUsers; systems; pkgsBySystem; }
  #
  # so `inherit (fleet) packages contractUsers;` IS the flake outputs, and `fleet.homes` is the
  # `<system>.<user>.<mode>` shape `mkMemberChecks` and a producer's own checks already consume —
  # and, since ADR-0032, a flake output in its own right.
  #
  # ADR-0029 REJECTED a fatter producer, and that rejection was overturned by its own second
  # amendment: both of its grounds were answered by surface that shipped afterwards. What was left
  # repo-side was mechanics rather than choices — the per-home eval loop, the members × system ×
  # mode fold, the two output merges, and the `systems`/`pkgs` derivation — re-typed
  # character-for-character in a second producer.
  #
  # THE HOME ARRIVES BY INJECTED CLOSURE (ADR-0004). `buildHome` is the CONSUMER's, so this function
  # names neither `mkContractHome` nor `stateVersion`, `extraModules` or `extraSpecialArgs`, and
  # never imports home-manager. That is what keeps three separate promises: the contract stays
  # package-free by the same posture `mkConfinementCheck`'s `buildHome` takes; a producer threads its
  # own `extraSpecialArgs` (the ADR-0020 `inputs` convention) without the contract learning what
  # `inputs` is; and a home built WITHOUT `mkContractHome` still bakes through here, because nothing
  # in this fold knows which builder made it. Taking the builder's own arguments instead would
  # re-fuse builder to bake — the very thing the overturned ground feared, and the thing this shape
  # avoids.
  #
  # `buildHome` takes an ATTRSET, `{ member, mode, pkgs }`. That is a third `buildHome` spelling
  # beside `mkConfinementCheck`'s `extraModules: home` and `mkMemberChecks`' curried
  # `member: extraModules: home`, and the inconsistency is deliberate: three positional arguments in
  # a fixed order is the worse footgun, since transposing `mode` and `pkgs` is a type error nowhere.
  # `mode` is the word the matrix, the builder, the published key and the manifest all use for one
  # value (ADR-0030/0032).
  #
  # `pkgsFor` IS A FUNCTION, not an attrset, for two reasons that compound. The ordering one:
  # `systems` is derived from `homeMatrix`, so a consumer handing over a pre-built `pkgsBySystem`
  # must derive `systems` itself first and the absorption never completes. The load-bearing one: the
  # producer then owns the MEMOIZATION rule both producers previously carried as prose — `import
  # nixpkgs` is not memoized across applications, so it must be instantiated once per SYSTEM and
  # never once per member × home × system. The fold below applies `pkgsFor` exactly once per system,
  # and `pkgsBySystem` is RETURNED so the rule is a value a caller can hold (and a suite can pin)
  # rather than a comment it has to trust.
  #
  # THE CROSS-PRODUCT IS HARD-WIRED: every member is BUILT for every mode in its system's row —
  # and then PUBLISHED for the ones it says it supports, which `mkContractUsers` decides one rung
  # down (ADR-0032 §6). Building is per-system and publishing is per-user, so the two cannot be one
  # step. This is also why `homes` is read back off the bindings below rather than re-filtered here:
  # "what is published" has one owner, and it is not the fold. That is the
  # call `mkMemberChecks` already made, whose coverage rule is the same "every member on every
  # system". A producer whose bake is NOT a full cross-product drops to `mkContractUsers`, which
  # stays PUBLIC for exactly that reason — the contract is consumed at a URL, so internalizing it
  # would lock out a third-party producer with no way back in.
  #
  # WHAT STAYS THE CONSUMER'S: `pkgsFor`, the members, the matrix, the `mkHome` partial application
  # (its `homeManagerConfiguration` and `stateVersion`), any unbaked home (a greeter-login mapper
  # keeps calling `mkContractHome` directly — it is exempt by design, not served), the
  # `homeConfigurations` published-name rule, and the checks.
  mkContractFleet =
    {
      # Kit-injected (a caller never passes it): forwarded to `mkContractUsers` below.
      loadIdentity,
      # WHO is in this repo — the `mkMembers` attrset (issue #57).
      members,
      # WHAT each system bakes — `mkHomeMatrix`'s value, `{ <system> = [ <mode> ]; }` (issue #58).
      # Its key set is this fleet's `systems`, which is why neither is stated twice.
      homeMatrix,
      # `system -> pkgs`. Applied once per system; see above.
      pkgsFor,
      # `{ member, mode, pkgs } -> home` — the consumer's own builder (ADR-0004).
      buildHome,
    }:
    let
      systems = lib.attrNames homeMatrix;
      rowOf = sys: homeMatrix.${sys};
      # Split by PARTITION rather than by two negated filters, for the reason `mkMemberChecks`
      # states one file over: the emptiness verdict below may only be asked of a row it can read,
      # and reporting a MALFORMED row as "names no home" would name the wrong mistake — so the two
      # sets have to stay exact complements, which a partition makes structural instead of a rule
      # two hand-written predicates have to keep agreeing on.
      byRowShape = lib.partition (sys: lib.isList (rowOf sys)) systems;
      malformedRows = byRowShape.wrong;
      emptyRows = lib.filter (sys: rowOf sys == [ ]) byRowShape.right;

      # THE MEMO. One application of `pkgsFor` per system, and the guard that the answer is about
      # the system it was asked for rides each entry — so it fires when that system's homes are
      # forced rather than when a caller merely reads `systems`, and a fleet is never charged for
      # instantiating nixpkgs for a system nothing asked about.
      #
      # Worth a named error because the raw one is opaque: `mkContractUsers` reads the system it
      # keys its outputs by off the `pkgs` it is handed (so a caller cannot key packages by a system
      # its pkgs was not built for), so a `pkgsFor` that answers the wrong system lands as an
      # `attribute '<system>' missing` from the merge below, naming nothing that went wrong.
      pkgsBySystem = lib.genAttrs systems (
        sys:
        let
          p = pkgsFor sys;
        in
        assert diag.must {
          ok = p.stdenv.hostPlatform.system == sys;
          who = "mkContractFleet";
          problem =
            "`pkgsFor ${showName sys}` returned pkgs for " + "${showName p.stdenv.hostPlatform.system} instead";
          why =
            "The outputs for a system are keyed by the system its own `pkgs` was built for, so "
            + "this fleet would publish one system's homes under another's name.";
          fix =
            "`pkgsFor` answers about the system it is asked for — " + "`sys: nixpkgs.legacyPackages.\${sys}`.";
        };
        p
      );

      # THE JOIN, and the only place it happens: the matrix hands out a MODE and this builds the
      # home for it, keyed by that very mode. Nothing is re-keyed and there is no record to pair —
      # the mode a home was built for and the mode it is published under are one key by
      # construction (ADR-0032 §6), which is why the cross-check that used to guard the join is
      # gone rather than moved.
      builtRows = lib.genAttrs systems (
        sys:
        lib.mapAttrs (
          _: member:
          lib.genAttrs (rowOf sys) (
            mode:
            buildHome {
              inherit member mode;
              pkgs = pkgsBySystem.${sys};
            }
          )
        ) members
      );

      # The per-system bake, `mkContractUsers` handed the built rows directly — its `homes`
      # argument IS `{ <user> = { <mode> = home; }; }`, so there is no reshaping between the two
      # and no second spelling of the fold.
      bindings = lib.mapAttrs (
        sys: byMember:
        mkContractUsers {
          inherit loadIdentity members;
          pkgs = pkgsBySystem.${sys};
          homes = byMember;
        }
      ) builtRows;
    in
    # Grouped by SUBJECT — the member set, then the matrix, then its rows — and within each the same
    # order the rest of this file uses: a shape that cannot be read before anything is read off it,
    # and a fold that would build NOBODY before any verdict about what it built. Grouped rather than
    # strictly most-specific-first because the two subjects are independent: a reader handed both
    # wrong should be told about the one they are looking at, not about whichever is more specific.
    assert diag.must {
      ok = lib.isAttrs members;
      who = "mkContractFleet";
      problem = "the member set is not an attrset";
      fix =
        "It is `mkMembers`'s own value (`{ <name> = { name; dir; identity; }; }`), keyed by member "
        + "name, not a list of members.";
    };
    assert diag.must {
      ok = members != { };
      who = "mkContractFleet";
      problem = "the member set is empty";
      why = diag.vacuity { subject = "member set"; };
      fix =
        "Derive it from the users directory (`mkMembers { usersDir = ./users; }`), which refuses "
        + "an empty one at the source.";
    };
    assert diag.must {
      ok = lib.isAttrs homeMatrix;
      who = "mkContractFleet";
      problem = "`homeMatrix` is not an attrset";
      fix = "It is `mkHomeMatrix`'s own value, keyed by system: `{ <system> = [ <mode> ]; }`.";
    };
    assert diag.must {
      ok = homeMatrix != { };
      who = "mkContractFleet";
      problem = "`homeMatrix` names no system";
      why = diag.vacuity { subject = "matrix"; };
      fix = "Its key set is the systems this fleet bakes for.";
    };
    assert diag.must {
      ok = malformedRows == [ ];
      who = "mkContractFleet";
      problem = "the `homeMatrix` row(s) for ${showList malformedRows} are not lists";
      fix = "Each system's row is a LIST of MODE names — one entry per home it builds.";
    };
    assert diag.must {
      ok = emptyRows == [ ];
      who = "mkContractFleet";
      problem = "system(s) ${showList emptyRows} name no home at all";
      why = diag.vacuity {
        subject = "row";
        verbs = "build, publish and check";
      };
      fix =
        "Leave a system out of the matrix entirely if this fleet does not bake for it. "
        + "`mkHomeMatrix` refuses an emptied row at the source.";
    };
    {
      inherit systems pkgsBySystem;
      # `<system>.<user>.<mode>` — the PUBLISHED homes, and a flake output in its own right
      # (ADR-0032 §6). Read back off the bindings rather than re-derived from `builtRows`: the
      # index's key set IS the published mode set, so taking it from there keeps ONE owner of the
      # `supports` cut. `attrNames` on the index forces no package, so this stays as lazy as the
      # bindings themselves.
      homes = lib.mapAttrs (
        sys: b:
        lib.mapAttrs (
          user: entry: lib.getAttrs (lib.attrNames entry.contractPackages) builtRows.${sys}.${user}
        ) b.contractUsers.${sys}
      ) bindings;
      # Nested by system, so `inherit (fleet) packages contractUsers;` is the flake outputs. Each
      # system's bake already keys its own outputs by that system, so this only unwraps the key it
      # was going to be looked up under anyway — never a re-keying.
      packages = lib.mapAttrs (sys: b: b.packages.${sys}) bindings;
      contractUsers = lib.mapAttrs (sys: b: b.contractUsers.${sys}) bindings;
    };

  # mkContractHome (ADR-0029, issue #40): the producer HOME builder — absorbs the mkHome glue every
  # producer hand-wrote (the umbrella + the user's home.nix + the identity/home.* inline module +
  # the hostFacts specialArg) into the one contract-owned composition. ADR-0004's package-free
  # invariant holds by INJECTION: the consumer passes home-manager's own entry point
  # (`home-manager.lib.homeManagerConfiguration`) verbatim, and the contract only composes the
  # arguments and applies the consumer's function — the same trick as mkConfinementCheck's
  # `buildHome`. `homeModule`/`homeBaselineModule`/`homeGreeterDesktopModule`/`loadIdentity` are
  # injected by the kit (as `homeModule` is for traceUser), so a caller passes only its own side.
  #
  # It builds a home for ONE MODE (ADR-0032). That is the whole of what used to be a grant set
  # here: a grant can no longer change a home, so there is nothing about the bake for the builder to
  # record and nothing for the producer to re-pair afterwards — the `contractBakedGrantKey` marker
  # and its `assertHomePairing` cross-check are gone with the pairing they existed to protect.
  #
  # THE GREETER-DESKTOP HELPER IS COMPOSED BY DEFAULT (ADR-0032). It writes `~/.contract-desktop`
  # from `contract.requests.gui.desktop` and is `mkIf (… != "")`, so it is inert when no desktop is
  # requested and costs a cli home nothing. It cannot move host-side: the greeter reads that dotfile
  # BEFORE evaluating the home's Nix, so the file must be in the home. It was opt-in only while a
  # separate greeter-granted home existed to opt it into; with grants no longer reaching homes there
  # is no such home, and composing it always is what retires `<u>-greeter` entirely.
  #
  # What stays consumer-side BY DESIGN: `pkgs` (each home layers its own overlays/config, and the
  # platform is read off it), `stateVersion` (a consumer fact — real repos differ — so no contract
  # default), and everything threaded through the two open seams: `extraModules` (confinement
  # probes, marker files, repo glue) and `extraSpecialArgs` (opaque passthrough, e.g. the ADR-0020
  # `inputs` convention). `hostFacts` is contract-owned and WINS over any extraSpecialArgs entry:
  # the mode a home was built for is the contract's own fact, so a caller cannot hand a home a
  # different one by spelling the specialArg itself.
  mkContractHome =
    {
      # Kit-injected (a caller never passes these): the home umbrella, the two home-manager-aware
      # helpers composed by default, and the identity.json loader behind `identity`'s default.
      homeModule,
      homeBaselineModule,
      homeGreeterDesktopModule,
      loadIdentity,
      # THE INJECTION SURFACE: home-manager's own builder, passed verbatim (ADR-0004).
      homeManagerConfiguration,
      # Per-user pkgs — consumer-side by design; also the source of `platform`.
      pkgs,
      # A member (see mkMembers): supplies BOTH the user's directory and its
      # already-resolved identity, so a producer that has a member set hands this one value and no
      # identity path is resolved a second time (issue #57).
      member ? null,
      # The user's subdir (ADR-0020 layout): holds home.nix, and identity.json unless `identity` is
      # passed. Either may be given INSTEAD of a member — the shape a single-user repo (or a
      # hand-driven build) keeps, and the one the suite drives when it composes a home from one
      # directory while holding an identity from elsewhere. Given BESIDE a member they may restate
      # it but not contradict it; `resolveMember` owns that rule for this and the producer coin
      # alike.
      memberDir ? null,
      identity ? null,
      # THE SESSION SHAPE this home is built for (ADR-0032) — the one mode, handed to the home as
      # `hostFacts.mode` and derived by the umbrella into `custom.home.profiles.<mode>.enable`.
      # REQUIRED and unvalidated against the registry here: the producer's matrix row is where a
      # mode name is checked (`mkHomeMatrix`), and re-checking it would be a second owner of the
      # rule. Named `mode` throughout — the matrix row, the builder, the published key and the
      # manifest field are one word for one value (ADR-0030).
      mode,
      # REQUIRED consumer fact — the real repos differ, so the contract carries no default.
      stateVersion,
      # The open seam: everything that makes one producer's homes differ from another's.
      extraModules ? [ ],
      # Opaque passthrough; `hostFacts` is contract-owned and wins (see above).
      extraSpecialArgs ? { },
    }:
    let
      # Who this home is for — the same resolution the producer coin runs (see `resolveMember`).
      # Only `dir` and `identity` are forced here; a builder call needs no published name, so one
      # that has neither a member nor a `memberDir` is told about the directory it is missing.
      who = resolveMember {
        context = "mkContractHome";
        dirRoutes = "`memberDir`, the ADR-0020 user directory holding this user's home.nix";
        inherit
          loadIdentity
          member
          memberDir
          identity
          ;
      };
    in
    homeManagerConfiguration {
      inherit pkgs;
      modules = [
        homeModule
        homeBaselineModule
        homeGreeterDesktopModule
        (homeFileIn who.dir)
        {
          identity = who.identity;
          home.username = who.identity.username;
          # A fixed contract rule, not a knob: the realized account lands at the same path (the
          # normal-user default the realization keeps, and the literal the greeter's provision
          # writes), so home and account can never disagree about where home is.
          home.homeDirectory = "/home/${who.identity.username}";
          home.stateVersion = stateVersion;
        }
      ]
      ++ extraModules;
      extraSpecialArgs = extraSpecialArgs // {
        # THE FACTS this home is handed (ADR-0032 §7), and the whole of them:
        #
        #   mode      the session shape it was BUILT for. The umbrella derives
        #             `custom.home.profiles.<mode>.enable` from it — exactly one true.
        #   platform  the system it is built for, read off the caller's own `pkgs`.
        #   exposed   false, because a pre-built home is built per MODE, not per host: which seat
        #             eventually binds it, and whether that seat is exposed, is unknowable here.
        #
        # `granted` is deliberately ABSENT. No grant can affect a home, so showing one the grant set
        # would be showing it something it must not use — the hazard ADR-0028's narrowing existed to
        # prevent, removed at the source rather than guarded. That narrowing WAS the whole content of
        # the exported `hostFactsFor`, so with nothing left to narrow there is no rule for a producer
        # to get wrong and no projection worth naming: the literal lives here, at its one site.
        hostFacts = {
          inherit mode;
          exposed = false;
          platform = pkgs.stdenv.hostPlatform.system;
        };
      };
    };

  # bindContractPackage (ADR-0016, issue #16): the INTERNAL package-level kernel `bindContractUser`
  # binds through. It reads the already-built `contract-requests.json` from a pinned store path and
  # bridges the feature requests via `mkUserAccount`/`bridgeRequests`. No home-manager dependency.
  # Returns a NixOS module (not a tracer value) that the host imports. NOT public: hosts consume the
  # user-level `bindContractUser`, which selects a contractPackage from the index and delegates here (ADR-0026).
  #
  # `contractPackage` must be a realized store path at eval time — in the pre-built workflow it is
  # a pinned flake input already in the store, so reading its JSON is a plain `builtins.readFile`,
  # not IFD. The module references `pkgs` (the host's NixOS pkgs) to build the package-policy
  # profile when `custom.host.packagePolicy.allowedPrograms` is non-empty (ADR-0017, issue #17).
  # `hostFacts` has no role in the pre-built path (the home is already evaluated) and is omitted.
  #
  # `runs` is the modes THIS HOST runs, derived from its affordances by the caller — the coupling
  # guard below is its only reader, and it takes the set rather than deriving it so this kernel
  # stays a pure function of what it is handed (the same posture `grants` takes). REQUIRED, with no
  # permissive default: the guard exists for exactly this path (the public `bindContractUser`
  # satisfies it by construction), so a default that let a caller opt out would make it inert
  # precisely where it is the only thing looking.
  bindContractPackage =
    {
      contractPackage,
      identity,
      runs,
      grants ? { },
    }:
    { config, pkgs, ... }:
    let
      username = identity.username;
      # Read the pinned manifest THROUGH the schema owner (the `manifest` module): it applies the
      # backward-compat read (an absent `mode` normalizes to `null`, absent `packages` to `[ ]`), so
      # this consumer never spells the field set or the filename itself.
      parsed = manifest.readManifest "${contractPackage}/${manifest.manifestFileName}";
      requests = parsed.requests;
      allowedPrograms = config.custom.host.packagePolicy.allowedPrograms;
      userPackages = parsed.packages;
      approvedNames = lib.filter (n: lib.elem n allowedPrograms) userPackages;
      approvedPkgs = lib.filter (p: p != null) (map (n: pkgs.${n} or null) approvedNames);
      # THE COUPLING GUARD (ADR-0016, restated by ADR-0032 §8): a host may activate a home only if
      # it actually RUNS the mode that home was built for. One field instead of a list, and the
      # same defense-in-depth posture — `bindContractUser`'s selection satisfies it by
      # construction, so this covers the internal path where the kernel is called directly.
      #
      # It is the mode rather than the grant because that is what a bind cannot fix: a grant not
      # conferred degrades silently by design (ADR-0002), whereas a home built for a graphical
      # session, activated on a machine with no display, is a worse answer than an error naming the
      # mismatch. The ONE case with nothing to check is a pre-v3 manifest, which reads back
      # `mode = null` because it predates the field — the same posture the v1 grant-key's `[ ]`
      # took, and confined to the same place.
      bakedMode = parsed.mode;
      guard = diag.must {
        ok = bakedMode == null || lib.elem bakedMode runs;
        who = "bindContractPackage";
        problem =
          "the home selected for ${showName username} was built for mode "
          + "${showName bakedMode}, which this host does not run (it runs ${showList runs})";
        why =
          "A mode is what the home IS, not something a bind confers, so activating it on a host "
          + "that cannot run it degrades into a session the user cannot use — the one mismatch "
          + "ADR-0002's silent degradation does not cover.";
        fix =
          "Afford the feature that mode is run under, or bind a user that supports a mode this "
          + "host runs.";
      };
    in
    {
      # The guard rides the account VALUE, not a wrapping `assert` on this whole attrset: when
      # `contractPackage` is SELECTED from config (bindContractUser), a top-level `assert` would
      # force the manifest read while the module system merely probes this module for unrelated
      # options (e.g. `nixpkgs.*` to build `pkgs`), and that read — reaching back through the
      # config-derived package into `pkgs` — is an infinite recursion. Attached to the account, the
      # guard fires whenever `custom.users.<u>` is read (always, via the realization) but never
      # during bare option-key probing. Still a hard eval error on violation.
      custom.users.${username} =
        assert guard;
        mkUserAccount { inherit identity grants requests; };
      # A login session that PERSISTS past activation: the home's user systemd services (sd-switch,
      # sops-nix) must keep running after the `runuser -l` activation exits, so the binding lingers
      # the user itself rather than leaving it a per-seat "should" (issue #1 review: linger was
      # unenforced — a production seat that forgot it silently degraded to non-persistent services).
      users.users.${username}.linger = true;
      # A systemd oneshot service (not system.activationScripts) so it runs after PAM is
      # configured. activationScripts run during the initrd activation phase where runuser/su
      # cannot open /etc/pam.conf yet — a oneshot service executes post-boot under the full
      # systemd environment where PAM is ready. Before= ensures the service completes before
      # multi-user.target, so callers waiting on that target see the home as activated.
      systemd.services."contract-activate-${username}" = {
        description = "Activate contract package for ${username}";
        wantedBy = [ "multi-user.target" ];
        before = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Run the home activation inside a real LOGIN session for the user (root → `runuser -l`),
          # NOT as `User=<u>` with a bare HOME. A REAL home-manager `activate` needs USER, a login
          # PATH, and — for its sd-switch/reloadSystemd step — a running user systemd manager plus
          # XDG_RUNTIME_DIR, all of which pam_systemd provisions on a login session. `User=<u>` +
          # `HOME=` alone activates a TRIVIAL script but a real home's activation fails there
          # (issue #1 integration: sd-switch could not reach the user manager). A seat that wants
          # the home's user services to PERSIST past activation should also linger the user.
          ExecStart = "${pkgs.util-linux}/bin/runuser -l ${username} -c ${contractPackage}/activate";
        }
        // (
          if allowedPrograms != [ ] then
            let
              profileEnv = pkgs.buildEnv {
                name = "contract-profile-${username}";
                paths = approvedPkgs;
                ignoreCollisions = true;
              };
            in
            {
              # After activate, replace ~/.nix-profile with the host-built policy profile
              # (intersection of allowedPrograms and user's manifest packages), as the user.
              ExecStartPost = "${pkgs.util-linux}/bin/runuser -l ${username} -c '${pkgs.coreutils}/bin/ln -sfn ${profileEnv} /home/${username}/.nix-profile'";
            }
          else
            { }
        );
      };
    };

  # bindContractUser (ADR-0025, issue #25): the turnkey HOST-SIDE bind — the consumer twin of the
  # producer's `mkContractUser` (bind one contract-user ⇄ make one contract-user). A host declares
  # its `contract.affordances` ONCE and imports each user with `{ usersFlake; username }` — no
  # per-user `grants`, no mode names, no identity paths (the host holds ZERO users-repo
  # internals). It returns a NixOS module that:
  #   1. infers `system` from the host's own `pkgs`, and reads the user's binding index off the
  #      pinned `usersFlake` (`contractUsers.<sys>.<user>`, the pure data `mkContractUser` emitted);
  #   2. derives the MODES it runs from its affordances — the floor, plus every mode whose
  #      associated grant it affords (ADR-0032 §4). Nobody declares a mode, so the disagreement
  #      between "affords gui" and "runs gui" is unwriteable rather than guarded;
  #   3. SELECTS the mode: `runs ∩ published`, a non-floor mode winning, the floor otherwise, and a
  #      hard named error for an empty intersection or two rich modes (see `selectModeOver`);
  #   4. derives the grant as `affordances ∩ offer` — the host's affordance is a NECESSARY
  #      condition (an absolute veto: a feature the host does not afford is never granted, whatever
  #      the user offers), and the user's offer completes it (ADR-0025 "the grant becomes a
  #      negotiation");
  #   5. delegates to the internal `bindContractPackage` kernel with the selected home, the derived
  #      grant, the index-supplied identity, and the run set its coupling guard checks against.
  #
  # Selection satisfies that guard by construction (the selected home's mode is in `runs`), which
  # is what makes the guard defense-in-depth for the internal path rather than the enforcement
  # point. This is the sole PUBLIC consumer bind: the grant is always negotiated
  # (affordances ∩ offer), never written unilaterally by the host (ADR-0026).
  bindContractUser =
    { usersFlake, username }:
    # Apply the inner bindContractPackage module to the current module args and return its config,
    # rather than returning it via `imports`: the selected home depends on
    # `config.contract.affordances`, and an `imports` list that depends on `config` is an infinite
    # recursion (imports must resolve before the config fixpoint). Splicing the inner module's
    # config in directly is legal because it defines only config (no options, no imports) and
    # merely READS config values.
    { config, pkgs, ... }:
    let
      # The host's platform, inferred from the host's own pkgs (ADR-0025). Everything this module
      # selects from `system` (the binding index lookup, hence identity/home/grant) lands in
      # config VALUES, never in this module's top-level option KEYS — so probing the module for an
      # unrelated option (`nixpkgs.*`, to build `pkgs` itself) never forces `system` and there is
      # no config↔pkgs cycle. The keys are the fixed `custom.users` / `users.users` / `systemd`
      # paths bindContractPackage always sets.
      system = pkgs.stdenv.hostPlatform.system;
      index =
        usersFlake.contractUsers.${system}.${username} or (diag.stop {
          who = "bindContractUser";
          problem =
            "the users flake exposes no binding index for ${showName username} on " + "${showName system}";
          fix = "Does that flake call `contract.lib.mkContractUser(s)` for this system?";
        });
      affordedNames = grantedNamesOf config.contract.affordances;
      # The modes this host runs, DERIVED (ADR-0032 §4) — the host declared affordances and nothing
      # else, so there is no second declaration to disagree with this one.
      runs = runsFor affordedNames;
      # …and the mode it binds this user in. The published key set IS the user's `supports` as
      # narrowed by the producer's matrix, so selection reads one value rather than intersecting
      # two that must agree.
      mode = selectModeOver {
        who = "bindContractUser";
        subject = username;
        floor = floorMode;
        inherit runs;
        published = lib.attrNames index.contractPackages;
      };
      # grant = affordances ∩ offer (both necessary; the host's affordance is the veto). Derived
      # INDEPENDENTLY of the mode: a host must still be able to confer gui's groups to a cli-mode
      # user, and `wants.gui` stays vetoable, which is why the mode never implies its grant.
      grantNames = lib.intersectLists affordedNames (grantedNamesOf index.offer);
      grants = lib.genAttrs grantNames (_: true);
    in
    (bindContractPackage {
      contractPackage = index.contractPackages.${mode};
      inherit (index) identity;
      inherit grants runs;
    })
      { inherit config pkgs; };
in
{
  inherit
    safeSet
    modeNames
    floorOf
    floorMode
    runsFor
    selectModeOver
    homeMatrixOver
    mkHomeMatrix
    ;

  # The runtime/greeter grant (ADR-0006, ADR-0008): "default-open over the safe set". The
  # greeter does not let an operator choose features — it auto-grants every runtime-eligible
  # one, and privilege is impossible because the safe set EXCLUDES secret-bearing and
  # privileged-group features by construction. This is the canonical, conformance-checked grant
  # value the greeter provisions with (`contract-greeter-provision` realizes AT MOST the safe set);
  # single-sourcing it here is exactly ADR-0008's conformance condition (3): a greeter grants AT
  # MOST the safe set. `grants` is shaped `{ <feature> = bool; }` (the registry's
  # grantedOptions), so this lifts the safe-set NAME LIST into that grant attrset.
  greeterGrants = lib.genAttrs safeSet (_: true);

  # The Tier-1 restricted-eval posture (ADR-0014): the canonical Nix settings under which the
  # greeter EVALUATES and BUILDS a host-signed (semi-trusted) user home (step 5/6). Tier 1 is
  # vouched-for by the host's signature (ADR-0011), not blindly trusted — the build still runs
  # under a restricted eval to contain accidents and, crucially, to keep the repo from WIDENING
  # its own eval posture (ADR-0011 applied to eval: a repo cannot self-certify). As nix.conf:
  #   - accept-flake-config = false           the repo's own `nixConfig` is IGNORED — the
  #                                           un-widenable linchpin; without it a Tier-1 flake could
  #                                           relax every setting below by self-declaration.
  #   - restrict-eval = true                  eval may only touch the store + allowed paths/URIs:
  #                                           no `builtins.readFile "/etc/shadow"`, no arbitrary
  #                                           eval-time fetch. Safe because the greeter warms the
  #                                           full input closure (nix flake archive) BEFORE building,
  #                                           so the restricted build needs no eval-time network.
  #   - allow-import-from-derivation = false  no IFD — eval cannot force a build and import its output.
  #   - sandbox = true                        the build itself runs isolated (no network, no host fs).
  # The greeter hands this to the host's `homeBuilder` as NIX_CONFIG (augmenting the seat's
  # /etc/nix/nix.conf, so experimental-features etc. survive), so a naive `nix build` binding gets
  # the floor for free; the host may only ADD restrictions, never remove them.
  tier1EvalConfig = {
    accept-flake-config = false;
    restrict-eval = true;
    allow-import-from-derivation = false;
    sandbox = true;
  };

  # Render a settings attrset to a NIX_CONFIG / nix.conf body (newline-separated `key = value`).
  # Single-sourced so the greeter and the conformance proof apply byte-for-byte the SAME posture.
  renderNixConfig =
    settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        n: v: "${n} = ${if lib.isBool v then lib.boolToString v else toString v}"
      ) settings
    );

  # traceUser (ADR-0007, ADR-0026): the home-manager-free DRY-RUN inspector, and the sole
  # request→grant→bridge tool that sits OUTSIDE the contractUser produce/consume coin. Given a
  # user's home module + identity + grants, it harvests the user's `contract.requests` and returns
  # a plain record `{ username; home; requests; system }` — the account fragment the realization
  # would materialize, the grants that power it, and the granted requests bridged into feature
  # configuration (ADR-0003). Ungranted requests are inert — never bridged — so a request for an
  # ungranted feature is a silent no-op, not an error (ADR-0002: "the grant is the sole enabler;
  # degradation is silent"). `homeModule` is the contract's homeModules.default, partially applied
  # by the kit so a caller passes only the user side.
  #
  # SCOPE — it evaluates the home against the contract umbrella ALONE (lib.evalModules, no
  # home-manager, not even a stub — ADR-0004's package-free invariant), so it can only trace a
  # CONTRACT-PURE home that sets nothing but contract options. A REAL home module also sets
  # home-manager options (programs.*, home.*), which are undeclared here and would throw — that is
  # by design: `traceUser` answers "given these grants, what does my home request, and does it
  # bridge?" WITHOUT a build. It is the logic-level proof the conformance suite drives and the
  # public tool a home author dry-runs against; it is NOT a deployment path (real binds are
  # pre-built: `bindContractUser`, ADR-0026).
  #
  # PERMISSIVE MODE (ADR-0028) — `permissive = true` tolerates a home written against a NEWER
  # contract: feature keys this revision does not declare land as DATA (reported in `unknown`)
  # instead of throwing. Tolerance is confined to this inspector — the bind path is fully typed
  # (`contract.wants`/`contract.requests` carry no freeform) — because traceUser is the one place
  # that co-evaluates a roaming home with a possibly-older host umbrella, so it is the one place
  # cross-revision skew is real; and an inspector that dies on the question it exists to answer
  # ("what does this home ask for?") turns a diagnosis into a dead end.
  traceUser =
    {
      homeModule,
      userModule,
      identity,
      grants ? { },
      hostFacts ? { },
      pkgs ? null,
      permissive ? false,
    }:
    let
      username = identity.username;
      # The permissive overlay: re-declare the two user-voice namespaces with a freeform type.
      # Declaring an option twice MERGES the declarations, and two submodule types merge by
      # unioning their modules — so this ADDS a freeform to the umbrella's own typed options
      # rather than restating them, and every known key keeps its type (a malformed KNOWN
      # request still errors, even here).
      # Each carries a TYPE only: the description and default belong to the umbrella's own
      # declaration, which this merges into (restating either would be a second owner of them).
      permissiveVoice = {
        options.contract.requests = lib.mkOption {
          type = lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; };
        };
        options.contract.wants = lib.mkOption {
          type = lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; };
        };
      };
      # Evaluate the user's home against the contract home umbrella. traceUser is the SINGLE
      # reader of the loaded identity (ADR-0009): it injects the same value into the home it
      # gives the system account, so the home HOLDS its identity (e.g. for git name/email)
      # and the account and home can never disagree about who the user is — the home never
      # loads identity.json itself. hostFacts/pkgs are injected for the user module to adapt to.
      home = lib.evalModules {
        modules = [
          homeModule
          { inherit identity; }
          userModule
        ]
        ++ lib.optional permissive permissiveVoice;
        specialArgs = { inherit hostFacts pkgs lib; };
      };
      requests = home.config.contract.requests;
      wants = home.config.contract.wants;
      # The feature keys this contract revision declares, read from the very values the umbrella
      # declares these namespaces FROM — the request option fragments, and the registry the want
      # options are one `mapAttrs` off — so "unknown" cannot drift from "undeclared".
      unknownIn = known: value: lib.filter (k: !lib.elem k known) (lib.attrNames value);
    in
    {
      inherit
        username
        home
        requests
        wants
        ;
      # What this home asked for that this contract revision does not know — the skew report an
      # inspector exists to produce. Always [ ] in strict mode (an unknown key throws first).
      unknown = {
        requests = unknownIn (lib.attrNames featureConfigOptions) requests;
        wants = unknownIn (lib.attrNames registry) wants;
      };
      # The system module a host merges to realize this user (the account, its powers, and the
      # bridged request params that feed the display surface) — see `mkUserAccount`.
      system.custom.users.${username} = mkUserAccount { inherit identity grants requests; };
    };

  inherit
    mkContractPackage
    mkContractPackageForHome
    bindContractPackage
    mkMembers
    mkContractUser
    mkContractUsers
    mkContractFleet
    mkContractHome
    bindContractUser
    ;
}
