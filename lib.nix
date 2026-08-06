# The contract's derivation logic — pure functions over the registry and its projections.
# The public producer/consumer coin is `mkContractUser`/`mkContractUsers` (bake a user, or a
# whole roster, into contractPackages + the binding index) and `bindContractUser` (a host
# binds one indexed user, grant = affordances ∩ offer); `traceUser` is the home-manager-free
# dry-run inspector. `mkContractPackageForHome`/`mkContractPackage`/`bindContractPackage` are
# the INTERNAL kernels those speak through (package-level, one rung below the user-level public
# surface), as is `mkHostFacts` (no host-side inline eval consumes it post-ADR-0026) and
# `runtimeEligibleFeature` (the kit's `safeSet` closes over it). `renderNixConfig` is the one
# public greeter helper here; `safeSet` is the derived value.
{
  lib,
  registry,
  manifest,
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

  # The request→feature-configuration bridge, shared by BOTH binding shapes (the headless
  # tracer below and the real `bindContractPackage`). Given a user's harvested `contract.requests`
  # and the set of features the host GRANTED, copy each granted feature's request params into
  # the system-side feature-configuration shape the realization consumes (ADR-0003) — the two
  # shapes are identical (both are featureConfigOptions), so it is a direct copy. Only KNOWN
  # granted features with request data are bridged; an ungranted request is never copied, so
  # requesting an ungranted feature is a silent no-op (ADR-0002: "the grant is the sole
  # enabler; degradation is silent"). `requests` is a value in the tracer and a CONFIG
  # REFERENCE in the module — the fold is identical either way.
  grantedNamesOf = grants: lib.filter (f: grants.${f}.enable or false) (lib.attrNames grants);
  # List subset test — `a ⊆ b`. Single-sourced so the coupling guard and the turnkey
  # variant-selection (covering + maximal) all spell "is this grant-key covered?" one way.
  subsetOf = a: b: lib.all (x: lib.elem x b) a;
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
        # The enabled feature names the home was baked with (ADR-0016 coupling guard).
        granted = grantedNamesOf grants;
      };
    in
    pkgs.runCommand "contract-package-${username}" { } ''
      mkdir -p $out
      cp ${activationPackage}/activate $out/activate
      chmod +x $out/activate
      cp ${manifestFile} $out/${manifest.manifestFileName}
    '';

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
  mkContractPackageForHome =
    {
      home,
      pkgs,
      grants ? { },
    }:
    mkContractPackage {
      inherit pkgs grants;
      activationPackage = home.activationPackage;
      requests = home.config.contract.requests;
      packages = home.config.home.packages;
      username = home.config.home.username;
    };

  # variantName (ADR-0025, issue #25): the canonical, ORDER-INDEPENDENT label for a baked
  # variant — the sorted home-affecting grant-key feature names, empty ⇒ `base`. It names the
  # published package (`<user>-contractPackage-<name>`) only; selection reads the machine-readable
  # grant-key off the binding index, never this string, so the format is cosmetic — a label, not a
  # parse target (ADR-0025 "Considered Options": name-parse selection rejected).
  variantName =
    granted:
    let
      names = lib.sort (a: b: a < b) (grantedNamesOf granted);
    in
    if names == [ ] then "base" else lib.concatStringsSep "-" names;

  # mkContractUser (ADR-0025, issue #25): the SINGULAR turnkey PRODUCER — the producer twin of the
  # consumer's `bindContractUser` (make one contract-user ⇄ bind one contract-user). A single-user
  # repo calls it once; `mkContractUsers` (below) is nothing but this mapped over a roster. It bakes
  # ONE user's declared variants and emits the same flake-output shape a host consumes — ready to
  # `inherit … packages contractUsers`:
  #   - the named packages `<user>-contractPackage-<variantName>` (built via mkContractPackageForHome
  #     — so this stays package-free, only READING attributes off an already-evaluated home, ADR-0004), and
  #   - the pure `contractUsers.<sys>.<user>` BINDING INDEX entry `{ identity; offer; variants = [{
  #     granted; package }] }`. The index is plain data (identity resolved once via loadIdentity from
  #     the ADR-0020 `<usersDir>/<user>/identity.json` path; `granted` is the variant's grant-key as a
  #     NAME LIST; `package` is the built derivation), so a host's `bindContractUser` selects a variant
  #     by reading it — never by building every variant to inspect a baked manifest (the ADR-0016
  #     "can't read manifests cheaply" trap, sidestepped).
  # `variants` is `[{ grants; home }]` — `grants` is the grant ATTRSET the variant is baked with (same
  # `{ <feature>.enable = bool; }` shape as everywhere else, and what `mkContractPackageForHome`
  # consumes); it is projected to the index's `granted` NAME LIST by `grantedNamesOf`. `loadIdentity`
  # is injected by the kit (like `homeModule` for `traceUser`) so the users flake calls this without
  # wiring the loader itself. `pkgs`/`system` stay parameters so one call can emit multi-arch outputs.
  mkContractUser =
    {
      loadIdentity,
      pkgs,
      system,
      usersDir,
      name,
      offer ? { },
      variants,
    }:
    let
      built = map (v: {
        granted = grantedNamesOf v.grants;
        package = mkContractPackageForHome {
          inherit pkgs;
          home = v.home;
          grants = v.grants;
        };
        label = variantName v.grants;
      }) variants;
    in
    {
      packages.${system} = lib.listToAttrs (
        map (v: lib.nameValuePair "${name}-contractPackage-${v.label}" v.package) built
      );
      contractUsers.${system}.${name} = {
        identity = loadIdentity "${usersDir}/${name}/identity.json";
        inherit offer;
        variants = map (v: { inherit (v) granted package; }) built;
      };
    };

  # mkContractUsers (ADR-0025, issue #25): the ROSTER convenience — `mkContractUser` mapped over a
  # whole multi-user repo and its outputs merged, so a `users` flake bakes its entire roster in ONE
  # call and `inherit … packages contractUsers`. It is the turnkey producer for the multi-user shape
  # (ADR-0020) exactly as `bindContractUser` is the turnkey consumer; the singular `mkContractUser`
  # is the true per-user partner underneath. Each input user is `{ offer; variants }`, forwarded to
  # `mkContractUser`. Adds no logic of its own beyond the roster fold — the per-user bake, naming,
  # and index shape all live in `mkContractUser`.
  mkContractUsers =
    {
      loadIdentity,
      pkgs,
      system,
      usersDir,
      users,
    }:
    let
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
          inherit (u) offer variants;
        }
      ) users;
    in
    {
      packages.${system} = lib.foldl' (acc: o: acc // o.packages.${system}) { } outs;
      contractUsers.${system} = lib.foldl' (acc: o: acc // o.contractUsers.${system}) { } outs;
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
  inherit runtimeEligibleFeature safeSet;

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

  # The restricted projection of host state a user's home modules may read (ADR-0002,
  # slice 12): self-scoped, no hostName. `exposed` is a plain host fact a home may adapt to;
  # the contract enforces nothing on it (it carries no secret-bearing features).
  mkHostFacts = config: userName: {
    exposed = config.custom.host.exposed;
    platform = config.nixpkgs.hostPlatform.system;
    granted = config.custom.users.${userName}.granted;
  };

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
  traceUser =
    {
      homeModule,
      userModule,
      identity,
      grants ? { },
      hostFacts ? { },
      pkgs ? null,
    }:
    let
      username = identity.username;
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
        ];
        specialArgs = { inherit hostFacts pkgs lib; };
      };
      requests = home.config.contract.requests;
    in
    {
      inherit username home requests;
      # The system module a host merges to realize this user (the account, its powers, and the
      # bridged request params that feed the display surface) — see `mkUserAccount`.
      system.custom.users.${username} = mkUserAccount { inherit identity grants requests; };
    };

  inherit
    mkContractPackage
    mkContractPackageForHome
    bindContractPackage
    mkContractUser
    mkContractUsers
    bindContractUser
    ;
}
