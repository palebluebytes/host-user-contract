# The contract's derivation logic — pure functions over the registry and its projections.
# The public producer/consumer coin is `mkContractUser`/`mkContractUsers` (bake a user, or a
# whole roster, into contractPackages + the binding index) and `bindContractUser` (a host
# binds one indexed user, grant = affordances ∩ offer); `traceUser` is the home-manager-free
# dry-run inspector. `mkContractPackageForHome`/`mkContractPackage`/`bindContractPackage` are
# the INTERNAL kernels those speak through (package-level, one rung below the user-level public
# surface), as is `runtimeEligibleFeature` (the kit's `safeSet` closes over it). `renderNixConfig`
# is the one public greeter helper here; `safeSet` is the derived value.
{
  lib,
  registry,
  manifest,
  grantLib,
  featureConfigOptions,
}:
let
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

  # The VARIANT AXES (ADR-0028): the features whose grant cannot be applied to an already-built
  # home (`needsOwnBuild` in the registry). Each is one axis of the build matrix a producer bakes,
  # which is what makes `variants` below its powerset; everything else rides the bind.
  #
  # INTERNAL. This was the public `homeAffecting`, and every consumer used it for exactly two
  # things — both now shipped whole, as `variants` and `hostFactsFor` below. With the derived
  # forms exported there is no consumer for the raw list, and keeping it in means the two
  # derivations can no longer drift apart in a producer's hands.
  variantAxes = lib.filter (f: registry.${f}.needsOwnBuild or false) (lib.attrNames registry);

  # The baked VARIANT SET — the answer to a producer's "what must I build?". One entry per
  # COMBINATION of the axes (`powerset(variantAxes)`, which is why a second axis doubles it),
  # carrying the grant attrset to bake with and the canonical label to publish it under.
  #
  # Every producer used to derive this by hand: a powerset fold, a label function mirroring the
  # private `variantName`, and a comment restating the taxonomy — re-typed per repo, and silently
  # wrong the moment the registry gains an axis (a host granting the new feature binds the maximal
  # variant that IS baked and the home simply lacks its content, which nothing downstream reports).
  # `label` travels with `grants` so a caller cannot pair them up wrongly.
  variants = map (
    names:
    let
      grants = lib.genAttrs names (_: {
        enable = true;
      });
    in
    {
      inherit grants;
      label = variantName grants;
    }
  ) (lib.foldl' (acc: f: acc ++ map (s: s ++ [ f ]) acc) [ [ ] ] variantAxes);

  # The producer-side `hostFacts` projection: what a PRODUCER passes into a home it is baking.
  # Deliberately NOT the retired `mkHostFacts` under a new name — that one projected from a NixOS
  # host `config`, which only exists where a host evaluates a home inline (retired with that path
  # by ADR-0026). This one has no host in sight.
  #
  # The whole content is the narrowing. `granted` is cut to the variant axes, because those are the
  # only grants whose value is true information inside a given build: a home reading a bind-riding
  # grant structurally gets `false` forever instead of becoming grant-sensitive on something no
  # variant bakes for. Producers wrote this `filterAttrs` out by hand — identically, in two
  # separate repos — and getting it wrong fails silently, by showing a home a grant it must not see.
  #
  # `exposed` defaults false because a pre-built variant is baked per grant-combination, not per
  # host: which seat eventually binds it, and whether that seat is exposed, is unknowable here.
  hostFactsFor =
    {
      granted ? { },
      platform,
      exposed ? false,
    }:
    {
      inherit exposed platform;
      granted = lib.filterAttrs (f: _: lib.elem f variantAxes) granted;
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
  # projection, the turnkey variant selection).
  grantedNamesOf = grantLib.grantedNames;
  # List subset test — `a ⊆ b`. Single-sourced so the coupling guard and the turnkey
  # variant-selection (covering + maximal) all spell "is this grant-key covered?" one way.
  subsetOf = a: b: lib.all (x: lib.elem x b) a;
  # The GRANT-KEY of a grant set: its enabled feature names, SORTED. The canonical,
  # order-independent identity of a variant, and the one spelling of "which grant set is this?"
  # that the variant label, the binding index's `granted`, and the bake-pairing guard (issue #56)
  # all read through — so "the same grant set" cannot mean two things across them. The sort is
  # what makes it a key rather than a list: `grantedNamesOf` happens to fold over `attrNames`
  # (already sorted), but the key's order-independence must not rest on that.
  grantKey = grants: lib.sort (a: b: a < b) (grantedNamesOf grants);
  # The human label for a grant-key: empty ⇒ `base`, else the names joined. Split out of
  # `variantName` (below) so the pairing guard can name a key it was HANDED — a recorded name
  # list, with no grant attrset to project — in the same words the published package uses.
  keyLabel = names: if names == [ ] then "base" else lib.concatStringsSep "-" names;
  bridgeRequests =
    requests: grantedNames:
    lib.foldl' (
      acc: f: if requests ? ${f} then acc // { ${f} = requests.${f}; } else acc
    ) { } grantedNames;

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
  # `bindContractPackage` can prove its own grant matches the baked variant (the secret-bearing
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
        granted = grantKey grants;
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
  # between them — a producer builds each variant's home, then re-pairs `{ grants; home }` by label
  # when it hands the list over. That pairing used to be trusted: `granted` — in the manifest, in the
  # binding index, and so in every downstream guard (the ADR-0016 coupling guard, `bindContractUser`'s
  # maximal-variant selection) — came from the grant attrset passed ALONGSIDE the home, never from
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
  assertBakePairing =
    {
      context,
      username,
      home,
      grants,
    }:
    let
      baked = home.contractBakedGrantKey or null;
      passed = grantKey grants;
      show = names: "'${keyLabel names}' ([${lib.concatStringsSep ", " names}])";
    in
    baked == null
    || lib.assertMsg (baked == passed) (
      "${context}: mispaired bake for '${username}' — its home was BUILT under grant-key "
      + "${show baked} but the producer paired it with ${show passed}. The manifest's `granted` "
      + "and the binding index's grant-key are taken from the grant passed alongside the home, so "
      + "this would publish a home under a grant set it was never built with — and every "
      + "downstream guard (the ADR-0016 coupling guard, maximal-variant selection) would read the "
      + "wrong one. Pass each variant the SAME grant attrset you passed `mkContractHome`."
    );

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
  # this is a thin convenience over it. `pkgs` stays a parameter so one call emits multi-arch variants.
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
    assert assertBakePairing {
      context = "mkContractPackageForHome";
      inherit username home grants;
    };
    mkContractPackage {
      inherit pkgs grants username;
      activationPackage = home.activationPackage;
      requests = home.config.contract.requests;
      packages = home.config.home.packages;
    };

  # variantName (ADR-0025, issue #25): the canonical, ORDER-INDEPENDENT label for a baked
  # variant — the sorted home-affecting grant-key feature names, empty ⇒ `base`. It names the
  # published package (`<user>-contractPackage-<name>`) only; selection reads the machine-readable
  # grant-key off the binding index, never this string, so the format is cosmetic — a label, not a
  # parse target (ADR-0025 "Considered Options": name-parse selection rejected).
  variantName = granted: keyLabel (grantKey granted);

  # THE ADR-0020 LAYOUT, spelled once (issue #57): a users directory holds one subdirectory per
  # user, and each holds that user's `identity.json` + `home.nix`. Every site that must name one of
  # those paths reads it through these three — the roster derivation below, and the two roster-less
  # fallbacks the coin and the home builder keep for a single-user repo — so the layout is ONE edit
  # rather than the four transcriptions this replaces. They are also why the join is spelled one way:
  # path concatenation, never string interpolation of the directory (which would coerce it into a
  # store path at a different moment than its siblings).
  userDirIn = usersDir: name: usersDir + "/${name}";
  identityFileIn = userDir: userDir + "/identity.json";
  homeFileIn = userDir: userDir + "/home.nix";

  # mkContractRoster (ADR-0020, issue #57): the contract's ONE answer to "who is in this users
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
  # mistake (off by a level, or renamed), and it must be a named error rather than an empty roster —
  # everything downstream maps over the roster, so an empty one bakes, publishes and checks NOTHING
  # while every flake output stays green (the same vacuity `mkIdentityPostureCheck` refuses).
  mkContractRoster =
    {
      # Kit-injected (a caller never passes it): the identity.json loader, ADR-0009's single loader.
      loadIdentity,
      # The ADR-0020 users directory — the parent of the per-user subdirectories.
      usersDir,
    }:
    let
      entries = builtins.readDir usersDir;
      names = lib.filter (
        n: entries.${n} == "directory" && builtins.pathExists (identityFileIn (userDirIn usersDir n))
      ) (lib.attrNames entries);
    in
    assert lib.assertMsg (names != [ ]) (
      "mkContractRoster: '${toString usersDir}' holds no member — no subdirectory of it has an "
      + "`identity.json`. A users directory is the ADR-0020 layout `users/<u>/identity.json`; an "
      + "empty roster would bake, publish and check nothing while every output stayed green, so this "
      + "is an error rather than `{ }`. Entries seen: ["
      + "${lib.concatStringsSep ", " (lib.attrNames entries)}]."
    );
    lib.genAttrs names (
      name:
      let
        dir = userDirIn usersDir name;
      in
      {
        inherit name dir;
        identity = loadIdentity (identityFileIn dir);
      }
    );

  # mkContractUser (ADR-0025, issue #25): the SINGULAR turnkey PRODUCER — the producer twin of the
  # consumer's `bindContractUser` (make one contract-user ⇄ bind one contract-user). A single-user
  # repo calls it once; `mkContractUsers` (below) is nothing but this mapped over a roster. It bakes
  # ONE user's declared variants and emits the same flake-output shape a host consumes — ready to
  # `inherit … packages contractUsers`:
  #   - the named packages `<user>-contractPackage-<variantName>` (built via mkContractPackageForHome
  #     — so this stays package-free, only READING attributes off an already-evaluated home, ADR-0004), and
  #   - the pure `contractUsers.<sys>.<user>` BINDING INDEX entry `{ identity; offer; variants = [{
  #     granted; package }] }`. The index is plain data (`granted` is the variant's grant-key as a
  #     NAME LIST; `package` is the built derivation), so a host's `bindContractUser` selects a variant
  #     by reading it — never by building every variant to inspect a baked manifest (the ADR-0016
  #     "can't read manifests cheaply" trap, sidestepped).
  #
  # WHO this user is comes in one of two ways (issue #57). Preferred: a `member` — a
  # `mkContractRoster` entry `{ name; dir; identity; }`, whose identity is ALREADY resolved, so this
  # re-derives no path and the `identity.json` is read once per evaluation for the whole repo.
  # Otherwise: `name` + `usersDir`, and the ADR-0020 path is resolved here through the kit-injected
  # `loadIdentity` (ADR-0009) — the shape a SINGLE-USER repo keeps, since one user is not a roster
  # and constructing one to bake it would be ceremony.
  #
  # `variants` is `[{ grants; home }]` — `grants` is the grant ATTRSET the variant is baked with (same
  # `{ <feature>.enable = bool; }` shape as everywhere else, and what `mkContractPackageForHome`
  # consumes); it is projected to the index's `granted` NAME LIST by `grantedNamesOf`. `loadIdentity`
  # is injected by the kit (like `homeModule` for `traceUser`) so the users flake calls this without
  # wiring the loader itself. `pkgs`/`system` stay parameters so one call can emit multi-arch outputs.
  #
  # The `offer` is HARVESTED, never passed (ADR-0028): it is `contract.wants` read off the already-
  # evaluated home, so the user's voice lives in the user's own home rather than in the producer's
  # flake. Because the offer is what the grant is DERIVED from (`affordances ∩ offer`), a want that
  # depends on `hostFacts.granted` is circular — the harvest would differ per variant and the
  # published offer would be whichever variant happened to be first. That is a bake-time error here,
  # not a subtle mis-negotiation later.
  mkContractUser =
    {
      loadIdentity,
      pkgs,
      system,
      # A roster entry (see mkContractRoster). Supplies both the name and the resolved identity.
      member ? null,
      # The user's name, for a caller with no roster. `null` means "not passed": passing it
      # ALONGSIDE a member is allowed only while the two agree — see the guard below.
      name ? null,
      usersDir ? null,
      variants,
    }:
    let
      # The name the outputs are keyed by. A member carries its own, and a `name` passed beside it
      # must MATCH: the published package name and the index key come from here while the identity
      # comes from the member, so a disagreement would put one user's identity under another's name
      # — the same species of silent mispairing the bake pairing rejects (issue #56), and equally
      # invisible downstream (a host binds by the index key it finds).
      userName =
        if member != null then
          assert lib.assertMsg (name == null || name == member.name) (
            "mkContractUser: mismatched user — the member is '${member.name}' but `name` says "
            + "'${name}'. The package name and the binding-index key come from `name` while the "
            + "identity comes from the member, so publishing these together would name one user's "
            + "artifacts after another. Pass the member alone, or a `name` that matches it."
          );
          member.name
        else if name != null then
          name
        else
          throw (
            "mkContractUser: pass either `member` (a `mkContractRoster` entry) or `name` + "
            + "`usersDir` (the ADR-0020 path to resolve this user's identity.json from)."
          );
      # Resolved ONCE, and only here: from the member if there is one (the roster already read the
      # file), otherwise from the ADR-0020 path. Nothing downstream of this re-derives it — the home
      # builder takes the same member, and the index below publishes this value.
      identity =
        if member != null then
          member.identity
        else if usersDir != null then
          loadIdentity (identityFileIn (userDirIn usersDir userName))
        else
          throw (
            "mkContractUser: '${userName}' was given a `name` but no `usersDir`, and no `member` "
            + "either — there is no identity.json to resolve. Pass a `mkContractRoster` entry, or "
            + "the users directory to resolve the ADR-0020 path under."
          );
      # The guard rides the whole variant RECORD (issue #56), so reading any of its three fields —
      # the index's grant-key, the published package NAME, or the package itself — forces it. That
      # is every route a mispaired variant could take out of this bake, not just the manifest
      # `mkContractPackageForHome` guards on its own. (The user-level `identity` and `offer` sit
      # OUTSIDE the record and stay readable: they are per-user facts a mispairing cannot corrupt.)
      built = map (
        v:
        assert assertBakePairing {
          context = "mkContractUser";
          username = userName;
          inherit (v) home grants;
        };
        {
          # The index publishes the GRANT-KEY — the very projection the guard above compared the
          # home's own recorded key against, so the two cannot be the same words for two things.
          granted = grantKey v.grants;
          package = mkContractPackageForHome {
            inherit pkgs;
            home = v.home;
            grants = v.grants;
          };
          label = variantName v.grants;
        }
      ) variants;
      # The harvested offer + its variant-invariance guard. Compared as the enabled-name PROJECTION
      # (what the index publishes and `bindContractUser` intersects), which is the whole observable
      # content of a want set.
      harvestedWants = map (v: v.home.config.contract.wants) variants;
      offeredNames = map grantedNamesOf harvestedWants;
      offer =
        if variants == [ ] then
          throw (
            "mkContractUser: '${userName}' declares no variants, so there is no evaluated home to "
            + "harvest `contract.wants` from — a user must bake at least one variant."
          )
        else if lib.all (o: o == lib.head offeredNames) offeredNames then
          lib.head harvestedWants
        else
          throw (
            "mkContractUser: variant-varying offer for '${userName}' — its `contract.wants` differs "
            + "across baked variants ("
            + lib.concatMapStringsSep "; " (o: "[${lib.concatStringsSep ", " o}]") offeredNames
            + "). An offer that depends on `hostFacts.granted` is circular: the grant is DERIVED "
            + "from the offer (affordances ∩ offer), so it cannot also be an input to it."
          );
    in
    {
      packages.${system} = lib.listToAttrs (
        map (v: lib.nameValuePair "${userName}-contractPackage-${v.label}" v.package) built
      );
      contractUsers.${system}.${userName} = {
        inherit identity offer;
        variants = map (v: { inherit (v) granted package; }) built;
      };
    };

  # mkContractUsers (ADR-0025, issue #25): the ROSTER convenience — `mkContractUser` mapped over a
  # whole multi-user repo and its outputs merged, so a `users` flake bakes its entire roster in ONE
  # call and `inherit … packages contractUsers`. It is the turnkey producer for the multi-user shape
  # (ADR-0020) exactly as `bindContractUser` is the turnkey consumer; the singular `mkContractUser`
  # is the true per-user partner underneath. Each input user is `{ variants }`, forwarded to
  # `mkContractUser` (the offer is harvested from each variant's home, ADR-0028 — a users entry
  # carries no `offer` field). Adds no logic of its own beyond the roster fold — the per-user bake,
  # naming, and index shape all live in `mkContractUser`.
  #
  # WHO the users are is a `roster` (issue #57): the `mkContractRoster` attrset, whose member for
  # each `users` key supplies that user's directory and already-resolved identity. `users` keys stay
  # the caller's own list because WHICH members it bakes, and with which variants, is the producer's
  # bake matrix — the same fleet fact the per-system variant filter is (decision #43), and not
  # something the contract opines on. A key the roster does NOT hold is the other story: that is a
  # hand-listed name that has drifted from the directory, so it is a named error rather than a bake
  # of nobody. (The pre-roster `usersDir` shape still works, and resolves per user as before.)
  mkContractUsers =
    {
      loadIdentity,
      pkgs,
      system,
      roster ? null,
      usersDir ? null,
      users,
    }:
    let
      memberFor =
        name:
        if roster == null then
          null
        else
          roster.${name} or (throw (
            "mkContractUsers: '${name}' is not in the roster — its `users` entry names somebody the "
            + "users directory does not hold (roster members: "
            + "[${lib.concatStringsSep ", " (lib.attrNames roster)}]). A `users` key is a member to "
            + "bake, so a name that has drifted from the directory is an error, not an empty bake."
          ));
      outs = lib.mapAttrsToList (
        name: u:
        mkContractUser {
          inherit
            loadIdentity
            pkgs
            system
            usersDir
            name
            ;
          member = memberFor name;
          inherit (u) variants;
        }
      ) users;
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
  # instead of a silently mislabelled variant — see `assertBakePairing`. It records the key AS
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
      # A roster entry (see mkContractRoster): supplies BOTH the user's directory and its
      # already-resolved identity, so a producer that has a roster hands this one value and no
      # identity path is resolved a second time (issue #57).
      member ? null,
      # The user's subdir (ADR-0020 layout): holds home.nix, and identity.json unless `identity`
      # is passed. Defaulted from the member; still passable on its own, so a single-user repo
      # (or a hand-driven build) needs no roster.
      #
      # These two are OVERRIDES, deliberately, and they win over the member: composing a home from
      # one directory while holding an identity from elsewhere is what the pre-roster `identity`
      # argument always allowed (the conformance suite drives the builder that way), and unlike the
      # coin's `name` it publishes nothing — the composed home is exactly what the caller asked for,
      # and its username follows the identity it was handed.
      userDir ? (
        if member != null then
          member.dir
        else
          throw (
            "mkContractHome: pass either `member` (a `mkContractRoster` entry) or `userDir` (the "
            + "ADR-0020 user directory holding home.nix) — there is no home to compose without one."
          )
      ),
      # Resolved-once override; taken from the member when there is one, else from the kit-injected
      # loader over userDir (ADR-0009: one identity loader, and the home HOLDS its identity rather
      # than loading it).
      identity ? (if member != null then member.identity else loadIdentity (identityFileIn userDir)),
      # The grant this variant is baked with; narrowed to the variant axes by hostFactsFor
      # (ADR-0028), so no caller re-derives that rule.
      granted ? { },
      # REQUIRED consumer fact — the real repos differ, so the contract carries no default.
      stateVersion,
      # The open seam: everything that makes one producer's homes differ from another's.
      extraModules ? [ ],
      # Opaque passthrough; `hostFacts` is contract-owned and wins (see above).
      extraSpecialArgs ? { },
    }:
    homeManagerConfiguration {
      inherit pkgs;
      modules = [
        homeModule
        homeBaselineModule
        (homeFileIn userDir)
        {
          inherit identity;
          home.username = identity.username;
          # A fixed contract rule, not a knob: the realized account lands at the same path (the
          # normal-user default the realization keeps, and the literal the greeter's provision
          # writes), so home and account can never disagree about where home is.
          home.homeDirectory = "/home/${identity.username}";
          home.stateVersion = stateVersion;
        }
      ]
      ++ extraModules;
      extraSpecialArgs = extraSpecialArgs // {
        hostFacts = hostFactsFor {
          inherit granted;
          platform = pkgs.stdenv.hostPlatform.system;
        };
      };
    }
    // {
      # The bake key travels with the home (see above). Added to the builder's RESULT, so a home
      # built by hand simply lacks it and the producer's cross-check is skipped rather than fired.
      contractBakedGrantKey = grantKey granted;
    };

  # bindContractPackage (ADR-0016, issue #16): the INTERNAL package-level kernel `bindContractUser`
  # binds through. It reads the already-built `contract-requests.json` from a pinned store path and
  # bridges the feature requests via `mkUserAccount`/`bridgeRequests`. No home-manager dependency.
  # Returns a NixOS module (not a tracer value) that the host imports. NOT public: hosts consume the
  # user-level `bindContractUser`, which selects a variant from the index and delegates here (ADR-0026).
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
      # The coupling guard (ADR-0016, finally enforced by ADR-0025): a host may bind a variant
      # only if it actually grants every feature the variant was BAKED with. `manifest.granted`
      # (the enabled feature names frozen into the home at bake time) MUST be a subset of the
      # grant the host passes — otherwise the host would activate a home built for privileges it
      # is not conferring (e.g. a home-affecting/secret-bearing bake it never granted). A v1
      # manifest predates the baked field (`granted or [ ]` ⇒ vacuously satisfied). Maximal-subset
      # selection in `bindContractUser` satisfies this by construction; the check is
      # defense-in-depth for the internal kernel.
      bakedGranted = parsed.granted;
      ungranted = lib.subtractLists (grantedNamesOf grants) bakedGranted;
      guard = lib.assertMsg (subsetOf bakedGranted (grantedNamesOf grants)) (
        "bindContractPackage: the variant for '${username}' was baked with grant(s) "
        + "[${lib.concatStringsSep ", " ungranted}] the host does not grant "
        + "(granted: [${lib.concatStringsSep ", " (grantedNamesOf grants)}]) — "
        + "the ADR-0016 coupling guard requires manifest.granted ⊆ granted."
      );
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
  # per-user `grants`, no variant names, no identity paths (the host holds ZERO users-repo
  # internals). It returns a NixOS module that:
  #   1. infers `system` from the host's own `pkgs`, and reads the user's binding index off the
  #      pinned `usersFlake` (`contractUsers.<sys>.<user>`, the pure data `mkContractUser` emitted);
  #   2. derives the grant as `affordances ∩ offer` — the host's affordance is a NECESSARY
  #      condition (an absolute veto: a feature the host does not afford is never granted, whatever
  #      the user offers), and the user's offer completes it (ADR-0025 "the grant becomes a
  #      negotiation");
  #   3. selects the MAXIMAL baked variant whose grant-key ⊆ the derived grant — `sudo`/`containers`
  #      ride the bind and never multiply variants; no unique maximum (two incomparable baked
  #      variants both ⊆ the grant) is a HARD eval error naming the available variants, never a
  #      silent fallback;
  #   4. delegates to the internal `bindContractPackage` kernel with the derived grant + the
  #      index-supplied identity.
  # Maximal-subset selection satisfies the coupling guard by construction (the selected variant's
  # baked grants are ⊆ the derived grant). This is the sole PUBLIC consumer bind: the grant is
  # always negotiated (affordances ∩ offer), never written unilaterally by the host (ADR-0026).
  bindContractUser =
    { usersFlake, username }:
    # Apply the inner bindContractPackage module to the current module args and return its config,
    # rather than returning it via `imports`: the selected variant depends on
    # `config.contract.affordances`, and an `imports` list that depends on `config` is an infinite
    # recursion (imports must resolve before the config fixpoint). Splicing the inner module's
    # config in directly is legal because it defines only config (no options, no imports) and
    # merely READS config values.
    { config, pkgs, ... }:
    let
      # The host's platform, inferred from the host's own pkgs (ADR-0025). Everything this module
      # selects from `system` (the binding index lookup, hence identity/variant/grant) lands in
      # config VALUES, never in this module's top-level option KEYS — so probing the module for an
      # unrelated option (`nixpkgs.*`, to build `pkgs` itself) never forces `system` and there is
      # no config↔pkgs cycle. The keys are the fixed `custom.users` / `users.users` / `systemd`
      # paths bindContractPackage always sets.
      system = pkgs.stdenv.hostPlatform.system;
      index =
        usersFlake.contractUsers.${system}.${username} or (throw (
          "bindContractUser: the users flake exposes no binding index for '${username}' on "
          + "'${system}' — does it call contract.lib.mkContractUser(s) for this system?"
        ));
      # grant = affordances ∩ offer (both necessary; the host's affordance is the veto).
      grantNames = lib.intersectLists (grantedNamesOf config.contract.affordances) (
        grantedNamesOf index.offer
      );
      grants = lib.genAttrs grantNames (_: {
        enable = true;
      });
      # Maximal baked variant whose grant-key ⊆ the derived grant. A variant covers when every
      # feature it was baked with is granted; the maximum covers every other cover. Zero or ≥2
      # maxima (an uncovered or incomparable combo the producer never baked) is a hard error.
      covering = lib.filter (v: subsetOf v.granted grantNames) index.variants;
      maxima = lib.filter (m: lib.all (c: subsetOf c.granted m.granted) covering) covering;
      availableList = lib.concatMapStringsSep "; " (
        v: "[${lib.concatStringsSep ", " v.granted}]"
      ) index.variants;
      selected =
        if lib.length maxima == 1 then
          lib.head maxima
        else
          throw (
            "bindContractUser: no unique maximal variant of '${username}' covers the derived "
            + "grant [${lib.concatStringsSep ", " grantNames}]; baked variants are: ${availableList}."
          );
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
    runtimeEligibleFeature
    safeSet
    variantAxes
    variants
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
    mkContractRoster
    mkContractUser
    mkContractUsers
    mkContractHome
    bindContractUser
    ;
}
