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

  # The HOME AXES (ADR-0028): the features whose grant cannot be applied to an already-built
  # home (`needsOwnHome` in the registry). Each is one axis of the home matrix a producer builds,
  # which is what makes `bakes` below its powerset; everything else rides the bind.
  #
  # INTERNAL. This was the public `homeAffecting`, and every consumer used it for exactly two
  # things — both now shipped whole, as `bakes` and `hostFactsFor` below. With the derived
  # forms exported there is no consumer for the raw list, and keeping it in means the two
  # derivations can no longer drift apart in a producer's hands.
  homeAxes = lib.filter (f: registry.${f}.needsOwnHome or false) (lib.attrNames registry);

  # The upper-bound HOME SET — the answer to a producer's "what must I build?". One entry per
  # COMBINATION of the axes (`powerset(homeAxes)`, which is why a second axis doubles it),
  # carrying the grant attrset to bake with and the canonical label to publish it under.
  #
  # Every producer used to derive this by hand: a powerset fold, a label function mirroring the
  # private `homeLabel`, and a comment restating the taxonomy — re-typed per repo, and silently
  # wrong the moment the registry gains an axis (a host granting the new feature binds the maximal
  # bake that IS baked and the home simply lacks its content, which nothing downstream reports).
  # `label` travels with `grants` so a caller cannot pair them up wrongly.
  homes = map (
    names:
    let
      grants = lib.genAttrs names (_: {
        enable = true;
      });
    in
    {
      inherit grants;
      label = homeLabel grants;
    }
  ) (lib.foldl' (acc: f: acc ++ map (s: s ++ [ f ]) acc) [ [ ] ] homeAxes);

  # The HOME MATRIX kernel (issue #58): narrow an upper bound to what each system bakes, and guard
  # the narrowing. `homeMatrixOver` takes the bound explicitly; the public `mkHomeMatrix` below is
  # this closed over the contract's own `bakes`, so no consumer-facing argument exists for the
  # suite's sake. INTERNAL, exposed only so the conformance suite can drive a synthetic TWO-axis
  # bound — the propagation this design exists for cannot otherwise be shown until some future
  # feature sets `needsOwnHome` (the posture `homeAxes` above is exposed under).
  #
  # WHICH bakes a fleet bakes per system stays the consumer's fleet fact (decision #43): the
  # matrix is the caller's declaration, and this only applies it. What the CONTRACT owns is the
  # SHAPE of that declaration, because the failure mode is silent: `bindContractUser` binds the
  # maximal bake that DOES exist, so an under-baked set costs a home its content with nothing
  # objecting. Producers hand-wrote the filter AND hand-wrote the assert catching their own filter's
  # failure — and a producer who writes it against a label list rather than the features, or against
  # the axes a system CAN use, drops a newly-added registry axis from a system's bake in silence.
  #
  # So the declaration is per-AXIS and OPEN by default: an axis a system's row omits is usable, and
  # a system's row states only what it takes AWAY. That is ADR-0002's "one mechanism, opposite
  # defaults" read for coverage rather than privilege — the same reasoning that defaults `wants` to
  # the safe set (ADR-0028): fail-CLOSED is right where the risk of the unknown is admitting
  # something, fail-OPEN where the risk is omitting it. Under-baking is silent and costly;
  # over-baking wastes build time and nothing else. A contract that gains an axis therefore bakes it
  # EVERYWHERE — on the restricted systems too — with no edit in any consumer repo.
  #
  # The three under-bakes an earlier shape needed asserts for are now UNEXPRESSIBLE rather than
  # caught: the matrix is keyed by system, so its rows and its system list cannot disagree; presence
  # in it IS the classification, so no system can go unclassified; and an unrestricted system is one
  # whose row takes nothing away, which no separate claim can contradict. What remains guarded is
  # what the type cannot say.
  homeMatrixOver =
    {
      # The fleet's whole home matrix, in ONE fact: `{ <system> = { <axis> = bool; }; }` — which
      # systems this repo bakes, and, per system, which home axes its SEATS can use. An axis a
      # row OMITS is usable (absent ⇒ true), so `{ }` is a system that can use everything the
      # contract names and `{ gui = false; }` is a headless tier. A system absent from the matrix is
      # not baked at all.
      systems,
      # The bound to narrow — `bakes` for the public entry point.
      upperBound,
    }:
    let
      # The axes of the handed bound — the features any of its bakes is baked per. Derived from
      # the bound rather than read off `homeAxes` so there is ONE input to disagree with: a row's
      # axis names are checked against the very set the filter cuts by.
      axes = lib.unique (lib.concatMap (v: lib.attrNames v.grants) upperBound);
      systemNames = lib.attrNames systems;
      rowOf = sys: systems.${sys};
      settingsIn = sys: lib.attrNames (rowOf sys);
      # The axes a system's seats CANNOT use: the `false` entries of its row, and only those.
      unusableIn = sys: lib.filter (f: !(rowOf sys).${f}) (settingsIn sys);
      # The narrowing itself: drop every bake made per an axis this system's seats cannot use.
      matrix = lib.genAttrs systemNames (
        sys: lib.filter (v: !lib.any (f: v.grants ? ${f}) (unusableIn sys)) upperBound
      );

      labelsOf = vs: showList (map (v: v.label) vs);

      malformedRows = lib.filter (sys: !lib.isAttrs (rowOf sys)) systemNames;
      nonBoolIn = sys: lib.filter (f: !lib.isBool (rowOf sys).${f}) (settingsIn sys);
      byNonBool = lib.filter (sys: nonBoolIn sys != [ ]) systemNames;
      # Checked on the KEY whatever the boolean says: `sudo = true` is as much a mistake about what
      # the bake fans out on as `sudo = false` is, and reads as though it had been considered.
      nonAxesIn = sys: lib.filter (f: !lib.elem f axes) (settingsIn sys);
      byNonAxis = lib.filter (sys: nonAxesIn sys != [ ]) systemNames;
      emptied = lib.filter (sys: matrix.${sys} == [ ]) systemNames;
    in
    # Ordered so a broken declaration reports before any verdict about the homes, most specific first:
    # no systems at all, then a row of the wrong shape, then a non-boolean setting, then a setting
    # that names nothing the bake fans out on — and only then the one verdict about what IS baked.
    assert diag.must {
      ok = systems != { };
      who = "mkHomeMatrix";
      problem = "the matrix is empty";
      why = diag.vacuity { subject = "matrix"; };
      fix =
        "`systems` is `{ <system> = { <axis> = bool; }; }`: one entry per system this repo builds "
        + "for, `{ }` for a system whose seats can use everything the contract names.";
    };
    assert diag.must {
      ok = malformedRows == [ ];
      who = "mkHomeMatrix";
      problem = "the row(s) for ${showList malformedRows} are not attrsets";
      fix =
        "Each system's row is `{ <axis> = bool; }`, the home axes its seats can use, and `{ }` for "
        + "a system that can use everything the contract names.";
    };
    assert diag.must {
      ok = byNonBool == [ ];
      who = "mkHomeMatrix";
      problem = "non-boolean axis setting(s): ${diag.showPer nonBoolIn byNonBool}";
      why = "Each axis in a row is a BOOL — `false` where that system's seats cannot use it.";
      fix = "An omitted axis is usable, so a row states only what it takes away.";
    };
    assert diag.must {
      ok = byNonAxis == [ ];
      who = "mkHomeMatrix";
      problem = "setting(s) that are not home AXES: ${diag.showPer nonAxesIn byNonAxis}";
      why =
        "The axes of this contract are ${showList axes} — only a feature whose grant cannot be "
        + "applied to an already-built home (`needsOwnHome`) is one. A bind-riding feature "
        + "(`sudo`), a home LABEL (`base`) or a typo names nothing the build fans out on, so the "
        + "system would build the full set while reading as restricted.";
      fix = "Name the FEATURES a system's seats cannot use.";
    };
    assert diag.must {
      ok = emptied == [ ];
      who = "mkHomeMatrix";
      problem = "system(s) ${diag.showPer unusableIn emptied} build NO home at all";
      why =
        "Those axes cut every entry of the upper bound ${labelsOf upperBound}. "
        + diag.vacuity {
          subject = "row";
          verbs = "publish, bind and check";
        };
      fix = "Leave a system out of the matrix entirely if this fleet does not build for it.";
    };
    matrix;

  # mkHomeMatrix (issue #58): the PUBLIC per-system home matrix — `homeMatrixOver` closed over the
  # contract's own `bakes`, which is what makes a registry that gains an axis reach every
  # consumer's bake with no edit. Returns `{ <system> = [ <bake> ]; }`, each entry the same
  # `{ grants; label; }` value `bakes` hands out, so a producer maps over a row exactly as it
  # would over the whole set. See `homeMatrixOver` above for the declaration shape and the guards.
  mkHomeMatrix =
    { systems }:
    homeMatrixOver {
      inherit systems;
      upperBound = homes;
    };

  # The producer-side `hostFacts` projection: what a PRODUCER passes into a home it is baking.
  # Deliberately NOT the retired `mkHostFacts` under a new name — that one projected from a NixOS
  # host `config`, which only exists where a host evaluates a home inline (retired with that path
  # by ADR-0026). This one has no host in sight.
  #
  # The whole content is the narrowing. The grant set is cut to the bake axes, because those are
  # the only grants whose value is true information inside a given build: a home reading a
  # bind-riding grant structurally gets `false` forever instead of becoming grant-sensitive on
  # something no bake exists for. Producers wrote this `filterAttrs` out by hand — identically, in
  # two separate repos — and getting it wrong fails silently, by showing a home a grant it must not
  # see.
  #
  # `exposed` defaults false because a pre-built bake is baked per grant-combination, not per
  # host: which seat eventually binds it, and whether that seat is exposed, is unknowable here.
  #
  # Takes `grants` and returns it under `granted`, deliberately: `grants` is the ARGUMENT name every
  # function on this surface uses for a grant attrset, while `granted` is the OPTION PATH a home
  # reads it back on (`hostFacts.granted`, the same word `custom.users.<u>.granted` uses). Argument
  # and option path are two different kinds of name, and this is the one place both appear.
  hostFactsFor =
    {
      grants ? { },
      platform,
      exposed ? false,
    }:
    {
      inherit exposed platform;
      granted = lib.filterAttrs (f: _: lib.elem f homeAxes) grants;
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
  # because the derivation logic below reads it heavily (the coupling guard, the tracer, the index
  # projection, the turnkey bake selection).
  grantedNamesOf = grantLib.grantedNames;
  # List subset test — `a ⊆ b`. Single-sourced so the coupling guard and the turnkey
  # bake-selection (covering + maximal) all spell "is this grant-key covered?" one way.
  subsetOf = a: b: lib.all (x: lib.elem x b) a;
  # The GRANT-KEY of a grant set: its enabled feature names, SORTED. The canonical,
  # order-independent identity of a bake, and the one spelling of "which grant set is this?"
  # that the bake label, the binding index's `granted`, and the bake-pairing guard (issue #56)
  # all read through — so "the same grant set" cannot mean two things across them. The sort is
  # what makes it a key rather than a list: `grantedNamesOf` happens to fold over `attrNames`
  # (already sorted), but the key's order-independence must not rest on that.
  grantKey = grants: lib.sort (a: b: a < b) (grantedNamesOf grants);
  # The human label for a grant-key: empty ⇒ `base`, else the names joined. Split out of
  # `homeLabel` (below) so the pairing guard can name a key it was HANDED — a recorded name
  # list, with no grant attrset to project — in the same words the published package uses.
  keyLabel = names: if names == [ ] then "base" else lib.concatStringsSep "-" names;
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
  # (the host needs names, not store paths); `username` is the account name; `grants` is the grant
  # set the home was BUILT with — its enabled feature names are baked into the manifest so a host
  # `bindContractPackage` can prove its own grant matches the bake (the secret-bearing
  # coupling, ADR-0016: "the grant baked into the home MUST match the grant the host passes").
  #
  # The manifest is serialized to a store path at EVAL TIME via the `manifest` module's `writeManifest`
  # (`builtins.toFile`, pure, no IFD), then copied into the derivation during the build. The manifest
  # module OWNS the schema (version, field set, filename); this producer only projects its inputs into
  # that shape — package DERIVATIONS to package NAMES (the host needs names, not store paths), the grant
  # attrset to the baked feature-name list. The derivation is content-addressed: the same home eval
  # always produces the same store path, covering both activate and the requests.
  mkContractPackage =
    {
      pkgs,
      activationPackage,
      requests,
      packages,
      username,
      grants ? { },
    }:
    let
      packageNames = map (p: p.pname or (builtins.parseDrvName p.name).name) packages;
      manifestFile = manifest.writeManifest {
        inherit username requests;
        packages = packageNames;
        # The GRANT-KEY the home was baked with (ADR-0016 coupling guard) — the same projection
        # the binding index publishes and the bake-pairing guard compares, so the manifest cannot
        # be a third spelling of "which grant set is this?".
        grantKey = grantKey grants;
      };
    in
    pkgs.runCommand "contract-package-${username}" { } ''
      mkdir -p $out
      cp ${activationPackage}/activate $out/activate
      chmod +x $out/activate
      cp ${manifestFile} $out/${manifest.manifestFileName}
    '';

  # THE BAKE PAIRING (issue #56) — the attribute a home built by `mkContractHome` CARRIES: the
  # grant-key it was baked under. The contract owns both ends of a bake (`mkContractHome` evaluates
  # one home under a grant set; the producer coin bakes an already-evaluated home) but not the JOIN
  # between them — a producer builds each bake's home, then re-pairs `{ grants; home }` by label
  # when it hands the list over. That pairing used to be trusted: `granted` — in the manifest, in the
  # binding index, and so in every downstream guard (the ADR-0016 coupling guard, `bindContractUser`'s
  # maximal-bake selection) — came from the grant attrset passed ALONGSIDE the home, never from
  # what the home was actually built with. A mispairing therefore shipped a `base` home published
  # under a `gui` grant-key, and nothing in the system could see it.
  #
  # So the grant set TRAVELS WITH THE HOME and the producer cross-checks it. The marker rides the
  # RETURNED VALUE rather than a home option, for two reasons: `homeModules.default` must stay
  # evaluable by bare `evalModules` with no home-manager (ADR-0004/0008), and `contract.*` in a home
  # is the USER's voice — a producer-written key there would be a second, spoofable spelling of a
  # fact the home already reads as `hostFacts.granted`. (It is a PUBLIC attribute either way: the
  # builder's result is what a producer publishes as `homeConfigurations.<u>`, which is also what a
  # greeter builds. Nothing reads it but this guard, and nothing may — it is a bake-time cross-check,
  # not a channel.)
  #
  # This is the guard: `true` when the pairing holds, a named hard eval error when it does not, and
  # `true` — SKIPPED, not fired — for a home built by hand rather than through `mkContractHome`.
  # Not every producer uses the builder (a hand-rolled or future nix-darwin home bakes through the
  # generic kernel), so the marker's absence must degrade to the old, trusting behaviour rather than
  # making the builder a hard requirement.
  #
  # Compared as GRANT-KEYS (`grantKey`, the sorted enabled names), which is the whole observable
  # content of a grant set and exactly what the index publishes — so `{ gui.enable = true;
  # sudo.enable = false; }` and `{ gui.enable = true; }` are the same key, as they are everywhere
  # else here. The comparison is on the key AS PASSED to the builder, not on the narrowed one the
  # home saw: the narrowing (ADR-0028) is deterministic, so key equality is the stronger claim, and
  # the rule a producer has to hold is the simple one — hand the bake the SAME grant attrset you
  # handed the builder.
  assertHomePairing =
    {
      context,
      username,
      home,
      grants,
    }:
    let
      baked = home.contractBakedGrantKey or null;
      passed = grantKey grants;
      show = names: "${showName (keyLabel names)} (${showList names})";
    in
    baked == null
    || diag.must {
      ok = baked == passed;
      who = context;
      problem =
        "mispaired build for ${showName username} — its home was BUILT under grant-key "
        + "${show baked} but the producer paired it with ${show passed}";
      why =
        "The manifest's grant-key and the binding index's are taken from the grant passed "
        + "alongside the home, so this would publish a home under a grant set it was never built "
        + "with — and every downstream guard (the ADR-0016 coupling guard, maximal-home selection) "
        + "would read the wrong one.";
      fix = "Pass each home the SAME grant attrset you passed `mkContractHome`.";
    };

  # assertNoVetoedRequests (issue #59): the second bake-time guard on a bake's home — the two
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
      vetoed = lib.filter (f: !(wants.${f}.enable or false)) (
        requestingFeatures home.config.contract.requests
      );
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

  # mkContractPackageForHome (ADR-0016, issue #23): the OPTIONAL home-manager producer adapter. It mirrors
  # `bindContractPackage`'s turnkey-ness on the PRODUCER side — since ~every producer builds its
  # home with home-manager, each one otherwise hand-rolls the identical adapter that reads the four
  # disassembled primitives (`activationPackage`, `requests`, `packages`, `username`) off its home.
  # This lifts that recurring wrapper into the contract so a producer calls `{ home; grants; pkgs; }`.
  #
  # It does NOT import home-manager (ADR-0004 package-free preserved): it only READS attributes off
  # an already-evaluated `home` (`activationPackage`, `config.contract.requests`,
  # `config.home.{packages,username}`), never importing the builder. The generic `mkContractPackage`
  # stays builder-agnostic (a hand-rolled or future nix-darwin home still calls the core directly);
  # this is a thin convenience over it. `pkgs` stays a parameter so one call emits multi-arch bakes.
  # INTERNAL: the public producer surface is `mkContractUser`/`mkContractUsers`, which bake through this.
  #
  # This is where a home and a grant set JOIN into a published artifact, so it is where the bake
  # pairing is verified (issue #56): a home that carries the key it was built under may only be
  # baked under that key. `mkContractUser` guards its INDEX entry with the same predicate — the
  # manifest and the index must agree with the home, and they are two separate reads of `grants`.
  mkContractPackageForHome =
    {
      home,
      pkgs,
      grants ? { },
    }:
    let
      username = home.config.home.username;
    in
    assert assertHomePairing {
      context = "mkContractPackageForHome";
      inherit username home grants;
    };
    mkContractPackage {
      inherit pkgs grants username;
      activationPackage = home.activationPackage;
      requests = home.config.contract.requests;
      packages = home.config.home.packages;
    };

  # homeLabel (ADR-0025, issue #25): the canonical, ORDER-INDEPENDENT label for a baked
  # bake — the sorted home-affecting grant-key feature names, empty ⇒ `base`. It names the
  # published package (`<user>-contractPackage-<name>`) only; selection reads the machine-readable
  # grant-key off the binding index, never this string, so the format is cosmetic — a label, not a
  # parse target (ADR-0025 "Considered Options": name-parse selection rejected).
  homeLabel = grants: keyLabel (grantKey grants);

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
  # it.** Nothing is silently overridden — a disagreement is the same species of mispairing the bake
  # pairing rejects one rung down (issue #56), where one user's material reaches an output under
  # another's name. The members-LESS shapes are untouched: they are simply the case with no member to
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
  # repo calls it once; `mkContractUsers` (below) is nothing but this mapped over the members. It bakes
  # ONE user's declared bakes and emits the same flake-output shape a host consumes — ready to
  # `inherit … packages contractUsers`:
  #   - the named packages `<user>-contractPackage-<homeLabel>` (built via mkContractPackageForHome
  #     — so this stays package-free, only READING attributes off an already-evaluated home, ADR-0004), and
  #   - the pure `contractUsers.<sys>.<user>` BINDING INDEX entry `{ identity; offer; contractPackages = [{
  #     granted; package }] }`. The index is plain data (`granted` is the bake's grant-key as a
  #     NAME LIST; `package` is the built derivation), so a host's `bindContractUser` selects a bake
  #     by reading it — never by building every bake to inspect a baked manifest (the ADR-0016
  #     "can't read manifests cheaply" trap, sidestepped).
  #
  # WHO this user is comes in one of two ways (issue #57), resolved by the shared `resolveMember`.
  # Preferred: a `member` — a `mkMembers` entry `{ name; dir; identity; }`, whose identity is
  # ALREADY resolved, so this re-derives no path and the `identity.json` is read once per evaluation
  # for the whole repo. Otherwise: `name` + `usersDir`, and the ADR-0020 path is resolved through the
  # kit-injected `loadIdentity` (ADR-0009) — the shape a SINGLE-USER repo keeps, since one user is
  # not a member set, and constructing one to bake it would be ceremony.
  #
  # `bakes` is `[{ grants; home }]` — `grants` is the grant ATTRSET the bake is baked with (the
  # same `{ <feature>.enable = bool; }` shape, under the same name, that `mkContractHome` bakes the
  # home under and `mkContractPackageForHome` consumes); it is projected to the index's `granted`
  # NAME LIST by `grantedNamesOf`. `loadIdentity` is injected by the kit (like `homeModule` for
  # `traceUser`) so the users flake calls this without wiring the loader itself. `pkgs` is a
  # parameter so one call can emit multi-arch outputs, and the system the outputs are keyed by is
  # read off it rather than passed a second time.
  #
  # The `offer` is HARVESTED, never passed (ADR-0028): it is `contract.wants` read off the already-
  # evaluated home, so the user's voice lives in the user's own home rather than in the producer's
  # flake. Because the offer is what the grant is DERIVED from (`affordances ∩ offer`), a want that
  # depends on `hostFacts.granted` is circular — the harvest would differ per bake and the
  # published offer would be whichever bake happened to be first. That is a bake-time error here,
  # not a subtle mis-negotiation later.
  #
  # Harvesting the offer is also where the user's TWO halves meet, so it is where they are held to
  # each other (issue #59): a home carrying `contract.requests` data for a feature its own
  # `contract.wants` vetoes fails the bake, because that is the one contradiction no host can
  # rescue. Both halves are typed, but typed independently, so this is the only site that sees them
  # together — see `assertNoVetoedRequests`.
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
      # Both guards ride the whole bake RECORD (issues #56, #59), so reading any of its three
      # fields — the index's grant-key, the published package NAME, or the package itself — forces
      # them. That is every route a mispaired bake could take out of this bake, not just the
      # manifest `mkContractPackageForHome` guards on its own. (The user-level `identity` and `offer`
      # sit OUTSIDE the record and stay readable: they are per-user facts a mispairing cannot
      # corrupt.)
      #
      # The voice guard rides the record too, rather than the published `offer`, for two reasons: a
      # home's REQUESTS may legitimately differ across bakes (only `wants` may not), so the check
      # is per-bake; and the repo that must catch its own dead data is the USER's, whose flake
      # check builds the packages and never reads the index a host binds through.
      built = map (
        v:
        assert assertHomePairing {
          context = "mkContractUser";
          username = userName;
          inherit (v) home grants;
        };
        assert assertNoVetoedRequests {
          username = userName;
          inherit (v) home;
        };
        {
          # The index publishes the GRANT-KEY, under that name — the very projection the guard above
          # compared the home's own recorded key against, so the two cannot be the same words for
          # two things. It is a sorted NAME LIST, which is why it is not called `granted`: that word
          # is reserved for the attrset-shaped option paths (ADR-0030).
          grantKey = grantKey v.grants;
          package = mkContractPackageForHome {
            inherit pkgs;
            home = v.home;
            grants = v.grants;
          };
          label = homeLabel v.grants;
        }
      ) homes;
      # The harvested offer + its bake-invariance guard. Compared as the enabled-name PROJECTION
      # (what the index publishes and `bindContractUser` intersects), which is the whole observable
      # content of a want set.
      harvestedWants = map (v: v.home.config.contract.wants) homes;
      offeredNames = map grantedNamesOf harvestedWants;
      offer =
        if homes == [ ] then
          diag.stop {
            who = "mkContractUser";
            problem = "${showName userName} declares no homes";
            why = "There is no evaluated home to harvest `contract.wants` from.";
            fix = "A user must build at least one home.";
          }
        else if lib.all (o: o == lib.head offeredNames) offeredNames then
          lib.head harvestedWants
        else
          diag.stop {
            who = "mkContractUser";
            problem =
              "home-varying offer for ${showName userName} — its `contract.wants` differs across "
              + "its homes: ${lib.concatMapStringsSep ", " showList offeredNames}";
            why =
              "An offer that depends on `hostFacts.granted` is circular: the grant is DERIVED from "
              + "the offer (affordances ∩ offer), so it cannot also be an input to it.";
            fix = "Declare `contract.wants` the same way in every home this user builds.";
          };
    in
    {
      packages.${system} = lib.listToAttrs (
        map (v: lib.nameValuePair "${userName}-contractPackage-${v.label}" v.package) built
      );
      contractUsers.${system}.${userName} = {
        inherit identity offer;
        contractPackages = map (v: { inherit (v) grantKey package; }) built;
      };
    };

  # mkContractUsers (ADR-0025, issue #25): the MEMBER-SET convenience — `mkContractUser` mapped over a
  # whole multi-user repo and its outputs merged, so a `users` flake bakes its entire members in ONE
  # call and `inherit … packages contractUsers`. It is the turnkey producer for the multi-user shape
  # (ADR-0020) exactly as `bindContractUser` is the turnkey consumer; the singular `mkContractUser`
  # is the true per-user partner underneath. Each input user is `{ bakes }`, forwarded to
  # `mkContractUser` (the offer is harvested from each bake's home, ADR-0028 — a users entry
  # carries no `offer` field). Adds no logic of its own beyond the members fold — the per-user bake,
  # naming, and index shape all live in `mkContractUser`.
  #
  # WHO the users are is a `members` (issue #57): the `mkMembers` attrset, whose member for
  # each `users` key supplies that user's directory and already-resolved identity. `users` keys stay
  # the caller's own list because WHICH members it builds homes for, and which homes, is the producer's
  # home matrix — the same fleet fact the per-system bake filter is (decision #43), and not
  # something the contract opines on. A key the members does NOT hold is the other story: that is a
  # hand-listed name that has drifted from the directory, so it is a named error rather than a bake
  # of nobody. (The pre-members `usersDir` shape still works, and resolves per user as before.)
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
    {
      packages.${system} = lib.foldl' (acc: o: acc // o.packages.${system}) { } outs;
      contractUsers.${system} = lib.foldl' (acc: o: acc // o.contractUsers.${system}) { } outs;
    };

  # mkContractHome (ADR-0029, issue #40): the producer HOME builder — absorbs the mkHome glue every
  # producer hand-wrote (the umbrella + the user's home.nix + the identity/home.* inline module +
  # the hostFactsFor specialArg) into the one contract-owned composition. ADR-0004's package-free
  # invariant holds by INJECTION: the consumer passes home-manager's own entry point
  # (`home-manager.lib.homeManagerConfiguration`) verbatim, and the contract only composes the
  # arguments and applies the consumer's function — the same trick as mkConfinementCheck's
  # `buildHome`. `homeModule`/`homeBaselineModule`/`loadIdentity` are injected by the kit (as
  # `homeModule` is for traceUser), so a caller passes only its own side.
  #
  # What stays consumer-side BY DESIGN: `pkgs` (each home layers its own overlays/config, and the
  # platform is read off it), `stateVersion` (a consumer fact — real repos differ — so no contract
  # default), and everything threaded through the two open seams: `extraModules` (confinement
  # probes, greeterDesktop, marker files, repo glue) and `extraSpecialArgs` (opaque passthrough,
  # e.g. the ADR-0020 `inputs` convention). `hostFacts` is contract-owned and WINS over any
  # extraSpecialArgs entry: the narrowing (ADR-0028) is the contract's rule, so a caller cannot
  # accidentally hand a home an un-narrowed grant set by spelling the specialArg itself.
  #
  # The built home CARRIES the grant-key it was baked under, as `contractBakedGrantKey` on the
  # returned value (issue #56). That is the fact the producer coin cross-checks against the grant it
  # is asked to publish the home under, so a mispaired `{ grants; home }` is a bake-time error
  # instead of a silently mislabelled bake — see `assertHomePairing`. It records the key AS
  # PASSED here, before the `hostFactsFor` narrowing, because the pairing rule a producer holds is
  # "hand the bake the same grant attrset you handed the builder".
  mkContractHome =
    {
      # Kit-injected (a caller never passes these): the home umbrella, the baseline hygiene
      # module composed by default, and the identity.json loader behind `identity`'s default.
      homeModule,
      homeBaselineModule,
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
      # The grant attrset this bake is baked with; narrowed to the bake axes by hostFactsFor
      # (ADR-0028), so no caller re-derives that rule. Named `grants` because that is what a producer
      # already holds it as — the `{ grants; home }` records the coin consumes — so one value keeps
      # one name from the home matrix all the way to the pairing guard.
      grants ? { },
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
        hostFacts = hostFactsFor {
          inherit grants;
          platform = pkgs.stdenv.hostPlatform.system;
        };
      };
    }
    // {
      # The bake key travels with the home (see above). Added to the builder's RESULT, so a home
      # built by hand simply lacks it and the producer's cross-check is skipped rather than fired.
      contractBakedGrantKey = grantKey grants;
    };

  # bindContractPackage (ADR-0016, issue #16): the INTERNAL package-level kernel `bindContractUser`
  # binds through. It reads the already-built `contract-requests.json` from a pinned store path and
  # bridges the feature requests via `mkUserAccount`/`bridgeRequests`. No home-manager dependency.
  # Returns a NixOS module (not a tracer value) that the host imports. NOT public: hosts consume the
  # user-level `bindContractUser`, which selects a bake from the index and delegates here (ADR-0026).
  #
  # `contractPackage` must be a realized store path at eval time — in the pre-built workflow it is
  # a pinned flake input already in the store, so reading its JSON is a plain `builtins.readFile`,
  # not IFD. The module references `pkgs` (the host's NixOS pkgs) to build the package-policy
  # profile when `custom.host.packagePolicy.allowedPrograms` is non-empty (ADR-0017, issue #17).
  # `hostFacts` has no role in the pre-built path (the home is already evaluated) and is omitted.
  bindContractPackage =
    {
      contractPackage,
      identity,
      grants ? { },
    }:
    { config, pkgs, ... }:
    let
      username = identity.username;
      # Read the pinned manifest THROUGH the schema owner (the `manifest` module): it applies the
      # v1→v2 compat (a v1 manifest's absent `granted`/`packages` normalize to `[ ]`), so this
      # consumer never spells the field set or the filename itself.
      parsed = manifest.readManifest "${contractPackage}/${manifest.manifestFileName}";
      requests = parsed.requests;
      allowedPrograms = config.custom.host.packagePolicy.allowedPrograms;
      userPackages = parsed.packages;
      approvedNames = lib.filter (n: lib.elem n allowedPrograms) userPackages;
      approvedPkgs = lib.filter (p: p != null) (map (n: pkgs.${n} or null) approvedNames);
      # The coupling guard (ADR-0016, finally enforced by ADR-0025): a host may bind a bake
      # only if it actually grants every feature the bake was BAKED with. The manifest's
      # GRANT-KEY (the enabled feature names frozen into the home at bake time) MUST be a subset of
      # the grant the host passes — otherwise the host would activate a home built for privileges it
      # is not conferring (e.g. a home-affecting/secret-bearing bake it never granted). A v1
      # manifest predates the field (`readManifest` normalizes it to `[ ]` ⇒ vacuously satisfied).
      # Maximal-subset selection in `bindContractUser` satisfies this by construction; the check is
      # defense-in-depth for the internal kernel.
      bakedKey = parsed.grantKey;
      ungranted = lib.subtractLists (grantedNamesOf grants) bakedKey;
      guard = diag.must {
        ok = subsetOf bakedKey (grantedNamesOf grants);
        who = "bindContractPackage";
        problem =
          "the home selected for ${showName username} was built with grant(s) "
          + "${showList ungranted} the host does not grant (granted: "
          + "${showList (grantedNamesOf grants)})";
        why =
          "The ADR-0016 coupling guard requires the manifest's grant-key ⊆ the host's grant — "
          + "otherwise the host would activate a home built for privileges it is not conferring.";
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
  # per-user `grants`, no bake names, no identity paths (the host holds ZERO users-repo
  # internals). It returns a NixOS module that:
  #   1. infers `system` from the host's own `pkgs`, and reads the user's binding index off the
  #      pinned `usersFlake` (`contractUsers.<sys>.<user>`, the pure data `mkContractUser` emitted);
  #   2. derives the grant as `affordances ∩ offer` — the host's affordance is a NECESSARY
  #      condition (an absolute veto: a feature the host does not afford is never granted, whatever
  #      the user offers), and the user's offer completes it (ADR-0025 "the grant becomes a
  #      negotiation");
  #   3. selects the MAXIMAL bake whose grant-key ⊆ the derived grant — `sudo`/`containers`
  #      ride the bind and never multiply homes; no unique maximum (two incomparable baked
  #      homes both ⊆ the grant) is a HARD eval error naming the available homes, never a
  #      silent fallback;
  #   4. delegates to the internal `bindContractPackage` kernel with the derived grant + the
  #      index-supplied identity.
  # Maximal-subset selection satisfies the coupling guard by construction (the selected bake's
  # baked grants are ⊆ the derived grant). This is the sole PUBLIC consumer bind: the grant is
  # always negotiated (affordances ∩ offer), never written unilaterally by the host (ADR-0026).
  bindContractUser =
    { usersFlake, username }:
    # Apply the inner bindContractPackage module to the current module args and return its config,
    # rather than returning it via `imports`: the selected bake depends on
    # `config.contract.affordances`, and an `imports` list that depends on `config` is an infinite
    # recursion (imports must resolve before the config fixpoint). Splicing the inner module's
    # config in directly is legal because it defines only config (no options, no imports) and
    # merely READS config values.
    { config, pkgs, ... }:
    let
      # The host's platform, inferred from the host's own pkgs (ADR-0025). Everything this module
      # selects from `system` (the binding index lookup, hence identity/bake/grant) lands in
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
      # grant = affordances ∩ offer (both necessary; the host's affordance is the veto).
      grantNames = lib.intersectLists (grantedNamesOf config.contract.affordances) (
        grantedNamesOf index.offer
      );
      grants = lib.genAttrs grantNames (_: {
        enable = true;
      });
      # Maximal bake whose grant-key ⊆ the derived grant. A bake covers when every
      # feature it was baked with is granted; the maximum covers every other cover. Zero or ≥2
      # maxima (an uncovered or incomparable combo the producer never baked) is a hard error.
      covering = lib.filter (v: subsetOf v.grantKey grantNames) index.contractPackages;
      maxima = lib.filter (m: lib.all (c: subsetOf c.grantKey m.grantKey) covering) covering;
      availableList = lib.concatMapStringsSep ", " (v: showList v.grantKey) index.contractPackages;
      selected =
        if lib.length maxima == 1 then
          lib.head maxima
        else
          diag.stop {
            who = "bindContractUser";
            problem =
              "no unique maximal home of ${showName username} covers the derived grant "
              + "${showList grantNames} — the published grant-keys are: ${availableList}";
            why =
              "A home covers when every feature it was built with is granted; the maximum covers "
              + "every other cover. Zero or two incomparable covers means the producer never built "
              + "for this grant combination.";
          };
    in
    (bindContractPackage {
      contractPackage = selected.package;
      inherit (index) identity;
      inherit grants;
    })
      { inherit config pkgs; };
in
{
  inherit
    safeSet
    homeAxes
    homes
    homeMatrixOver
    mkHomeMatrix
    hostFactsFor
    ;

  # The runtime/greeter grant (ADR-0006, ADR-0008): "default-open over the safe set". The
  # greeter does not let an operator choose features — it auto-grants every runtime-eligible
  # one, and privilege is impossible because the safe set EXCLUDES secret-bearing and
  # privileged-group features by construction. This is the canonical, conformance-checked grant
  # value the greeter provisions with (`contract-greeter-provision` realizes AT MOST the safe set);
  # single-sourcing it here is exactly ADR-0008's conformance condition (3): a greeter grants AT
  # MOST the safe set. `grants` is shaped `{ <feature>.enable = bool; }` (the registry's
  # grantedOptions), so this lifts the safe-set NAME LIST into that grant attrset.
  greeterGrants = lib.genAttrs safeSet (_: {
    enable = true;
  });

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
    mkContractHome
    bindContractUser
    ;
}
