# Conformance domain: the traceUser inspector (ADR-0007/0026). traceUser is the home-manager-free
# DRY-RUN — harvest a contract-pure home with bare evalModules and report what the contract resolves
# to, WITHOUT a build. It sits outside the contractUser produce/consume coin; it proves the
# request→grant→bridge kernel at the logic level. Proving that a NON-contract-pure home (one that
# sets home-manager `programs.*`/`home.*`) binds without throwing needs home-manager, which the
# contract cannot depend on (ADR-0004) — so that proof lives in `examples/users`' `home-build`
# check, not in this suite. Here the pre-built path (./contract-package.nix) proves only the
# manifest→bridge kernel, from a static fixture.
{
  toolkit,
  traceUser,
  greeterGrants,
}:
let
  inherit (toolkit)
    eval
    referenceHome
    referenceIdentity
    referenceHostFacts
    ;

  # Runtime path: the canonical greeter grant — default-open over the safe set (greeterGrants).
  boundRuntime = traceUser {
    userModule = referenceHome;
    identity = referenceIdentity;
    grants = greeterGrants;
    hostFacts = referenceHostFacts;
  };
  # No grants: the same gui.desktop request must be inert (never bridged).
  boundNone = traceUser {
    userModule = referenceHome;
    identity = referenceIdentity;
    grants = { };
    hostFacts = referenceHostFacts;
  };
  # Realize traceUser's system fragment on a synthetic host ⇒ exercises realization + the surface.
  boundHost = eval [ boundRuntime.system ];
in
{
  assertions = [
    {
      name = "traceUser: the home evaluates and its gui.desktop request is harvested";
      ok = (boundRuntime.home ? config) && boundRuntime.requests.gui.desktop == "plasma";
    }
    {
      name = "traceUser: the home HOLDS the injected identity (single loader, ADR-0009)";
      ok = boundRuntime.home.config.identity.name == "Ada Reference";
    }
    {
      name = "traceUser: the account materializes from identity.json";
      ok =
        boundHost.users.users.ada.isNormalUser && boundHost.users.users.ada.description == "Ada Reference";
    }
    {
      name = "traceUser: a safe-set grant bridges the gui request, enabling the display surface";
      ok = boundHost.custom.gui.surface.enabled;
    }
    {
      name = "traceUser: an ungranted request is inert (no system feature config bridged)";
      ok = !(boundNone.system.custom.users.ada ? gui);
    }
  ];
}
