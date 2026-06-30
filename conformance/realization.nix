# Conformance domain: the system-side realization — grant/deny, the gui-session union DECISION,
# the privileged-group clamp, the exposed-host ban, the identity.json loader, and the safe-set /
# feature-group projections. The contract's core "manifest + grant ⇒ account" promise.
{
  lib,
  toolkit,
  loadIdentity,
  safeSet,
  featureGroups,
  privilegedGroups,
}:
let
  inherit (toolkit)
    eval
    mkUser
    grant
    failing
    ;
  groupsOf = c: c.users.users.alice.extraGroups;

  # --- grant / deny ---
  granted = eval [
    (mkUser "alice" { })
    (grant "alice" { gui.enable = true; })
  ];
  denied = eval [ (mkUser "alice" { }) ];

  # --- the gui-session union DECISION (the contract's output, not a display backend) ---
  waylandOnly = eval [
    (mkUser "alice" { session = "wayland"; })
    (grant "alice" { gui.enable = true; })
  ];
  x11Only = eval [
    (mkUser "bob" { session = "x11"; })
    (grant "bob" { gui.enable = true; })
  ];
  bothSessions = eval [
    (mkUser "alice" { session = "wayland"; })
    (mkUser "bob" { session = "x11"; })
    (grant "alice" { gui.enable = true; })
    (grant "bob" { gui.enable = true; })
  ];

  # --- the privileged-group clamp ---
  clampNoGrant = eval [
    (mkUser "alice" { })
    {
      custom.users.alice.identity.extraGroups = [
        "docker"
        "audio"
      ];
    }
  ];
  clampWithGrant = eval [
    (mkUser "alice" { })
    (grant "alice" { workstation.enable = true; })
    { custom.users.alice.identity.extraGroups = [ "docker" ]; }
  ];

  # --- the exposed-host ban (signing is the secret-bearing feature) ---
  exposedSecret = eval [
    (mkUser "alice" { })
    (grant "alice" { signing.enable = true; })
    {
      custom.host.exposed = true;
      networking.hostName = "agent";
    }
  ];
  normalSecret = eval [
    (mkUser "alice" { })
    (grant "alice" { signing.enable = true; })
    { networking.hostName = "box"; }
  ];

  # --- the identity.json loader (ADR-0023, issue #5): lossless over identity.nix ---
  # A fixture identity.json written at eval time, carrying the optional fields ADR-0023's
  # first 5-field schema dropped (trustedKeys, extraGroups) — the realization reads both,
  # so the loader must carry both.
  identityFixture = builtins.toFile "identity.json" (
    builtins.toJSON {
      name = "Dana Example";
      email = "dana@example.invalid";
      username = "dana";
      sshKey = "ssh-ed25519 AAAAprimary";
      trustedKeys = [ "ssh-ed25519 AAAAtrusted" ];
      extraGroups = [
        "audio"
        "docker"
      ]; # docker is privileged ⇒ must be clamped even via the loader
    }
  );
  loadedIdentity = loadIdentity identityFixture;
  loadedHost = eval [ { custom.users.dana.identity = loadedIdentity; } ];
  danaKeys = loadedHost.users.users.dana.openssh.authorizedKeys.keys;
  danaGroups = loadedHost.users.users.dana.extraGroups;
in
{
  assertions = [
    {
      # The gui grant's contract effect on the account: it confers the non-privileged
      # input groups (the uinput *device* is a host binding, tested in the host repo).
      name = "grant: gui confers its input groups (uinput) to the account";
      ok = lib.elem "uinput" (groupsOf granted);
    }
    {
      name = "deny: no grant leaves the gui input groups off";
      ok = !(lib.elem "uinput" (groupsOf denied));
    }
    {
      name = "grant: the gui surface decision is enabled";
      ok = granted.custom.gui.surface.enabled;
    }
    {
      name = "deny: the gui surface decision is off";
      ok = !denied.custom.gui.surface.enabled;
    }
    {
      name = "union: a wayland user ⇒ surface offers wayland, not x11";
      ok = waylandOnly.custom.gui.surface.wayland && !waylandOnly.custom.gui.surface.x11;
    }
    {
      name = "union: an x11 user ⇒ surface offers x11, not wayland";
      ok = x11Only.custom.gui.surface.x11 && !x11Only.custom.gui.surface.wayland;
    }
    {
      name = "union: wayland + x11 users ⇒ surface offers both";
      ok = bothSessions.custom.gui.surface.wayland && bothSessions.custom.gui.surface.x11;
    }
    {
      name = "clamp: a privileged group in identity is dropped without a grant";
      ok = !(lib.elem "docker" (groupsOf clampNoGrant));
    }
    {
      name = "clamp: a non-privileged declared group passes through";
      ok = lib.elem "audio" (groupsOf clampNoGrant);
    }
    {
      name = "grant: the workstation grant confers the privileged group";
      ok = lib.elem "docker" (groupsOf clampWithGrant);
    }
    {
      name = "exposed host granting a secret-bearing feature (signing) fails an assertion";
      ok = lib.any (a: lib.hasInfix "signing" a.message) (failing exposedSecret);
    }
    {
      name = "non-exposed host granting the same feature raises no exposed-host failure";
      ok = !(lib.any (a: lib.hasInfix "exposed host" a.message) (failing normalSecret));
    }
    {
      name = "safe set: gui is runtime-eligible";
      ok = lib.elem "gui" safeSet;
    }
    {
      name = "safe set: privileged + secret-bearing features are excluded";
      ok =
        !(lib.elem "workstation" safeSet)
        && !(lib.elem "virtualization" safeSet)
        && !(lib.elem "signing" safeSet);
    }
    {
      name = "gui confers no privileged group";
      ok = !(lib.any (g: lib.elem g privilegedGroups) featureGroups.gui);
    }
    {
      name = "virtualization confers privileged groups (only via its grant)";
      ok = lib.elem "libvirtd" featureGroups.virtualization;
    }
    {
      name = "identity.json: loadIdentity realizes the account (required fields carried)";
      ok =
        loadedHost.users.users.dana.isNormalUser
        && loadedHost.users.users.dana.description == "Dana Example";
    }
    {
      name = "identity.json: sshKey + trustedKeys both reach authorizedKeys (lossless)";
      ok = lib.elem "ssh-ed25519 AAAAprimary" danaKeys && lib.elem "ssh-ed25519 AAAAtrusted" danaKeys;
    }
    {
      name = "identity.json: a non-privileged extraGroup passes, a privileged one is clamped";
      ok = lib.elem "audio" danaGroups && !(lib.elem "docker" danaGroups);
    }

    # --- the nix-daemon feature (ADR-0033, issue #15) ---
    {
      name = "nix-daemon: grant confers nix-users group";
      ok =
        let
          grantedDaemon = eval [
            (mkUser "alice" { })
            (grant "alice" { nix-daemon.enable = true; })
          ];
        in
        lib.elem "nix-users" grantedDaemon.users.users.alice.extraGroups;
    }
    {
      name = "nix-daemon: deny means no nix-users group";
      ok =
        let
          deniedDaemon = eval [ (mkUser "alice" { }) ];
        in
        !(lib.elem "nix-users" deniedDaemon.users.users.alice.extraGroups);
    }
    {
      name = "nix-daemon: nix-users is a privileged group (excluded from safe set)";
      ok = !(lib.elem "nix-daemon" safeSet);
    }
    {
      name = "clamp: nix-users declared in identity.extraGroups is dropped without the nix-daemon grant";
      ok =
        let
          selfDeclared = eval [
            (mkUser "alice" { })
            {
              custom.users.alice.identity.extraGroups = [
                "nix-users"
                "audio"
              ];
            }
          ];
        in
        !(lib.elem "nix-users" selfDeclared.users.users.alice.extraGroups)
        && lib.elem "audio" selfDeclared.users.users.alice.extraGroups;
    }
    {
      name = "nix-users is in privilegedGroups";
      ok = lib.elem "nix-users" privilegedGroups;
    }
  ];
}
