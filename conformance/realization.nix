# Conformance domain: the system-side realization — grant/deny, the session-agnostic gui-surface
# DECISION, the privileged-group clamp, the identity.json loader, and the safe-set / feature-group
# projections. The contract's core "manifest + grant ⇒ account" promise.
{
  lib,
  toolkit,
  loadIdentity,
  safeSet,
  variantAxes,
  variants,
  hostFactsFor,
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
    (grant "alice" { containers.enable = true; })
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
  # sudo confers wheel and ONLY wheel — no docker/podman (those are the separate `containers`
  # grant). Real production accounts ship it (admin/eyeofalligator on weedySeadragon, admin in
  # examples/fleet). Mirror the clamp→grant→restore cycle `containers` also has.
  sudoClampNoGrant = eval [
    (mkUser "alice" { })
    { custom.users.alice.identity.extraGroups = [ "wheel" ]; }
  ];
  sudoGranted = eval [
    (mkUser "alice" { })
    (grant "alice" { sudo.enable = true; })
    # self-declare wheel too, so this proves the full clamp→grant→RESTORE cycle in one eval
    # (as the containers grant's clampWithGrant does), not merely a conferral.
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
  #   alice — gui + containers + sudo + virtualization (docker/podman + wheel + libvirtd); self-declares wheel
  #   bob   — gui only, NO privileged grant; self-declares wheel  → must be clamped
  #   carol — sudo (wheel only), no gui
  isolationHost = eval [
    (mkUser "alice" { })
    (mkUser "bob" { })
    (mkUser "carol" { gui = false; })
    (grant "alice" {
      gui.enable = true;
      containers.enable = true;
      sudo.enable = true;
      virtualization.enable = true;
    })
    (grant "bob" { gui.enable = true; })
    (grant "carol" { sudo.enable = true; })
    {
      # two co-residents self-declare wheel: alice (restored by her sudo grant) and bob (no grant ⇒ clamped)
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

  # --- the home-affecting feature set (ADR-0028) ---
  # The public data surface a PRODUCER narrows `hostFacts.granted` with (and derives its baked
  # variant set from). There is no host config at bake time, so the facts literal is built on the
  # producer side — but the FOLD itself is the contract's rule, shipped as `hostFactsFor` and
  # applied by `mkContractHome` on every producer home. What is pinned here is the surface and the
  # RESULT that fold must yield on a maximal grant: a home may only SEE the home-affecting
  # features, so one reading `granted.sudo` structurally gets false forever and cannot become
  # grant-sensitive on a feature nothing bakes for.
  everyFeature = [
    "gui"
    "containers"
    "sudo"
    "virtualization"
    "nix-daemon"
  ];
  fullGrant = lib.genAttrs everyFeature (_: {
    enable = true;
  });
  # Driven through the SHIPPED projection rather than a re-typed `filterAttrs`: this used to
  # restate the producer's idiom, which meant the suite proved its own copy and would have gone
  # on passing if `hostFactsFor` drifted from it.
  narrowedFacts =
    (hostFactsFor {
      granted = fullGrant;
      platform = "x86_64-linux";
    }).granted;
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
      name = "grant: the containers grant confers the privileged group";
      ok = lib.elem "docker" (groupsOf clampWithGrant);
    }

    # --- the sudo feature (issue #18): wheel-only privileged grant ---
    {
      name = "sudo: a self-declared wheel in identity is clamped out without the grant";
      ok = !(lib.elem "wheel" (groupsOf sudoClampNoGrant));
    }
    {
      name = "sudo: the grant restores wheel and confers it ONLY (no docker/podman — those are the containers grant)";
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
      # co-residents do NOT. the containers grant's docker/podman reach alice alone.
      name = "isolation: the containers grant's docker/podman reach ONLY the granted account, not its ungranted co-residents";
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
      # co-residents legitimately hold wheel (alice and carol via sudo). Their grants do not leak
      # to him, and his self-declaration confers nothing on anyone.
      name = "isolation: a self-declared wheel is clamped for the ungranted user, and neighbours' wheel grants do not leak to him";
      ok =
        lib.elem "wheel" (isoGroups "alice") # sudo grant restores her self-declared wheel
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
      ok = lib.all (f: !(lib.elem f safeSet)) [
        "containers"
        "sudo"
        "virtualization"
        "nix-daemon"
      ];
    }
    # --- the variant axes and the producer projection over them (ADR-0028) ---
    {
      # gui is the only feature with a home channel today: it carries request params the home
      # emits, so a home can legitimately fan out on the gui grant.
      name = "variantAxes: gui cannot be applied to an already-built home, so it is an axis";
      ok = variantAxes == [ "gui" ];
    }
    {
      # The pure privileged-group grants confer host-side powers and touch no home content, so
      # they ride the BIND and never multiply a producer's variants.
      name = "variantAxes: pure privileged-group grants need no build of their own (they ride the bind)";
      ok = lib.all (f: !(lib.elem f variantAxes)) [
        "containers"
        "sudo"
        "virtualization"
        "nix-daemon"
      ];
    }
    {
      # `variants` is what a producer bakes from, so its SHAPE is load-bearing: one entry per
      # subset of the axes. Asserted generically (2^n entries, unique labels, exactly one
      # grant-less `base`) so a second axis is covered the day it lands, with no new case here.
      name = "variants: one labelled entry per combination of the axes";
      ok =
        let
          expected = lib.foldl' (acc: _: acc * 2) 1 variantAxes;
          labels = map (v: v.label) variants;
          empties = lib.filter (v: v.grants == { }) variants;
        in
        lib.length variants == expected
        && lib.length (lib.unique labels) == expected
        && lib.length empties == 1
        && (lib.head empties).label == "base";
    }
    {
      # Nothing that rides the bind may appear as a baked grant: a variant keyed on a bind-riding
      # feature would multiply every user's bake for a grant the home cannot even see.
      name = "variants: every baked grant is a variant axis";
      ok = lib.all (v: lib.all (f: lib.elem f variantAxes) (lib.attrNames v.grants)) variants;
    }
    {
      # The narrowing a producer performs with this surface: a home may see only what something
      # bakes for. `granted.sudo` is then structurally absent ⇒ `or false` forever.
      name = "hostFactsFor: the shipped projection drops every bind-riding grant";
      ok =
        narrowedFacts.gui.enable
        && !(narrowedFacts.sudo.enable or false)
        && lib.attrNames narrowedFacts == variantAxes;
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
      name = "containers confers BOTH docker and podman (its atomic privileged groups, only via its grant)";
      ok = lib.elem "docker" featureGroups.containers && lib.elem "podman" featureGroups.containers;
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
