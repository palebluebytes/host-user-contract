# Conformance domain: STRUCTURAL confinement (ADR-0002, issue #1 acceptance criterion 2).
#
# The user surface is a home-manager module with NO system channel. Host-affecting effects
# leave the user ONLY as `contract.requests` the host harvests and applies `mkIf granted`
# (proven in ./bind.nix / ./requests.nix). This file proves the OTHER half of that promise —
# the negative space: a system option (`users.users`, `security.sudo`, `boot.*`, `sops.*`) is
# *unexpressible* in the user's world, not merely rejected or `mkIf`-denied downstream.
#
# The proof is that these paths are UNDECLARED in the contract home umbrella (modules.nix's
# `homeModule` declares only `identity`, `custom.home.profiles`, and the fully-typed
# `contract.wants` / `contract.requests` namespaces — no freeformType anywhere since ADR-0028). So a home that
# sets one throws "option does not exist" at eval, exactly as a stray `home.packages` does in
# the headless traceUser inspector. This is the SAME universe traceUser harvests in (../lib.nix),
# so what is unexpressible here is unexpressible in a real bound user. Privilege escalation is
# impossible because the vocabulary to request it does not exist — structural, not a blocklist.
{
  lib,
  toolkit,
}:
let
  inherit (toolkit) evalHome;

  # Does a one-module home evaluate against the contract umbrella? Force a declared attr
  # (`contract.requests.gui.desktop`, always present via its "" default): building `config`
  # runs the module system's unmatched-definition check across ALL definitions, so an
  # UNDECLARED system option makes this throw — caught as `success = false`. A `false` therefore
  # means "this path is unexpressible", never an unrelated eval error.
  evaluates = mod: (builtins.tryEval ((evalHome [ mod ]).contract.requests.gui.desktop)).success;

  # The system options ADR-0002 names as out-of-universe. Each is a real NixOS/sops option a
  # user might reach for to escalate; none exists in the home umbrella, so each is unexpressible.
  outOfUniverse = {
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
    # A privileged group grab via the system account option is likewise unexpressible: the
    # home cannot name `users.users.<u>.extraGroups` at all (grants flow the other way — the
    # host adds groups `mkIf granted`, ADR-0003).
    "users.users.extraGroups" = {
      users.users.example.extraGroups = [ "wheel" ];
    };
  };

  unexpressibleAssertions = lib.mapAttrsToList (path: mod: {
    name = "confinement: `${path}` is unexpressible in the user home (no system channel, ADR-0002)";
    ok = !(evaluates mod);
  }) outOfUniverse;
in
{
  assertions = unexpressibleAssertions ++ [
    {
      # Positive control: confinement is structural, not a broken harness that rejects
      # everything. A legitimate host-affecting request (the user's ONLY channel) evaluates.
      name = "confinement: a legitimate contract.requests still evaluates (the sanctioned channel)";
      ok = evaluates { contract.requests.gui.desktop = "plasma"; };
    }
    {
      # Until ADR-0028 the freeformType inside `contract.requests` ACCEPTED a system-shaped key as
      # an inert (never-bridged) request, so this claim read "inert under contract.requests, fatal
      # at top level". With the freeform gone the namespace is fully typed and the same key throws
      # in BOTH positions. Confinement itself is unchanged (an inert request never reached system
      # state either way); what changed is that the typo-net now covers the request namespace too.
      name = "confinement: `users.users` is unexpressible at top level AND inside contract.requests";
      ok =
        !(evaluates { contract.requests.users.users.root = "inert-request"; })
        && !(evaluates { users.users.root.hashedPassword = "!escalate"; });
    }
  ];
}
