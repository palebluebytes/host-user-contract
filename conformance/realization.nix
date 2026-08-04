# Conformance domain: the system-side realization — grant/deny, the session-agnostic gui-surface
# DECISION, the privileged-group clamp, the identity.json loader, and the safe-set / feature-group
# projections. The contract's core "manifest + grant ⇒ account" promise.
{
  lib,
  toolkit,
  loadIdentity,
  mkHostFacts,
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

  # --- mkHostFacts: the read-only, self-scoped host projection a home may read (ADR-0002) ---
  # The host builds this per-user for the inline-eval bind path; a home branches on it (e.g.
  # hostFacts.granted.gui.enable) but must never see the hostName. Build a host that HAS a hostName
  # and a grant, then prove the projection carries the grant + platform and NOTHING else — the
  # confinement the home relies on.
  factsHostConfig = eval [
    (mkUser "alice" { })
    (grant "alice" { gui.enable = true; })
    { networking.hostName = "secret-box"; }
  ];
  facts = mkHostFacts factsHostConfig "alice";

  # --- grant / deny ---
  granted = eval [
    (mkUser "alice" { })
    (grant "alice" { gui.enable = true; })
  ];
  denied = eval [ (mkUser "alice" { }) ];

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

  # --- the identity.json loader (ADR-0007, issue #5): lossless over identity.nix ---
  # A fixture identity.json written at eval time, carrying the optional fields ADR-0007's
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

  # --- the sudo feature: the MINIMAL privileged grant (wheel only) ---
  # sudo confers wheel and ONLY wheel — no docker/podman (the contrast that distinguishes it
  # from workstation). Real production accounts ship it (admin/eyeofalligator on weedySeadragon,
  # admin in examples/fleet). Mirror the clamp→grant→restore cycle workstation already has.
  sudoClampNoGrant = eval [
    (mkUser "alice" { })
    { custom.users.alice.identity.extraGroups = [ "wheel" ]; }
  ];
  sudoGranted = eval [
    (mkUser "alice" { })
    (grant "alice" { sudo.enable = true; })
    # self-declare wheel too, so this proves the full clamp→grant→RESTORE cycle in one eval
    # (as workstation's clampWithGrant does), not merely a conferral.
    { custom.users.alice.identity.extraGroups = [ "wheel" ]; }
  ];

  # --- loadIdentity reject paths: the data-side typo-net (cf. requests' malformedRequest) ---
  # loadIdentity loudly asserts on an unknown key and on a missing required field, but conformance
  # only ever calls it on a well-formed fixture. tryEval proves both reject rather than silently
  # producing a wrong account.
  unknownKeyIdentity = builtins.toFile "identity-unknown.json" (
    builtins.toJSON {
      name = "Typo Example";
      email = "typo@example.invalid";
      username = "typo";
      bogusField = "not a real identity field"; # unknown key ⇒ loud reject
    }
  );
  loadUnknownKey = builtins.tryEval (loadIdentity unknownKeyIdentity);
  missingFieldIdentity = builtins.toFile "identity-missing.json" (
    builtins.toJSON {
      name = "No Username";
      email = "nousername@example.invalid";
      # username omitted — a required (no-default) identity field ⇒ loud reject
    }
  );
  loadMissingField = builtins.tryEval (loadIdentity missingFieldIdentity);

  # --- empty sshKey: a real user (eyeofalligator) ships sshKey: "" ---
  # realization guards authorizedKeys with `lib.optional (sshKey != "")`; the identity fixture always
  # sets a non-empty key, so the empty path went unexercised. Prove no "" is injected while trustedKeys
  # still land.
  emptyKeyIdentity = builtins.toFile "identity-emptykey.json" (
    builtins.toJSON {
      name = "Empty Key";
      email = "emptykey@example.invalid";
      username = "emptykey";
      sshKey = "";
      trustedKeys = [ "ssh-ed25519 AAAAtrusted" ];
    }
  );
  emptyKeyHost = eval [ { custom.users.emptykey.identity = loadIdentity emptyKeyIdentity; } ];
  emptyKeys = emptyKeyHost.users.users.emptykey.openssh.authorizedKeys.keys;

  # --- grant ISOLATION between co-resident users (issue #19) ---
  # Every clamp/grant assertion above is single-user (alice alone), so none proves a grant to one
  # account stays off another. Real fleet host weedySeadragon binds THREE users with divergent grant
  # sets on ONE system, and users self-declare wheel in their identity. Model a synthetic co-resident
  # host and prove per-account confinement: a privileged grant confers its groups ONLY to the granted
  # account, and a user self-declaring wheel escalates neither itself nor a neighbour.
  #
  #   alice — gui + workstation + virtualization (docker/podman/wheel + libvirtd); self-declares wheel
  #   bob   — gui only, NO privileged grant; self-declares wheel  → must be clamped
  #   carol — sudo (wheel only), no gui
  isolationHost = eval [
    (mkUser "alice" { })
    (mkUser "bob" { })
    (mkUser "carol" { gui = false; })
    (grant "alice" {
      gui.enable = true;
      workstation.enable = true;
      virtualization.enable = true;
    })
    (grant "bob" { gui.enable = true; })
    (grant "carol" { sudo.enable = true; })
    {
      # two co-residents self-declare wheel: alice (restored by her grant) and bob (no grant ⇒ clamped)
      custom.users.alice.identity.extraGroups = [ "wheel" ];
      custom.users.bob.identity.extraGroups = [ "wheel" ];
    }
  ];
  isoGroups = name: isolationHost.users.users.${name}.extraGroups;
  isoNames = [
    "alice"
    "bob"
    "carol"
  ];
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
      # Session-agnostic: a granted gui user ⇒ the host needs a display surface. The session TYPE
      # (wayland vs x11) is wholly the seat's concern now (ADR-0021) — the contract offers no
      # desktop→type map and no per-type surface flags to assert.
      name = "grant: a granted gui user ⇒ the display surface is enabled";
      ok = granted.custom.gui.surface.enabled;
    }
    {
      name = "deny: no granted gui user ⇒ the display surface is off";
      ok = !denied.custom.gui.surface.enabled;
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

    # --- the sudo feature (issue #18): wheel-only privileged grant ---
    {
      name = "sudo: a self-declared wheel in identity is clamped out without the grant";
      ok = !(lib.elem "wheel" (groupsOf sudoClampNoGrant));
    }
    {
      name = "sudo: the grant restores wheel and confers it ONLY (no docker/podman, unlike workstation)";
      ok =
        lib.elem "wheel" (groupsOf sudoGranted)
        && !(lib.elem "docker" (groupsOf sudoGranted))
        && !(lib.elem "podman" (groupsOf sudoGranted));
    }
    {
      name = "sudo: excluded from safeSet (privileged, build-time-only, never a greeter auto-grant)";
      ok = !(lib.elem "sudo" safeSet);
    }
    # --- grant isolation between co-resident users (issue #19) ---
    {
      name = "isolation: three co-resident users with divergent grants all realize, no failing assertion";
      ok =
        lib.all (n: isolationHost.users.users.${n}.isNormalUser or false) isoNames
        && failing isolationHost == [ ];
    }
    {
      # criterion 2: the granted user receives the feature's privileged groups; the ungranted
      # co-residents do NOT. workstation's docker/podman reach alice alone.
      name = "isolation: workstation's docker/podman reach ONLY the granted account, not its ungranted co-residents";
      ok =
        lib.elem "docker" (isoGroups "alice")
        && lib.elem "podman" (isoGroups "alice")
        && !(lib.any (n: lib.elem "docker" (isoGroups n) || lib.elem "podman" (isoGroups n)) [
          "bob"
          "carol"
        ]);
    }
    {
      name = "isolation: virtualization's libvirtd reaches ONLY alice, the sole granted account";
      ok =
        lib.elem "libvirtd" (isoGroups "alice")
        && !(lib.elem "libvirtd" (isoGroups "bob"))
        && !(lib.elem "libvirtd" (isoGroups "carol"));
    }
    {
      # criterion 3: a user self-declaring wheel escalates neither itself nor a neighbour. bob
      # self-declares wheel with no wheel-conferring grant ⇒ clamped, even though BOTH his
      # co-residents legitimately hold wheel (alice via workstation, carol via sudo). Their grants
      # do not leak to him, and his self-declaration confers nothing on anyone.
      name = "isolation: a self-declared wheel is clamped for the ungranted user, and neighbours' wheel grants do not leak to him";
      ok =
        lib.elem "wheel" (isoGroups "alice") # workstation grant restores her self-declared wheel
        && lib.elem "wheel" (isoGroups "carol") # sudo grant confers wheel
        && !(lib.elem "wheel" (isoGroups "bob")); # gui-only + self-declared wheel ⇒ clamped, no leak in
    }
    {
      # the grant is per-account for NON-privileged groups too: gui's uinput reaches its two
      # gui-granted accounts and not the cli co-resident (carol, granted sudo only).
      name = "isolation: gui's uinput reaches the gui-granted accounts (alice, bob) but not the cli co-resident (carol)";
      ok =
        lib.elem "uinput" (isoGroups "alice")
        && lib.elem "uinput" (isoGroups "bob")
        && !(lib.elem "uinput" (isoGroups "carol"));
    }
    {
      name = "safe set: gui is runtime-eligible";
      ok = lib.elem "gui" safeSet;
    }
    {
      name = "safe set: privileged-group features are excluded";
      ok = !(lib.elem "workstation" safeSet) && !(lib.elem "virtualization" safeSet);
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
    {
      name = "loadIdentity: an identity.json with an unknown key fails to evaluate";
      ok = !loadUnknownKey.success;
    }
    {
      name = "loadIdentity: an identity.json missing a required field (username) fails to evaluate";
      ok = !loadMissingField.success;
    }
    {
      name = "identity.json: an empty sshKey injects no authorizedKeys entry, while trustedKeys still land";
      ok = !(lib.elem "" emptyKeys) && lib.elem "ssh-ed25519 AAAAtrusted" emptyKeys;
    }

    # --- mkHostFacts (ADR-0002): the self-scoped, secret-free host projection ---
    {
      name = "mkHostFacts: exposes EXACTLY the self-scoped projection (exposed/granted/platform) — no hostName, no secret";
      ok =
        lib.sort (a: b: a < b) (lib.attrNames facts) == [
          "exposed"
          "granted"
          "platform"
        ];
    }
    {
      name = "mkHostFacts: carries the user's grants + the platform, never the hostName the host was given";
      ok =
        facts.granted.gui.enable
        && facts.platform == factsHostConfig.nixpkgs.hostPlatform.system
        && !(facts ? hostName);
    }

    # --- the nix-daemon feature (ADR-0017, issue #15) ---
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
    {
      name = "privilegedGroups: kvm is reserved (present in the derived list despite no feature granting it)";
      ok = lib.elem "kvm" privilegedGroups;
    }
  ];
}
