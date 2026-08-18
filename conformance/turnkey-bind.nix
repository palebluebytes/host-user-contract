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

  # Fabricate a binding index exactly as mkContractUsers would emit it — pure data.
  # `contractPackages` is keyed by MODE and its leaf is the package, so its KEY SET is what this
  # user publishes here (its `supports` as the producer's matrix narrowed it) and selection reads
  # exactly that. The package is the repo-path fixture, so selection builds nothing.
  mkIndex =
    {
      identity,
      offer,
      modes,
      package ? fixturePackage,
    }:
    {
      inherit identity offer;
      contractPackages = lib.genAttrs modes (_: package);
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
  # afforded, so the host's veto drops it. The GRANT is derived independently of the mode, which is
  # what keeps "gui's groups on a cli-mode user" expressible: this index publishes cli alone.
  adaGuiSudoOffer = mkIndex {
    identity = adaIdentity;
    offer = {
      gui = true;
      sudo = true;
    };
    modes = [ "cli" ];
  };
  vetoBind = bindTurnkey {
    index = adaGuiSudoOffer;
    affordances = {
      gui = true;
    };
  };
  vetoGrant = vetoBind.custom.users.ada.granted;

  # --- (b) MODE SELECTION (ADR-0032 §5) ---
  # A user publishing both modes. A host affording gui RUNS { cli, gui }, so the rich mode wins; a
  # host affording nothing runs { cli } alone, so selection falls back to the floor. Nobody
  # declares `cli` anywhere in either case — the run set is derived from the affordances.
  twoModes =
    offer:
    mkIndex {
      identity = adaIdentity;
      inherit offer;
      modes = [
        "cli"
        "gui"
      ];
    };
  selGui = bindTurnkey {
    index = twoModes {
      gui = true;
      sudo = true;
    };
    affordances = {
      gui = true;
      sudo = true;
    };
  };
  selFloor = bindTurnkey {
    index = twoModes {
      sudo = true;
    };
    affordances = {
      sudo = true;
    };
  };

  # THE REFUSAL (ADR-0032's narrowing of ADR-0002): a user publishing gui ALONE, bound by a host
  # that affords nothing. `runs ∩ published` is empty, and that is a hard error naming both sets —
  # not a silently lesser home, because a home built for a graphical session activated on a machine
  # with no display is the worse answer. This is the `vault`/`agent` case in the reference fleet.
  guiOnlyIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui = true;
    };
    modes = [ "gui" ];
  };
  noCommonModeEval = builtins.tryEval (
    (bindTurnkey {
      index = guiOnlyIndex;
      affordances = { };
    }).custom.users.ada.granted
  );
  # …and its positive control: the SAME gui-only user on a host that affords gui binds fine, so the
  # refusal is about the mismatch and not about publishing one mode.
  guiOnlyOnASeat = bindTurnkey {
    index = guiOnlyIndex;
    affordances = {
      gui = true;
    };
  };

  # --- (c) the mode coupling guard on the turnkey path ---
  # Selection satisfies the guard by construction — it can only pick a mode the host runs — so what
  # the turnkey path proves is that a home whose FROZEN mode is one this host runs binds. The gui
  # fixture's manifest carries `mode = "gui"`, so binding it under the gui key on a gui-affording
  # host exercises the guard's accept end through the real selection. Its reject end is only
  # reachable by calling the kernel directly, which ./contract-package.nix does.
  guiFixtureIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui = true;
    };
    modes = [ "gui" ];
    package = ./fixtures/reference-contract-package-gui;
  };
  frozenModeBind = bindTurnkey {
    index = guiFixtureIndex;
    affordances = {
      gui = true;
    };
  };

  # --- (d) untrusted safety: a privileged offer under a safe-set affordance ---
  # mallory offers sudo and self-declares `wheel` in identity. The host affords only gui (the safe
  # set's shape). grant = { } for sudo ⇒ wheel is never conferred AND the clamp drops the
  # self-declared wheel. The account must have NO wheel.
  malloryIndex = mkIndex {
    identity = wheelClaimant;
    offer = {
      sudo = true;
    };
    modes = [ "cli" ];
  };
  malloryBind = eval [
    {
      contract.affordances = {
        gui = true;
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
    {
      wants,
      requests,
      supports ? adaSupports,
    }:
    {
      activationPackage = activationStub;
      config = {
        contract.requests = requests;
        contract.wants = wants;
        contract.supports = supports;
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
  # The full support set a real home eval yields: every registry mode present, one bool each. ada
  # is an ordinary desktop user — she supports gui, and says so.
  adaSupports = {
    cli = false;
    gui = true;
  };
  # The full want set a real home eval yields: every registry feature present, one bool each.
  adaWants = {
    gui = true;
    sudo = false;
    containers = false;
    virtualization = false;
    nix-daemon = false;
  };
  syntheticHome = mkSyntheticHome adaWants;
  # `{ <mode> = home; }` — what a system BUILT for this user, its matrix row. ada supports gui, so
  # gui is what gets published; the cli home the row also built is cut by `supports`.
  adaHomes = {
    cli = syntheticHome;
    gui = syntheticHome;
  };
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
  # --- (f) the offer must be mode-INVARIANT (ADR-0028) ---
  # A user whose two homes harvest DIFFERENT wants — exactly what a home branching on `hostFacts`
  # produces. The offer is what the grant is derived from, so a host-dependent want is circular and
  # must fail the BAKE with a named error, not silently publish one home's.
  # The other end of the harvest: with NO homes there is no evaluated home to read `wants` off,
  # so the index has no offer to publish. That is a named bake error too, never an empty offer
  # (which would silently negotiate down to no grant at all).
  noHomeUser = builtins.tryEval (
    (mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = { };
    }).contractUsers.${system}.ada.offer
  );
  # …and the same vacuity ONE RUNG UP (issue #67, first guard defect): `mkContractUsers` used to
  # accept `homes = { }` outright — it deep-forced to empty outputs and reported success, which is
  # the exact shape of failure its three siblings all refuse by name. A producer whose member fold
  # collapsed would have published, bound and checked NOTHING with every output green.
  noUsersBaked = builtins.tryEval (
    builtins.deepSeq (mkContractUsers {
      inherit pkgs;
      usersDir = ../examples/users/users;
      homes = { };
    }) true
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
  # The routes OUT of a bake, spelled once, so each guard is probed through the ones it must reach
  # rather than through whichever is handy. They are not interchangeable, and the difference is
  # structural since homes became mode-keyed (ADR-0032):
  #
  #   readPackageNames  the published NAMES. `<user>-contractPackage-<mode>` is derived from the
  #                     PUBLISHED KEY SET alone, so reading it forces the voice — which decides
  #                     that set — and nothing per-home.
  #   readPackages      the published DERIVATIONS, which is what a user repo's own
  #                     `checks = packages` forces. This is the route a per-home guard must reach.
  #                     Taken to `outPath` rather than deep-forced: a derivation is a recursive
  #                     attrset, so `deepSeq` over one never terminates — `outPath` forces the
  #                     package (and so every guard riding it) and stops at a string.
  #   readIndex         the binding index a host reads.
  readPackageNames = u: lib.attrNames u.packages.${system};
  readPackages = u: lib.mapAttrs (_: p: p.outPath) u.packages.${system};
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
  # --- (f3) the SUPPORTS half of the voice, and its three named errors (ADR-0032 §3, issue #66) ---
  # `contract.supports` is harvested exactly as the offer is, and guarded in three directions. Each
  # is driven through the published package NAMES, one of the two routes out of a bake, because a
  # guard that only fired on the index would leave the user's own `checks = packages` green.
  supportsBake =
    {
      supports,
      wants ? adaWants,
    }:
    builtins.tryEval (
      builtins.deepSeq (readPackageNames (mkContractUser {
        inherit pkgs;
        usersDir = ../examples/users/users;
        name = "ada";
        homes.cli = mkSyntheticHomeWith {
          inherit supports wants;
          requests = {
            gui.desktop = "";
          };
        };
      })) true
    );
  # A user supporting NO mode is uninstallable: nothing would be published for it, and a host that
  # tried to bind it would find an empty index entry rather than a refusal.
  noSupportedMode = supportsBake {
    supports = {
      cli = false;
      gui = false;
    };
  };
  # Supporting a mode while VETOING the grant that mode is run under — issue #59's rule one layer
  # up. No host can rescue it: it confers the gui grant in order to run the gui mode.
  modeWithoutItsGrant = supportsBake {
    supports = adaSupports;
    wants = adaWants // {
      gui = false;
    };
  };
  # A `supports` that VARIED by mode would make the published set depend on which mode happened to
  # be evaluated first — the same circularity the offer guard refuses, on the other half.
  varyingSupports = builtins.tryEval (
    builtins.deepSeq (readPackageNames (mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = {
        gui = mkSyntheticHomeWith {
          supports = adaSupports;
          wants = adaWants;
          requests = {
            gui.desktop = "plasma";
          };
        };
        cli = mkSyntheticHomeWith {
          supports = adaSupports // {
            cli = true;
          };
          wants = adaWants;
          requests = {
            gui.desktop = "plasma";
          };
        };
      };
    })) true
  );
  varyingUser = builtins.tryEval (
    (mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes = {
        gui = mkSyntheticHome adaWants;
        cli = mkSyntheticHome (adaWants // { containers = true; });
      };
    }).contractUsers.${system}.ada.offer
  );
  # --- (f2) the user's two halves must not contradict each other (issue #59) ---
  # `contract.wants` and `contract.requests` are typed INDEPENDENTLY, so one home can veto a feature
  # and still carry its parameters. Those parameters can never bridge on any host — the grant is
  # `affordances ∩ offer` and the user's side of the intersection is already empty — so this is dead
  # data in the user's own repo, not a degradation. It must fail the BAKE.
  #
  # This guard rides each PUBLISHED home, so both routes that reach one are probed: the published
  # package derivations (what a user repo's own `checks = packages` forces — the repo that owns the
  # defect) and the binding index a host reads.
  vetoBake =
    requests:
    mkContractUser {
      inherit pkgs;
      usersDir = ../examples/users/users;
      name = "ada";
      homes.cli = mkSyntheticHomeWith {
        wants = adaWants // {
          gui = false;
        };
        # The svc posture entire (ADR-0032): a user vetoing gui drops the gui MODE with it, or
        # the voice guard one section up refuses the pair before this one is reached.
        supports = {
          cli = true;
          gui = false;
        };
        inherit requests;
      };
    };
  vetoWith = read: requests: builtins.tryEval (builtins.deepSeq (read (vetoBake requests)) true);
  vetoedRequestPackage = vetoWith readPackages { gui.desktop = "plasma"; };
  vetoedRequestIndex = vetoWith readIndex { gui.desktop = "plasma"; };
  # The svc posture (examples/users/users/svc): the same veto with the request namespace left at its
  # DEFAULT is a perfectly good user. Spelled as an explicit `desktop = ""` rather than an absent
  # key, so this proves the guard tests request DATA against the schema's default and not mere key
  # presence — every declared key is always present on a real harvested home (ADR-0028, no freeform).
  vetoNoRequestUser = vetoWith readPackages { gui.desktop = ""; };
in
{
  assertions = [
    # (a) affordances ∩ offer, with the host veto
    {
      name = "affordances ∩ offer: gui is granted (offered ∧ afforded)";
      ok = vetoGrant.gui;
    }
    {
      name = "host veto: sudo is offered but not afforded ⇒ not granted (absolute veto)";
      ok = !(vetoGrant.sudo or false);
    }

    # (b) mode selection (ADR-0032 §5) — nobody declares a mode; `runs` is derived
    {
      # A gui-affording host RUNS { cli, gui }, so the rich mode wins over the floor.
      name = "mode selection: a gui-affording host runs { cli, gui } and binds the gui home";
      ok = selGui.users.users.ada.isNormalUser && selGui.custom.gui.surface.enabled;
    }
    {
      # …and one affording nothing runs { cli } alone, so selection falls back to the floor —
      # without any host having written `cli` anywhere.
      name = "mode selection: a host affording no mode grant falls back to the floor";
      ok = selFloor.users.users.ada.isNormalUser && !selFloor.custom.gui.surface.enabled;
    }
    {
      # THE REFUSAL: a gui-only user on a headless host has no mode in common with it, and that is
      # a hard error naming both sets — ADR-0032 narrows ADR-0002's silent degradation to GRANTS.
      name = "mode selection: a gui-only user on a host running only the floor is a hard error";
      ok = !noCommonModeEval.success;
    }
    {
      # …and its control: the same user on a gui-affording seat binds, so the refusal is about the
      # mismatch and not about publishing one mode.
      name = "mode selection: the same gui-only user binds on a gui-affording seat (the control)";
      ok = guiOnlyOnASeat.users.users.ada.isNormalUser;
    }

    # (c) the mode coupling guard, reached through the real selection
    {
      name = "coupling guard: a home frozen as `gui` binds on a host that runs gui (accept)";
      ok = frozenModeBind.users.users.ada.isNormalUser;
    }
    {
      name = "coupling guard: a pre-v3 manifest freezes no mode ⇒ nothing to check (turnkey binds ok)";
      ok = vetoBind.users.users.ada.isNormalUser;
    }

    # (d) untrusted safety
    {
      name = "untrusted safety: a privileged offer under a safe (gui-only) affordance confers no wheel";
      ok = !(lib.elem "wheel" malloryBind.users.users.mallory.extraGroups);
    }
    {
      name = "untrusted safety: sudo offered-but-unafforded is not granted (grant is empty)";
      ok = !(malloryBind.custom.users.mallory.granted.sudo or false);
    }

    # (e) mkContractUsers shape + no-IFD selection
    {
      name = "mkContractUsers: emits the named package <user>-contractPackage-<mode>";
      ok = bindings.packages.${system} ? "ada-contractPackage-gui";
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
      name = "mkContractUser: an offer that varies across a user's homes is a hard bake error";
      ok = !varyingUser.success;
    }
    {
      name = "mkContractUser: a user with no homes has nothing to harvest ⇒ hard bake error";
      ok = !noHomeUser.success;
    }

    # (f3) the supports half of the voice (ADR-0032 §3)
    {
      name = "mkContractUser: a user supporting NO mode is a hard bake error, not an empty publish";
      ok = !noSupportedMode.success;
    }
    {
      # Its positive control is the svc case below — the same gui veto with the gui MODE dropped
      # too bakes — so this guard is about the CONTRADICTION and not about vetoing gui.
      name = "mkContractUser: supporting a mode while vetoing its grant is a hard bake error";
      ok = !modeWithoutItsGrant.success;
    }
    {
      name = "mkContractUser: `supports` that varies across a user's homes is a hard bake error";
      ok = !varyingSupports.success;
    }

    # (f2) the user's own veto vs its request data (issue #59)
    {
      name = "mkContractUser: request data for a feature the USER vetoed is a hard bake error";
      ok = !vetoedRequestPackage.success && !vetoedRequestIndex.success;
    }
    {
      name = "mkContractUser: the whole svc posture — gui vetoed, gui mode dropped, no gui request — bakes";
      ok = vetoNoRequestUser.success;
    }
    {
      # ADR-0002 is UNCHANGED, at the seam the new guard sits on: ada wants gui and carries the SAME
      # gui.desktop request svc is rejected for, and the only bake here grants NOTHING. The
      # bake still stands and still publishes gui as the offer — an ungranted request is the host's
      # silent degradation, never a defect. That the request is then not BRIDGED is the other half,
      # proven where the bridge is (./bind.nix's "an ungranted request is inert").
      name = "mkContractUser: a request no host grants stays inert — the bake stands (ADR-0002)";
      ok = emittedIndex.offer.gui && emittedIndex.contractPackages ? gui;
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
        && membersFromMember.packages.${system} ? "ada-contractPackage-gui";
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

    # publication: the KEY a home is published under IS the mode it was built for (ADR-0032 §6)
    {
      # There is nothing to pair, which is why there is no pairing guard: `homes` comes in keyed by
      # mode and goes out keyed by mode, so a home cannot be published under a shape it was never
      # built as. What CAN differ is which of the built homes reach the index — that is `supports`,
      # and ada supports gui alone, so her cli home is built and never published.
      name = "mkContractUser: the index is keyed by the PUBLISHED modes, the cut `supports` decides";
      ok =
        lib.attrNames emittedIndex.contractPackages == [ "gui" ]
        && emittedIndex.contractPackages.gui ? outPath;
    }
    {
      name = "mkContractUsers: the published package is named for its mode";
      ok = lib.attrNames bindings.packages.${system} == [ "ada-contractPackage-gui" ];
    }
    {
      # …and the anti-vacuity guard one rung up (issue #67): a member fold that collapsed to no
      # users at all must be a named error, not empty outputs reporting success.
      name = "mkContractUsers: `homes` naming no user is a hard error, never empty green outputs";
      ok = !noUsersBaked.success;
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
          singleUser.packages.${system}."ada-contractPackage-gui".outPath
          == bindings.packages.${system}."ada-contractPackage-gui".outPath
        )
        && singleUser.contractUsers.${system}.ada.identity.username == "ada"
        && singleUser.contractUsers.${system}.ada.offer.gui;
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
      ok = !(lib.elem "/share/xdg-desktop-portal" selFloor.environment.pathsToLink);
    }
  ];
}
