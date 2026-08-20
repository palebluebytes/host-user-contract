# Conformance domain: the system-side realization — the two host dimensions held apart, the gui-surface
# DECISION, the impossibility of self-declared groups, the identity.json loader, and the feature-group
# projections. The contract's core "manifest + grant ⇒ account" promise.
{
  lib,
  toolkit,
  loadIdentity,
  safeSet,
  modes,
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

  # --- the two host dimensions, held apart ---
  # A machine that runs the gui mode, with an account bound in it. Nothing is GRANTED: a graphical
  # session's input groups ride the mode, so this is what an ordinary desktop user's account looks
  # like on a seat — an identity, a session shape, and an empty grant set.
  guiSeat = eval [
    (mkUser "alice" { mode = "gui"; })
    { contract.modes = [ "gui" ]; }
  ];
  # The same machine, an account bound in the floor. The seat still has a display; this account
  # still gets no input groups, because the groups follow the SELECTED mode rather than the box.
  cliOnSeat = eval [
    (mkUser "alice" { })
    { contract.modes = [ "gui" ]; }
  ];
  # A machine that declares nothing. No display surface, whatever its accounts hold.
  headless = eval [
    (mkUser "alice" { })
    (grant "alice" { containers = true; })
  ];

  # --- an identity cannot name a group at all ---
  # The strongest form of the old privileged-group clamp: rather than FILTERING what a user wrote
  # into their own public record, the vocabulary to write it does not exist. That is the same
  # structural argument confinement makes about `users.users` — escalation is impossible because
  # there is nothing to say it with, not because something is checked.
  #
  # It matters most on the greeter path, where `identity.json` arrives from a stranger. The old
  # deny-list caught eight privileged names and passed everything else, so a walk-up user could put
  # themselves in `networkmanager` by editing their own file.
  # Forced SHALLOWLY, at the one attribute the definition would land in: `users.users` holds
  # derivations, and `deepSeq` over one never terminates. Reading a plain list is enough — the
  # module system runs its unmatched-definition check to produce it.
  selfDeclaredGroups = builtins.tryEval (
    groupsOf (eval [
      (mkUser "alice" { })
      { contract.users.alice.identity.extraGroups = [ "audio" ]; }
    ])
  );
  # …and the same through the LOADER, which is how an identity actually arrives: `loadIdentity`
  # rejects an unknown key loudly, so a stale `identity.json` carrying the field is a named error
  # in the user's own repo rather than a field silently ignored.
  loadedWithGroups = builtins.tryEval (
    loadIdentity (
      builtins.toFile "identity-with-groups.json" (
        builtins.toJSON {
          name = "Stale Example";
          email = "stale@example.invalid";
          username = "stale";
          extraGroups = [ "networkmanager" ];
        }
      )
    )
  );

  # --- the identity.json loader: lossless over identity.nix ---
  # A fixture identity.json written at eval time, carrying every optional field the schema knows,
  # so the loader is proven to carry all of them rather than only the required three.
  identityFixture = builtins.toFile "identity.json" (
    builtins.toJSON {
      name = "Dana Example";
      email = "dana@example.invalid";
      username = "dana";
      sshKey = "ssh-ed25519 AAAAprimary";
      trustedKeys = [ "ssh-ed25519 AAAAtrusted" ];
    }
  );
  loadedIdentity = loadIdentity identityFixture;
  loadedHost = eval [ { contract.users.dana.identity = loadedIdentity; } ];
  danaKeys = loadedHost.users.users.dana.openssh.authorizedKeys.keys;
  danaGroups = loadedHost.users.users.dana.extraGroups;

  # --- the sudo feature: the MINIMAL privileged grant (wheel only) ---
  # sudo confers wheel and ONLY wheel — no docker/podman (those are the separate `containers`
  # grant). Real production accounts ship it (admin/eyeofalligator on weedySeadragon, admin in
  # examples/fleet). Mirror the clamp→grant→restore cycle `containers` also has.
  sudoUngranted = eval [ (mkUser "alice" { }) ];
  sudoGranted = eval [
    (mkUser "alice" { })
    (grant "alice" { sudo = true; })
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
  emptyKeyHost = eval [ { contract.users.emptykey.identity = loadIdentity emptyKeyIdentity; } ];
  emptyKeys = emptyKeyHost.users.users.emptykey.openssh.authorizedKeys.keys;

  # --- grant ISOLATION between co-resident users (issue #19) ---
  # Every clamp/grant assertion above is single-user (alice alone), so none proves a grant to one
  # account stays off another. Real fleet host weedySeadragon binds THREE users with divergent grant
  # sets on ONE system. Model a synthetic co-resident host and prove per-account confinement: a
  # privileged grant confers its groups ONLY to the granted account, and a neighbour's grant reaches
  # nobody else.
  #
  #   alice — gui MODE + containers + sudo + virtualization (docker/podman + wheel + libvirtd)
  #   bob   — gui MODE, NO privileged grant at all
  #   carol — the floor, sudo (wheel only)
  isolationHost = eval [
    { contract.modes = [ "gui" ]; }
    (mkUser "alice" { mode = "gui"; })
    (mkUser "bob" { mode = "gui"; })
    (mkUser "carol" { })
    (grant "alice" {
      containers = true;
      sudo = true;
      virtualization = true;
    })
    (grant "carol" { sudo = true; })
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
      # A graphical session's input groups ride the MODE, and reach an account with an entirely
      # EMPTY grant set. This is the claim the split exists for: needing input devices is a
      # property of running a graphical session, not a power somebody decided this person deserves.
      name = "mode groups: a gui-mode account gets uinput with NOTHING granted";
      ok =
        lib.elem "uinput" (groupsOf guiSeat)
        && lib.all (v: !v) (lib.attrValues guiSeat.contract.users.alice.granted);
    }
    {
      # …and its control, on the SAME machine: an account bound in the floor gets none of them. The
      # groups follow the account's session shape, never the box's capability.
      name = "mode groups: a cli-mode account on the SAME gui machine gets none of them";
      ok = !(lib.elem "uinput" (groupsOf cliOnSeat));
    }
    {
      # The display surface follows the MACHINE's declaration, not its accounts. A seat has one
      # before any user is bound — which is exactly what a greeter needs, since the surface must
      # exist before the first walk-up user does. Session-agnostic: which session type a desktop
      # runs is wholly the seat's concern, so there is no per-type flag to assert.
      name = "display: a machine declaring the gui mode has a display surface";
      ok = guiSeat.contract.display.enabled && cliOnSeat.contract.display.enabled;
    }
    {
      name = "display: a machine declaring no mode has none, whatever its accounts hold";
      ok = !headless.contract.display.enabled && headless.contract.users.alice.granted.containers;
    }
    {
      # An identity cannot name a group AT ALL — not even a harmless one. Escalation is impossible
      # because the vocabulary does not exist, which is a structural claim rather than a filter.
      name = "identity: a group cannot be named in an identity — the option does not exist";
      ok = !selfDeclaredGroups.success;
    }
    {
      # …and through the LOADER, which is how one actually arrives. A stale identity.json carrying
      # the retired field is a loud error in the user's own repo, not a silently ignored key — and
      # `networkmanager` is the name that used to pass the deny-list untouched.
      name = "identity: an identity.json still carrying `extraGroups` is refused by the loader";
      ok = !loadedWithGroups.success;
    }

    {
      name = "grant: the containers grant confers the privileged group";
      ok = lib.elem "docker" (groupsOf headless);
    }

    # --- the sudo feature (issue #18): wheel-only privileged grant ---
    {
      name = "sudo: an ungranted account gets no wheel";
      ok = !(lib.elem "wheel" (groupsOf sudoUngranted));
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
      name = "isolation: a neighbour's wheel grant reaches nobody else";
      ok =
        lib.elem "wheel" (isoGroups "alice") # her own sudo grant
        && lib.elem "wheel" (isoGroups "carol") # her own sudo grant
        && !(lib.elem "wheel" (isoGroups "bob")); # granted nothing ⇒ nothing, no leak in
    }
    {
      # Per-account for the MODE's groups too: gui's uinput reaches the two accounts bound in the
      # gui mode and not the floor co-resident, on one machine that runs both.
      name = "isolation: the gui mode's uinput reaches its two accounts (alice, bob) but not the floor co-resident (carol)";
      ok =
        lib.elem "uinput" (isoGroups "alice")
        && lib.elem "uinput" (isoGroups "bob")
        && !(lib.elem "uinput" (isoGroups "carol"));
    }
    {
      # The predicate is real, and this is the non-vacuous half: every feature in the registry is
      # excluded, one by one, because every one of them carries privileged groups.
      name = "safe set: privileged-group features are excluded";
      ok = lib.all (f: !(lib.elem f safeSet)) [
        "containers"
        "sudo"
        "virtualization"
        "nix-daemon"
      ];
    }
    {
      # THE TRIPWIRE. The safe set is what a greeter confers on a stranger, and it is currently
      # EMPTY — every feature left in the registry is a power somebody has to decide about. This
      # claim is deliberately brittle: it fails the day a non-privileged feature is added, which is
      # exactly when a human should be asked whether somebody who just typed a URL at a login
      # prompt ought to receive it. Do not "fix" it by loosening the assertion.
      name = "safe set: it is EMPTY — a greeter confers no feature at all (tripwire)";
      ok = safeSet == [ ];
    }
    {
      # A MODE's groups are non-privileged by construction — a mode is a capability of the machine,
      # never a power over it — so a privileged group in `modes.nix` would be an escalation route
      # around the clamp. It is clamped anyway (accountPlan runs mode groups through the same
      # filter as self-declared ones), but the registry should never rely on that.
      name = "mode groups: no mode confers a privileged group";
      ok = lib.all (m: !(lib.any (g: lib.elem g privilegedGroups) (m.groups or [ ]))) (
        lib.attrValues modes
      );
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
      # An identity that came off disk still yields an account with no groups of its own: the
      # loader is lossless over the schema, and the schema has nothing about groups in it.
      name = "identity.json: a loaded identity confers no groups on its own";
      ok = danaGroups == [ ];
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
            (grant "alice" { nix-daemon = true; })
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
      name = "nix-users is in privilegedGroups";
      ok = lib.elem "nix-users" privilegedGroups;
    }
    {
      name = "privilegedGroups: kvm is reserved (present in the derived list despite no feature granting it)";
      ok = lib.elem "kvm" privilegedGroups;
    }
  ];
}
