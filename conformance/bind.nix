# Conformance domain: the two binding shapes (ADR-0007/0008). bindUser is the HEADLESS TRACER
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

  # --- the headless bindUser tracer (ADR-0007/0008, issue #5) ---
  # Runtime path: the canonical greeter grant — default-open over the safe set (greeterGrants).
  boundRuntime = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = greeterGrants;
    hostFacts = exampleHostFacts;
  };
  # No grants: the same gui.desktop request must be inert (never bridged).
  boundNone = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = { };
    hostFacts = exampleHostFacts;
  };
  # Realize bindUser's system fragment on a synthetic host ⇒ exercises realization + union.
  boundHost = eval [ boundRuntime.system ];

  # --- the REAL bind: bindUserModule (ADR-0008, issue #8) ---
  # The contract can't depend on home-manager (ADR-0004), so this suite supplies a package-free
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
  # the real bind must not. (Kept inline, NOT in the reference user's home.nix, which stays
  # contract-pure so the tracer can still harvest it — ADR-0008 / issue #5.)
  realHome =
    { config, ... }:
    {
      programs.git.userName = config.identity.name;
      contract.requests.gui.desktop = "wayland-de";
    };
  realBound =
    grants:
    eval [
      hmStub
      (bindUserModule {
        userModule = realHome;
        identity = exampleIdentity; # username "ada", name "Ada Reference"
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
      name = "bindUser: the home evaluates and its gui.desktop request is harvested";
      ok = (boundRuntime.home ? config) && boundRuntime.requests.gui.desktop == "plasma";
    }
    {
      name = "bindUser: the home HOLDS the injected identity (single loader, ADR-0009)";
      ok = boundRuntime.home.config.identity.name == "Ada Reference";
    }
    {
      name = "bindUser: the account materializes from identity.json";
      ok =
        boundHost.users.users.ada.isNormalUser && boundHost.users.users.ada.description == "Ada Reference";
    }
    {
      name = "bindUser: a safe-set grant bridges the gui request, enabling the display surface";
      ok = boundHost.custom.gui.surface.enabled;
    }
    {
      name = "bindUser: an ungranted request is inert (no system feature config bridged)";
      ok = !(boundNone.system.custom.users.ada ? gui);
    }
    {
      # issue #8: a REAL home (programs.git, a non-contract option) binds without throwing —
      # the harvest happens inside home-manager, not the tracer's bare evalModules.
      name = "bindUserModule: a real home-manager home (programs.git) binds and evaluates";
      ok =
        realBoundRuntime.home-manager.users.ada.programs.git.userName == "Ada Reference"
        && realBoundRuntime.home-manager.users.ada.contract.requests.gui.desktop == "wayland-de";
    }
    {
      name = "bindUserModule: the account materializes from identity.json";
      ok =
        realBoundRuntime.users.users.ada.isNormalUser
        && realBoundRuntime.users.users.ada.description == "Ada Reference";
    }
    {
      # The bridge is a CONFIG REFERENCE into the single home eval — the granted request enables
      # the surface without a second harvest (ADR-0002 data-flow inversion).
      name = "bindUserModule: a granted request bridges by config reference, enabling the display surface";
      ok = realBoundRuntime.custom.gui.surface.enabled;
    }
    {
      # Post-eval `custom.users.<u>.gui` always exists (it is a declared option), so inertness
      # is proven by the observable effect: ungranted ⇒ the request feeds NO surface.
      name = "bindUserModule: an ungranted request is inert (the union offers no surface)";
      ok = !realBoundNone.custom.gui.surface.enabled;
    }
  ];
}
