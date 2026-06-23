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
  # A feature is runtime/greeter-eligible iff it bears no secret, confers no privileged
  # group, and carries no host-executed payload (ADR-0018, slice 15).
  runtimeEligibleFeature =
    feature:
    let
      f = registry.${feature} or { };
    in
    !(f.secretBearing or false)
    && (lib.intersectLists (f.groups or [ ]) privilegedGroups == [ ])
    && !(f.execPayload or false);
in
{
  inherit runtimeEligibleFeature;

  safeSet = lib.filter runtimeEligibleFeature (lib.attrNames registry);

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
  # SCOPE — this is the HEADLESS TRACER (issue #5), not yet the full "one mechanism both paths
  # call" of ADR-0024. It harvests by evaluating the home against the contract umbrella ALONE
  # (lib.evalModules, no home-manager — ADR-0020's package-free invariant), so it can only
  # evaluate a CONTRACT-PURE home that sets nothing but contract options. A REAL home module
  # also sets home-manager options (programs.*, home.*), which are undeclared here and would
  # throw. The real bound flow therefore evaluates the home ONCE inside the host's
  # home-manager and reads `contract.requests` from THAT eval (the bridge becomes a config
  # reference, not a separate harvest) — host integration tracked as a follow-up issue. The
  # tracer proves the confined request→grant→bridge logic with zero home-manager dependency;
  # it does not yet harvest real homes.
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
      grantedNames = lib.filter (f: grants.${f}.enable or false) (lib.attrNames grants);
      # Bridge each granted feature's request params into custom.users.<u>.<feature>; the
      # request shape IS the system featureConfig shape (both are featureConfigOptions), so
      # this is a direct copy. Only KNOWN granted features with request data are bridged.
      bridged = lib.foldl' (
        acc: f: if requests ? ${f} then acc // { ${f} = requests.${f}; } else acc
      ) { } grantedNames;
    in
    {
      inherit username home requests;
      # The system module a host merges to realize this user: the realization reads
      # custom.users.<u> for the account, the grants decide its powers, and the bridged
      # request params (e.g. gui.session) feed the gui-session union.
      system = {
        custom.users.${username} = {
          inherit identity;
          granted = grants;
        }
        // bridged;
      };
    };
}
