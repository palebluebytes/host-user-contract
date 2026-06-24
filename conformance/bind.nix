# Conformance domain: the two binding shapes (ADR-0023/0024). bindUser is the HEADLESS TRACER
# (issue #5) — harvest a contract-pure home with bare evalModules, no home-manager. bindUserModule
# is the REAL mechanism (issue #8) — the home is evaluated once by the host's home-manager and the
# request→feature bridge is a config reference, so a REAL home (programs.git) binds.
{
  toolkit,
  bindUser,
  bindUserModule,
  greeterGrants,
}:
let
  inherit (toolkit)
    eval
    exampleHome
    exampleIdentity
    exampleHostFacts
    ;

  # --- the headless bindUser tracer (ADR-0023/0024, issue #5) ---
  # Runtime path: the canonical greeter grant — default-open over the safe set (greeterGrants).
  boundRuntime = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = greeterGrants;
    hostFacts = exampleHostFacts;
  };
  # No grants: the same gui.session request must be inert (never bridged).
  boundNone = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = { };
    hostFacts = exampleHostFacts;
  };
  # Realize bindUser's system fragment on a synthetic host ⇒ exercises realization + union.
  boundHost = eval [ boundRuntime.system ];

  # --- the REAL bind: bindUserModule (ADR-0024, issue #8) ---
  # The contract can't depend on home-manager (ADR-0020), so this suite supplies a package-free
  # STAND-IN for the `home-manager.users` option the bind module references: an attrsOf a freeform
  # submodule. That declares the option path so the config reference resolves, and the freeformType
  # makes a home that sets non-contract options (programs.git) evaluate without throwing, the way real
  # home-manager does. (Real home-manager RENDERING is the host's integration test, the same boundary
  # as the gui-union VM vs the gui DECISION proven here.)
  hmStub =
    { lib, ... }:
    {
      options.home-manager.users = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submoduleWith {
            modules = [ { freeformType = lib.types.attrsOf lib.types.anything; } ];
          }
        );
      };
    };
  # A REAL-ish home: it sets a non-contract home-manager option (programs.git, reading the
  # injected identity) AND emits a contract request. The tracer would throw on programs.git;
  # the real bind must not. (Kept inline, NOT in examples/user/home.nix, which stays
  # contract-pure so the tracer can still harvest it — ADR-0024 / issue #5.)
  realHome =
    { config, ... }:
    {
      programs.git.userName = config.identity.name;
      contract.requests.gui.session = "wayland";
    };
  realBound =
    grants:
    eval [
      hmStub
      (bindUserModule {
        userModule = realHome;
        identity = exampleIdentity; # username "example", name "Example User"
        inherit grants;
        hostFacts = exampleHostFacts;
      })
    ];
  realBoundRuntime = realBound greeterGrants;
  realBoundNone = realBound { };
in
{
  assertions = [
    {
      name = "bindUser: the home evaluates and its gui.session request is harvested";
      ok = (boundRuntime.home ? config) && boundRuntime.requests.gui.session == "x11";
    }
    {
      name = "bindUser: the home HOLDS the injected identity (single loader, ADR-0025)";
      ok = boundRuntime.home.config.identity.name == "Example User";
    }
    {
      name = "bindUser: the account materializes from identity.json";
      ok =
        boundHost.users.users.example.isNormalUser
        && boundHost.users.users.example.description == "Example User";
    }
    {
      name = "bindUser: a safe-set grant bridges the gui request, feeding the union (x11)";
      ok = boundHost.custom.gui.surface.enabled && boundHost.custom.gui.surface.x11;
    }
    {
      name = "bindUser: an ungranted request is inert (no system feature config bridged)";
      ok = !(boundNone.system.custom.users.example ? gui);
    }
    {
      # issue #8: a REAL home (programs.git, a non-contract option) binds without throwing —
      # the harvest happens inside home-manager, not the tracer's bare evalModules.
      name = "bindUserModule: a real home-manager home (programs.git) binds and evaluates";
      ok =
        realBoundRuntime.home-manager.users.example.programs.git.userName == "Example User"
        && realBoundRuntime.home-manager.users.example.contract.requests.gui.session == "wayland";
    }
    {
      name = "bindUserModule: the account materializes from identity.json";
      ok =
        realBoundRuntime.users.users.example.isNormalUser
        && realBoundRuntime.users.users.example.description == "Example User";
    }
    {
      # The bridge is a CONFIG REFERENCE into the single home eval — the granted request feeds
      # the union without a second harvest (ADR-0018 data-flow inversion).
      name = "bindUserModule: a granted request bridges by config reference, feeding the union (wayland)";
      ok = realBoundRuntime.custom.gui.surface.enabled && realBoundRuntime.custom.gui.surface.wayland;
    }
    {
      # Post-eval `custom.users.<u>.gui` always exists (it is a declared option), so inertness
      # is proven by the observable effect: ungranted ⇒ the wayland request feeds NO surface.
      name = "bindUserModule: an ungranted request is inert (the union offers no surface)";
      ok = !realBoundNone.custom.gui.surface.enabled;
    }
  ];
}
