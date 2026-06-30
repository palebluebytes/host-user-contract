# The contract's derivation logic — pure functions over the registry and its
# projections, split out of kit.nix (thermo-nuclear review). `runtimeEligibleFeature`
# and `exposedHostOffenders` are internal (the kit's `safeSet` and the umbrella's
# exposed-host assertion close over them); `mkFeatureRecipients` / `mkHostFacts` are the
# public functions hosts consume (ADR-0020 Q4); `safeSet` is the derived value.
{
  lib,
  registry,
  privilegedGroups,
  featureMeta,
}:
let
  # A feature is runtime/greeter-eligible iff it bears no secret and confers no
  # privileged group (ADR-0018, slice 15). The exec-payload clause is deferred —
  # no feature uses it yet; it will be re-introduced alongside the first feature
  # that carries a host-executed user payload (ADR-0032).
  runtimeEligibleFeature =
    feature:
    let
      f = registry.${feature} or { };
    in
    !(f.secretBearing or false) && (lib.intersectLists (f.groups or [ ]) privilegedGroups == [ ]);

  # The runtime-eligible feature names — the safe set (ADR-0018, slice 15).
  safeSet = lib.filter runtimeEligibleFeature (lib.attrNames registry);

  # The request→feature-configuration bridge, shared by BOTH binding shapes (the headless
  # tracer below and the real `bindUserModule`). Given a user's harvested `contract.requests`
  # and the set of features the host GRANTED, copy each granted feature's request params into
  # the system-side feature-configuration shape the realization consumes (ADR-0019) — the two
  # shapes are identical (both are featureConfigOptions), so it is a direct copy. Only KNOWN
  # granted features with request data are bridged; an ungranted request is never copied, so
  # requesting an ungranted feature is a silent no-op (ADR-0018: "the grant is the sole
  # enabler; degradation is silent"). `requests` is a value in the tracer and a CONFIG
  # REFERENCE in the module — the fold is identical either way.
  grantedNamesOf = grants: lib.filter (f: grants.${f}.enable or false) (lib.attrNames grants);
  bridgeRequests =
    requests: grantedNames:
    lib.foldl' (
      acc: f: if requests ? ${f} then acc // { ${f} = requests.${f}; } else acc
    ) { } grantedNames;

  # The system account fragment a bind PRODUCES, given the user's identity, the host's grants,
  # and the user's harvested `contract.requests`: the account the realization materializes, the
  # grants that power it, and the granted requests bridged into feature configuration. BOTH
  # bind shapes emit exactly this — the tracer nested under `system`, the module at top level —
  # so they share their whole output shape, not just the bridge step, and differ only in where
  # `requests` come from (a harvest value vs a config reference) and what wrapper they return.
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
in
{
  inherit runtimeEligibleFeature safeSet;

  # The runtime/greeter grant (ADR-0022, ADR-0024): "default-open over the safe set". The
  # greeter does not let an operator choose features — it auto-grants every runtime-eligible
  # one, and privilege is impossible because the safe set EXCLUDES secret-bearing and
  # privileged-group features by construction. This is the canonical, conformance-checked grant
  # value the greeter binds with (`bindUserModule { grants = greeterGrants; … }`); single-sourcing
  # it here is exactly ADR-0024's conformance condition (3): a greeter grants AT MOST the safe
  # set. `grants` is shaped `{ <feature>.enable = bool; }` (the registry's grantedOptions), so
  # this lifts the safe-set NAME LIST into that grant attrset.
  greeterGrants = lib.genAttrs safeSet (_: {
    enable = true;
  });

  # The Tier-1 restricted-eval posture (ADR-0030): the canonical Nix settings under which the
  # greeter EVALUATES and BUILDS a host-signed (semi-trusted) user home (step 5/6). Tier 1 is
  # vouched-for by the host's signature (ADR-0027), not blindly trusted — the build still runs
  # under a restricted eval to contain accidents and, crucially, to keep the repo from WIDENING
  # its own eval posture (ADR-0027 applied to eval: a repo cannot self-certify). As nix.conf:
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

  # Recipients-from-grants (ADR-0015, slice 06): for each secret-bearing feature's sops
  # file, the set of hosts that GRANT it — the single source of truth for .sops.yaml
  # recipients. Applied to a fleet's nixosConfigurations by the host (it reads the fleet).
  mkFeatureRecipients =
    nixosConfigurations:
    let
      secretFeatures = lib.filter (f: featureMeta.${f}.secretBearing or false) (
        lib.attrNames featureMeta
      );
      hostNames = lib.attrNames nixosConfigurations;
      hostGrants =
        host: feature:
        lib.any (u: u.granted.${feature}.enable or false) (
          lib.attrValues nixosConfigurations.${host}.config.custom.users
        );
    in
    lib.foldl' (
      acc: feature:
      let
        hosts = lib.filter (h: hostGrants h feature) hostNames;
      in
      lib.foldl' (a: file: a // { ${file} = lib.unique ((a.${file} or [ ]) ++ hosts); }) acc (
        featureMeta.${feature}.secretFiles or [ ]
      )
    ) { } secretFeatures;

  # The secret-bearing features an exposed host has been (wrongly) granted — the
  # exposed-host ban (ADR-0015 threat model). Must be empty.
  exposedHostOffenders =
    config:
    lib.concatMap (
      uname:
      let
        granted = config.custom.users.${uname}.granted;
      in
      lib.filter (
        fname: (granted.${fname}.enable or false) && (featureMeta.${fname}.secretBearing or false)
      ) (lib.attrNames featureMeta)
    ) (lib.attrNames config.custom.users);

  # The restricted projection of host state a user's home modules may read (ADR-0018,
  # slice 12): self-scoped, no hostName, no secret value.
  mkHostFacts = config: userName: {
    exposed = config.custom.host.exposed;
    platform = config.nixpkgs.hostPlatform.system;
    granted = config.custom.users.${userName}.granted;
  };

  # bindUser (ADR-0023, ADR-0024): binds an external user's home module to the contract —
  # it harvests the user's `contract.requests`, then returns the system fragment that realizes
  # the account (identity), records the grants, and BRIDGES the GRANTED requests to the
  # system-side feature configuration the realization consumes (ADR-0019). Ungranted requests
  # are inert — never bridged — so requesting an ungranted feature is a silent no-op, not an
  # error (ADR-0018: "the grant is the sole enabler; degradation is silent"). `homeModule` is
  # the contract's homeModules.default, partially applied by the kit so a caller passes only
  # the user side.
  #
  # SCOPE — this is the HEADLESS TRACER (issue #5): the package-PUREST proof of the confined
  # request→grant→bridge logic. It harvests by evaluating the home against the contract
  # umbrella ALONE (lib.evalModules, no home-manager, not even a stub — ADR-0020's package-free
  # invariant), so it can only evaluate a CONTRACT-PURE home that sets nothing but contract
  # options. A REAL home module also sets home-manager options (programs.*, home.*), which are
  # undeclared here and would throw. `bindUserModule` below is the REAL binding mechanism both
  # paths (operator-grant + greeter) call — it evaluates the home once inside the host's
  # home-manager and bridges by config reference, so real homes bind (issue #8). The tracer
  # remains the logic-level proof: same bridge (`bridgeRequests`), zero home-manager dependency.
  bindUser =
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
      # Evaluate the user's home against the contract home umbrella. bindUser is the SINGLE
      # reader of the loaded identity (ADR-0025): it injects the same value into the home it
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
      # bridged request params that feed the gui-session union) — see `mkUserAccount`.
      system.custom.users.${username} = mkUserAccount { inherit identity grants requests; };
    };

  # bindUserModule (ADR-0024, issue #8): the REAL binding mechanism, called by BOTH paths an
  # operator build-time grant and a runtime greeter (ADR-0022). Unlike the tracer, it harvests
  # nothing itself — it returns a NixOS MODULE the host imports, and the home is evaluated ONCE
  # by the host's home-manager. The bridge is then a CONFIG REFERENCE
  # (config.home-manager.users.<u>.contract.requests), not a second eval, so the data flows the
  # right way (ADR-0018: the system reads the home eval) and a REAL home that sets home-manager
  # options (programs.git, home.packages) binds — those options are declared by the host's
  # home-manager, the very thing the tracer's bare evalModules lacks.
  #
  # PACKAGE-FREE (ADR-0020): this module only *references* `home-manager.*` option paths; it
  # does NOT import home-manager. The HOST supplies home-manager (it already does to build
  # homes) — so the contract keeps depending on nixpkgs `lib` alone. Identity is the single
  # loaded value injected into both the account and the home (ADR-0025), exactly as the tracer;
  # `hostFacts` is injected per-user via the home submodule's `_module.args` (home-manager's
  # `extraSpecialArgs` is global, so the read-only, per-user host projection rides the submodule
  # instead). `pkgs` needs no injection here — home-manager provides it to the home natively.
  bindUserModule =
    {
      homeModule,
      userModule,
      identity,
      grants ? { },
      hostFacts ? { },
    }:
    { config, ... }:
    let
      username = identity.username;
    in
    {
      # The system account (identity + grants + bridged requests, see `mkUserAccount`). The
      # requests are read by CONFIG REFERENCE from the single home eval — no second harvest.
      custom.users.${username} = mkUserAccount {
        inherit identity grants;
        requests = config.home-manager.users.${username}.contract.requests;
      };
      # The home, evaluated once by the host's home-manager. identity is injected (ADR-0025);
      # hostFacts rides the submodule's module args so the home reads its self-scoped, read-only
      # host projection (ADR-0018) without a global specialArg.
      home-manager.users.${username} = {
        imports = [
          homeModule
          { inherit identity; }
          userModule
        ];
        _module.args.hostFacts = hostFacts;
      };
    };
}
