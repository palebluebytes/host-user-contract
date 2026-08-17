# Conformance domain: the turnkey host-side bind (ADR-0025, issue #25) — `contract.affordances`,
# `bindContractUser`, the `mkContractUser`/`mkContractUsers` producer coin, the coupling guard, and
# the gui XDG fold. All synthetic:
# no host repo, no home-manager. A binding index is fabricated as PLAIN DATA (bake packages are
# the repo-path fixture `bindContractPackage` already uses, so selection reads the index with NO
# derivation build — the no-IFD property is structural, not asserted by side effect).
{
  lib,
  toolkit,
  loadIdentity,
  bindContractUser,
  mkContractUser,
  mkContractUsers,
  pkgs,
  system,
}:
let
  inherit (toolkit) eval;

  # The repo-path fixture (a plain path, not a derivation) that stands in for a bake's
  # package. bindContractPackage reads its contract-requests.json at eval time — no build, no IFD.
  fixturePackage = ./fixtures/reference-contract-package;

  # A synthetic user's on-disk identity path (ADR-0020 layout), reused for the binding index and
  # the account assertions. ada declares no privileged group; a second identity below declares
  # `wheel` to prove the clamp still drops a self-declared privileged group.
  adaIdentity = loadIdentity ../examples/users/users/ada/identity.json;
  # An identity that self-declares the privileged `wheel` group — untrusted input the clamp drops
  # unless a grant confers it (the untrusted-safety case (d)).
  wheelClaimant = adaIdentity // {
    username = "mallory";
    name = "Mallory Claimant";
    extraGroups = [ "wheel" ];
  };

  # Fabricate a binding index exactly as mkContractUsers would emit it — pure data. `grantKey` is
  # a home's sorted NAME LIST; `package` is the fixture path. Two entries (base + gui) let us
  # exercise maximal-subset selection without building anything.
  mkIndex =
    {
      identity,
      offer,
      grantKeys,
    }:
    {
      inherit identity offer;
      contractPackages = map (grantKey: {
        inherit grantKey;
        package = fixturePackage;
      }) grantKeys;
    };

  # A usersFlake stand-in: only the `contractUsers.<sys>.<user>` surface bindContractUser reads.
  mkUsersFlake = index: { contractUsers.${system}.ada = index; };

  # Bind a user via the turnkey path against a fabricated flake + a host affordance set.
  bindTurnkey =
    {
      index,
      affordances,
    }:
    eval [
      { contract.affordances = affordances; }
      (bindContractUser {
        usersFlake = mkUsersFlake index;
        username = "ada";
      })
    ];

  # --- (a) affordances ∩ offer grant derivation, incl. the host veto ---
  # ada offers gui + sudo; the host affords gui only ⇒ grant = { gui }. sudo is offered but not
  # afforded, so the host's veto drops it.
  adaGuiSudoOffer = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
      sudo.enable = true;
    };
    grantKeys = [
      [ ] # base
    ];
  };
  vetoBind = bindTurnkey {
    index = adaGuiSudoOffer;
    affordances = {
      gui.enable = true;
    };
  };
  vetoGrant = vetoBind.custom.users.ada.granted;

  # --- (b) maximal-subset bake selection incl. the hard-error case ---
  # A user with base + gui bakes. Grant { gui, sudo } ⇒ selects gui (sudo rides the bind);
  # grant { sudo } ⇒ selects base (gui not covered). The selected package is the fixture path,
  # so we assert selection SUCCEEDS (the account materializes) rather than inspecting the path.
  twoHomes =
    offer:
    mkIndex {
      identity = adaIdentity;
      inherit offer;
      grantKeys = [
        [ ] # base
        [ "gui" ] # gui
      ];
    };
  selGui = bindTurnkey {
    index = twoHomes {
      gui.enable = true;
      sudo.enable = true;
    };
    affordances = {
      gui.enable = true;
      sudo.enable = true;
    };
  };
  selBase = bindTurnkey {
    index = twoHomes {
      sudo.enable = true;
    };
    affordances = {
      sudo.enable = true;
    };
  };

  # The hard-error case: two incomparable bakes ([gui] and [sudo]) both ⊆ the derived
  # grant { gui, sudo }, and the combo [gui, sudo] was never baked ⇒ no unique maximum ⇒ throw.
  incomparableIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
      sudo.enable = true;
    };
    grantKeys = [
      [ "gui" ]
      [ "sudo" ]
    ];
  };
  incomparableEval = builtins.tryEval (
    (bindTurnkey {
      index = incomparableIndex;
      affordances = {
        gui.enable = true;
        sudo.enable = true;
      };
    }).custom.users.ada.granted
  );

  # --- (c) the coupling guard: accept ⊆, reject ⊄ ---
  # The fixture is a v1 manifest (no baked grant-key) ⇒ grantKey = [ ] ⊆ any grant, so the
  # turnkey binds above already exercise ACCEPT. To exercise REJECT we drive the primitive with a
  # bake whose grant-key is NOT granted — modelled by selecting a baked-[gui] bake while the
  # host affords/derives nothing. Selection would pick base if it existed; with ONLY a [gui]
  # bake and an empty grant, [gui] is not covered ⇒ selection itself errors first. The guard's
  # own accept/reject is proven directly against bindContractPackage in ./contract-package.nix's
  # sibling world; here we assert the turnkey path never lets an uncovered bake through.
  onlyGuiIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
    };
    grantKeys = [
      [ "gui" ]
    ];
  };
  uncoveredEval = builtins.tryEval (
    (bindTurnkey {
      index = onlyGuiIndex;
      affordances = { }; # affords nothing ⇒ grant = { } ⇒ [gui] uncovered
    }).custom.users.ada.granted
  );

  # --- (d) untrusted safety: a privileged offer under a safe-set affordance ---
  # mallory offers sudo and self-declares `wheel` in identity. The host affords only gui (the safe
  # set's shape). grant = { } for sudo ⇒ wheel is never conferred AND the clamp drops the
  # self-declared wheel. The account must have NO wheel.
  malloryIndex = mkIndex {
    identity = wheelClaimant;
    offer = {
      sudo.enable = true;
    };
    grantKeys = [
      [ ]
    ];
  };
  malloryBind = eval [
    {
      contract.affordances = {
        gui.enable = true;
      };
    }
    (bindContractUser {
      usersFlake = {
        contractUsers.${system}.mallory = malloryIndex;
      };
      username = "mallory";
    })
  ];

  # --- (e) mkContractUsers: the emitted shape, the HARVESTED offer, + no-IFD selection ---
  # A synthetic already-evaluated home (attribute paths mirror a homeManagerConfiguration result),
  # exactly as ./contract-package.nix stands one in for mkContractPackageForHome. Its
  # `contract.wants` is what mkContractUser harvests as the index's offer (ADR-0028) — the `offer`
  # ARGUMENT is gone, so a synthetic user declares its offer in its home like a real one. One base
  # bake.
  activationStub = pkgs.runCommand "turnkey-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';
  mkSyntheticHomeWith =
    { wants, requests }:
    {
      activationPackage = activationStub;
      config = {
        contract.requests = requests;
        contract.wants = wants;
        home = {
          packages = [ pkgs.hello ];
          username = "ada";
        };
      };
    };
  # The reference synthetic home: gui parameters, and whichever want set the case needs.
  mkSyntheticHome =
    wants:
    mkSyntheticHomeWith {
      inherit wants;
      requests = {
        gui.desktop = "plasma";
      };
    };
  # The full want set a real home eval yields: every registry feature present, `.enable` a bool.
  adaWants = {
    gui.enable = true;
    sudo.enable = false;
    containers.enable = false;
    virtualization.enable = false;
    nix-daemon.enable = false;
  };
  syntheticHome = mkSyntheticHome adaWants;
  adaHomes = [
    {
      grants = { };
      home = syntheticHome;
    }
  ];
  bindings = mkContractUsers {
    inherit pkgs;
    usersDir = ../examples/users/users;
    homes.ada = adaHomes;
  };
  emittedIndex = bindings.contractUsers.${system}.ada;
  # The SINGULAR partner: mkContractUser bakes ONE user and must emit byte-identical outputs to the
  # members form for that user (mkContractUsers is nothing but this mapped over the members).
  singleUser = mkContractUser {
    inherit pkgs;
    usersDir = ../examples/users/users;
    name = "ada";
    homes = adaHomes;
  };
  # --- (f) the offer must be bake-INVARIANT (ADR-0028) ---
  # A user whose two bakes harvest DIFFERENT wants — exactly what a home branching on
  # `hostFacts.granted` produces. The offer is what the grant is derived from, so a grant-dependent
  # want is circular and must fail the BAKE with a named error, not silently publish one bake's.
  # The other end of the harvest: with NO bakes there is no evaluated home to read `wants` off,
  # so the index has no offer to publish. That is a named bake error too, never an empty offer
  # (which would silently negotiate down to no grant at all).
  noHomeUser = builtins.tryEval (
    (mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = [ ];
    }).contractUsers.${system}.ada.offer
  );
  # --- (g) the bake pairing must hold across the whole bake record (issue #56) ---
  # A home built through `mkContractHome` carries the grant-key it was baked under. The producer
  # coin cross-checks it, so a `{ grants; home }` re-paired by the wrong label fails the BAKE rather
  # than publishing a home under a grant set it was never built with — which nothing downstream
  # could see (the index's grant-key, the manifest's grant-key, and so the coupling guard and
  # maximal-bake selection all read the grant passed ALONGSIDE the home). The marker is applied
  # by hand here for the same reason ./contract-package.nix does: the builder needs home-manager and
  # this suite has none. The guard rides the whole bake record, so BOTH routes out of the bake
  # are probed — the index entry's grant-key and the published package's name.
  #
  # The SEAM this leaves — a real `mkContractHome` result driven through the coin, marker and all —
  # is covered where home-manager lives (ADR-0004/0022): `examples/users` builds every home through
  # the builder and bakes the members through `mkContractUsers`, so its `nix flake check` is the
  # end-to-end half of this proof. What the message SAYS on failure is likewise unassertable here
  # (`tryEval` discards it), exactly as for this file's other named bake errors above.
  bakeUnder =
    { key, grants }:
    mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = [
        {
          inherit grants;
          home = syntheticHome // {
            contractBakedGrantKey = key;
          };
        }
      ];
    };
  pairedBake = bakeUnder {
    key = [ "gui" ];
    grants = {
      gui.enable = true;
    };
  };
  mispairedIndex = builtins.tryEval (
    (lib.head
      (bakeUnder {
        key = [ "gui" ];
        grants = { };
      }).contractUsers.${system}.ada.contractPackages
    ).grantKey
  );
  mispairedPackageName = builtins.tryEval (
    lib.attrNames
      (bakeUnder {
        key = [ ];
        grants = {
          gui.enable = true;
        };
      }).packages.${system}
  );
  # --- (h) the coin takes a MEMBER (issue #57) ---
  # A `mkMembers` entry, stood in for by hand so these stay claims about the COIN. Its
  # `identity` deliberately does NOT match the one on disk under its `dir` (the fixture's own
  # `name` is "Ada Reference"), so the index can only carry it if `mkContractUser` stopped
  # resolving `<usersDir>/<name>/identity.json` for itself — which is the whole point: the members
  # resolved that file once, and the coin reads the member.
  #
  # The `usersDir` + `name` calls above are the same claim from the other side: they still work, so
  # a single-user repo (and every existing producer) bakes without constructing a member set at all.
  adaMember = {
    name = "ada";
    dir = ../examples/users/users/ada;
    identity = adaIdentity // {
      name = "Rosa Member";
    };
  };
  memberUser = mkContractUser {
    inherit pkgs;
    member = adaMember;
    homes = adaHomes;
  };
  membersFromMember = mkContractUsers {
    inherit pkgs;
    members = {
      ada = adaMember;
    };
    homes.ada = adaHomes;
  };
  # The two routes OUT of a bake, spelled once: the published package NAMES and the binding INDEX.
  # Every guard that rides the bake record must be probed through both (issues #56, #59), so the
  # readers are named here rather than re-spelled at each call site.
  readPackageNames = u: lib.attrNames u.packages.${system};
  readIndex = u: u.contractUsers.${system};
  # A member handed alongside a DISAGREEING `name`: the package name and the index key come from
  # `name`, the identity from the member, so this would publish ada's identity under ben's name —
  # invisible downstream, since a host binds by the index key it finds. Both routes out of the bake
  # are probed, as for the bake pairing.
  mismatched =
    read:
    builtins.tryEval (
      read (mkContractUser {
        inherit pkgs;
        member = adaMember;
        name = "ben";
        homes = adaHomes;
      })
    );
  mismatchedIndex = mismatched readIndex;
  mismatchedPackageName = mismatched readPackageNames;
  # A `users` entry naming somebody the members does not hold — a hand-listed name that has drifted
  # from the directory. It must be a named error, never a member silently baked from nothing.
  strayEval = builtins.tryEval (
    (mkContractUsers {
      inherit pkgs;
      members = {
        ada = adaMember;
      };
      homes.ben = adaHomes;
    }).contractUsers.${system}.ben.identity
  );
  varyingUser = builtins.tryEval (
    (mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = [
        {
          grants = { };
          home = mkSyntheticHome adaWants;
        }
        {
          grants = {
            gui.enable = true;
          };
          home = mkSyntheticHome (adaWants // { containers.enable = true; });
        }
      ];
    }).contractUsers.${system}.ada.offer
  );
  # --- (f2) the user's two halves must not contradict each other (issue #59) ---
  # `contract.wants` and `contract.requests` are typed INDEPENDENTLY, so one home can veto a feature
  # and still carry its parameters. Those parameters can never bridge on any host — the grant is
  # `affordances ∩ offer` and the user's side of the intersection is already empty — so this is dead
  # data in the user's own repo, not a degradation. It must fail the BAKE.
  #
  # Like the pairing guard below, this one rides the whole bake RECORD, so both routes out of the
  # bake are probed: the published package NAME (what a user repo's own `checks = packages` forces —
  # the repo that owns the defect) and the binding index a host reads.
  vetoBake =
    requests:
    mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = [
        {
          grants = { };
          home = mkSyntheticHomeWith {
            wants = adaWants // {
              gui.enable = false;
            };
            inherit requests;
          };
        }
      ];
    };
  vetoWith = read: requests: builtins.tryEval (builtins.deepSeq (read (vetoBake requests)) true);
  vetoedRequestPackage = vetoWith readPackageNames { gui.desktop = "plasma"; };
  vetoedRequestIndex = vetoWith readIndex { gui.desktop = "plasma"; };
  # The svc posture (examples/users/users/svc): the same veto with the request namespace left at its
  # DEFAULT is a perfectly good user. Spelled as an explicit `desktop = ""` rather than an absent
  # key, so this proves the guard tests request DATA against the schema's default and not mere key
  # presence — every declared key is always present on a real harvested home (ADR-0028, no freeform).
  vetoNoRequestUser = vetoWith readPackageNames { gui.desktop = ""; };
in
{
  assertions = [
    # (a) affordances ∩ offer, with the host veto
    {
      name = "affordances ∩ offer: gui is granted (offered ∧ afforded)";
      ok = vetoGrant.gui.enable;
    }
    {
      name = "host veto: sudo is offered but not afforded ⇒ not granted (absolute veto)";
      ok = !(vetoGrant.sudo.enable or false);
    }

    # (b) maximal-subset selection
    {
      name = "bake selection: grant {gui,sudo} over {base,gui} selects gui (account materializes)";
      ok = selGui.users.users.ada.isNormalUser && selGui.custom.gui.surface.enabled;
    }
    {
      name = "bake selection: grant {sudo} over {base,gui} selects base (no gui surface)";
      ok = selBase.users.users.ada.isNormalUser && !selBase.custom.gui.surface.enabled;
    }
    {
      name = "bake selection: incomparable covers (gui|sudo, combo never baked) is a hard error";
      ok = !incomparableEval.success;
    }

    # (c) coupling guard / turnkey never binds an uncovered bake
    {
      name = "coupling guard: v1 manifest (grantKey=[]) ⊆ any grant ⇒ accept (turnkey binds ok)";
      ok = vetoBind.users.users.ada.isNormalUser;
    }
    {
      name = "turnkey: an uncovered [gui]-only bake under an empty grant is a hard error";
      ok = !uncoveredEval.success;
    }

    # (d) untrusted safety
    {
      name = "untrusted safety: a privileged offer under a safe (gui-only) affordance confers no wheel";
      ok = !(lib.elem "wheel" malloryBind.users.users.mallory.extraGroups);
    }
    {
      name = "untrusted safety: sudo offered-but-unafforded is not granted (grant is empty)";
      ok = !(malloryBind.custom.users.mallory.granted.sudo.enable or false);
    }

    # (e) mkContractUsers shape + no-IFD selection
    {
      name = "mkContractUsers: emits the named package <user>-contractPackage-base";
      ok = bindings.packages.${system} ? "ada-contractPackage-base";
    }
    {
      name = "mkContractUsers: the binding index carries { identity; offer; bakes }";
      ok =
        (emittedIndex ? identity)
        && (emittedIndex ? offer)
        && (emittedIndex ? contractPackages)
        && emittedIndex.identity.username == "ada";
    }
    {
      # ADR-0028: the offer is HARVESTED off the home's contract.wants, not passed in.
      name = "mkContractUsers: the index offer is the home's harvested contract.wants";
      ok = emittedIndex.offer == adaWants;
    }
    {
      name = "mkContractUser: an offer that varies across bakes is a hard bake error";
      ok = !varyingUser.success;
    }
    {
      name = "mkContractUser: a user with no bakes has no home to harvest ⇒ hard bake error";
      ok = !noHomeUser.success;
    }

    # (f2) the user's own veto vs its request data (issue #59)
    {
      name = "mkContractUser: request data for a feature the USER vetoed is a hard bake error";
      ok = !vetoedRequestPackage.success && !vetoedRequestIndex.success;
    }
    {
      name = "mkContractUser: the same veto with the request namespace at its default bakes (svc)";
      ok = vetoNoRequestUser.success;
    }
    {
      # ADR-0002 is UNCHANGED, at the seam the new guard sits on: ada wants gui and carries the SAME
      # gui.desktop request svc is rejected for, and the only bake here grants NOTHING. The
      # bake still stands and still publishes gui as the offer — an ungranted request is the host's
      # silent degradation, never a defect. That the request is then not BRIDGED is the other half,
      # proven where the bridge is (./bind.nix's "an ungranted request is inert").
      name = "mkContractUser: a request no bake grants stays inert — the bake stands (ADR-0002)";
      ok = emittedIndex.offer.gui.enable && (lib.head emittedIndex.contractPackages).grantKey == [ ];
    }

    # (h) the member as the coin's input
    {
      name = "mkContractUser: a member's identity reaches the index (no path re-derived)";
      ok = memberUser.contractUsers.${system}.ada.identity.name == "Rosa Member";
    }
    {
      name = "mkContractUsers: the member set's members are what its `users` entries bake";
      ok =
        membersFromMember.contractUsers.${system}.ada.identity.name == "Rosa Member"
        && membersFromMember.packages.${system} ? "ada-contractPackage-base";
    }
    {
      name = "mkContractUsers: a `users` entry the members does not hold is a hard bake error";
      ok = !strayEval.success;
    }
    {
      name = "mkContractUser: a member paired with a disagreeing `name` is a hard bake error (index + package name)";
      ok = !mismatchedIndex.success && !mismatchedPackageName.success;
    }
    {
      # …and the positive control for it: the agreeing pair (a member set's own key beside its own
      # member, which is what mkContractUsers always passes) must still bake.
      name = "mkContractUser: a member paired with its own name bakes (the guard is not blanket)";
      ok =
        (mkContractUser {
          inherit pkgs;
          member = adaMember;
          name = "ada";
          homes = adaHomes;
        }).contractUsers.${system}.ada.identity.name == "Rosa Member";
    }

    # (g) the bake pairing: the home's own key must match the one it is published under
    {
      name = "bake pairing: a home baked under [gui] paired with {gui} publishes the gui bake";
      ok =
        let
          v = lib.head pairedBake.contractUsers.${system}.ada.contractPackages;
        in
        v.grantKey == [ "gui" ] && pairedBake.packages.${system} ? "ada-contractPackage-gui";
    }
    {
      name = "bake pairing: a [gui] home paired with {} is a hard bake error (reading the index)";
      ok = !mispairedIndex.success;
    }
    {
      name = "bake pairing: a base home paired with {gui} is a hard bake error (reading the package name)";
      ok = !mispairedPackageName.success;
    }
    {
      # The homes in (e) above carry no key at all — they stand in for a home built by hand rather
      # than through `mkContractHome`, which must still bake. That those assertions pass IS the
      # skipped-not-fired proof; this names it so the property cannot be lost silently.
      name = "bake pairing: an unmarked home (built without mkContractHome) still bakes";
      ok =
        !(syntheticHome ? contractBakedGrantKey)
        && (lib.head emittedIndex.contractPackages).grantKey == [ ];
    }
    {
      name = "mkContractUsers: the index bake carries its grant-key names + package";
      ok =
        let
          v = lib.head emittedIndex.contractPackages;
        in
        v.grantKey == [ ] && (v.package ? outPath);
    }
    {
      name = "no-IFD: selection reads the index (plain data) and binds against a repo-path fixture";
      ok = vetoBind.systemd.services ? "contract-activate-ada";
    }
    {
      # The singular producer is the true per-user partner of bindContractUser: its one-user output
      # must match the members form for that user (same package store path, same index entry).
      name = "mkContractUser: the singular producer matches mkContractUsers for one user";
      ok =
        (
          singleUser.packages.${system}."ada-contractPackage-base".outPath
          == bindings.packages.${system}."ada-contractPackage-base".outPath
        )
        && singleUser.contractUsers.${system}.ada.identity.username == "ada"
        && singleUser.contractUsers.${system}.ada.offer.gui.enable;
    }

    # gui XDG fold
    {
      name = "XDG fold: a granted gui surface links the XDG portal/applications dirs";
      ok =
        let
          p = selGui.environment.pathsToLink;
        in
        lib.elem "/share/xdg-desktop-portal" p && lib.elem "/share/applications" p;
    }
    {
      name = "XDG fold: a cli-only host omits the XDG pathsToLink";
      ok = !(lib.elem "/share/xdg-desktop-portal" selBase.environment.pathsToLink);
    }
  ];
}
